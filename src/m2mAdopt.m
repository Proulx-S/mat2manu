function ax = m2mAdopt(fig, name, srcAx, opts)
% M2MADOPT  Copy an axes drawn by an existing plotting function into layout box NAME.
%   f0 = plotSomething(data);                  % makes its own figure / tiledlayout
%   ax = m2mAdopt(fig, 'E', f0.Children.Children(2));
%
% For plotting code that builds its own figure or tiledlayout. The source axes and its
% figure are never modified. The copy is re-sized to the box (a re-layout at true size, not
% a scaled picture), its fonts are forced to the page font, and its legend and colorbar come
% with it:
%   - legend:   to box '<NAME>.leg' if the layout has one, else it keeps its Location;
%   - colorbar: to box '<NAME>.cb' if the layout has one, else a 2 mm bar 1 mm right of
%               the box (it cannot stay 'eastoutside': that shrinks the plot box).
%
% opts.legendBox    box for the legend   ('' = '<NAME>.leg' when present)
% opts.colorbarBox  box for the colorbar ('' = '<NAME>.cb'  when present)
% opts.keepAspect   keep 'axis image/equal' (false: the plot box fills the box)
% opts.keepFontSize keep the source's font sizes (false: use the page font size)
if nargin == 0
    help m2mAdopt
    ax = struct('legendBox', '', 'colorbarBox', '', 'keepAspect', false, 'keepFontSize', false);
    return
end
def = struct('legendBox', '', 'colorbarBox', '', 'keepAspect', false, 'keepFontSize', false);
if nargin < 4, opts = struct(); end
for f = fieldnames(def)', if ~isfield(opts, f{1}), opts.(f{1}) = def.(f{1}); end, end
S = getappdata(fig, 'm2m');
if isempty(S), error('m2m:notPage', 'Not an m2m page figure: create it with m2mPage.'); end
if ~isa(srcAx, 'matlab.graphics.axis.Axes') || ~isscalar(srcAx)
    error('m2m:adopt', 'm2mAdopt needs one Cartesian axes; got %s.', class(srcAx));
end
if numel(srcAx.YAxis) > 1
    error('m2m:adopt', 'yyaxis axes cannot be copied by copyobj; draw panel "%s" with m2mAxes.', name);
end
pos = m2mBox(S, name);
names = {S.L.boxes.name};
lgBox = opts.legendBox; if isempty(lgBox) && any(strcmp(names, [name '.leg'])), lgBox = [name '.leg']; end
cbBox = opts.colorbarBox; if isempty(cbBox) && any(strcmp(names, [name '.cb'])), cbBox = [name '.cb']; end

% capture what copyobj loses (matlab2manuscript docs/findings.md)
fsRuler = [srcAx.XAxis.FontSize srcAx.YAxis.FontSize];
fsLabel = [srcAx.XLabel.FontSize srcAx.YLabel.FontSize srcAx.Title.FontSize];
lg0 = srcAx.Legend; cb0 = srcAx.Colorbar;
src = srcAx;
if ~isempty(lg0), src = [src lg0]; end
if ~isempty(cb0), src = [src cb0]; end
new = copyobj(src, fig);  % axes alone would drop the legend and the colorbar
ax = new(1);
lg = ax.Legend; cb = ax.Colorbar;
if ~isempty(cb), cb.Location = 'manual'; end  % before touching the axes position
if ~opts.keepAspect
    ax.PlotBoxAspectRatioMode = 'auto';
    ax.DataAspectRatioMode = 'auto';
end
ax.Units = 'centimeters';
ax.PositionConstraint = 'innerposition';
ax.Position = pos;
ax.Tag = ['m2m:' name];

% fonts: page font everywhere; sizes from the page default unless asked to keep
fn = S.opts.fontName;
set(findall(ax, '-property', 'FontName'), 'FontName', fn);
ax.FontName = fn;
if opts.keepFontSize
    ax.XAxis.FontSize = fsRuler(1); ax.YAxis.FontSize = fsRuler(2);  % rulers first ...
    ax.XLabel.FontSize = fsLabel(1); ax.YLabel.FontSize = fsLabel(2); ax.Title.FontSize = fsLabel(3);
else
    fs = S.opts.fontSize;
    ax.FontSize = fs;
    ax.XAxis.FontSize = fs; ax.YAxis.FontSize = fs;  % ... then labels (setting a ruler resets its label)
    ax.XLabel.FontSize = fs; ax.YLabel.FontSize = fs; ax.Title.FontSize = fs;
    ax.Title.FontWeight = 'normal';
    set(findall(ax, 'Type', 'text'), 'FontSize', fs);
end
m2mRegister(fig, name, 'axes', ax);

if ~isempty(lg)
    lg.FontName = fn;
    if ~opts.keepFontSize, lg.FontSize = S.opts.fontSize; end
    if ~isempty(lgBox)
        m2mLegend(lg, lgBox);
    end
end
if ~isempty(cb)
    cb.FontName = fn;
    if ~opts.keepFontSize, cb.FontSize = S.opts.fontSize; end
    if ~isempty(cbBox)
        m2mColorbar(ax, cbBox);
    else
        cb.Units = 'centimeters';
        cb.Position = [pos(1) + pos(3) + 0.1, pos(2), 0.2, pos(4)];
        fprintf('m2mAdopt: panel %s colorbar placed 1 mm right of the box (no "%s.cb" box)\n', name, name);
    end
end
end
