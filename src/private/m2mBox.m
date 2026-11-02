function [posCm, b] = m2mBox(S, name)
% M2MBOX  Box NAME from the layout in S as a MATLAB figure position [x y w h] in cm
% (bottom-left origin). Errors loudly, listing the layout's boxes, if NAME is not there.
names = {S.L.boxes.name};
k = find(strcmp(names, name));
if isempty(k)
    error('m2m:noBox', ['Panel code asks for box "%s", which the layout %s does not have.\n' ...
        'Boxes in the layout: %s\nDraw a rect labelled "%s" in the "layout" layer, or fix the name.'], ...
        name, S.L.file, strjoin(names, ', '), name);
end
b = S.L.boxes(k);
posCm = [b.x, S.L.height_mm - b.y - b.h, b.w, b.h] / 10;
end
