function m2mRegister(fig, name, kind, h, ax)
% M2MREGISTER  Record that box NAME is filled by graphics object H (kind axes|colorbar|legend).
% One box, one object: a second claim on the same box is an error.
S = getappdata(fig, 'm2m');
if isempty(S), error('m2m:notPage', 'Not an m2m page figure: create it with m2mPage.'); end
k = find(strcmp({S.items.name}, name), 1);
if ~isempty(k)
    error('m2m:boxTaken', 'Box "%s" is already filled by a %s; one box holds one object.', ...
        name, S.items(k).kind);
end
if nargin < 5, ax = h; end
S.items(end+1) = struct('name', name, 'kind', kind, 'h', h, 'axes', ax);
setappdata(fig, 'm2m', S);
end
