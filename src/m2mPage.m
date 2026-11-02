function fig = m2mPage(layout, opts)
% M2MPAGE  One invisible, page-sized figure for a layout, at true size.
%   fig = m2mPage('fig1_layout.svg')            % or an m2mLayout struct
%   fig = m2mPage(L, struct('fontSize', 7))
%
% opts.fontSize   default text size in pt (7)
% opts.fontName   'Arial' (set explicitly: MATLAB's default falls back to LiberationSans)
% opts.lineWidth  default axes line width in pt (0.5)
%
% Light theme is forced (tako's default dark GraphicsTheme draws light-grey text).
% Then draw with m2mAxes / m2mAdopt / m2mColorbar / m2mLegend, and finish with m2mExport.
if nargin == 0
    help m2mPage
    fig = struct('fontSize', 7, 'fontName', 'Arial', 'lineWidth', 0.5);
    return
end
def = struct('fontSize', 7, 'fontName', 'Arial', 'lineWidth', 0.5);
if nargin < 2, opts = struct(); end
for f = fieldnames(def)', if ~isfield(opts, f{1}), opts.(f{1}) = def.(f{1}); end, end
if ischar(layout) || isstring(layout), L = m2mLayout(layout); else, L = layout; end

W = L.width_mm / 10; H = L.height_mm / 10;  % cm
fig = figure('Visible', 'off', 'Units', 'centimeters', 'Color', 'w', 'InvertHardcopy', 'off');
fig.Position = [1 1 W H];
if any(abs(fig.Position(3:4) - [W H]) > 1e-6)
    error('m2m:page', 'Figure refused its size: asked %.3f x %.3f cm, got %.3f x %.3f', W, H, fig.Position(3:4));
end
theme(fig, 'light');
set(fig, 'PaperUnits', 'centimeters', 'PaperSize', [W H], 'PaperPosition', [0 0 W H], ...
    'PaperPositionMode', 'manual');
fn = opts.fontName; fs = opts.fontSize;
set(fig, 'DefaultAxesFontName', fn, 'DefaultTextFontName', fn, 'DefaultLegendFontName', fn, ...
    'DefaultAxesFontSize', fs, 'DefaultTextFontSize', fs, 'DefaultLegendFontSize', fs, ...
    'DefaultAxesLineWidth', opts.lineWidth, 'DefaultAxesTitleFontSizeMultiplier', 1, ...
    'DefaultAxesLabelFontSizeMultiplier', 1, 'DefaultAxesTitleFontWeight', 'normal');
try, set(fig, 'DefaultColorbarFontName', fn, 'DefaultColorbarFontSize', fs); catch, end

S.L = L;
S.opts = opts;
S.items = struct('name', {}, 'kind', {}, 'h', {}, 'axes', {});  % kind: axes | colorbar | legend
setappdata(fig, 'm2m', S);
end
