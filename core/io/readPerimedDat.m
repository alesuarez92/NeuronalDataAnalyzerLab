function P = readPerimedDat(p)
% readPerimedDat - Read a Perimed PeriCam PSI / PIMSoft .dat recording (laser speckle).
%
% P = readPerimedDat(file)
%
% PIMSoft (Perimed PeriCam PSI) saves each recording as a .dat file with a
% header and, per frame, a speckle variance image and an intensity image.
% Layout (the vendor's note 44-00208-02 is not public; this is the layout
% two independent open-source readers agree on), little-endian:
%   @0   char[10]  'PSI' (zero padded)
%   @10  int32     version (1, 2 or 3)
%   @14  float64   gain k (perfusion scale)
%   @22  float64   beta (speckle coherence factor)
%   @30  float64   number of images (= 2 x frames: variance + intensity)
%   @38  int32     width,  @42 int32 height
%   version >= 2: @46 char[80] name, @126 char[20] serial number,
%        @146 char[20] start time, @166 float64 duration (s),
%        @494 float64 distance (mm), @502 char[20] frame rate (text),
%        @522 float64 resolution (mm per pixel); header ends at 540
%   version 3: header ends at 581, then 32 bytes per frame
%   data: offset 46 (v1), 540 (v2), 581 + 32 x frames (v3); all variance
%        images, then all intensity images, float64, each H x W (read as
%        fread(fid, [H W], 'double'))
% Derived (as PIMSoft):
%   contrast   C = beta * sign(V) * sqrt(|V|) / I
%   perfusion  P = k * (1 / C - 1), limited to 0..3000 (PU)
% To average frames, average V and I first and convert after
% (perimedPerfusion).
%
% Output P: version, gain, beta, nFrames, width, height, name, serial,
% startTime, durationS, distanceMm, frameRateText, fps (NaN when the text
% has no number), resolutionMm, dataOffset, variance (H x W x N double),
% intensity, contrast, perfusion, notes (cellstr).
%
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:perimed (not a
% PSI file, or its size does not match the header). Base MATLAB only;
% also runs in GNU Octave.
%
if exist(p, 'file') ~= 2
    error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', p);
end
fid = fopen(p, 'r', 'ieee-le');
if fid < 0, error('NeuroAnalyzer:io:perimed', 'Cannot open %s', p); end
c = onCleanup(@() fclose(fid));
fseek(fid, 0, 'eof'); fileBytes = ftell(fid); fseek(fid, 0, 'bof');
if fileBytes < 46
    error('NeuroAnalyzer:io:perimed', '%s is too short to be a PIMSoft .dat file.', nameOf(p));
end
magic = str(fread(fid, 10, 'uint8=>char')');
if ~strcmp(magic, 'PSI')
    error('NeuroAnalyzer:io:perimed', '%s is not a PIMSoft (PeriCam PSI) .dat file: it does not start with PSI.', nameOf(p));
end
P.version = fread(fid, 1, 'int32');
P.gain = fread(fid, 1, 'double');
P.beta = fread(fid, 1, 'double');
nImages = fread(fid, 1, 'double');
P.width = fread(fid, 1, 'int32');
P.height = fread(fid, 1, 'int32');
if ~any(P.version == [1 2 3]) || ~(P.width > 0 && P.height > 0) || ~(nImages >= 2)
    error('NeuroAnalyzer:io:perimed', ['%s: unexpected header (version %g, %g x %g pixels, %g images); ' ...
        'only PIMSoft file versions 1 to 3 are known.'], nameOf(p), P.version, P.width, P.height, nImages);
end
P.nFrames = floor(nImages / 2);
P.name = ''; P.serial = ''; P.startTime = ''; P.durationS = NaN; P.distanceMm = NaN;
P.frameRateText = ''; P.fps = NaN; P.resolutionMm = NaN;
P.notes = {};
if P.version >= 2
    P.name = strAt(fid, 46, 80);
    P.serial = strAt(fid, 126, 20);
    P.startTime = strAt(fid, 146, 20);
    P.durationS = numAt(fid, 166);
    P.distanceMm = numAt(fid, 494);
    P.frameRateText = strAt(fid, 502, 20);
    P.resolutionMm = numAt(fid, 522);
    tok = regexp(strrep(P.frameRateText, ',', '.'), '[\d.]+', 'match', 'once');
    if ~isempty(tok), P.fps = str2double(tok); end
end
switch P.version
    case 1, P.dataOffset = 46;
    case 2, P.dataOffset = 540;
    otherwise, P.dataOffset = 581 + 32 * P.nFrames;
end
H = P.height; W = P.width; N = P.nFrames;
need = P.dataOffset + 2 * N * H * W * 8;
if fileBytes < need
    error('NeuroAnalyzer:io:perimed', ['%s is %d bytes, but its header (version %d, %d frames of %d x %d ' ...
        'pixels) needs %d: the file is cut short or its layout is not the known one.'], nameOf(p), ...
        fileBytes, P.version, N, W, H, need);
end
if fileBytes > need
    P.notes{end+1} = sprintf('%d bytes after the images were not read.', fileBytes - need);
end
fseek(fid, P.dataOffset, 'bof');
P.variance = zeros(H, W, N);
P.intensity = zeros(H, W, N);
for k = 1:N, P.variance(:, :, k) = fread(fid, [H W], 'double'); end
for k = 1:N, P.intensity(:, :, k) = fread(fid, [H W], 'double'); end
[P.contrast, P.perfusion] = perimedPerfusion(P.variance, P.intensity, P.beta, P.gain);
P.notes{end+1} = sprintf('PIMSoft file version %d: %d frames of %d x %d pixels, beta %g, gain %g.', ...
    P.version, N, W, H, P.beta, P.gain);
if isfinite(P.fps)
    P.notes{end+1} = sprintf('Frame rate %g images/s (from "%s").', P.fps, P.frameRateText);
end
if isfinite(P.resolutionMm) && P.resolutionMm > 0
    P.notes{end+1} = sprintf('Resolution %g mm per pixel.', P.resolutionMm);
end
end

%% ------------------------------------------------------------------------
function s = strAt(fid, pos, n)
fseek(fid, pos, 'bof');
s = str(fread(fid, n, 'uint8=>char')');
end

function v = numAt(fid, pos)
fseek(fid, pos, 'bof');
v = fread(fid, 1, 'double');
if isempty(v), v = NaN; end
end

function s = str(c)
k = find(c == char(0), 1);
if ~isempty(k), c = c(1:k-1); end
s = strtrim(c);
end

function n = nameOf(p)
[~, a, b] = fileparts(p);
n = [a b];
end
