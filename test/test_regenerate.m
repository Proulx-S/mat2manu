function R = test_regenerate(outDir)
% TEST_REGENERATE  Change the data and the axis limits, re-run, and check:
%   1. the human layers of the layout are untouched (C14N hash), and the layout file is not
%      rewritten at all after the first run (the preview link is already in place);
%   2. the hand-drawn annotations land at the same place in the final PDF (they survive);
%   3. how far the data under a hand-drawn arrow moves (the drift inherent to the model),
%      versus a data-anchored arrow drawn by MATLAB (m2mDataArrow), which should not drift;
%   4. m2mExport names the annotations over a panel whose limits changed.
% Three runs on panel A: base (peak at t=5 s, ylim [-0.5 2.5]); limits only ([-0.5 4]);
% data and limits (peak at 8 s, ylim [-0.5 4]).
here = fileparts(mfilename('fullpath')); root = fileparts(here);
addpath(fullfile(root, 'src'), fullfile(root, 'examples'));
if nargin < 1, outDir = fullfile(root, 'scratch', 'test_regenerate'); end
if isfolder(outDir), rmdir(outDir, 's'); end
mkdir(outDir);
lay = fullfile(outDir, 'fig1_layout.svg');
copyfile(fullfile(root, 'examples', 'fig1_layout.svg'), lay);
L = m2mLayout(lay); bA = L.boxes(strcmp({L.boxes.name}, 'A'));
warning('off', 'm2m:check');
h0 = humanHash(root, lay);
runs = {struct('peakT', 5, 'ylimA', [-0.5 2.5]), struct('peakT', 5, 'ylimA', [-0.5 4]), ...
        struct('peakT', 8, 'ylimA', [-0.5 4])};
names = {'base', 'limits', 'data+limits'};
R = struct([]);
for r = 1:numel(runs)
    o = runs{r}; o.layout = lay; o.out = fullfile(outDir, 'fig1.pdf');
    info = makeFig1(o);
    M = m2mMeasure(o.out);
    fileBytes = fileread(lay);
    % hand-drawn arrow (stroke #c0392b) and the data arrow head (fill [0.1 0.5 0.2]) in the PDF
    hand = M.strokes(arrayfun(@(s) numel(s.color) == 3 && max(abs(s.color(:)' - [192 57 43] / 255)) < 1e-3, M.strokes));
    dat = M.fills(arrayfun(@(f) numel(f.color) == 3 && max(abs(f.color(:)' - [0.1 0.5 0.2])) < 2e-3, M.fills));
    % where the panel-A peak is, in mm, from the box and the final limits
    S = getappdata(info.fig, 'm2m'); ax = S.items(strcmp({S.items.name}, 'A')).h;
    ln = findobj(ax, 'Type', 'line', 'DisplayName', 'response');
    near = abs(ln.XData - o.peakT) < 1; y = ln.YData; y(~near) = -Inf; [ypk, k] = max(y); tpk = ln.XData(k);
    pk = [bA.x + (tpk - ax.XLim(1)) / diff(ax.XLim) * bA.w, bA.y + (ax.YLim(2) - ypk) / diff(ax.YLim) * bA.h];
    R(r).run = names{r};
    R(r).humanLayersUnchanged = isequal(humanHash(root, lay), h0);
    R(r).layoutBytes = fileBytes;
    R(r).handArrowBbox = hand(1).bbox(:)';
    R(r).dataHeadCenter = dat(1).bbox(1:2)' + dat(1).bbox(3:4)' / 2;
    R(r).peakMm = pk;
    R(r).warnings = info.warnings;
    R(r).suspect = info.suspectAnnotations;
    close(info.fig);
end
% ------------------------------------------------------------------ report + assertions
fprintf('\n%-12s %-8s %-22s %-22s %-22s\n', 'run', 'human=', 'peak (mm)', 'hand arrow tail (mm)', 'data head ctr (mm)');
for r = 1:numel(R)
    fprintf('%-12s %-8d [%6.2f %6.2f]        [%6.2f %6.2f]        [%6.2f %6.2f]\n', R(r).run, R(r).humanLayersUnchanged, ...
        R(r).peakMm, R(r).handArrowBbox(1:2), R(r).dataHeadCenter);
end
for r = 2:numel(R)
    dPeak = R(r).peakMm - R(1).peakMm;
    dHand = R(r).handArrowBbox(1:2) - R(1).handArrowBbox(1:2);
    dData = R(r).dataHeadCenter - R(1).dataHeadCenter;
    fprintf(['%s vs base: data under the hand arrow moved %.2f mm ([%+.2f %+.2f]); hand arrow moved %.3f mm; ' ...
        'data arrow tracked the peak to %.3f mm\n'], R(r).run, norm(dPeak), dPeak, norm(dHand), norm(dData - dPeak));
    fprintf('   flagged: %s\n', strjoin(R(r).suspect, '; '));
    assert(norm(dHand) < 1e-3, 'hand-drawn arrow moved in the final PDF');
    assert(norm(dData - dPeak) < 0.3, 'data-anchored arrow did not follow the data');
    assert(any(contains(R(r).suspect, 'arrowA')), 'changed limits did not flag arrowA');
end
assert(all([R.humanLayersUnchanged]), 'a human layer changed');
% the warning persists until acknowledged, then clears
o = runs{3}; o.layout = lay; o.out = fullfile(outDir, 'fig1.pdf');
i4 = makeFig1(o); close(i4.fig);
assert(any(contains(i4.suspectAnnotations, 'arrowA')), 'warning vanished without acknowledgement');
o.export = struct('ackChanges', true); i5 = makeFig1(o); close(i5.fig);
o.export = struct(); i6 = makeFig1(o); close(i6.fig);
assert(isempty(i6.suspectAnnotations), 'warning persisted after acknowledgement');
fprintf('PASS: the drift warning repeats on re-runs until opts.ackChanges, then clears\n');
assert(isequal(R(2).layoutBytes, R(1).layoutBytes) && isequal(R(3).layoutBytes, R(1).layoutBytes), ...
    'layout file rewritten after the first run');
fprintf('PASS: human layers byte-identical (C14N) across runs; layout file not rewritten after run 1\n');
R = rmfield(R, 'layoutBytes');
end

function h = humanHash(root, lay)
py = fullfile(getenv('HOME'), 'opt', 'mat2manu-py', 'bin', 'python');
if ~isfile(py), py = 'python3'; end
[st, out] = system(sprintf('env -u LD_LIBRARY_PATH "%s" "%s" humanhash "%s"', py, fullfile(root, 'src', 'm2m_svg.py'), lay));
assert(st == 0, out);
h = jsondecode(out);
end
