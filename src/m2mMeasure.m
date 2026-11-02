function M = m2mMeasure(pdfFile)
% M2MMEASURE  What is really in a PDF, read with mutool trace (via m2m_svg.py measure).
%   M = m2mMeasure('out/fig1.pdf')
% M.page (w_mm, h_mm, w_bp, h_bp); M.fills (color, bbox mm from top-left); M.texts (font,
% size pt, text, x, y mm); M.strokes (color, lw pt, bbox); M.images (px, mm, ppi, bbox).
if nargin == 0
    help m2mMeasure
    M = struct('page', struct(), 'fills', [], 'texts', [], 'strokes', [], 'images', []);
    return
end
M = jsondecode(m2mPy('measure', pdfFile));
for f = {'fills', 'texts', 'strokes', 'images'}
    if iscell(M.(f{1})), M.(f{1}) = [M.(f{1}){:}]; end
end
end
