function info = makeFig1(opts)
% MAKEFIG1  Example 178 mm figure: seven panels from synthetic data, laid out by
% examples/fig1_layout.svg (boxes A, A.leg, Ainset, B, B.cb, C, D, E, F, G).
%   info = makeFig1()                                  % defaults
%   info = makeFig1(struct('route', 'R1'))
%
% opts.layout     layout SVG                 (examples/fig1_layout.svg)
% opts.out        output PDF                 (scratch/out/fig1.pdf)
% opts.route      'R2' | 'R1'
% opts.seed       RNG seed for the synthetic data (1)
% opts.peakT      time of the panel-A peak, s (5): moves the data under the 'peak' arrow
% opts.ylimA      panel-A y limits ([-0.5 2.5])
% opts.dataArrow  true: also draw a data-anchored 'peak' arrow (m2mDataArrow), for comparison
%                 with the hand-drawn one in the layout's annotations layer
% opts.markBoxes  false: true paints each plot box a unique colour (accuracy tests)
% opts.skip       {}: panel names whose code is skipped (edit-loop tests)
% opts.extra      {}: extra panel names to draw (edit-loop tests: code without a box)
% opts.export     struct passed to m2mExport
if nargin == 0, opts = struct(); end
here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..', 'src'));
def = struct('layout', fullfile(here, 'fig1_layout.svg'), 'out', fullfile(here, '..', 'scratch', 'out', 'fig1.pdf'), ...
    'route', 'R2', 'seed', 1, 'dataArrow', true, 'peakT', 5, 'ylimA', [-0.5 2.5], 'markBoxes', false, ...
    'skip', {{}}, 'extra', {{}}, 'export', struct());
for f = fieldnames(def)', if ~isfield(opts, f{1}), opts.(f{1}) = def.(f{1}); end, end
rng(opts.seed);
fig = m2mPage(opts.layout);
c1 = [0.12 0.47 0.71]; c2 = [0.85 0.37 0.01];
do = @(n) ~any(strcmp(opts.skip, n));

% A: line + error band, legend in its own box, inset zoom
t = linspace(0, 20, 201);
if do('A')
    ax = m2mAxes(fig, 'A'); hold(ax, 'on');
    y = 2 * exp(-(t - opts.peakT).^2 / 2) + 0.1 * randn(size(t));
    s = 0.2 + 0.05 * rand(size(t));
    fill(ax, [t fliplr(t)], [y - s fliplr(y + s)], c1, 'EdgeColor', 'none', 'FaceAlpha', 0.25, 'HandleVisibility', 'off');
    plot(ax, t, y, 'Color', c1, 'LineWidth', 0.75, 'DisplayName', 'response');
    plot(ax, t, 0.5 * exp(-(t - 12).^2 / 8), '--', 'Color', c2, 'LineWidth', 0.75, 'DisplayName', 'model');
    ylim(ax, opts.ylimA); xlim(ax, [0 20]);
    xlabel(ax, 'time (s)'); ylabel(ax, 'signal (a.u.)');
    m2mLegend(legend(ax), 'A.leg');
    if opts.dataArrow  % mitigation for drift: the tip is a data point, drawn at export
        near = abs(t - opts.peakT) < 1; [ym, im] = max(y .* near + -1e9 * ~near);
        m2mDataArrow(ax, [t(im) ym], [-3.5 4.5], 'peak (data)', struct('color', [0.1 0.5 0.2]));
    end
    if do('Ainset')
        ai = m2mAxes(fig, 'Ainset'); hold(ai, 'on');
        k = t >= 10 & t <= 16;
        plot(ai, t(k), y(k), 'Color', c1, 'LineWidth', 0.5);
        xlim(ai, [10 16]); ai.FontSize = 6; ai.Box = 'on';
    end
end

% B: image + colorbar in its own box
if do('B')
    ax = m2mAxes(fig, 'B');
    [X, Y] = meshgrid(linspace(-3, 3, 64));
    imagesc(ax, linspace(-3, 3, 64), linspace(-3, 3, 64), exp(-(X.^2 + Y.^2)) + 0.05 * randn(64));
    colormap(ax, parula(256)); clim(ax, [0 1]);
    xlabel(ax, 'x (mm)'); ylabel(ax, 'y (mm)');
    if do('B.cb')
        cb = m2mColorbar(ax, 'B.cb'); cb.Label.String = 'amplitude';
    end
end

% C: scatter
if do('C')
    ax = m2mAxes(fig, 'C');
    x = randn(80, 1); scatter(ax, x, 0.6 * x + 0.4 * randn(80, 1), 6, c1, 'filled');
    xlabel(ax, 'predictor'); ylabel(ax, 'outcome'); box(ax, 'off');
end

% D: histogram
if do('D')
    ax = m2mAxes(fig, 'D'); hold(ax, 'on');
    histogram(ax, randn(500, 1), 30, 'FaceColor', c1, 'EdgeColor', 'none');
    histogram(ax, randn(500, 1) + 1.2, 30, 'FaceColor', c2, 'EdgeColor', 'none', 'FaceAlpha', 0.5);
    xlabel(ax, 'value'); ylabel(ax, 'count');
end

% E, F: adopted from a plotting function that makes its own tiledlayout figure
if do('E') || do('F')
    Yd = 0.3 * randn(12, numel(t), 2, 2) + permute([1; 0.6], [3 2 1]) .* exp(-(t - 6).^2 / 6);
    f0 = plotTiledPair(t, Yd, {'rest', 'task'});
    tiles = flipud(findobj(f0, 'Type', 'axes'));
    adopted = {};
    if do('E'), adopted{end+1} = m2mAdopt(fig, 'E', tiles(1)); end
    if do('F'), adopted{end+1} = m2mAdopt(fig, 'F', tiles(2)); end
    % the source labels use TeX '\Delta', which embeds MATLAB's Computer Modern (mwb_cmr10),
    % not Arial: use the Unicode character in Arial instead
    for k = 1:numel(adopted)
        set(adopted{k}.YLabel, 'Interpreter', 'none', 'String', [char(916) 'S/S (%)']);
    end
    close(f0);
end

% G: error bars
if do('G')
    ax = m2mAxes(fig, 'G');
    xg = 1:8; errorbar(ax, xg, 1 + 0.2 * xg + 0.2 * randn(1, 8), 0.1 + 0.1 * rand(1, 8), 'o-', ...
        'Color', c2, 'MarkerSize', 3, 'MarkerFaceColor', c2, 'LineWidth', 0.75, 'CapSize', 2);
    xlim(ax, [0.5 8.5]); xlabel(ax, 'session'); ylabel(ax, 'effect size');
end

% panel code with no box (edit-loop test)
for n = opts.extra, ax = m2mAxes(fig, n{1}); plot(ax, 1:3); end %#ok<NASGU>

if opts.markBoxes  % unique plot-box colours so the accuracy test can find each box in the PDF
    S = getappdata(fig, 'm2m');
    for i = 1:numel(S.items)
        if strcmp(S.items(i).kind, 'axes'), S.items(i).h.Color = [1, (i - 1) / 255, 1]; end
    end
end
eo = opts.export; eo.route = opts.route;
info = m2mExport(fig, opts.out, eo);
info.fig = fig;
end
