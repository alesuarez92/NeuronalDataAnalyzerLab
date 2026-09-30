function writeImageJRoi(file, xy, name, kind, subPixel)
% writeImageJRoi - Write one ImageJ .roi file (polygon, rectangle or oval), for tests and demos.
%
% writeImageJRoi(file, xy, name)                   polygon, integer corners
% writeImageJRoi(file, xy, name, 'polygon', true)  polygon, float corners
% writeImageJRoi(file, [left top right bottom], name, 'rect' | 'oval')
%
% xy: K x 2 [x y] in ImageJ coordinates (pixel corner at 0). Layout as
% readRegions reads it (ImageJ's RoiDecoder): 64-byte header, the
% corners, then a second header with the name (UTF-16). Version 228.
% Base MATLAB only; also runs in GNU Octave.
%
if nargin < 3 || isempty(name), name = ''; end
if nargin < 4 || isempty(kind), kind = 'polygon'; end
if nargin < 5, subPixel = false; end
h = zeros(1, 64, 'uint8');
h(1:4) = uint8('Iout');
h = put16(h, 4, 228);
switch kind
    case 'polygon'
        type = 0;
        left = floor(min(xy(:, 1))); top = floor(min(xy(:, 2)));
        right = ceil(max(xy(:, 1))); bottom = ceil(max(xy(:, 2)));
        n = size(xy, 1);
    case {'rect', 'oval'}
        type = 1 + strcmp(kind, 'oval');
        left = xy(1); top = xy(2); right = xy(3); bottom = xy(4);
        n = 0;
    otherwise
        error('NeuroAnalyzer:io:regions', 'kind must be polygon, rect or oval.');
end
h(7) = uint8(type);
h = put16(h, 8, top); h = put16(h, 10, left); h = put16(h, 12, bottom); h = put16(h, 14, right);
h = put16(h, 16, n);
if subPixel, h = put16(h, 50, 128); end
body = zeros(1, 0, 'uint8');
if n > 0
    xi = round(xy(:, 1)) - left; yi = round(xy(:, 2)) - top;
    for i = 1:n, body = [body be16(xi(i))]; end %#ok<AGROW>
    for i = 1:n, body = [body be16(yi(i))]; end %#ok<AGROW>
    if subPixel
        body = [body beSingle(xy(:, 1)) beSingle(xy(:, 2))];
    end
end
h2off = 64 + numel(body);
h = put32(h, 60, h2off);
h2 = zeros(1, 64, 'uint8');
nameOff = h2off + 64;
h2 = put32(h2, 16, nameOff);
h2 = put32(h2, 20, numel(name));
nm = zeros(1, 2 * numel(name), 'uint8');
u = double(name);
nm(1:2:end) = uint8(floor(u / 256));
nm(2:2:end) = uint8(mod(u, 256));
fid = fopen(file, 'w');
if fid < 0, error('NeuroAnalyzer:io:regions', 'Cannot write %s', file); end
fwrite(fid, [h body h2 nm], 'uint8');
fclose(fid);
end

function h = put16(h, o, v)
h(o+1:o+2) = be16(v);
end

function h = put32(h, o, v)
v = mod(round(v), 2^32);
h(o+1:o+4) = uint8([floor(v / 2^24), mod(floor(v / 2^16), 256), mod(floor(v / 256), 256), mod(v, 256)]);
end

function b = be16(v)
v = mod(round(v), 65536);
b = uint8([floor(v / 256), mod(v, 256)]);
end

function b = beSingle(v)
b = zeros(1, 4 * numel(v), 'uint8');
for i = 1:numel(v)
    b(4*i-3:4*i) = fliplr(typecast(single(v(i)), 'uint8'));
end
end
