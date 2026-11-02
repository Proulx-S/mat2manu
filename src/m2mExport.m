function info = m2mExport(fig, outPdf, opts)
% M2MEXPORT  Check the page against its layout, render the final PDF, refresh the preview.
%   info = m2mExport(fig, 'out/fig1.pdf')
%   info = m2mExport(fig, 'out/fig1.pdf', struct('route', 'R1'))
%
% Steps
%  1. Loud errors: a layout box no panel code filled (unless opts.allowUnused), or an axes
%     on the page that did not come from a box (m2mAxes / m2mAdopt).
%  2. Re-applies every box (so plot() resets cannot move anything) and stacks the axes in
%     the layout's z-order (later rect = on top: insets).
%  3. Warnings: a plot box MATLAB drew off its box (axis image, etc.), tick or axis labels
%     overlapping a neighbour or running off the page, a legend larger than its box, a page
%     width that is not a PNAS width, data or axis limits that changed since the last run while
%     annotations sit over that panel (their positions are now suspect).
%  4b. Lint of the final PDF (mutool trace): page size, fonts other than the page font, text
%     under opts.minTextPt, strokes under opts.minStrokePt, raster images under opts.minPpi.
%  4. Renders:
%     R2 (default): MATLAB prints the page to PDF; the human layers of the layout are
%        rendered to a transparent PDF (librsvg) and stamped on top (pypdf). Page cropped to
%        the exact layout size. MATLAB SVG is never used.
%     R1: MATLAB prints the page to SVG, which becomes the 'generated' layer of a copy of the
%        layout (<out>.svg); librsvg renders that to PDF.
%  5. Preview: a PNG of the page, linked from the layout's 'generated' layer (written into
%     the layout file only the first time; Inkscape reloads a changed linked image).
%
% opts.route        'R2' | 'R1'
% opts.allowUnused  false: an unfilled box is an error
% opts.preview      true: write <layout>_preview.png and link it
% opts.previewDpi   200
% opts.keep         false: delete intermediate files
% opts.checkLimits  true: compare each panel's data and limits with <out>.m2mstate.json
% opts.ackChanges   false: true accepts the current data/limits as the new baseline for
%                   panels with hand-drawn annotations over them (after checking them)
% opts.labelTolMm   0.2: overlap tolerance for the label check
% opts.minTextPt    6     lint: smallest text in the final PDF (PNAS)
% opts.enforceMinText true: raise any font size that MATLAB would print below minTextPt
%                   (it floors sizes to its pixel grid: at 95 ppi, 6 pt prints as 5.31 pt)
% opts.minStrokePt  0.25  lint: thinnest stroke
% opts.minPpi       300   lint: lowest raster resolution
if nargin == 0
    help m2mExport
    info = defaults();
    return
end
if nargin < 3, opts = struct(); end
def = defaults();
for f = fieldnames(def)', if ~isfield(opts, f{1}), opts.(f{1}) = def.(f{1}); end, end
S = getappdata(fig, 'm2m');
if isempty(S), error('m2m:notPage', 'Not an m2m page figure: create it with m2mPage.'); end
L = S.L;
tAll = tic;
info = struct('route', opts.route, 'pdf', '', 'svg', '', 'warnings', {{}}, 'deviationMm', struct(), ...
    'limitsChanged', {{}}, 'changeKind', {{}}, 'suspectAnnotations', {{}}, 'fonts', {{}}, 'timing', struct());

% ---------------------------------------------------------------- 1. loud errors
boxNames = {L.boxes.name};
used = {S.items.name};
unused = setdiff(boxNames, used, 'stable');
if ~isempty(unused) && ~opts.allowUnused
    error('m2m:unusedBox', ['Layout box(es) with no panel code: %s.\nDelete the rect(s) from the ' ...
        '"layout" layer, fill them (m2mAxes/m2mAdopt/m2mColorbar/m2mLegend), or pass opts.allowUnused.'], ...
        strjoin(unused, ', '));
