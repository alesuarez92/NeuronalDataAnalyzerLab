function M = tiffMeta(info)
% tiffMeta - What a TIFF says about itself: pixel size, time, channels and page order.
%
% M = tiffMeta(imfinfo(file))
%
% One reading of the metadata the common microscope and slide software
% writes into TIFF files, for every window that opens TIFFs (Histology,
% ROI analysis, Laser speckle). Recognised (first match wins):
%   OME-TIFF      OME-XML in the first page's ImageDescription: Pixels
%                 DimensionOrder, SizeC / SizeZ / SizeT, PhysicalSizeX / Y /
%                 Z with their units (default um), TimeIncrement (+ unit,
%                 default s), Channel Name; the first Image only
%   ScanImage     'SI.' lines in the Software tag (2016 and later) or the
%                 ImageDescription: SI.hChannels.channelSave,
%                 SI.hRoiManager.scanFrameRate, pixelsPerLine,
%                 linesPerFrame, imagingFovUm (um per pixel),
%                 SI.hStackManager.numSlices / actualNumSlices /
%                 framesPerSlice, SI.hFastZ.enable /
%                 numDiscardFlybackFrames; frameTimestamps_sec of every
%                 page. Pages: channel fastest, then frame, then slice
%                 (flyback frames included), then volume
%   ImageJ        'ImageJ=' ImageDescription: channels, slices, frames
%                 (hyperstack order: channel fastest, then slice, then
%                 frame), unit (µm escapes decoded), spacing,
%                 finterval; pixel size = 1 / XResolution in that unit
%   Aperio (.svs) 'Aperio' ImageDescription: MPP (um per pixel), AppMag
%   plain TIFF    XResolution with ResolutionUnit centimeter or inch
%                 (72 / 96 / 300 dpi are screen or print defaults, not a
%                 scale, and are ignored)
%
% Output M:
%   source        'ome' | 'scanimage' | 'imagej' | 'aperio' | 'tiff'
%   pixelSizeUm   um per pixel in x (NaN when unknown); pixelSizeYUm
%   zStepUm       um between slices (NaN)
%   frameInterval s between frames (NaN); fps = 1 / frameInterval
%   nChannels, nSlices, nFrames   sizes (pages the file holds decide
%                 nFrames when the header says more)
%   pageMap       nChannels x nSlices x nFrames page numbers (1-based)
%   channelNames  1 x nChannels cellstr ('' when unknown)
%   t             1 x nFrames frame times (s) when the file has them, else []
%   magnification objective magnification (Aperio AppMag; NaN)
%   notes         cellstr: what was read, in plain words
%
% um = tiffMeta('unit', 'µm') gives the micrometres in one unit
% (NaN when not a length).
% Base MATLAB only (regular expressions, no xmlread); also runs in GNU
% Octave.
%
M = struct('source', 'tiff', 'pixelSizeUm', NaN, 'pixelSizeYUm', NaN, 'zStepUm', NaN, ...
    'frameInterval', NaN, 'fps', NaN, 'nChannels', 1, 'nSlices', 1, 'nFrames', numel(info), ...
    'pageMap', [], 'channelNames', {{''}}, 't', [], 'magnification', NaN, 'notes', {{}});
nPages = numel(info);
desc = textField(info(1), 'ImageDescription');
soft = textField(info(1), 'Software');
if ~isempty(regexp(desc, '<OME[\s>]', 'once'))
    M = fromOME(M, desc, nPages);
elseif ~isempty(regexp([soft newline desc], '(?m)^\s*SI[.\d]*\.', 'once'))
    M = fromScanImage(M, [soft newline desc], info);
elseif ~isempty(strfind(desc, 'ImageJ=')) %#ok<STREMP>
    M = fromImageJ(M, desc, info(1), nPages);
elseif strncmp(desc, 'Aperio', 6)
    M = fromAperio(M, desc);
else
    M.pixelSizeUm = plainResolution(info(1), 'XResolution');
    M.pixelSizeYUm = plainResolution(info(1), 'YResolution');
end
if ~isfinite(M.pixelSizeYUm), M.pixelSizeYUm = M.pixelSizeUm; end
if isfinite(M.frameInterval) && M.frameInterval > 0, M.fps = 1 / M.frameInterval; end
if isempty(M.pageMap)
    M.pageMap = pageMapOf('CZT', M.nChannels, M.nSlices, M.nFrames, nPages);
end
M.nFrames = size(M.pageMap, 3);
if ~isempty(M.t) && numel(M.t) ~= M.nFrames, M.t = []; end
M.channelNames(end+1:M.nChannels) = {''};
M.channelNames = M.channelNames(1:M.nChannels);
if isfinite(M.pixelSizeUm)
    M.notes{end+1} = sprintf('Pixel size %g um read from the file (%s).', M.pixelSizeUm, M.source);
