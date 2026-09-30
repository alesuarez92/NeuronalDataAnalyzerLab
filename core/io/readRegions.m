function [R, notes] = readRegions(p)
% readRegions - Regions (polygons) drawn in ImageJ / Fiji or QuPath, for Histology.
%
% [R, notes] = readRegions(file)
%
% Reads:
%   .roi          one ImageJ ROI (ImageJ's RoiDecoder layout: big-endian,
%                 'Iout' at 0; version @4, type @6, top / left / bottom /
%                 right @8-14, number of points @16 (int32 @18 when 0),
%                 options @50 (128 = sub-pixel coordinates), second header
%                 offset @60 with the name offset / length @16 / @20 of it;
%                 points at 64: x then y as int16 relative to left / top,
%                 or float32 absolute coordinates after them)
%   .zip          ImageJ's RoiSet.zip (one .roi per region)
%   .geojson / .json   QuPath (or any) GeoJSON: Feature / FeatureCollection /
%                 array of features with Polygon or MultiPolygon geometry;
%                 the name from properties.name, else
%                 properties.classification.name
% Areas are kept: polygon, freehand, traced, rectangle and oval ROIs (an
% oval becomes a 72-point polygon); lines and points are skipped, and so
% are composite ImageJ shapes and polygon holes (notes says so).
% Coordinates: ImageJ and QuPath put the pixel corner at 0, so 0.5 is
% added to give MATLAB pixel coordinates (pixel centres at 1, 2, ...).
%
% Output R: struct array name, xy (K x 2, [x y] pixels), source (file
% name). notes: cellstr. Errors: NeuroAnalyzer:io:fileNotFound,
% NeuroAnalyzer:io:regions. Base MATLAB (unzip, jsondecode); also runs in
% GNU Octave.
%
if exist(p, 'file') ~= 2
    error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', p);
end
[~, base, ext] = fileparts(p);
R = struct('name', {}, 'xy', {}, 'source', {});
notes = {};
switch lower(ext)
    case '.roi'
        [r, n] = readRoi(p, base);
        R = [R r]; notes = [notes n];
    case '.zip'
        d = tempname;
        mkdir(d);
        c = onCleanup(@() rmdir(d, 's'));
        files = cellstr(unzip(p, d));
        for k = 1:numel(files)                       % Octave gives names relative to d
            if exist(files{k}, 'file') ~= 2, files{k} = fullfile(d, files{k}); end
        end
        files = sort(files(~cellfun(@isempty, regexpi(files, '\.roi$', 'once'))));
        for k = 1:numel(files)
            [~, b] = fileparts(files{k});
            [r, n] = readRoi(files{k}, b);
            R = [R r]; notes = [notes n]; %#ok<AGROW>
        end
    case {'.geojson', '.json'}
        [R, notes] = readGeoJSON(p);
    otherwise
        error('NeuroAnalyzer:io:regions', ['%s%s: regions are read from ImageJ .roi / RoiSet.zip files ' ...
            'or QuPath GeoJSON (.geojson).'], base, ext);
end
[~, b, e] = fileparts(p);
for k = 1:numel(R), R(k).source = [b e]; end
if isempty(R)
    notes{end+1} = sprintf('%s%s holds no areas.', b, e);
end
end

%% ---------------------------------------------------------------- ImageJ
function [R, notes] = readRoi(f, defaultName)
R = struct('name', {}, 'xy', {}, 'source', {});
notes = {};
fid = fopen(f, 'r', 'ieee-be');
if fid < 0, error('NeuroAnalyzer:io:regions', 'Cannot open %s', f); end
b = fread(fid, Inf, 'uint8=>uint8')';
fclose(fid);
if numel(b) < 64 || ~strcmp(char(b(1:4)), 'Iout')
    error('NeuroAnalyzer:io:regions', '%s is not an ImageJ ROI (it does not start with Iout).', defaultName);
end
version = u16(b, 4);
type = double(b(7));
top = s16(b, 8); left = s16(b, 10); bottom = s16(b, 12); right = s16(b, 14);
n = u16(b, 16);
options = u16(b, 50);
shapeSize = s32(b, 36);
name = defaultName;
h2 = s32(b, 60);
if h2 > 0 && h2 + 24 <= numel(b)
    off = s32(b, h2 + 16); len = s32(b, h2 + 20);
    if off > 0 && len > 0 && off + 2 * len <= numel(b)
        u = double(b(off+1:2:off+2*len)) * 256 + double(b(off+2:2:off+2*len));
        name = char(u(u < 65536));
    end
end
if shapeSize > 0
    notes{end+1} = sprintf('%s: a composite ImageJ shape, not read (split it into simple ROIs in ImageJ).', name);
    return;
