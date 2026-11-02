function f = plotTiledPair(t, Y, names)
% PLOTTILEDPAIR  Stand-in for an existing plotting function: it makes its OWN figure and a
% 1x2 tiledlayout (as Seb's plotting code does), a mean +- SD band per condition, a legend
% outside the plot box. Synthetic use only. Nothing here knows about mat2manu.
f = figure('Visible', 'off', 'Color', 'k');  % dark style of a diagnostic figure
tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact');
cols = hsv2rgb([0.58 0.9 1; 0.08 0.9 1]);
for k = 1:2
    ax = nexttile(tl);
    hold(ax, 'on');
    for c = 1:size(Y, 3)
        m = mean(Y(:, :, c, k), 1); s = std(Y(:, :, c, k), 0, 1);
        fill(ax, [t fliplr(t)], [m - s fliplr(m + s)], cols(c, :), 'EdgeColor', 'none', ...
            'FaceAlpha', 0.3, 'HandleVisibility', 'off');
        plot(ax, t, m, 'Color', cols(c, :), 'LineWidth', 1.5, 'DisplayName', names{c});
    end
    xlabel(ax, 'time (s)'); ylabel(ax, '\DeltaS/S (%)');
    title(ax, sprintf('condition %d', k));
    ax.FontSize = 12;  % big diagnostic fonts: m2mAdopt resets them to the page size
    if k == 2, legend(ax, 'Location', 'eastoutside'); end
end
end
