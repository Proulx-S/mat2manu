function ax = m2mAxes(fig, name, varargin)
% M2MAXES  Axes whose plot box is the layout box NAME, at true size.
%   ax = m2mAxes(fig, 'A')
%   ax = m2mAxes(fig, 'A', 'Box', 'on')        % extra name-value pairs go to axes()
%
% The box is the inner position (the plot box); tick labels, axis labels and titles spill
% outside it. m2mExport re-applies the box at the end, so plot() resetting the axes
% (NextPlot 'replace') cannot move it. Errors if NAME is not in the layout or already used.
if nargin == 0
    help m2mAxes
    ax = struct();
    return
end
S = getappdata(fig, 'm2m');
if isempty(S), error('m2m:notPage', 'Not an m2m page figure: create it with m2mPage.'); end
pos = m2mBox(S, name);
ax = axes(fig, 'Units', 'centimeters', 'Position', pos, 'PositionConstraint', 'innerposition', ...
    'Tag', ['m2m:' name], varargin{:});
m2mRegister(fig, name, 'axes', ax);
end
