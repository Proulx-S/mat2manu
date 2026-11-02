function lg = m2mLegend(lg, name)
% M2MLEGEND  Put legend LG with its top-left corner at the top-left of layout box NAME.
%   lg = m2mLegend(legend(ax, 'show'), 'A.leg')
% The legend keeps its natural size (set by its text); m2mExport warns if it is larger
% than the box.
if nargin == 0
    help m2mLegend
    lg = struct();
    return
end
fig = ancestor(lg, 'figure');
S = getappdata(fig, 'm2m');
if isempty(S), error('m2m:notPage', 'Not an m2m page figure: create it with m2mPage.'); end
m2mBox(S, name);  % errors now if the box does not exist
lg.Location = 'none';
lg.Units = 'centimeters';
m2mRegister(fig, name, 'legend', lg, lg.Axes);
m2mPlace(S, name, lg);
end