end
if isfinite(M.fps)
    M.notes{end+1} = sprintf('Frame interval %g s (%g Hz) read from the file (%s).', M.frameInterval, M.fps, M.source);
end
end

%% ------------------------------------------------------------------ OME
function M = fromOME(M, xml, nPages)
M.source = 'ome';
img = regexp(xml, '<(\w+:)?Image[\s>].*?</(\w+:)?Image>', 'match', 'once');
if isempty(img), img = xml; end
px = regexp(img, '<(\w+:)?Pixels\s[^>]*>', 'match', 'once');
order = attr(px, 'DimensionOrder');
if isempty(order), order = 'XYCZT'; end
M.nChannels = attrNum(px, 'SizeC', 1);
M.nSlices = attrNum(px, 'SizeZ', 1);
M.nFrames = attrNum(px, 'SizeT', 1);
M.pixelSizeUm = attrNum(px, 'PhysicalSizeX', NaN) * unitUm(attr(px, 'PhysicalSizeXUnit'), 1);
M.pixelSizeYUm = attrNum(px, 'PhysicalSizeY', NaN) * unitUm(attr(px, 'PhysicalSizeYUnit'), 1);
M.zStepUm = attrNum(px, 'PhysicalSizeZ', NaN) * unitUm(attr(px, 'PhysicalSizeZUnit'), 1);
ti = attrNum(px, 'TimeIncrement', NaN);
if isfinite(ti)
    M.frameInterval = ti * timeS(attr(px, 'TimeIncrementUnit'));
end
chans = regexp(img, '<(\w+:)?Channel\s[^>]*>', 'match');
names = cell(1, numel(chans));
for k = 1:numel(chans), names{k} = attr(chans{k}, 'Name'); end
if ~isempty(names), M.channelNames = names; end
% Plane DeltaT gives the frame times when present (first channel, first slice)
planes = regexp(img, '<(\w+:)?Plane\s[^>]*>', 'match');
if ~isempty(planes)
    t = NaN(1, M.nFrames);
    for k = 1:numel(planes)
        if attrNum(planes{k}, 'TheC', 0) == 0 && attrNum(planes{k}, 'TheZ', 0) == 0
            it = attrNum(planes{k}, 'TheT', 0) + 1;
            if it <= M.nFrames
                t(it) = attrNum(planes{k}, 'DeltaT', NaN) * timeS(attr(planes{k}, 'DeltaTUnit'));
            end
        end
    end
    if all(isfinite(t)), M.t = t; end
end
dims = regexprep(upper(order), '[XY]', '');
M.pageMap = pageMapOf(dims, M.nChannels, M.nSlices, M.nFrames, nPages);
M.notes{end+1} = sprintf('OME-TIFF: %d channel(s), %d slice(s), %d time point(s), order %s.', ...
    M.nChannels, M.nSlices, M.nFrames, order);
end

