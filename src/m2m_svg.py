#!/usr/bin/env python3
"""m2m_svg.py: the SVG/PDF side of mat2manu (figurefirst model).

Standard library only, except `overlay` (needs pypdf). MATLAB calls this through system().

Subcommands
  layout  LAYOUT.svg                         print the layout as JSON (page size, boxes in mm)
  preview LAYOUT.svg PNG                     link PNG into the 'generated' layer (writes only if changed)
  annot   LAYOUT.svg OUT.pdf                 render every layer except 'layout'/'generated' to PDF
  inject  LAYOUT.svg MATLAB.svg OUT.svg OUT.pdf   R1: MATLAB page SVG into the generated layer, render
  overlay BASE.pdf TOP.pdf OUT.pdf WMM HMM   R2: crop BASE to WMM x HMM (top-left anchored), stamp TOP
  annotboxes LAYOUT.svg                      bboxes (mm) of the human layers' objects (inkscape --query-all)
  humanhash LAYOUT.svg                       sha256 of each human layer (C14N): survival checks
  measure PDF                                what is in a PDF (mutool trace): page, fills, texts, strokes, images

Conventions (see docs/evaluation.md)
  - A layer is a <g inkscape:groupmode="layer">, named by inkscape:label.
  - Layer 'layout' holds the boxes: every <rect> in it (any depth) is a box, named by its
    inkscape:label. Unlabeled or duplicate names are errors. Other elements there are ignored
    and reported.
  - Layer 'generated' is owned by the pipeline: wiped and refilled.
  - Every other layer is the human's and is never modified.
  - Box geometry is the rect's geometric box (x, y, width, height) through all transforms,
    in mm from the page's top-left corner. Rotation or skew is an error.
"""
import json
import math
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

SVG = 'http://www.w3.org/2000/svg'
INK = 'http://www.inkscape.org/namespaces/inkscape'
SODI = 'http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd'
XLINK = 'http://www.w3.org/1999/xlink'
LAYOUT_LAYER = 'layout'
GEN_LAYER = 'generated'
UNIT_MM = {'mm': 1.0, 'cm': 10.0, 'in': 25.4, 'pt': 25.4 / 72, 'pc': 25.4 / 6, 'px': 25.4 / 96, '': 25.4 / 96}


class LayoutError(Exception):
    pass


# ---------------------------------------------------------------- parsing helpers
def register_namespaces(path):
    """Keep the document's own prefixes when ElementTree writes it back."""
    for _, (prefix, uri) in ET.iterparse(path, events=['start-ns']):
        if uri == SVG:
            prefix = ''  # Inkscape also declares xmlns:svg; keep SVG as the default namespace
        try:
            ET.register_namespace(prefix, uri)
        except ValueError:
            pass  # reserved prefixes such as 'xml'


def parse(path):
    register_namespaces(path)
    parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True, insert_pis=True))
    return ET.parse(path, parser)


def length_mm(s, what):
    m = re.fullmatch(r'\s*([-+0-9.eE]+)\s*([a-z%]*)\s*', s or '')
    if not m or m.group(2) not in UNIT_MM:
        raise LayoutError(f'cannot read the page {what} "{s}": give it in mm, cm, in, pt, pc or px')
    return float(m.group(1)) * UNIT_MM[m.group(2)]


def mat_mul(a, b):
    """Compose 2D affine matrices [a b c d e f] (SVG order): result = a * b."""
    return [a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1],
            a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3],
            a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5]]


IDENT = [1, 0, 0, 1, 0, 0]


def parse_transform(s):
    m_total = IDENT
    if not s:
        return m_total
    for name, args in re.findall(r'(\w+)\s*\(([^)]*)\)', s):
        v = [float(x) for x in re.split(r'[\s,]+', args.strip()) if x]
        if name == 'matrix':
            m = v
        elif name == 'translate':
            m = [1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0]
        elif name == 'scale':
            m = [v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0]
        elif name == 'rotate':
            a = math.radians(v[0])
            m = [math.cos(a), math.sin(a), -math.sin(a), math.cos(a), 0, 0]
            if len(v) == 3:
                m = mat_mul(mat_mul([1, 0, 0, 1, v[1], v[2]], m), [1, 0, 0, 1, -v[1], -v[2]])
        elif name == 'skewX':
            m = [1, 0, math.tan(math.radians(v[0])), 1, 0, 0]
        elif name == 'skewY':
            m = [1, math.tan(math.radians(v[0])), 0, 1, 0, 0]
        else:
            raise LayoutError(f'unknown transform "{name}"')
        m_total = mat_mul(m_total, m)
    return m_total


