function out = m2mDataArrow(ax, xy, offsetMm, label, opts)
% M2MDATAARROW  An annotation arrow whose TIP is a data point and whose tail is an offset
% in mm. It is drawn by m2mExport with the final box and axis limits, so it follows the data
% when the data or the limits change (a hand-drawn Inkscape arrow cannot).
%   m2mDataArrow(ax, [5 2.1], [5 6], 'peak')         % tip at x=5,y=2.1; tail 5 mm right, 6 mm up
%
% offsetMm  [dx dy] from tip to tail in mm, +x right, +y up
% opts.color [0.75 0.22 0.17]; opts.lineWidth 0.5 (pt); opts.headMm 1.2; opts.fontSize (page);
% opts.gapMm 0.5 (between the tail and the label)
if nargin == 0
    help m2mDataArrow
    out = struct('color', [0.75 0.22 0.17], 'lineWidth', 0.5, 'headMm', 1.2, 'fontSize', [], 'gapMm', 0.5);
    return
end
def = struct('color', [0.75 0.22 0.17], 'lineWidth', 0.5, 'headMm', 1.2, 'fontSize', [], 'gapMm', 0.5);
if nargin < 4, label = ''; end
if nargin < 5, opts = struct(); end
for f = fieldnames(def)', if ~isfield(opts, f{1}), opts.(f{1}) = def.(f{1}); end, end
if ~strcmp(ax.XScale, 'linear') || ~strcmp(ax.YScale, 'linear')
    error('m2m:dataArrow', 'm2mDataArrow supports linear axes only');
end
fig = ancestor(ax, 'figure');
S = getappdata(fig, 'm2m');
if isempty(S), error('m2m:notPage', 'Not an m2m page figure: create it with m2mPage.'); end
if ~isfield(S, 'arrows'), S.arrows = struct('ax', {}, 'xy', {}, 'off', {}, 'label', {}, 'opts', {}, 'h', {}); end
S.arrows(end+1) = struct('ax', ax, 'xy', xy, 'off', offsetMm, 'label', label, 'opts', opts, 'h', gobjects(0));
setappdata(fig, 'm2m', S);
end