%% ------------------------------------------------------------ ScanImage
function M = fromScanImage(M, txt, info)
M.source = 'scanimage';
nPages = numel(info);
chSave = siNum(txt, 'SI.hChannels.channelSave', 1);
M.nChannels = max(1, numel(chSave));
M.channelNames = arrayfun(@(c) sprintf('Channel %d', c), chSave(:)', 'UniformOutput', false);
rate = siNum(txt, 'SI.hRoiManager.scanFrameRate', NaN);
fastZ = siNum(txt, 'SI.hFastZ.enable', 0);
fastZ = ~isempty(fastZ) && fastZ(1) ~= 0;
slices = siNum(txt, 'SI.hStackManager.actualNumSlices', NaN);
if ~isfinite(slices(1)), slices = siNum(txt, 'SI.hStackManager.numSlices', 1); end
slices = max(1, slices(1));
perSlice = siNum(txt, 'SI.hStackManager.framesPerSlice', 1);
perSlice = max(1, perSlice(1));
flyback = 0;
if fastZ
    flyback = siNum(txt, 'SI.hFastZ.numDiscardFlybackFrames', 0);
    flyback = max(0, flyback(1));
    perSlice = 1;                                   % one frame per slice in a volume
end
volumes = siNum(txt, 'SI.hFastZ.numVolumes', NaN);
zStep = siNum(txt, 'SI.hStackManager.stackZStepSize', NaN);
M.zStepUm = abs(zStep(1));
if isfinite(rate(1)) && rate(1) > 0
    M.frameInterval = 1 / rate(1);
    if slices > 1 && fastZ
        M.frameInterval = (slices + flyback) / rate(1);    % one volume per time point
    end
end
fov = siNum(txt, 'SI.hRoiManager.imagingFovUm', NaN);
ppl = siNum(txt, 'SI.hRoiManager.pixelsPerLine', NaN);
lpf = siNum(txt, 'SI.hRoiManager.linesPerFrame', NaN);
if numel(fov) == 8 && isfinite(ppl(1)) && ppl(1) > 0
    fov = reshape(fov, 2, [])';                       % corners, one [x y] per row
    M.pixelSizeUm = (max(fov(:, 1)) - min(fov(:, 1))) / ppl(1);
    if isfinite(lpf(1)) && lpf(1) > 0, M.pixelSizeYUm = (max(fov(:, 2)) - min(fov(:, 2))) / lpf(1); end
end
% Pages: channel, frame (within the slice), slice (with flyback), volume
nC = M.nChannels;
perVolume = nC * perSlice * (slices + flyback);
nVol = floor(nPages / perVolume);
if isfinite(volumes(1)) && volumes(1) >= 1, nVol = min(nVol, volumes(1)); end
nVol = max(nVol, 0);
nT = perSlice * nVol;
map = zeros(nC, slices, nT);
for v = 1:nVol
    for z = 1:slices
        for f = 1:perSlice
            for c = 1:nC
                page = (v - 1) * perVolume + ((z - 1) * perSlice + (f - 1)) * nC + c;
                map(c, z, (v - 1) * perSlice + f) = page;
            end
        end
    end
end
M.nSlices = slices;
M.pageMap = map;
% Frame times of the first channel and slice
t = NaN(1, nT);
for k = 1:nT
    pg = map(1, 1, k);
    tok = regexp(textField(info(pg), 'ImageDescription'), 'frameTimestamps_sec\s*=\s*([-+0-9.eE]+)', 'tokens', 'once');
    if ~isempty(tok), t(k) = str2double(tok{1}); end
end
if nT > 0 && all(isfinite(t)), M.t = t; end
M.notes{end+1} = sprintf('ScanImage: %d saved channel(s), %d slice(s)%s, %d frame(s) per slice, %d volume(s).', ...
    nC, slices, ifelse(flyback > 0, sprintf(' + %d flyback', flyback), ''), perSlice, nVol);
end

function v = siNum(txt, key, default)
tok = regexp(txt, ['(?m)^\s*' regexptranslate('escape', key) '\s*=\s*([^\r\n]*)'], 'tokens', 'once');
v = default;
if isempty(tok), return; end
s = strtrim(tok{1});
s = regexprep(s, '[\[\]{};,]', ' ');
if any(strcmpi(s, {'true', 'false'})), v = double(strcmpi(s, 'true')); return; end
x = sscanf(s, '%f')';
if ~isempty(x), v = x; end
end

%% --------------------------------------------------------------- ImageJ
function M = fromImageJ(M, desc, info1, nPages)
M.source = 'imagej';
M.nChannels = max(1, keyNum(desc, 'channels', 1));
M.nSlices = max(1, keyNum(desc, 'slices', 1));
fr = keyNum(desc, 'frames', NaN);
if ~isfinite(fr)
    fr = floor(nPages / (M.nChannels * M.nSlices));
end
M.nFrames = max(1, fr);
if M.nChannels * M.nSlices * M.nFrames > nPages && M.nFrames > 1
    M.nFrames = floor(nPages / (M.nChannels * M.nSlices));
end
tok = regexp(desc, '(?m)^unit=([^\r\n]*)', 'tokens', 'once');
u = '';
if ~isempty(tok), u = strtrim(tok{1}); end
f = unitUm(u, NaN);
if isfinite(f)
    if isfield(info1, 'XResolution') && ~isempty(info1.XResolution) && info1.XResolution > 0
        M.pixelSizeUm = f / double(info1.XResolution);
    end
    if isfield(info1, 'YResolution') && ~isempty(info1.YResolution) && info1.YResolution > 0
        M.pixelSizeYUm = f / double(info1.YResolution);
    end
    sp = keyNum(desc, 'spacing', NaN);
    if isfinite(sp), M.zStepUm = sp * f; end
elseif isempty(u)
    % No unit: ImageJ leaves the scale in pixels unless the plain TIFF tags say more
    M.pixelSizeUm = plainResolution(info1, 'XResolution');
    M.pixelSizeYUm = plainResolution(info1, 'YResolution');
end
fi = keyNum(desc, 'finterval', NaN);
if isfinite(fi) && fi > 0
    M.frameInterval = fi * timeS(regexp(desc, '(?m)^tunit=([^\r\n]*)', 'tokens', 'once'));
end
if ~isfinite(M.frameInterval)
    fps = keyNum(desc, 'fps', NaN);
    if isfinite(fps) && fps > 0, M.frameInterval = 1 / fps; end
end
M.pageMap = pageMapOf('CZT', M.nChannels, M.nSlices, M.nFrames, nPages);
if M.nChannels > 1 || M.nSlices > 1
    M.notes{end+1} = sprintf('ImageJ hyperstack: %d channel(s), %d slice(s), %d frame(s).', ...
        M.nChannels, M.nSlices, M.nFrames);
end
end

function v = keyNum(desc, key, default)
tok = regexp(desc, ['(?m)^' key '=([-+0-9.eE]+)'], 'tokens', 'once');
if isempty(tok), v = default; else, v = str2double(tok{1}); end
end

%% --------------------------------------------------------------- Aperio
function M = fromAperio(M, desc)
M.source = 'aperio';
tok = regexp(desc, 'MPP\s*=\s*([0-9.eE+-]+)', 'tokens', 'once');
if ~isempty(tok), M.pixelSizeUm = str2double(tok{1}); end
tok = regexp(desc, 'AppMag\s*=\s*([0-9.eE+-]+)', 'tokens', 'once');
if ~isempty(tok)
    M.magnification = str2double(tok{1});
    M.notes{end+1} = sprintf('Aperio slide scanned at %gx.', M.magnification);
end
end

%% -------------------------------------------------------------- helpers
function um = plainResolution(info1, field)
um = NaN;
if ~isfield(info1, field) || isempty(info1.(field)) || ~(info1.(field) > 0), return; end
res = double(info1.(field));
unit = '';
if isfield(info1, 'ResolutionUnit'), unit = lower(char(info1.ResolutionUnit)); end
switch unit
    case 'centimeter', um = 1e4 / res;
    case 'inch'
        if ~any(res == [72 96 300]), um = 25400 / res; end   % screen / print defaults: not a scale
end
end

%% pageMapOf - Page numbers (C x Z x T) for dims given fastest first, e.g. 'CZT' or 'ZCT'
function map = pageMapOf(dims, nC, nZ, nT, nPages)
dims = upper(dims);
dims = dims(ismember(dims, 'CZT'));
for d = 'CZT'
    if ~any(dims == d), dims(end+1) = d; end %#ok<AGROW>
end
n = struct('C', nC, 'Z', nZ, 'T', nT);
sz = [n.(dims(1)) n.(dims(2)) n.(dims(3))];
idx = reshape(1:prod(sz), sz);                         % pages in file order
perm = [find(dims == 'C') find(dims == 'Z') find(dims == 'T')];
map = permute(idx, perm);
map = reshape(map, nC, nZ, nT);
% Keep the time points the file holds completely
full = squeeze(all(all(map <= nPages, 1), 2));
last = find(full, 1, 'last');
if isempty(last), last = 0; end
map = map(:, :, 1:last);
end

function s = textField(fi, name)
s = '';
if isfield(fi, name) && ~isempty(fi.(name))
    v = fi.(name);
    if iscell(v), v = v{1}; end
    if ischar(v) || isstring(v), s = char(v); end
end
end

function v = attr(tag, name)
tok = regexp(tag, ['\s' name '\s*=\s*"([^"]*)"'], 'tokens', 'once');
if isempty(tok), v = ''; else, v = decodeXml(tok{1}); end
end

function v = attrNum(tag, name, default)
s = attr(tag, name);
v = str2double(s);
if isempty(s) || ~isfinite(v), v = default; end
end

function s = decodeXml(s)
% Numeric character references and the five named entities (no dynamic regexprep: Octave)
[tok, starts, ends] = regexp(s, '&#(x?)([0-9a-fA-F]+);', 'tokens', 'start', 'end');
for k = numel(tok):-1:1
    if isempty(tok{k}{1}), code = str2double(tok{k}{2}); else, code = hex2dec(tok{k}{2}); end
    if code == 181 || code == 956
        r = 'u';                                        % micro sign: read as 'u' by unitScale
    elseif code < 128
        r = char(code);
    else
        r = '?';
    end
    s = [s(1:starts(k)-1) r s(ends(k)+1:end)];
end
s = strrep(strrep(strrep(strrep(strrep(s, '&lt;', '<'), '&gt;', '>'), '&quot;', '"'), '&apos;', ''''), '&amp;', '&');
end

%% unitUm - Micrometres in one length unit ('' -> default; NaN when not a length)
function f = unitUm(u, default)
if iscell(u), if isempty(u), u = ''; else, u = u{1}; end, end
if isempty(strtrim(char(u))), f = default; return; end
f = unitScale(u);
end

%% timeS - Seconds in one time unit (default s)
function f = timeS(u)
if iscell(u), if isempty(u), u = ''; else, u = u{1}; end, end
f = unitScale(u, 'time');
if ~isfinite(f), f = 1; end
end

function s = ifelse(c, a, b)
if c, s = a; else, s = b; end
end