end
allAx = findobj(fig, 'Type', 'axes', '-depth', 1);
tracked = [S.items(strcmp({S.items.kind}, 'axes')).h];
foreign = allAx(~ismember(allAx, tracked));
if ~isempty(foreign)
    error('m2m:foreignAxes', ['%d axes on the page did not come from a layout box (Tags: %s). ' ...
        'Create axes with m2mAxes or m2mAdopt.'], numel(foreign), strjoin(get(foreign, {'Tag'})', ', '));
end
bad = ~arrayfun(@isvalid, [S.items.h]);
if any(bad)
    error('m2m:deleted', 'The object(s) for box(es) %s were deleted after placement.', strjoin(used(bad), ', '));
end

% ---------------------------------------------------------------- 2. enforce geometry
for lg = findobj(fig, 'Type', 'legend')'
    if strcmp(lg.FontSizeMode, 'auto'), lg.FontSize = S.opts.fontSize; end  % auto = 0.9 x axes font
end
pixMm = 25.4 / get(0, 'ScreenPixelsPerInch');
info.pixelMm = pixMm;
order = arrayfun(@(it) L.boxes(strcmp(boxNames, it.name)).order, S.items);
for i = 1:numel(S.items)
    it = S.items(i);
    dev = m2mPlace(S, it.name, it.h);
    info.deviationMm.(matlab.lang.makeValidName(it.name)) = dev;
    switch it.kind
        case 'axes'
            % MATLAB snaps edges to its screen-pixel grid (1/ScreenPixelsPerInch): tolerate one pixel
            if max(abs(dev)) > pixMm + 0.01
                warn(sprintf('Panel %s: plot box drawn %.2f mm off its box (aspect constraint? axis image/equal)', ...
                    it.name, max(abs(dev))));
            end
        case 'legend'
            if any(dev > 0.1)
                warn(sprintf('Legend in box %s is %.1f x %.1f mm larger than the box', it.name, dev(3), dev(4)));
            end
    end
end
m2mDrawArrows(fig);  % data-anchored arrows, with the final boxes and limits
if opts.enforceMinText
    info.fontsBumped = bumpSmallText(fig, opts.minTextPt);
    if info.fontsBumped > 0
        fprintf('m2mExport: %d font size(s) raised so they print at >= %g pt\n', info.fontsBumped, opts.minTextPt);
    end
end
isAx = strcmp({S.items.kind}, 'axes');
[~, k] = sort(order(isAx), 'descend');
axTop = [S.items(isAx).h]; axTop = axTop(k);
others = fig.Children(~ismember(fig.Children, axTop));
fig.Children = [others(:); axTop(:)];  % legends/colorbars above all axes; later rect above earlier

% ---------------------------------------------------------------- 3. warnings
W = L.width_mm; H = L.height_mm;
if ~any(abs(W - [87 114.3 178]) < 0.05)
    warn(sprintf('Page width %.2f mm is not a PNAS width (87, 114.3, 178 mm)', W));
end
if H > 225, warn(sprintf('Page height %.1f mm exceeds PNAS''s 225 mm', H)); end
info.labelIssues = labelCheck(S, W, H, opts.labelTolMm);
for i = 1:numel(info.labelIssues), warn(info.labelIssues{i}); end

[base, ~] = strtok_ext(outPdf);
stateFile = [base '.m2mstate.json'];
state = struct();
for it = S.items(isAx)
    fld = matlab.lang.makeValidName(it.name);
    state.(fld) = struct('name', it.name, 'XLim', it.h.XLim, 'YLim', it.h.YLim, 'CLim', it.h.CLim, ...
        'data', dataHash(it.h));
end
hasSuspect = strings(0);
if opts.checkLimits && isfile(stateFile)
    old = jsondecode(fileread(stateFile));
    for f = fieldnames(state)'
        if isfield(old, f{1})
            a = state.(f{1}); b = old.(f{1});
            limCh = any(abs([a.XLim a.YLim a.CLim] - [b.XLim(:)' b.YLim(:)' b.CLim(:)']) > 1e-9 * max(1, abs([a.XLim a.YLim a.CLim])));
            datCh = ~isfield(b, 'data') || ~strcmp(a.data, b.data);
            if limCh || datCh
                info.limitsChanged{end+1} = a.name;
                info.changeKind{end+1} = strjoin([repmat({'limits'}, 1, limCh) repmat({'data'}, 1, datCh)], '+');
            end
        end
    end
    if ~isempty(info.limitsChanged)
        ab = jsondecode(m2mPy('annotboxes', L.file));
        for nm = info.limitsChanged
            b = L.boxes(strcmp(boxNames, nm{1}));
            for j = 1:numel(ab)
                a = ab(j);
                if a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
                    info.suspectAnnotations{end+1} = sprintf('%s (layer %s) over panel %s', a.id, a.layer, nm{1});
                    hasSuspect(end+1) = string(nm{1}); %#ok<AGROW>
                end
            end
        end
        if ~isempty(info.suspectAnnotations)
            warn(sprintf(['Data or axis limits changed in panel(s) %s since the annotations were last ' ...
                'acknowledged; these hand-drawn annotations may no longer point at the right data: %s. ' ...
                'Check them, then re-run with opts.ackChanges = true.'], ...
                strjoin(strcat(info.limitsChanged, {' ('}, info.changeKind, {')'}), ', '), ...
                strjoin(info.suspectAnnotations, '; ')));
        end
        % the baseline of a panel with suspect annotations stays until acknowledged, so the
        % warning repeats on every run instead of vanishing after one
        if ~opts.ackChanges
            for nm = unique(hasSuspect)
                fld = matlab.lang.makeValidName(char(nm));
                state.(fld) = old.(fld);
            end
        end
    end
end

% ---------------------------------------------------------------- 4. render
outDir = fileparts(outPdf);
if ~isempty(outDir) && ~isfolder(outDir), mkdir(outDir); end
tR = tic;
switch upper(opts.route)
    case 'R2'
        basePdf = [base '.matlab.pdf'];
        annPdf = [base '.annot.pdf'];
        t = tic; print(fig, '-dpdf', '-vector', basePdf); info.timing.matlabPrint = toc(t);
        t = tic; m2mPy('annot', L.file, annPdf); info.timing.annot = toc(t);
        t = tic; m2mPy('overlay', basePdf, annPdf, outPdf, sprintf('%.6f', W), sprintf('%.6f', H));
        info.timing.overlay = toc(t);
        if ~opts.keep, delete(basePdf); delete(annPdf); delete([base '.annot.annot.svg']); end
    case 'R1'
        msvg = [base '.matlab.svg'];
        info.svg = [base '.svg'];
        t = tic; print(fig, '-dsvg', '-vector', msvg); info.timing.matlabPrint = toc(t);
        t = tic; m2mPy('inject', L.file, msvg, info.svg, outPdf); info.timing.injectRender = toc(t);
        if ~opts.keep, delete(msvg); end
    otherwise
        error('m2m:route', 'Unknown route "%s" (R1 or R2)', opts.route);
end
info.timing.render = toc(tR);
info.pdf = outPdf;
writelines(jsonencode(state, 'PrettyPrint', true), stateFile);

% ---------------------------------------------------------------- 4b. lint the final PDF
% thresholds from matlab2manuscript docs/pnas-overleaf-pipeline-strategy.md section 9.6
t = tic;
try
    M = jsondecode(m2mPy('measure', outPdf));
catch e
    M = [];
    warn(['Final PDF not measured (needs mutool): ' e.message]);
end
if ~isempty(M)
    info.page = M.page;
    if abs(M.page.w_mm - W) > 0.01 || abs(M.page.h_mm - H) > 0.01
        warn(sprintf('PDF page is %.3f x %.3f mm, layout is %.3f x %.3f mm', M.page.w_mm, M.page.h_mm, W, H));
    end
    tx = M.texts; if iscell(tx), tx = [tx{:}]; end
    info.fonts = unique({tx.font});
    info.textSizes = unique([tx.size]);
    want = strrep(S.opts.fontName, ' ', '');
    odd = info.fonts(~startsWith(info.fonts, want));
    if ~isempty(odd), warn(sprintf('Fonts other than %s in the PDF: %s', S.opts.fontName, strjoin(odd, ', '))); end
    small = tx([tx.size] < opts.minTextPt - 1e-3);
    if ~isempty(small)
        warn(sprintf('%d text run(s) below %g pt (smallest %.2f pt: "%s"). MATLAB rounds sizes to its pixel grid and draws colorbar/legend/small-axes text at 90%%.', ...
            numel(small), opts.minTextPt, min([small.size]), small(find([small.size] == min([small.size]), 1)).text));
    end
    if ~isempty(M.strokes)
        st_ = M.strokes; if iscell(st_), st_ = [st_{:}]; end
        lw = [st_.lw]; info.minStrokePt = min(lw);
        if min(lw) < opts.minStrokePt - 1e-3
            warn(sprintf('%d stroke(s) thinner than %g pt (thinnest %.3f pt)', sum(lw < opts.minStrokePt - 1e-3), opts.minStrokePt, min(lw)));
        end
    end
    if ~isempty(M.images)
        im = M.images; if iscell(im), im = [im{:}]; end
        ppi = arrayfun(@(i) min(i.ppi), im);
        info.imagePpi = ppi;
        if any(ppi < opts.minPpi)
            warn(sprintf(['%d raster image(s) at %s ppi (< %g). MATLAB rasterizes images at screen ' ...
                'resolution even in vector output, whatever -r or Resolution says.'], sum(ppi < opts.minPpi), ...
                mat2str(round(ppi(ppi < opts.minPpi))), opts.minPpi));
        end
    end
end
info.timing.lint = toc(t);

% ---------------------------------------------------------------- 5. preview
if opts.preview
    t = tic;
    [lb, ~] = strtok_ext(L.file);
    png = [lb '_preview.png'];
    print(fig, '-dpng', sprintf('-r%d', opts.previewDpi), png);
    p = jsondecode(m2mPy('preview', L.file, png));
    info.previewWrittenToLayout = p.written;
    info.timing.preview = toc(t);
end
info.timing.total = toc(tAll);

    function warn(msg)
        info.warnings{end+1} = msg;
        warning('m2m:check', '%s', msg);
    end
end

% ======================================================================
function d = defaults()
d = struct('route', 'R2', 'allowUnused', false, 'preview', true, 'previewDpi', 200, ...
    'keep', false, 'checkLimits', true, 'ackChanges', false, 'enforceMinText', true, 'labelTolMm', 0.2, 'minTextPt', 6, 'minStrokePt', 0.25, ...
    'minPpi', 300);
end

function h = dataHash(ax)
% MD5 of the data plotted in AX (X/Y/Z/CData of its children, m2m arrows excluded).
md = java.security.MessageDigest.getInstance('MD5');
for c = allchild(ax)'
    if strcmp(c.HandleVisibility, 'off') && any(strcmp(c.Type, {'line', 'patch', 'text'})), continue; end
    for p = {'XData', 'YData', 'ZData', 'CData', 'Vertices', 'Data'}
        if isprop(c, p{1})
            v = c.(p{1});
            if isnumeric(v) || islogical(v)
                if ~isempty(v), md.update(typecast(double(v(:)'), 'int8')); end
            end
        end
    end
end
h = sprintf('%02x', typecast(md.digest(), 'uint8'));
end

function n = bumpSmallText(fig, minPt)
% MATLAB prints a font size s as floor(s*ppi/72) screen pixels. Raise every size that would
% print below minPt to the smallest pixel size that does not. Rulers first, then text objects
% (setting a ruler's size resets its label's size mode).
k = get(0, 'ScreenPixelsPerInch') / 72;
printed = @(s) floor(s * k + 1e-9) / k;
fix = ceil(minPt * k - 1e-9) / k;
n = 0;
for ax = findall(fig, 'Type', 'axes')'
    for r = [ax.XAxis(:); ax.YAxis(:)]'
        if printed(r.FontSize) < minPt - 1e-9, r.FontSize = fix; n = n + 1; end
    end
end
for h = findall(fig, '-property', 'FontSize')'
    if isa(h, 'matlab.graphics.axis.Axes'), continue; end
    if printed(h.FontSize) < minPt - 1e-9, h.FontSize = fix; n = n + 1; end
end
end

function [base, ext] = strtok_ext(f)
[p, n, ext] = fileparts(f);
base = fullfile(p, n);
end

function issues = labelCheck(S, W, H, tol)
% Extent of each axes with its labels (tightPosition IncludeLabels), each colorbar and legend
% (boxed or not), in mm, top-left origin. Overlaps between different panels, and anything off
% the page. A legend or colorbar without a box of its own is checked against its axes' box.
issues = {};
names = {S.L.boxes.name};
items = struct('label', {}, 'h', {}, 'owner', {}, 'box', {});
for it = S.items
    items(end+1) = struct('label', it.name, 'h', it.h, 'owner', it.axes, 'box', it.name); %#ok<AGROW>
end
boxed = [S.items.h];
for it = S.items(strcmp({S.items.kind}, 'axes'))
    for extra = {it.h.Legend, it.h.Colorbar}
        e = extra{1};
        if ~isempty(e) && isvalid(e) && ~any(boxed == e) && strcmp(e.Visible, 'on')
            items(end+1) = struct('label', sprintf('%s %s (no box)', it.name, e.Type), 'h', e, ...
                'owner', it.h, 'box', it.name); %#ok<AGROW>
        end
    end
end
n = numel(items);
ext = zeros(n, 4);
for i = 1:n
    h = items(i).h;
    if strcmp(h.Type, 'axes')
        p = tightPosition(h, 'IncludeLabels', true, 'Units', 'centimeters');
    else
        u = h.Units; h.Units = 'centimeters'; p = h.Position; h.Units = u;
    end
    p = p * 10;
    ext(i, :) = [p(1), H - p(2) - p(4), p(3), p(4)];
    if p(1) < -tol || p(2) < -tol || p(1) + p(3) > W + tol || p(2) + p(4) > H + tol
        issues{end+1} = sprintf('%s (%s) runs off the page by %.1f mm: it will be clipped', items(i).label, ...
            h.Type, max([-p(1), -p(2), p(1) + p(3) - W, p(2) + p(4) - H])); %#ok<AGROW>
    end
end
for i = 1:n
    for j = i+1:n
        if items(i).owner == items(j).owner, continue; end
        bi = S.L.boxes(strcmp(names, items(i).box)); bj = S.L.boxes(strcmp(names, items(j).box));
        if contains_(bi, bj) || contains_(bj, bi), continue; end  % insets sit inside by design
        ov = [min(ext(i,1)+ext(i,3), ext(j,1)+ext(j,3)) - max(ext(i,1), ext(j,1)), ...
              min(ext(i,2)+ext(i,4), ext(j,2)+ext(j,4)) - max(ext(i,2), ext(j,2))];
        if all(ov > tol)
            issues{end+1} = sprintf('%s and %s overlap (labels included) by %.1f x %.1f mm', ...
                items(i).label, items(j).label, ov(1), ov(2)); %#ok<AGROW>
        end
    end
end
end

function tf = contains_(a, b)
tf = b.x >= a.x - 1e-6 && b.y >= a.y - 1e-6 && b.x + b.w <= a.x + a.w + 1e-6 && b.y + b.h <= a.y + a.h + 1e-6;
end
