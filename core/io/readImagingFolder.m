function S = readImagingFolder(p, S, opts)
% readImagingFolder - Image stacks saved by microscope software as a folder or a vendor file.
%
% S = readImagingFolder(path, S, opts)     (called by readImageStack)
%
% Fills S (see readImageStack) from:
%   Inscopix .isxd      movie file: frames from byte 0, then a JSON footer
%                       whose length is the first int32 of the last 8 bytes
%                       (footer ends 1 byte before them); dataType 0 uint16,
%                       1 float32, 2 uint8; spacingInfo.numPixels,
%                       timingInfo.numTimes / period (num / den s). Files
%                       whose frames carry headers (hasFrameHeaderFooter,
%                       raw nVista recordings) are refused: export them from
%                       Inscopix Data Processing as .isxd or TIFF
%   ThorImageLS folder  Experiment.xml (LSM pixelX / pixelY / pixelSizeUM
%                       or widthUM, frameRate, averageMode / averageNum;
%                       Streaming frames, flybackFrames, zFastEnable;
%                       ZStage steps; Wavelengths) and Image_0001_0001.raw
%                       (or Image_001_001.raw): 16-bit little-endian
%                       samples, every channel of a frame one after the
%                       other; read as unsigned (ThorImage versions differ;
%                       see the note)
%   Bruker Prairie View folder (or its .xml): PVScan XML with Sequence /
%                       Frame (relativeTime / absoluteTime in s) / File
%                       (channel, filename) and micronsPerPixel (new
%                       PVStateValue / IndexedValue or old Key layout);
%                       one TIFF per frame and channel. Z-series: the first
%                       plane of every volume
%   UCLA Miniscope folder  numbered videos (V4: 0.avi, 1.avi ...; V3:
%                       msCam1.avi ...) with timeStamps.csv ('Time Stamp
%                       (ms)') or timestamp.dat, and metaData.json
%                       (frameRate, e.g. "30FPS")
% opts.Channel picks the channel (1-based) where there are several.
% Errors: NeuroAnalyzer:io:unknownFormat, NeuroAnalyzer:io:noStack,
% NeuroAnalyzer:io:imaging. Regular expressions and jsondecode only; runs
% in GNU Octave except the Miniscope videos (VideoReader).
%
if nargin < 3 || isempty(opts), opts = struct(); end
kind = readImagingFolderKind(p);
switch kind
    case 'isxd',      S = readISXD(p, S);
    case 'thorimage', S = readThor(folderOf(p), S, opts);
    case 'prairie',   S = readPrairie(p, S, opts);
    case 'miniscope', S = readMiniscope(folderOf(p), S);
    otherwise
        error('NeuroAnalyzer:io:unknownFormat', ['%s is not an imaging folder this toolbox knows ' ...
            '(ThorImageLS, Prairie View, UCLA Miniscope) or an Inscopix .isxd movie.'], p);
end
end

function kind = readImagingFolderKind(p)
kind = '';
[~, ~, ext] = fileparts(p);
if strcmpi(ext, '.isxd'), kind = 'isxd'; return; end
d = folderOf(p);
if strcmpi(ext, '.xml') && isPVScan(p), kind = 'prairie'; return; end
if exist(fullfile(d, 'Experiment.xml'), 'file') == 2, kind = 'thorimage'; return; end
x = dir(fullfile(d, '*.xml'));
for k = 1:numel(x)
    if isPVScan(fullfile(d, x(k).name)), kind = 'prairie'; return; end
end
if ~isempty(miniscopeVideos(d)), kind = 'miniscope'; end
end

function d = folderOf(p)
if exist(p, 'dir') == 7, d = p; else, d = fileparts(p); end
end

%% ------------------------------------------------------------- Inscopix
function S = readISXD(p, S)
fid = fopen(p, 'r', 'ieee-le');
if fid < 0, error('NeuroAnalyzer:io:imaging', 'Cannot open %s', p); end
c = onCleanup(@() fclose(fid));
fseek(fid, 0, 'eof'); nBytes = ftell(fid);
fseek(fid, -8, 'eof');
L = fread(fid, 1, 'int32');
if isempty(L) || L <= 0 || L + 9 > nBytes
    error('NeuroAnalyzer:io:imaging', '%s has no Inscopix footer.', nameOf(p));
end
fseek(fid, -8 - L - 1, 'eof');
J = jsondecode(fread(fid, L, 'uint8=>char')');
if isfield(J, 'type') && ~any(J.type == [0 4])
    error('NeuroAnalyzer:io:noStack', ['%s is an Inscopix file of type %d (not a movie or image): ' ...
        'cell sets, events and GPIO files hold no frames.'], nameOf(p), J.type);
end
if isfield(J, 'hasFrameHeaderFooter') && J.hasFrameHeaderFooter
    error('NeuroAnalyzer:io:imaging', ['%s stores a header with every frame (a raw nVista recording), ' ...
        'whose layout is not published: export it from Inscopix Data Processing as a processed .isxd ' ...
        'or a TIFF.'], nameOf(p));
end
W = J.spacingInfo.numPixels.x;
H = J.spacingInfo.numPixels.y;
N = J.timingInfo.numTimes;
switch J.dataType
    case 0, cls = 'uint16'; b = 2;
    case 1, cls = 'single'; b = 4;
    case 2, cls = 'uint8'; b = 1;
    otherwise
        error('NeuroAnalyzer:io:imaging', '%s: unknown Inscopix data type %d.', nameOf(p), J.dataType);
end
if N * W * H * b > nBytes - L - 9
    error('NeuroAnalyzer:io:imaging', '%s is shorter than its footer says (%d frames of %d x %d).', ...
        nameOf(p), N, W, H);
end
prec = cls;
if strcmp(cls, 'single'), prec = 'float32'; end
fseek(fid, 0, 'bof');
S.stack = zeros(H, W, N, cls);
for k = 1:N
    S.stack(:, :, k) = fread(fid, [W H], ['*' prec])';     % rows (y) of x pixels
end
S.info.format = 'isxd';
per = J.timingInfo.period;
if per.den > 0 && per.num > 0
    S.fps = per.den / per.num;
    S.info.notes{end+1} = sprintf('Inscopix movie: %d frames of %d x %d at %g Hz.', N, W, H, S.fps);
end
if isfield(J.spacingInfo, 'pixelSize') && isfield(J.spacingInfo.pixelSize, 'x')
    px = J.spacingInfo.pixelSize.x;
    if isstruct(px) && isfield(px, 'num') && px.den > 0, S.pixelSizeUm = px.num / px.den; end
end
if isfield(J.timingInfo, 'dropped') && ~isempty(J.timingInfo.dropped)
    S.info.notes{end+1} = sprintf('%d dropped frame(s) listed in the file: frame times assume a regular rate.', ...
        numel(J.timingInfo.dropped));
end
end

%% ----------------------------------------------------------- ThorImageLS
function S = readThor(d, S, opts)
xml = fileread(fullfile(d, 'Experiment.xml'));
lsm = regexp(xml, '<LSM\s[^>]*>', 'match', 'once');
W = attrNum(lsm, 'pixelX', NaN); H = attrNum(lsm, 'pixelY', NaN);
if ~(W > 0 && H > 0)
    error('NeuroAnalyzer:io:imaging', 'Experiment.xml in %s has no LSM pixelX / pixelY.', d);
end
rate = attrNum(lsm, 'frameRate', NaN);
avgMode = attrNum(lsm, 'averageMode', 0); avgNum = attrNum(lsm, 'averageNum', 1);
px = attrNum(lsm, 'pixelSizeUM', NaN);
if ~isfinite(px)
    wum = attrNum(lsm, 'widthUM', NaN);
    if isfinite(wum), px = wum / W; end
end
wl = regexp(xml, '<Wavelength\s[^>]*>', 'match');
nC = max(1, numel(wl));
names = cell(1, nC);
for k = 1:numel(wl), names{k} = attr(wl{k}, 'name'); end
st = regexp(xml, '<Streaming\s[^>]*>', 'match', 'once');
zFast = attrNum(st, 'zFastEnable', 0) ~= 0;
flyback = attrNum(st, 'flybackFrames', 0);
zs = regexp(xml, '<ZStage\s[^>]*>', 'match', 'once');
steps = max(1, attrNum(zs, 'steps', 1));
raw = '';
for c = {'Image_0001_0001.raw', 'Image_001_001.raw'}
    if exist(fullfile(d, c{1}), 'file') == 2, raw = fullfile(d, c{1}); break; end
end
if isempty(raw)
    r = dir(fullfile(d, 'Image_*.raw'));
    if isempty(r)
        error('NeuroAnalyzer:io:noStack', ['%s has no Image_0001_0001.raw: ThorImageLS saved the ' ...
            'images as TIFF; open those instead.'], d);
    end
    raw = fullfile(d, r(1).name);
end
fid = fopen(raw, 'r', 'ieee-le');
c = onCleanup(@() fclose(fid));
fseek(fid, 0, 'eof'); nBytes = ftell(fid); fseek(fid, 0, 'bof');
perFrame = W * H * nC * 2;
nPages = floor(nBytes / perFrame);
ch = 1;
if isfield(opts, 'Channel') && ~isempty(opts.Channel), ch = min(max(1, round(opts.Channel)), nC); end
if zFast && steps > 1
    perVol = steps + flyback;
    frames = 1:perVol:nPages;                       % first plane of every volume
    S.info.notes{end+1} = sprintf('Fast z: %d planes + %d flyback per volume; the first plane is used.', steps, flyback);
else
    frames = 1:nPages;
end
S.stack = zeros(H, W, numel(frames), 'uint16');
for k = 1:numel(frames)
    fseek(fid, (frames(k) - 1) * perFrame + (ch - 1) * W * H * 2, 'bof');
    S.stack(:, :, k) = fread(fid, [W H], '*uint16')';
end
S.info.format = 'thorimage';
S.info.nChannels = nC;
S.info.channel = ch;
if isfinite(rate) && rate > 0
    if avgMode == 1 && avgNum > 1, rate = rate / avgNum; end
    if zFast && steps > 1, rate = rate / (steps + flyback); end
    S.fps = rate;
end
if isfinite(px), S.pixelSizeUm = px; end
nm = names{ch}; if isempty(nm), nm = sprintf('%d', ch); end
S.info.notes{end+1} = sprintf(['ThorImageLS: %d frame(s) of %d x %d, channel %s of %d, %g Hz. Samples read ' ...
    'as unsigned 16-bit (some ThorImage versions write signed values: check the intensities).'], ...
    numel(frames), W, H, nm, nC, S.fps);
end

%% ---------------------------------------------------------- Prairie View
function tf = isPVScan(f)
tf = false;
fid = fopen(f, 'r');
if fid < 0, return; end
head = fread(fid, 4096, 'uint8=>char')';
fclose(fid);
tf = ~isempty(strfind(head, '<PVScan')); %#ok<STREMP>
end

function S = readPrairie(p, S, opts)
if exist(p, 'dir') == 7
    x = dir(fullfile(p, '*.xml'));
    f = '';
    for k = 1:numel(x)
        if isPVScan(fullfile(p, x(k).name)), f = fullfile(p, x(k).name); break; end
    end
    d = p;
else
    f = p; d = fileparts(p);
end
xml = fileread(f);
seqs = regexp(xml, '<Sequence\s.*?</Sequence>', 'match');
if isempty(seqs), seqs = {xml}; end
seqType = attr(regexp(seqs{1}, '<Sequence\s[^>]*>', 'match', 'once'), 'type');
volumes = numel(seqs) > 1 && ~isempty(strfind(lower(seqType), 'zseries')); %#ok<STREMP>
files = {}; t = [];
chans = [];
for s = 1:numel(seqs)
    fr = regexp(seqs{s}, '<Frame\s.*?</Frame>', 'match');
    if volumes, fr = fr(1:min(1, numel(fr))); end
    for k = 1:numel(fr)
        ftags = regexp(fr{k}, '<File\s[^>]*>', 'match');
        cs = zeros(1, numel(ftags)); fn = cell(1, numel(ftags));
        for j = 1:numel(ftags)
            cs(j) = attrNum(ftags{j}, 'channel', j);
            fn{j} = attr(ftags{j}, 'filename');
        end
        if isempty(chans), chans = sort(cs); end
        files(end+1, 1:numel(fn)) = fn; %#ok<AGROW>
        chanOf(size(files, 1), 1:numel(cs)) = cs; %#ok<AGROW>
        ftag = regexp(fr{k}, '<Frame\s[^>]*>', 'match', 'once');
        at = attrNum(ftag, 'absoluteTime', NaN);
        if ~isfinite(at) || ~volumes, at = attrNum(ftag, 'relativeTime', NaN) + seqOffset(seqs{s}, s); end
        t(end+1) = at; %#ok<AGROW>
    end
end
if isempty(files)
    error('NeuroAnalyzer:io:noStack', '%s lists no frames.', nameOf(f));
end
ch = 1;
if isfield(opts, 'Channel') && ~isempty(opts.Channel), ch = min(max(1, round(opts.Channel)), numel(chans)); end
want = chans(ch);
N = size(files, 1);
first = [];
for k = 1:N
    j = find(chanOf(k, :) == want, 1);
    img = imread(fullfile(d, files{k, j}));
    if isempty(first)
        first = img;
        S.stack = zeros(size(img, 1), size(img, 2), N, class(img));
    end
    S.stack(:, :, k) = img(:, :, 1);
end
S.info.format = 'prairie';
S.info.nChannels = numel(chans);
S.info.channel = ch;
if all(isfinite(t)) && N > 1
    S.t = t - t(1);
end
px = regexp(xml, 'key="micronsPerPixel"\s*>\s*<IndexedValue[^>]*index="XAxis"[^>]*value="([^"]+)"', 'tokens', 'once');
if isempty(px), px = regexp(xml, 'key="micronsPerPixel"\s*>\s*<IndexedValue[^>]*value="([^"]+)"[^>]*index="XAxis"', 'tokens', 'once'); end
if isempty(px), px = regexp(xml, 'key="micronsPerPixel_XAxis"[^>]*value="([^"]+)"', 'tokens', 'once'); end
if ~isempty(px), S.pixelSizeUm = str2double(px{1}); end
S.info.notes{end+1} = sprintf('Prairie View %s: %d frame(s), channel %d of %d.', ...
    ifelse(volumes, 'Z-series (first plane of each volume)', 'T-series'), N, want, numel(chans));
end

function off = seqOffset(seq, s)
% Frame relativeTime restarts in every sequence: add the sequence start when known
off = 0;
if s == 1, return; end
tag = regexp(seq, '<Sequence\s[^>]*>', 'match', 'once');
tok = regexp(tag, 'time="(\d+):(\d+):([\d.]+)', 'tokens', 'once');
if ~isempty(tok), off = str2double(tok{1}) * 3600 + str2double(tok{2}) * 60 + str2double(tok{3}); end
end

%% ------------------------------------------------------------- Miniscope
function v = miniscopeVideos(d)
a = dir(fullfile(d, '*.avi'));
names = {a.name};
v = {};
num = regexp(names, '^(msCam)?(\d+)\.avi$', 'tokens', 'once');
ok = ~cellfun(@isempty, num);
if ~any(ok), return; end
names = names(ok); num = num(ok);
idx = cellfun(@(c) str2double(c{end}), num);
[~, o] = sort(idx);
v = fullfile(d, names(o));
if ischar(v), v = {v}; end
if ~(exist(fullfile(d, 'timeStamps.csv'), 'file') == 2 || exist(fullfile(d, 'timestamp.dat'), 'file') == 2 || ...
        exist(fullfile(d, 'metaData.json'), 'file') == 2)
    v = {};
end
end

function S = readMiniscope(d, S)
vids = miniscopeVideos(d);
parts = {};
for k = 1:numel(vids)
    r = VideoReader(vids{k});
    while hasFrame(r)
        fr = readFrame(r);
        if ndims(fr) == 3, fr = fr(:, :, 1); end    % grey stored as RGB
        parts{end+1} = fr; %#ok<AGROW>
    end
end
if isempty(parts)
    error('NeuroAnalyzer:io:noStack', 'The Miniscope videos in %s have no frames.', d);
end
S.stack = cat(3, parts{:});
S.info.format = 'miniscope';
N = size(S.stack, 3);
t = [];
if exist(fullfile(d, 'timeStamps.csv'), 'file') == 2
    txt = fileread(fullfile(d, 'timeStamps.csv'));
    lines = regexp(txt, '\r?\n', 'split');
    head = strsplit(lines{1}, ',');
    col = find(~cellfun(@isempty, regexpi(head, 'time\s*stamp', 'once')), 1);
    if isempty(col), col = 2; end
    vals = [];
    for k = 2:numel(lines)
        c = strsplit(lines{k}, ',');
        if numel(c) >= col, vals(end+1) = str2double(c{col}); end %#ok<AGROW>
    end
    t = vals(isfinite(vals)) / 1000;
elseif exist(fullfile(d, 'timestamp.dat'), 'file') == 2
    txt = fileread(fullfile(d, 'timestamp.dat'));
    lines = regexp(txt, '\r?\n', 'split');
    vals = [];
    for k = 2:numel(lines)
        c = sscanf(lines{k}, '%f')';
        if numel(c) >= 3 && c(1) == 0, vals(end+1) = c(3); end %#ok<AGROW>   % camera 0: the Miniscope
    end
    t = vals / 1000;
end
if numel(t) == N
    S.t = t - t(1);
elseif ~isempty(t)
    S.info.notes{end+1} = sprintf('%d time stamps for %d frames: not used.', numel(t), N);
end
if exist(fullfile(d, 'metaData.json'), 'file') == 2
    try
        J = jsondecode(fileread(fullfile(d, 'metaData.json')));
        if isfield(J, 'frameRate')
            fr = J.frameRate;
            if ischar(fr), fr = str2double(regexp(fr, '[\d.]+', 'match', 'once')); end
            if isfinite(fr) && fr > 0, S.fps = fr; end
        end
    catch
        S.info.notes{end+1} = 'metaData.json could not be read.';
    end
end
S.info.notes{end+1} = sprintf('UCLA Miniscope: %d video file(s), %d frames.', numel(vids), N);
end

%% -------------------------------------------------------------- helpers
function v = attr(tag, name)
tok = regexp(tag, ['\s' name '\s*=\s*"([^"]*)"'], 'tokens', 'once');
if isempty(tok), v = ''; else, v = tok{1}; end
end

function v = attrNum(tag, name, default)
s = attr(tag, name);
v = str2double(s);
if isempty(s) || ~isfinite(v)
    if any(strcmpi(s, {'true', 'false'})), v = double(strcmpi(s, 'true')); else, v = default; end
end
end

function n = nameOf(p)
[~, a, b] = fileparts(p);
n = [a b];
end

function s = ifelse(c, a, b)
if c, s = a; else, s = b; end
end