def is_layer(el):
    return el.tag == f'{{{SVG}}}g' and el.get(f'{{{INK}}}groupmode') == 'layer'


def label(el):
    return el.get(f'{{{INK}}}label')


def top_layers(root):
    return [el for el in root if is_layer(el)]


def find_layer(root, name):
    hits = [el for el in root.iter() if is_layer(el) and (label(el) or '').strip().lower() == name]
    if len(hits) > 1:
        raise LayoutError(f'{len(hits)} layers are named "{name}"; keep exactly one')
    return hits[0] if hits else None


def page_geometry(root):
    """mm per user unit, and the page size in mm."""
    w_mm = length_mm(root.get('width'), 'width')
    h_mm = length_mm(root.get('height'), 'height')
    vb = root.get('viewBox')
    if vb:
        x0, y0, vw, vh = [float(x) for x in re.split(r'[\s,]+', vb.strip())]
    else:
        x0, y0, vw, vh = 0, 0, w_mm / UNIT_MM['px'], h_mm / UNIT_MM['px']
    sx, sy = w_mm / vw, h_mm / vh
    if abs(sx - sy) > 1e-6 * max(sx, sy):
        raise LayoutError('viewBox aspect ratio differs from width/height: non-uniform page scale')
    return dict(width_mm=w_mm, height_mm=h_mm, mm_per_unit=sx, origin=(x0, y0))


# ---------------------------------------------------------------- layout
def read_layout(path):
    tree = parse(path)
    root = tree.getroot()
    page = page_geometry(root)
    k = page['mm_per_unit']
    x0, y0 = page['origin']
    lay = find_layer(root, LAYOUT_LAYER)
    if lay is None:
        raise LayoutError(f'no layer named "{LAYOUT_LAYER}" in {path}')

    # composed transform of the layout layer itself (its ancestors included)
    parent = {c: p for p in root.iter() for c in p}

    def ctm(el):
        chain = []
        while el is not None and el is not root:
            chain.append(el)
            el = parent.get(el)
        m = IDENT
        for e in reversed(chain):
            m = mat_mul(m, parse_transform(e.get('transform')))
        return m

    boxes, ignored, unlabeled = [], [], []
    order = 0
    for el in lay.iter():
        if el is lay:
            continue
        tag = el.tag.split('}')[-1]
        if tag != 'rect':
            if tag not in ('g', 'title', 'desc') and not isinstance(el.tag, type(ET.Comment)):
                ignored.append(dict(tag=tag, id=el.get('id'), label=label(el)))
            continue
        name = (label(el) or '').strip()
        if not name:
            unlabeled.append(el.get('id'))
            continue
        m = ctm(el)
        tol = 1e-6 * max(abs(v) for v in m[:4])
        aligned = (abs(m[1]) < tol and abs(m[2]) < tol) or (abs(m[0]) < tol and abs(m[3]) < tol)
        if not aligned:  # 0/90/180/270 degrees (and flips) still give an axis-aligned box
            raise LayoutError(f'box "{name}" (id {el.get("id")}) is rotated or skewed: '
                              f'transform {[round(v, 6) for v in m]}. Remove the rotation '
                              f'(Object > Transform > Rotate back, or Edit > Remove Transform).')
        x, y = float(el.get('x', 0)), float(el.get('y', 0))
        w, h = float(el.get('width')), float(el.get('height'))
        pts = [(m[0] * px + m[2] * py + m[4], m[1] * px + m[3] * py + m[5])
               for px, py in ((x, y), (x + w, y), (x, y + h), (x + w, y + h))]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        order += 1
        boxes.append(dict(name=name, id=el.get('id'), order=order,
                          x=(min(xs) - x0) * k, y=(min(ys) - y0) * k,
                          w=(max(xs) - min(xs)) * k, h=(max(ys) - min(ys)) * k,
                          transformed=m != IDENT))
    if unlabeled:
        raise LayoutError(f'rect(s) in the "{LAYOUT_LAYER}" layer without an inkscape:label: '
                          f'{", ".join(map(str, unlabeled))}. Name each box (Objects panel or '
                          f'Object Properties > Label).')
    names = [b['name'] for b in boxes]
    dup = sorted({n for n in names if names.count(n) > 1})
    if dup:
        raise LayoutError(f'duplicate box name(s): {", ".join(dup)} (a duplicated rect keeps its label)')
    layers = [dict(label=label(el), id=el.get('id')) for el in root.iter() if is_layer(el)]
    return dict(file=os.path.abspath(path), width_mm=page['width_mm'], height_mm=page['height_mm'],
                boxes=boxes, ignored=ignored, layers=layers)


