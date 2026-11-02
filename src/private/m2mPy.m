function out = m2mPy(varargin)
% M2MPY  Run src/m2m_svg.py with the given arguments; error loudly on failure.
%   out = m2mPy('layout', 'fig1_layout.svg')
% Python: $M2M_PYTHON, else ~/opt/mat2manu-py/bin/python (has pypdf), else python3.
% MATLAB's LD_LIBRARY_PATH is dropped so rsvg-convert links against its own libraries.
py = getenv('M2M_PYTHON');
if isempty(py)
    py = fullfile(getenv('HOME'), 'opt', 'mat2manu-py', 'bin', 'python');
    if ~isfile(py), py = 'python3'; end
end
script = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'm2m_svg.py');
args = cellfun(@(a) ['"' char(a) '"'], varargin, 'UniformOutput', false);
cmd = sprintf('env -u LD_LIBRARY_PATH NO_COLOR=1 PYTHON_COLORS=0 "%s" "%s" %s 2>&1', py, script, strjoin(args, ' '));
[st, out] = system(cmd);
if st ~= 0
    msg = strtrim(out);
    k = strfind(msg, 'M2M-ERROR: ');
    if ~isempty(k), msg = msg(k(end)+11:end); end
    error('m2m:svg', 'm2m_svg.py %s failed:\n%s', char(varargin{1}), msg);
end
end
