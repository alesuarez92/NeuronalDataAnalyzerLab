function S = readImageStack(p, opts)
% readImageStack - Read an image stack over time (.mat, multi-page TIFF or video) with its metadata.
%
% S = readImageStack(path)
% S = readImageStack(path, struct('Channel', 2))
%
% One reader for the imaging windows (Laser speckle, ROI analysis), so a
% file opens the same way everywhere and what the file says about itself
% (frame rate, pixel size, exposure, channels) is used instead of being
% typed again.
%
% Formats:
%   .mat   - the stack in a variable named frames, stack, images, speckle,
%            contrast, K, perfusion, flux, flow or data (else the first 3-D
%            numeric variable): H x W x N, or H x W x 3 x N (RGB, averaged
%            to grey). Optional: t / timeVec / time (s, one per frame),
%            fps / frameRate, exposureMs, dark, stim (one value per frame),
%            roiMasks / roiMask (+ roiNames), pixelSizeUm, kind ('raw
%            speckle' | 'contrast' | 'flow'), truth.
%   .tif / .tiff - every page is a frame (RGB pages averaged to grey).
%            ImageJ files: frame interval (finterval), channels / slices /
%            frames (hyperstacks: one channel is kept, opts.Channel) and
%            the pixel size (XResolution with unit=micron or cm / inch).
%   .avi / .mp4 / .mov / .mj2 - video (VideoReader): grey frames and the
%            frame rate.
%
% Output struct S:
%   stack        H x W x N, class of the file (uint8 / uint16 / single /
%                double) to keep memory low
%   t            1 x N times (s) when the file has them, else []
%   fps          frames per second (NaN when unknown)
%   exposureMs, pixelSizeUm, dark   NaN / [] when unknown
%   stim         1 x N stimulus trace ([] when none)
%   roiMasks     H x W x K logical ([] when none), roiNames 1 x K cellstr
%   kind         '' | 'raw speckle' | 'contrast' | 'flow'
%   truth        ground truth of demo files ([] otherwise)
%   info         struct: format, file, variable, nChannels, channel, notes
%                (cellstr: what was read from the file, in plain words)
%
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:noStack,
% NeuroAnalyzer:io:unknownFormat. Base MATLAB only.
%
if nargin < 2 || isempty(opts), opts = struct(); end
if exist(p, 'file') ~= 2
    error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', p);
end
[~, ~, ext] = fileparts(p);
S = struct('stack', [], 't', [], 'fps', NaN, 'exposureMs', NaN, 'pixelSizeUm', NaN, ...
    'dark', [], 'stim', [], 'roiMasks', [], 'roiNames', {{}}, 'kind', '', 'truth', [], ...
    'info', struct('format', '', 'file', p, 'variable', '', 'nChannels', 1, 'channel', 1, 'notes', {{}}));
switch lower(ext)
    case '.mat'
        S = readMat(p, S);
    case {'.tif', '.tiff'}
        S = readTiff(p, S, opts);
    case {'.avi', '.mp4', '.mov', '.mj2', '.m4v'}
        S = readVideo(p, S);
    otherwise
        error('NeuroAnalyzer:io:unknownFormat', ...
            'Cannot read %s: choose a .mat, .tif / .tiff or a video (.avi, .mp4).', p);
end
N = size(S.stack, 3);
if ~isempty(S.t) && numel(S.t) ~= N
    S.info.notes{end+1} = sprintf('The time vector has %d values for %d frames: ignored.', numel(S.t), N);
    S.t = [];
end
if ~isempty(S.t) && N > 1 && ~(isfinite(S.fps) && S.fps > 0)
    S.fps = (N - 1) / (S.t(end) - S.t(1));
end
end

%% ------------------------------------------------------------------------
function S = readMat(p, S)
d = load(p);
fn = fieldnames(d);
if isempty(fn)
    error('NeuroAnalyzer:io:noStack', 'The file contains no variables.');
end
S.info.format = 'mat';
names = {'frames', 'stack', 'images', 'speckle', 'contrast', 'K', 'perfusion', 'flux', 'flow', 'data'};
v = '';
for k = 1:numel(names)
    if isfield(d, names{k}) && isnumeric(d.(names{k})) && ndims(d.(names{k})) >= 3
        v = names{k}; break;
    end
end
if isempty(v)
    for k = 1:numel(fn)
        x = d.(fn{k});
        if (isnumeric(x) || islogical(x)) && ndims(x) >= 3
            v = fn{k}; break;
        end
    end
end
if isempty(v)
    error('NeuroAnalyzer:io:noStack', ['No image stack found. Save the frames as a numeric variable ' ...
        'named ''frames'' or ''stack'' (H x W x N).']);
end
x = d.(v);
if ndims(x) == 4
    x = reshape(mean(double(x), 3), size(x, 1), size(x, 2), size(x, 4));
    S.info.notes{end+1} = sprintf('%s is H x W x 3 x N (colour): the colours were averaged.', v);
end
S.stack = x;
S.info.variable = v;
S.t = firstField(d, {'t', 'timeVec', 'time'}, []);
if ~isempty(S.t), S.t = double(S.t(:)'); S.info.notes{end+1} = 'Frame times read from the file.'; end
S.fps = firstField(d, {'fps', 'frameRate', 'FrameRate'}, NaN);
S.exposureMs = firstField(d, {'exposureMs', 'exposure_ms'}, NaN);
S.dark = firstField(d, {'dark', 'darkLevel'}, []);
S.pixelSizeUm = firstField(d, {'pixelSizeUm', 'pixelSize'}, NaN);
S.stim = firstField(d, {'stim', 'stimulus'}, []);
if ~isempty(S.stim), S.stim = double(S.stim(:)'); end
S.kind = char(firstField(d, {'kind'}, ''));
if isfield(d, 'truth') && isstruct(d.truth), S.truth = d.truth; end
if isfield(d, 'roiMasks') && ~isempty(d.roiMasks)
    S.roiMasks = logical(d.roiMasks);
elseif isfield(d, 'roiMask') && ~isempty(d.roiMask)
    S.roiMasks = logical(d.roiMask);
end
if ~isempty(S.roiMasks)
    if size(S.roiMasks, 1) ~= size(x, 1) || size(S.roiMasks, 2) ~= size(x, 2)
        S.info.notes{end+1} = 'The ROI masks are not the size of a frame: ignored.';
        S.roiMasks = [];
    else
        K = size(S.roiMasks, 3);
        S.roiNames = arrayfun(@(k) sprintf('ROI %d', k), 1:K, 'UniformOutput', false);
        if isfield(d, 'roiNames')
            nm = cellstr(d.roiNames);
            S.roiNames(1:min(K, numel(nm))) = nm(1:min(K, numel(nm)));
        end
    end
end
if isfinite(S.fps), S.info.notes{end+1} = sprintf('Frame rate %g Hz read from the file.', S.fps); end
if isfinite(S.exposureMs), S.info.notes{end+1} = sprintf('Exposure %g ms read from the file.', S.exposureMs); end
end

%% ------------------------------------------------------------------------
function S = readTiff(p, S, opts)
info = imfinfo(p);
n = numel(info);
S.info.format = 'tiff';
desc = '';
if isfield(info, 'ImageDescription') && ischar(info(1).ImageDescription)
    desc = info(1).ImageDescription;
end
ij = parseImageJ(desc);
% Hyperstack: pages are channel-fastest (ImageJ order CZT); keep one channel
nC = max(1, ij.channels);
ch = 1;
if isfield(opts, 'Channel') && ~isempty(opts.Channel), ch = opts.Channel; end
ch = min(max(1, round(ch)), nC);
pages = ch:nC:n;
S.info.nChannels = nC;
S.info.channel = ch;
if nC > 1
    S.info.notes{end+1} = sprintf('ImageJ hyperstack with %d channels: channel %d is used.', nC, ch);
end
first = imread(p, pages(1));
if ndims(first) == 3
    cls = 'double';
else
    cls = class(first);
end
S.stack = zeros(size(first, 1), size(first, 2), numel(pages), cls);
for k = 1:numel(pages)
    fr = imread(p, pages(k));
    if ndims(fr) == 3
        fr = mean(double(fr(:, :, 1:min(3, size(fr, 3)))), 3);
    end
    S.stack(:, :, k) = fr;
end
if ndims(first) == 3
    S.info.notes{end+1} = 'Colour pages were averaged to grey.';
end
if isfinite(ij.finterval) && ij.finterval > 0
    S.fps = 1 / ij.finterval;
    S.info.notes{end+1} = sprintf('Frame interval %g s read from the ImageJ header (%g Hz).', ij.finterval, S.fps);
end
S.pixelSizeUm = tiffPixelSize(info(1), ij);
if isfinite(S.pixelSizeUm)
    S.info.notes{end+1} = sprintf('Pixel size %g um read from the file.', S.pixelSizeUm);
end
end

%% parseImageJ - key=value lines of an ImageJ ImageDescription
function ij = parseImageJ(desc)
ij = struct('isImageJ', false, 'channels', 1, 'slices', 1, 'frames', NaN, 'finterval', NaN, 'unit', '');
if isempty(desc) || isempty(strfind(desc, 'ImageJ=')), return; end %#ok<STREMP>
ij.isImageJ = true;
ij.channels = keyNum(desc, 'channels', 1);
ij.slices = keyNum(desc, 'slices', 1);
ij.frames = keyNum(desc, 'frames', NaN);
ij.finterval = keyNum(desc, 'finterval', NaN);
tok = regexp(desc, '(?m)^unit=(.*)$', 'tokens', 'once');
if ~isempty(tok), ij.unit = strtrim(tok{1}); end
end

function v = keyNum(desc, key, default)
tok = regexp(desc, ['(?m)^' key '=([-+0-9.eE]+)'], 'tokens', 'once');
if isempty(tok), v = default; else, v = str2double(tok{1}); end
end

%% tiffPixelSize - um per pixel from XResolution (pixels per unit) and the unit
function um = tiffPixelSize(info, ij)
um = NaN;
if ~isfield(info, 'XResolution') || isempty(info.XResolution) || ~(info.XResolution > 0), return; end
px = 1 / info.XResolution;                      % units per pixel
u = lower(ij.unit);
if any(strcmp(u, {'micron', 'um', 'µm', 'µm'}))
    um = px;
elseif strcmp(u, 'nm')
    um = px / 1000;
elseif strcmp(u, 'mm')
    um = px * 1000;
elseif isfield(info, 'ResolutionUnit') && ~ij.isImageJ
    switch lower(char(info.ResolutionUnit))
        case 'centimeter', um = px * 1e4;
        case 'inch'
            if info.XResolution ~= 72 && info.XResolution ~= 96 && info.XResolution ~= 300
                um = px * 25400;               % screen / print defaults say nothing about the sample
            end
    end
end
end

%% ------------------------------------------------------------------------
function S = readVideo(p, S)
v = VideoReader(p);
S.info.format = 'video';
S.fps = v.FrameRate;
frames = {};
while hasFrame(v)
    fr = readFrame(v);
    if ndims(fr) == 3, fr = mean(double(fr), 3); end
    frames{end+1} = fr; %#ok<AGROW>
end
if isempty(frames)
    error('NeuroAnalyzer:io:noStack', 'The video has no frames: %s', p);
end
S.stack = cat(3, frames{:});
if isa(frames{1}, 'double') && all(S.stack(:) == round(S.stack(:)))
    S.stack = uint8(S.stack);
end
S.info.notes{end+1} = sprintf(['Video: %d frames at %g Hz. Videos are usually compressed, which changes ' ...
    'pixel values; use uncompressed TIFF for quantitative work.'], size(S.stack, 3), S.fps);
end

function v = firstField(d, names, default)
v = default;
for k = 1:numel(names)
    if isfield(d, names{k}) && ~isempty(d.(names{k}))
        v = d.(names{k});
        if isnumeric(v) && isscalar(v), v = double(v); end
        return;
    end
end
end
