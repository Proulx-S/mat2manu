function L = m2mLayout(svgFile)
% M2MLAYOUT  Read the boxes of an Inkscape layout SVG.
%   L = m2mLayout('fig1_layout.svg')
%
% Every <rect> in the layer labelled 'layout' is a box, named by its Inkscape label.
% Returns L.file, L.width_mm, L.height_mm, L.boxes (struct array: name, x, y, w, h in mm
% from the page's top-left corner, order = document order = z-order) and L.ignored
% (non-rect elements found in the layout layer). Errors on unlabeled or duplicate boxes,
% rotated or skewed boxes, a missing 'layout' layer, or unreadable page units.
if nargin == 0
    help m2mLayout
    L = struct('file', '', 'width_mm', [], 'height_mm', [], 'boxes', struct([]), 'ignored', {{}});
    return
end
if ~isfile(svgFile), error('m2m:layout', 'Layout SVG not found: %s', svgFile); end
L = jsondecode(m2mPy('layout', svgFile));
if isempty(L.boxes), error('m2m:layout', 'No boxes in the "layout" layer of %s', svgFile); end
if ~isempty(L.ignored)
    ig = L.ignored;
    if iscell(ig), ig = [ig{:}]; end
    warning('m2m:layout:ignored', '%d non-rect element(s) in the layout layer are ignored (%s).', ...
        numel(ig), strjoin(arrayfun(@(e) sprintf('%s#%s', e.tag, e.id), ig, 'UniformOutput', false), ', '));
end
end
