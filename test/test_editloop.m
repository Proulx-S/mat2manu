function E = test_editloop(outDir)
% TEST_EDITLOOP  Edit the layout with real Inkscape (CLI actions), re-run, check the result.
% Edits: move A by (+6, +2) mm, scale D x1.15, delete G, add H (a duplicate of C, relabelled,
% moved into G's place). Then:
%   1. unchanged panel code   -> loud error: code for G has no box
%   2. G's code skipped       -> loud error: box H has no code
%   3. H's code added         -> renders; every box (A, D, H included) lands where Inkscape
%                                put it, within one MATLAB pixel
% Also: a rotated box and a duplicated (same-label) box fail loudly at read time.
here = fileparts(mfilename('fullpath')); root = fileparts(here);
addpath(fullfile(root, 'src'), fullfile(root, 'examples'));
if nargin < 1, outDir = fullfile(root, 'scratch', 'test_editloop'); end
if isfolder(outDir), rmdir(outDir, 's'); end
mkdir(outDir);
base = fullfile(root, 'examples', 'fig1_layout.svg');
lay = fullfile(outDir, 'fig1_layout.svg');
px = 96 / 25.4;  % inkscape --actions translate in px
inkscape(base, lay, sprintf(['select-by-id:boxA;transform-translate:%g,%g;select-clear;' ...
    'select-by-id:boxD;transform-scale:1.15;select-clear;select-by-id:boxG;delete-selection;' ...
    'select-by-id:boxC;duplicate;object-set-attribute:inkscape:label,H;transform-translate:%g,%g'], ...
    6 * px, 2 * px, 88 * px, 46 * px));
L = m2mLayout(lay);
fprintf('After Inkscape: %s\n', strjoin(arrayfun(@(b) sprintf('%s[%.2f %.2f %.2f %.2f]', b.name, b.x, b.y, b.w, b.h), ...
    L.boxes, 'UniformOutput', false), ' '));
warning('off', 'm2m:check');
E = struct();
o = struct('layout', lay, 'out', fullfile(outDir, 'fig1.pdf'), 'markBoxes', true, ...
    'export', struct('preview', false, 'checkLimits', false));
% 1. panel code for a deleted box
E.err1 = expectError(@() makeFig1(o), 'm2m:noBox');
% 2. a new box with no code
o.skip = {'G'};
E.err2 = expectError(@() makeFig1(o), 'm2m:unusedBox');
% 3. code for the new box
o.extra = {'H'};
info = makeFig1(o);
M = m2mMeasure(o.out);
S = getappdata(info.fig, 'm2m');
pix = 25.4 / get(0, 'ScreenPixelsPerInch');
worst = 0;
for k = find(strcmp({S.items.kind}, 'axes'))
    want = [1, (k - 1) / 255, 1];
    hit = M.fills(arrayfun(@(f) numel(f.color) == 3 && max(abs(f.color(:)' - want)) < 0.6 / 255, M.fills));
    a = arrayfun(@(f) f.bbox(3) * f.bbox(4), hit); bb = hit(a == max(a)).bbox(:)';
    b = L.boxes(strcmp({L.boxes.name}, S.items(k).name));
    e = max(abs([bb(1) - b.x, bb(2) - b.y, bb(1) + bb(3) - b.x - b.w, bb(2) + bb(4) - b.y - b.h]));
    fprintf('   %-7s max edge error %.3f mm\n', S.items(k).name, e);
    worst = max(worst, e);
end
E.worstMm = worst;
E.warnings = info.warnings;
fprintf('   warnings: %s\n', strjoin(info.warnings, ' | '));
close(info.fig);
assert(worst <= pix + 0.01, 'a box landed more than one pixel off after the edit');
% 4. rotated / duplicated boxes fail at read time
inkscape(base, fullfile(outDir, 'rot.svg'), 'select-by-id:boxE;transform-rotate:15');
E.err4 = expectError(@() m2mLayout(fullfile(outDir, 'rot.svg')), 'm2m:svg');
inkscape(base, fullfile(outDir, 'dup.svg'), 'select-by-id:boxC;duplicate');
E.err5 = expectError(@() m2mLayout(fullfile(outDir, 'dup.svg')), 'm2m:svg');
fprintf('PASS: edit loop (worst box error %.3f mm)\n', worst);
end

function msg = expectError(f, id)
try
    f();
catch e
    if ~strcmp(e.identifier, id)
        rethrow(e);
    end
    msg = e.message;
    fprintf('   expected error %s:\n      %s\n', id, strrep(msg, newline, [newline '      ']));
    return
end
error('test:editloop', 'expected error %s, got none', id);
end

function inkscape(src, dst, actions)
cmd = sprintf('env -u LD_LIBRARY_PATH inkscape "%s" --actions="%s;export-filename:%s;export-overwrite;export-do" 2>&1', ...
    src, actions, dst);
[st, out] = system(cmd);
assert(st == 0 && isfile(dst), 'inkscape failed: %s', out);
end