# ---------------------------------------------------------------- writing helpers
def ensure_gen_layer(root):
    gen = find_layer(root, GEN_LAYER)
    if gen is None:
        gen = ET.Element(f'{{{SVG}}}g', {f'{{{INK}}}groupmode': 'layer', f'{{{INK}}}label': GEN_LAYER,
                                          'id': 'm2m-generated', f'{{{SODI}}}insensitive': 'true'})
        # bottom of the stack: the human's layers draw on top of generated content
        idx = next((i for i, el in enumerate(root) if is_layer(el)), len(root))
        root.insert(idx, gen)
    return gen


def write(tree, path):
    tree.write(path, encoding='UTF-8', xml_declaration=True)


def page_user_box(root):
    page = page_geometry(root)
    x0, y0 = page['origin']
    return x0, y0, page['width_mm'] / page['mm_per_unit'], page['height_mm'] / page['mm_per_unit']


def preview(layout_path, png_path):
    """Link PNG (relative path) into the generated layer, covering the page. Idempotent."""
    tree = parse(layout_path)
    root = tree.getroot()
    if find_layer(root, LAYOUT_LAYER) is None:
        raise LayoutError(f'no layer named "{LAYOUT_LAYER}"')
    gen = ensure_gen_layer(root)
    x0, y0, w, h = page_user_box(root)
    href = os.path.relpath(os.path.abspath(png_path), os.path.dirname(os.path.abspath(layout_path)))
    want = {'id': 'm2m-preview', f'{{{XLINK}}}href': href, 'x': f'{x0:g}', 'y': f'{y0:g}',
            'width': f'{w:g}', 'height': f'{h:g}', 'preserveAspectRatio': 'none'}
    kids = list(gen)
    if (len(kids) == 1 and kids[0].tag == f'{{{SVG}}}image'
            and all(kids[0].get(a) == v for a, v in want.items()) and gen.get('transform') is None):
        return False  # already current; never rewrite the human's file needlessly
    for c in kids:
        gen.remove(c)
    gen.attrib.pop('transform', None)
    img = ET.SubElement(gen, f'{{{SVG}}}image', want)
    gen.text, img.tail = '\n    ', '\n  '
    if not (gen.tail or '').strip():
        gen.tail = '\n  '
    write(tree, layout_path)
    return True


def strip_for_render(root, drop_gen=True):
    for name in ([LAYOUT_LAYER, GEN_LAYER] if drop_gen else [LAYOUT_LAYER]):
        el = find_layer(root, name)
        if el is not None:
            parent = {c: p for p in root.iter() for c in p}[el]
            parent.remove(el)


def rsvg(svg_path, pdf_path):
    r = subprocess.run(['rsvg-convert', '-f', 'pdf', '-o', pdf_path, svg_path],
                       capture_output=True, text=True)
    if r.returncode:
        raise LayoutError(f'rsvg-convert failed: {r.stderr.strip()}')


def annot(layout_path, pdf_path):
    tree = parse(layout_path)
    strip_for_render(tree.getroot())
    tmp = pdf_path[:-4] + '.annot.svg'
    write(tree, tmp)
    rsvg(tmp, pdf_path)
    return tmp


