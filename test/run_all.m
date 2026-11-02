% RUN_ALL  Every mat2manu test, from the repo root:  matlab -batch "run('test/run_all.m')"
% Needs: inkscape 1.2, rsvg-convert, mutool, pdffonts, python3 (+ pypdf: ~/opt/mat2manu-py
% or $M2M_PYTHON), and an X display (MATLAB's print hangs without one on tako).
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'test'));
[st, out] = system(sprintf('env -u LD_LIBRARY_PATH python3 "%s"', fullfile(root, 'test', 'test_layout.py')));
disp(out); assert(st == 0, 'test_layout.py failed');
test_accuracy();
test_regenerate();
test_editloop();
disp('ALL TESTS PASSED');
