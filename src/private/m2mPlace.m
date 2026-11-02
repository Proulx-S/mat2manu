function dev = m2mPlace(S, name, h)
% M2MPLACE  (Re)apply box NAME to graphics object H. Returns the deviation in mm between
% the box and where MATLAB actually put the object ([left bottom width height] differences;
% for legends only the top-left corner is placed, so width/height report the overflow).
pos = m2mBox(S, name);
switch h.Type
    case 'axes'
        h.Units = 'centimeters';
        h.PositionConstraint = 'innerposition';
        h.Position = pos;
        drawnow;
        tp = tightPosition(h, 'Units', 'centimeters');  % the plot box actually drawn
        dev = (tp - pos) * 10;
    case 'colorbar'
        h.Location = 'manual';
        h.Units = 'centimeters';
        h.Position = pos;
        dev = (h.Position - pos) * 10;
    case 'legend'
        h.Location = 'none';
        h.Units = 'centimeters';
        p = h.Position;
        h.Position = [pos(1), pos(2) + pos(4) - p(4), p(3), p(4)];
        dev = [0 0 max(0, p(3) - pos(3)) max(0, p(4) - pos(4))] * 10;
    otherwise
        error('m2m:place', 'Cannot place a %s', h.Type);
end
end
