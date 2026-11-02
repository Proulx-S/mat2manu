function m2mDrawArrows(fig)
% M2MDRAWARROWS  Draw the m2mDataArrow specs with the final box and limits (called by
% m2mExport after the boxes are re-applied). Limits are frozen first so the arrows cannot
% rescale the axes; arrows from an earlier export of the same figure are replaced.
S = getappdata(fig, 'm2m');
if ~isfield(S, 'arrows'), return; end
for i = 1:numel(S.arrows)
    a = S.arrows(i);
    delete(a.h(isgraphics(a.h)));
    ax = a.ax;
    ax.XLim = ax.XLim; ax.YLim = ax.YLim;  % freeze
    u = ax.Units; ax.Units = 'centimeters'; p = ax.Position * 10; ax.Units = u;  % mm
    sx = diff(ax.XLim) / p(3); sy = diff(ax.YLim) / p(4);  % data units per mm
    if strcmp(ax.XDir, 'reverse'), sx = -sx; end
    if strcmp(ax.YDir, 'reverse'), sy = -sy; end
    o = a.opts;
    if isempty(o.fontSize), o.fontSize = S.opts.fontSize; end
    v = a.off / norm(a.off);                               % tip -> tail, mm
    base = o.headMm * v; n = [-v(2) v(1)] * o.headMm * 0.4; % head, mm
    hx = a.xy(1) + [0, base(1) + n(1), base(1) - n(1)] * sx;
    hy = a.xy(2) + [0, base(2) + n(2), base(2) - n(2)] * sy;
    h1 = line(ax, a.xy(1) + [base(1) a.off(1)] * sx, a.xy(2) + [base(2) a.off(2)] * sy, ...
        'Color', o.color, 'LineWidth', o.lineWidth, 'Clipping', 'off', 'HandleVisibility', 'off');
    h2 = patch(ax, hx, hy, o.color, 'EdgeColor', 'none', 'Clipping', 'off', 'HandleVisibility', 'off');
    h = [h1 h2];
    if ~isempty(a.label)
        ha = 'left'; if v(1) < -0.3, ha = 'right'; elseif abs(v(1)) <= 0.3, ha = 'center'; end
        va = 'bottom'; if v(2) < -0.3, va = 'top'; elseif abs(v(2)) <= 0.3, va = 'middle'; end
        tail = a.off + o.gapMm * v;
        h(end+1) = text(ax, a.xy(1) + tail(1) * sx, a.xy(2) + tail(2) * sy, a.label, 'Color', o.color, ...
            'FontSize', o.fontSize, 'FontName', S.opts.fontName, 'HorizontalAlignment', ha, ...
            'VerticalAlignment', va, 'Clipping', 'off', 'HandleVisibility', 'off');
    end
    S.arrows(i).h = h;
end
setappdata(fig, 'm2m', S);
end
