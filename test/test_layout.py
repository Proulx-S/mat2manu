#!/usr/bin/env python3
"""test_layout.py: layout parsing against REAL Inkscape 1.2 edits.

Each case edits examples/fig1_layout.svg with `inkscape --actions` (the same transform code the
GUI's select tool uses), saves it as Inkscape SVG, then checks every box m2m_svg.py reads
against Inkscape's own geometry (`inkscape --query-all`, px -> mm). The boxes have no stroke,
so Inkscape's visual bbox equals the geometric box. Also records what Inkscape wrote to the
rect (x/y/width/height rewritten, or a transform added).

Run from the repo root:  python3 test/test_layout.py   (writes into scratch/test_layout/)
"""
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'src'))
import m2m_svg  # noqa: E402

OUT = os.path.join(ROOT, 'scratch', 'test_layout')
BASE = os.path.join(ROOT, 'examples', 'fig1_layout.svg')
INK = '{http://www.inkscape.org/namespaces/inkscape}'
TOL = 1e-3  # mm
results, failures = [], []


def ink(src, dst, actions):
    r = subprocess.run(['inkscape', src, f'--actions={actions};export-filename:{dst};export-overwrite;export-do'],
                       capture_output=True, text=True, timeout=120)
    if not os.path.isfile(dst):
        raise RuntimeError(f'inkscape wrote nothing: {r.stderr[-400:]}')


def query(path):
    r = subprocess.run(['inkscape', '--query-all', path], capture_output=True, text=True, check=True)
    q = {}
    for line in r.stdout.splitlines():
        p = line.split(',')
        if len(p) == 5:
            q[p[0]] = [float(v) * 25.4 / 96 for v in p[1:]]
    return q


def rect_attrs(path, rid):
    for e in ET.parse(path).getroot().iter('{http://www.w3.org/2000/svg}rect'):
        if e.get('id') == rid:
            return {k: e.get(k) for k in ('x', 'y', 'width', 'height', 'transform')}


def check(name, path, expect_error=None, show=()):
    try:
        L = m2m_svg.read_layout(path)
    except m2m_svg.LayoutError as e:
        ok = expect_error is not None and re.search(expect_error, str(e))
        results.append((name, 'error' + (' (expected)' if ok else ' (UNEXPECTED)'), str(e)[:110]))
        if not ok:
            failures.append(name)
        return
    if expect_error:
        results.append((name, 'FAIL: no error', ''))
        failures.append(name)
        return
    q = query(path)
    worst = 0.0
    for b in L['boxes']:
        qx = q[b['id']]
        worst = max(worst, max(abs(a - c) for a, c in zip([b['x'], b['y'], b['w'], b['h']], qx)))
    ok = worst < TOL
    if not ok:
        failures.append(name)
    notes = '; '.join(f'{rid}: {rect_attrs(path, rid)}' for rid in show)
    results.append((name, f'{len(L["boxes"])} boxes, max |m2m - inkscape| = {worst:.2e} mm', notes))


def main():
    os.makedirs(OUT, exist_ok=True)
    p = lambda n: os.path.join(OUT, n)  # noqa: E731
    check('unedited', BASE)
    ink(BASE, p('move.svg'), 'select-by-id:boxA;transform-translate:7.5,-2')
    check('move A (select tool translate)', p('move.svg'), show=['boxA'])
    ink(BASE, p('scale.svg'), 'select-by-id:boxB;transform-scale:1.25')
    check('scale B x1.25', p('scale.svg'), show=['boxB'])
    ink(BASE, p('grow.svg'), 'select-by-id:boxC;transform-grow:3')
    check('grow C by 3 px', p('grow.svg'), show=['boxC'])
    ink(BASE, p('rot90.svg'), 'select-by-id:boxD;transform-rotate:90')
    check('rotate D 90 deg', p('rot90.svg'), show=['boxD'])
    ink(BASE, p('rot30.svg'), 'select-by-id:boxE;transform-rotate:30')
    check('rotate E 30 deg', p('rot30.svg'), expect_error='rotated or skewed')
    ink(BASE, p('dup.svg'), 'select-by-id:boxG;duplicate;transform-translate:0,40')
    check('duplicate G', p('dup.svg'), expect_error='duplicate box name')
    ink(BASE, p('dup_relabel.svg'),
        'select-by-id:boxG;duplicate;object-set-attribute:inkscape:label,H;transform-translate:0,40')
    check('duplicate G, relabel H', p('dup_relabel.svg'))
    ink(BASE, p('delete.svg'), 'select-by-id:boxF;delete-selection')
    check('delete F', p('delete.svg'))

    # a transform on the layout layer, and a group inside it, both then edited by Inkscape
    s = open(BASE).read()
    s = s.replace('inkscape:label="layout">', 'inkscape:label="layout" transform="translate(5,3)">')
    c = re.search(r'    <rect id="boxC".*?/>\n', s).group(0)
    d = re.search(r'    <rect id="boxD".*?/>\n', s).group(0)
    s = s.replace(c, '').replace(d, '    <g id="grpCD">\n' + c + d + '    </g>\n')
    open(p('layer.svg'), 'w').write(s)
    check('layer translate(5,3) + group', p('layer.svg'))
    ink(p('layer.svg'), p('layer_move.svg'), 'select-by-id:boxA;transform-translate:10,10')
    check('  ... then move A', p('layer_move.svg'), show=['boxA'])
    ink(p('layer.svg'), p('layer_grpscale.svg'), 'select-by-id:grpCD;transform-scale:1.1')
    check('  ... then scale group C+D', p('layer_grpscale.svg'), show=['boxC'])

    # px user units (an Inkscape 0.92-style document): width in mm, viewBox in px
    s = open(BASE).read()
    k = 96 / 25.4
    s = s.replace('viewBox="0 0 178 140"', f'viewBox="0 0 {178 * k:.6f} {140 * k:.6f}"')
    s = s.replace('inkscape:label="layout">', f'inkscape:label="layout" transform="scale({k:.9f})">')
    open(p('px.svg'), 'w').write(s)
    check('px viewBox + scaled layer', p('px.svg'))

    # unlabeled rect
    s = open(BASE).read().replace(' inkscape:label="C"', '')
    open(p('unlabeled.svg'), 'w').write(s)
    check('unlabeled rect', p('unlabeled.svg'), expect_error='without an inkscape:label')

    for r in results:
        print(f'{r[0]:34s} {r[1]}')
        if r[2]:
            print(f'{"":34s}   {r[2]}')
    print('FAILED: ' + ', '.join(failures) if failures else 'ALL PASSED')
    json.dump(results, open(p('results.json'), 'w'), indent=1)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