end
switch type
    case 1                                                      % rectangle
        xy = [left top; right top; right bottom; left bottom];
    case 2                                                      % oval
        a = (0:71)' / 72 * 2 * pi;
        cx = (left + right) / 2; cy = (top + bottom) / 2;
        xy = [cx + (right - left) / 2 * cos(a), cy + (bottom - top) / 2 * sin(a)];
    case {0, 7, 8}                                              % polygon, freehand, traced
        if n == 0 && numel(b) >= 22, n = s32(b, 18); end
        sub = bitand(options, 128) ~= 0 && version >= 222;
        base = 64;
        if sub
            fb = base + 4 * n;
            if fb + 8 * n > numel(b)
                error('NeuroAnalyzer:io:regions', '%s: the ROI file is cut short.', name);
            end
            x = typecast(fliplr(b(fb+1:fb+4*n)), 'single'); x = double(fliplr(x));
            y = typecast(fliplr(b(fb+4*n+1:fb+8*n)), 'single'); y = double(fliplr(y));
            xy = [x(:) y(:)];
        else
            if base + 4 * n > numel(b)
                error('NeuroAnalyzer:io:regions', '%s: the ROI file is cut short.', name);
            end
            x = zeros(n, 1); y = zeros(n, 1);
            for i = 1:n
                x(i) = left + max(0, s16(b, base + 2 * (i - 1)));
                y(i) = top + max(0, s16(b, base + 2 * n + 2 * (i - 1)));
            end
            xy = [x y];
        end
    otherwise
        kinds = {'line', 'freehand line', 'segmented line', 'no ROI', '', '', 'angle', 'point'};
        k = type - 2;
        if k >= 1 && k <= numel(kinds) && ~isempty(kinds{k}), what = kinds{k}; else, what = sprintf('type %d', type); end
        notes{end+1} = sprintf('%s: an ImageJ %s ROI is not an area; skipped.', name, what);
        return;
end
if size(xy, 1) < 3
    notes{end+1} = sprintf('%s: fewer than 3 corners; skipped.', name);
    return;
end
R(1).name = name;
R(1).xy = xy + 0.5;
R(1).source = '';
end

function v = u16(b, o), v = double(b(o+1)) * 256 + double(b(o+2)); end
function v = s16(b, o), v = u16(b, o); if v >= 32768, v = v - 65536; end, end
function v = s32(b, o)
v = ((double(b(o+1)) * 256 + double(b(o+2))) * 256 + double(b(o+3))) * 256 + double(b(o+4));
if v >= 2^31, v = v - 2^32; end
end

%% --------------------------------------------------------------- GeoJSON
function [R, notes] = readGeoJSON(p)
R = struct('name', {}, 'xy', {}, 'source', {});
notes = {};
J = jsondecode(fileread(p));
feats = features(J);
holes = 0;
for k = 1:numel(feats)
    f = feats{k};
    if ~isfield(f, 'geometry') || isempty(f.geometry), continue; end
    g = f.geometry;
    name = '';
    if isfield(f, 'properties') && isstruct(f.properties)
        pr = f.properties;
        if isfield(pr, 'name') && ischar(pr.name), name = pr.name; end
        if isempty(name) && isfield(pr, 'classification') && isstruct(pr.classification) && ...
                isfield(pr.classification, 'name')
            name = pr.classification.name;
        end
    end
    if isempty(name), name = sprintf('Region %d', numel(R) + 1); end
    switch g.type
        case 'Polygon',      polys = {g.coordinates};
        case 'MultiPolygon', polys = multi(g.coordinates);
        otherwise
            notes{end+1} = sprintf('%s: a %s, not an area; skipped.', name, g.type); %#ok<AGROW>
            continue;
    end
    for j = 1:numel(polys)
        rings = ringsOf(polys{j});
        if isempty(rings), continue; end
        holes = holes + numel(rings) - 1;
        nm = name;
        if numel(polys) > 1, nm = sprintf('%s %d', name, j); end
        xy = rings{1};
        if size(xy, 1) > 3 && isequal(xy(1, :), xy(end, :)), xy = xy(1:end-1, :); end
        R(end+1) = struct('name', nm, 'xy', xy + 0.5, 'source', ''); %#ok<AGROW>
    end
end
if holes > 0
    notes{end+1} = sprintf('%d hole(s) inside regions were ignored (the outer outline is used).', holes);
end
end

function c = features(J)
if iscell(J)
    c = J(:)';
elseif isstruct(J) && numel(J) > 1
    c = num2cell(J(:)');
elseif isfield(J, 'type') && strcmp(J.type, 'FeatureCollection')
    c = features(J.features);
elseif isfield(J, 'type') && strcmp(J.type, 'Feature')
    c = {J};
elseif isfield(J, 'type') && any(strcmp(J.type, {'Polygon', 'MultiPolygon'}))
    c = {struct('geometry', J)};
else
    c = {};
end
end

%% ringsOf - Polygon coordinates (as jsondecode gives them) to a cell of K x 2 rings
function rings = ringsOf(c)
if isnumeric(c)
    if ndims(c) == 3                                   % 1 x K x 2 (one ring, equal ring sizes)
        rings = arrayfun(@(i) reshape(c(i, :, :), [], 2), 1:size(c, 1), 'UniformOutput', false);
    elseif size(c, 2) == 2
        rings = {c};
    else
        rings = {};
    end
else
    rings = {};
    for k = 1:numel(c)
        r = c{k};
        if iscell(r), r = cell2mat(cellfun(@(v) v(:)', r(:), 'UniformOutput', false)); end
        if isnumeric(r) && ndims(r) == 3, r = reshape(r, [], 2); end
        if isnumeric(r) && size(r, 2) == 2, rings{end+1} = double(r); end %#ok<AGROW>
    end
end
end

function polys = multi(c)
if isnumeric(c)
    if ndims(c) == 4
        polys = arrayfun(@(i) reshape(c(i, :, :, :), size(c, 2), size(c, 3), 2), 1:size(c, 1), 'UniformOutput', false);
    else
        polys = {c};
    end
else
    polys = c(:)';
end
end
