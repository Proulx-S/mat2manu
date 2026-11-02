function cb = m2mColorbar(ax, name, varargin)
% M2MCOLORBAR  Colorbar of AX filling the layout box NAME (the gradient bar is the box).
%   cb = m2mColorbar(ax, 'B.cb')
%   cb = m2mColorbar(ax, 'B.cb', 'Ticks', [0 1])   % extra name-value pairs go to colorbar()
% Orientation follows the box: taller than wide gives a vertical bar.
if nargin == 0
    help m2mColorbar
    cb = struct();
    return
end
fig = ancestor(ax, 'figure');
S = getappdata(fig, 'm2m');
if isempty(S), error('m2m:notPage', 'Not an m2m page figure: create it with m2mPage.'); end
pos = m2mBox(S, name);
cb = ax.Colorbar;
if isempty(cb), cb = colorbar(ax); end
if pos(4) >= pos(3), loc = 'eastoutside'; else, loc = 'southoutside'; end
cb.Location = loc;  % sets the orientation and tick side ...
cb.Location = 'manual';  % ... then decouple it from the axes box
cb.Units = 'centimeters';
cb.Position = pos;
cb.FontSize = S.opts.fontSize;  % MATLAB's default is 90% of the axes font
if ~isempty(varargin), set(cb, varargin{:}); end
m2mRegister(fig, name, 'colorbar', cb, ax);
end
