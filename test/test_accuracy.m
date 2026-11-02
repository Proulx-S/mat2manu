function T = test_accuracy(outDir)
% TEST_ACCURACY  Where things land in the final PDF, for both routes, versus the layout.
%   T = test_accuracy()          % writes into scratch/test_accuracy/
% Each plot box is painted a unique colour (makeFig1 markBoxes) and found in the final PDF
% (m2m_svg.py measure = mutool trace). Reports, per panel and route, the box edges' error in
% mm; the colorbar gradient's placement; the page size; fonts and text sizes; stroke widths.
% Passes if every edge is within one MATLAB screen pixel (25.4/ScreenPixelsPerInch mm).
here = fileparts(mfilename('fullpath')); root = fileparts(here);
addpath(fullfile(root, 'src'), fullfile(root, 'examples'));

if nargin < 1, outDir = fullfile(root, 'scratch', 'test_accuracy'); end
if ~isfolder(outDir), mkdir(outDir); end
lay = fullfile(outDir, 'fig1_layout.svg');
copyfile(fullfile(root, 'examples', 'fig1_layout.svg'), lay);
L = m2mLayout(lay);
sppi = get(0, 'ScreenPixelsPerInch'); pix = 25.4 / sppi;
fprintf('ScreenPixelsPerInch = %g -> MATLAB pixel = %.3f mm\n', sppi, pix);
warning('off', 'm2m:check');
T = table();
for route = {'R2', 'R1'}
    out = fullfile(outDir, ['fig1_' route{1} '.pdf']);
    t0 = tic;
    info = makeFig1(struct('layout', lay, 'out', out, 'route', route{1}, 'markBoxes', true, ...
        'export', struct('preview', false, 'checkLimits', false)));
    tRun = toc(t0);
    M = m2mMeasure(out);
    F = M.fills; if iscell(F), F = [F{:}]; end
    S = getappdata(info.fig, 'm2m');
    axItems = S.items(strcmp({S.items.kind}, 'axes'));
    for i = 1:numel(S.items)
        it = S.items(i);
        if ~strcmp(it.kind, 'axes'), continue; end
        k = find(strcmp({S.items.name}, it.name));
        want = [1, (k - 1) / 255, 1];
        hit = F(arrayfun(@(f) numel(f.color) == 3 && max(abs(f.color(:)' - want)) < 0.6 / 255, F));
        if isempty(hit), error('test:accuracy', 'Panel %s: box colour not found in %s', it.name, out); end
        a = arrayfun(@(f) f.bbox(3) * f.bbox(4), hit); bb = hit(a == max(a)).bbox(:)';
        b = L.boxes(strcmp({L.boxes.name}, it.name));
        e = [bb(1) - b.x, bb(2) - b.y, bb(1) + bb(3) - b.x - b.w, bb(2) + bb(4) - b.y - b.h];
        T = [T; table(string(route{1}), string(it.name), e(1), e(2), e(3), e(4), max(abs(e)), ...
            'VariableNames', {'route', 'panel', 'left', 'top', 'right', 'bottom', 'maxAbs'})]; %#ok<AGROW>
    end
    % colorbar gradient (an image) vs its box
    im = M.images; if iscell(im), im = [im{:}]; end
    b = L.boxes(strcmp({L.boxes.name}, 'B.cb'));
    d = arrayfun(@(m) max(abs(m.bbox(:)' - [b.x b.y b.w b.h])), im);
    [dm, j] = min(d); bb = im(j).bbox(:)';
    e = [bb(1) - b.x, bb(2) - b.y, bb(1) + bb(3) - b.x - b.w, bb(2) + bb(4) - b.y - b.h];
    T = [T; table(string(route{1}), "B.cb (gradient)", e(1), e(2), e(3), e(4), max(abs(e)), ...
        'VariableNames', T.Properties.VariableNames)]; %#ok<AGROW>
    tx = M.texts; if iscell(tx), tx = [tx{:}]; end
    st = M.strokes; if iscell(st), st = [st{:}]; end
    fprintf('\n== %s: page %.4f x %.4f mm (layout %.1f x %.1f); %.1f s for makeFig1 incl. export\n', route{1}, ...
        M.page.w_mm, M.page.h_mm, L.width_mm, L.height_mm, tRun);
    [g, fn, sz] = findgroups({tx.font}', [tx.size]');
    cnt = splitapply(@numel, (1:numel(tx))', g);
    for q = 1:numel(cnt), fprintf('   text %-14s %6.3f pt  x%d\n', fn{q}, sz(q), cnt(q)); end
    [g, lw] = findgroups(round([st.lw]', 3));
    cnt = splitapply(@numel, (1:numel(st))', g);
    fprintf('   strokes (pt: count): %s\n', strjoin(arrayfun(@(a, c) sprintf('%.3g:%d', a, c), lw, cnt, 'UniformOutput', false), '  '));
    fprintf('   image ppi: %s\n', mat2str(round(arrayfun(@(m) min(m.ppi), im))));
    fprintf('   export timing: %s\n', strjoin(cellfun(@(f) sprintf('%s %.2fs', f, info.timing.(f)), fieldnames(info.timing)', 'UniformOutput', false), ', '));
    close(info.fig);
end
disp(T);
writetable(T, fullfile(outDir, sprintf('accuracy_sppi%d.csv', sppi)));
bad = T.maxAbs > pix + 0.01;
if any(bad)
    disp(T(bad, :));
    error('test:accuracy', '%d box edge(s) off by more than one MATLAB pixel (%.3f mm)', sum(bad), pix);
end
fprintf('PASS: every box within %.3f mm (one pixel at %g ppi); worst %.3f mm\n', pix, sppi, max(T.maxAbs));
end