def inject(layout_path, matlab_svg, out_svg, out_pdf):
    """R1: the MATLAB page SVG becomes the generated layer of a copy of the layout."""
    tree = parse(layout_path)
    root = tree.getroot()
    strip_for_render(root, drop_gen=False)
    gen = ensure_gen_layer(root)
    for c in list(gen):
        gen.remove(c)
    page = page_geometry(root)
    x0, y0 = page['origin']
    ms = ET.parse(matlab_svg).getroot()
    mw_mm = length_mm(ms.get('width'), 'width (MATLAB SVG)')
    mvb = [float(v) for v in re.split(r'[\s,]+', ms.get('viewBox').strip())]
    s = mw_mm / mvb[2] / page['mm_per_unit']  # MATLAB user unit -> layout user unit
    # MATLAB SVG is anchored at its own top-left: map (0,0) to the page's top-left
    g = ET.SubElement(gen, f'{{{SVG}}}g', {'id': 'm2m-matlab',
                                            'transform': f'matrix({s:.9g},0,0,{s:.9g},{x0:g},{y0:g})'})
    # MATLAB ids (clip paths, patterns) are prefixed so they cannot collide with Inkscape's
    idmap = {}
    for el in ms.iter():
        if el.get('id'):
            idmap[el.get('id')] = 'm2m-' + el.get('id')
    for el in ms.iter():
        el.tag = el.tag  # keep the SVG namespace
        if el.get('id'):
            el.set('id', idmap[el.get('id')])
        for a, v in list(el.attrib.items()):
            if 'url(#' in v:
                el.set(a, re.sub(r'url\(#([^)]+)\)', lambda mm: f'url(#{idmap.get(mm.group(1), mm.group(1))})', v))
            if a == f'{{{XLINK}}}href' and v.startswith('#'):
                el.set(a, '#' + idmap.get(v[1:], v[1:]))
    for c in list(ms):
        if c.tag.split('}')[-1] in ('title', 'desc'):
            continue
        g.append(c)
    write(tree, out_svg)
    rsvg(out_svg, out_pdf)


def overlay(base_pdf, top_pdf, out_pdf, w_mm, h_mm):
    from pypdf import PdfReader, PdfWriter, Transformation
    from pypdf.generic import RectangleObject
    W, H = w_mm / 25.4 * 72, h_mm / 25.4 * 72
    base = PdfReader(base_pdf).pages[0]
    bx0, by0, bx1, by1 = [float(v) for v in base.mediabox]
    # MATLAB rounds its page up to whole points and anchors content at the top-left:
    # shift down so the top edges coincide, then crop to the exact size.
    dy = (by1 - by0) - H
    if dy < -0.01 or (bx1 - bx0) - W < -0.01:
        raise LayoutError(f'MATLAB page {bx1 - bx0:.3f} x {by1 - by0:.3f} bp is smaller than '
                          f'the layout {W:.3f} x {H:.3f} bp')
    base.add_transformation(Transformation().translate(-bx0, -by0 - dy))
    top = PdfReader(top_pdf).pages[0]
    tw, th = float(top.mediabox.width), float(top.mediabox.height)
    if abs(tw - W) > 0.01 or abs(th - H) > 0.01:
        raise LayoutError(f'annotation PDF is {tw:.3f} x {th:.3f} bp, expected {W:.3f} x {H:.3f}')
    base.merge_page(top)
    for box in ('mediabox', 'cropbox', 'trimbox', 'bleedbox', 'artbox'):
        setattr(base, box, RectangleObject([0, 0, W, H]))
    w = PdfWriter()
    w.add_page(base)
    w.compress_identical_objects()
    with open(out_pdf, 'wb') as f:
        w.write(f)


def annot_boxes(layout_path):
    """Bounding boxes (mm, page top-left origin) of the top-level objects of the human layers,
    measured by Inkscape itself (--query-all), so text and strokes count."""
    tree = parse(layout_path)
    root = tree.getroot()
    page = page_geometry(root)
    ids = {}
    for lay in root.iter():
        if not is_layer(lay) or (label(lay) or '').strip().lower() in (LAYOUT_LAYER, GEN_LAYER):
            continue
        for c in lay:
            if c.get('id') and not is_layer(c):
                ids[c.get('id')] = label(lay)
    if not ids:
        return []
    r = subprocess.run(['inkscape', '--query-all', layout_path], capture_output=True, text=True)
    if r.returncode:
        raise LayoutError(f'inkscape --query-all failed: {r.stderr.strip()[-300:]}')
    out = []
    # --query-all reports px (1/96 in) from the page's top-left corner
    for line in r.stdout.splitlines():
        p = line.split(',')
        if len(p) == 5 and p[0] in ids:
            x, y, w, h = (float(v) * 25.4 / 96 for v in p[1:])
            out.append(dict(id=p[0], layer=ids[p[0]], x=x, y=y, w=w, h=h))
    return out


# ---------------------------------------------------------------- measuring a final PDF
MM = 25.4 / 72


def mat(s):
    return [float(v) for v in s.split()] if s else [1, 0, 0, 1, 0, 0]


def apply(m, x, y):
    return m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]


def scale(m):
    return math.sqrt(abs(m[0] * m[3] - m[1] * m[2]))


def bbox(el, m):
    pts = [apply(m, float(p.get('x')), float(p.get('y'))) for p in el if p.get('x') is not None]
    if not pts:
        return None
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return [min(xs) * MM, min(ys) * MM, (max(xs) - min(xs)) * MM, (max(ys) - min(ys)) * MM]


def measure(pdf):
    xml = subprocess.run(['mutool', 'trace', pdf], capture_output=True, text=True, check=True).stdout
    root = ET.fromstring(xml)
    page = root.find('page')
    mb = [float(v) for v in page.get('mediabox').split()]
    out = dict(page=dict(w_bp=mb[2] - mb[0], h_bp=mb[3] - mb[1], w_mm=(mb[2] - mb[0]) * MM,
                         h_mm=(mb[3] - mb[1]) * MM), fills=[], texts=[], strokes=[], images=[])
    for el in page.iter():
        tag = el.tag
        m = mat(el.get('transform'))
        col = [float(v) for v in el.get('color', '').split()] if el.get('color') else None
        if tag == 'fill_path':
            out['fills'].append(dict(color=col, bbox=bbox(el, m)))
        elif tag == 'stroke_path':
            out['strokes'].append(dict(color=col, lw=float(el.get('linewidth', 1)) * scale(m), bbox=bbox(el, m)))
        elif tag == 'fill_text':
            for sp in el.findall('span'):
                trm = mat(sp.get('trm'))
                gl = sp.findall('g')
                if not gl:
                    continue
                size = scale(trm) * scale(m)
                x, y = apply(m, float(gl[0].get('x')), float(gl[0].get('y')))
                out['texts'].append(dict(font=sp.get('font').split('+')[-1], size=round(size, 4),
                                         text=''.join(g.get('unicode', '') for g in gl),
                                         x=x * MM, y=y * MM))
        elif tag == 'fill_image':
            w, h = int(el.get('width')), int(el.get('height'))
            pw, ph = math.hypot(m[0], m[1]) * MM, math.hypot(m[2], m[3]) * MM
            c = [apply(m, u, v) for u, v in ((0, 0), (1, 0), (0, 1), (1, 1))]
            xs, ys = [q[0] for q in c], [q[1] for q in c]
            out['images'].append(dict(px=[w, h], mm=[pw, ph], ppi=[w / pw * 25.4, h / ph * 25.4],
                                      bbox=[min(xs) * MM, min(ys) * MM, (max(xs) - min(xs)) * MM,
                                            (max(ys) - min(ys)) * MM]))
    return out



def human_hash(layout_path):
    """sha256 of the canonical XML (C14N 2.0) of each human layer: proves they were not touched."""
    import hashlib
    root = parse(layout_path).getroot()
    out = {}
    for lay in root.iter():
        if is_layer(lay) and (label(lay) or '').strip().lower() not in (LAYOUT_LAYER, GEN_LAYER):
            xml = ET.canonicalize(ET.tostring(lay, encoding='unicode'), strip_text=True)
            out[label(lay) or lay.get('id')] = hashlib.sha256(xml.encode()).hexdigest()
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd, a = argv[1], argv[2:]
    try:
        if cmd == 'layout':
            print(json.dumps(read_layout(a[0])))
        elif cmd == 'preview':
            print(json.dumps(dict(written=preview(a[0], a[1]))))
        elif cmd == 'annot':
            annot(a[0], a[1])
        elif cmd == 'inject':
            inject(a[0], a[1], a[2], a[3])
        elif cmd == 'annotboxes':
            print(json.dumps(annot_boxes(a[0])))
        elif cmd == 'humanhash':
            print(json.dumps(human_hash(a[0])))
        elif cmd == 'measure':
            print(json.dumps(measure(a[0])))
        elif cmd == 'overlay':
            overlay(a[0], a[1], a[2], float(a[3]), float(a[4]))
        else:
            print(f'unknown subcommand {cmd}', file=sys.stderr)
            return 2
    except LayoutError as e:
        print(f'M2M-ERROR: {e}', file=sys.stderr)
        return 3
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
