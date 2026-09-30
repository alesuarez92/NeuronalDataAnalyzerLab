function out = writeBiopacACQ(file, channels, sampleTimeMs, varargin)
% writeBiopacACQ - Write a synthetic BIOPAC AcqKnowledge .acq file (4.1 layout) from arrays.
%
% out = writeBiopacACQ(file, channels, sampleTimeMs, Name, Value, ...)
%
% Writes channels in the AcqKnowledge 4.1 layout (file revision 84) that
% readBiopacACQ reads (see its header for the layout and sources: BIOPAC
% Application Note 156 and bioread's notes). Used to make demo and test
% files; not a replacement for AcqKnowledge, and header fields that the
% readers do not use are left at zero.
%
% Inputs:
%   file          output .acq path
%   channels      struct array with fields
%                   name, units   text (up to 39 / 19 bytes)
%                   data          1 x n values in physical units
%                   divider       frequency divider (1 = base rate; the
%                                 channel has one sample every divider
%                                 base samples)
%                   type          'int16' (default: stored as int16 with
%                                 scale and offset) or 'double'
%                   scale, offset int16 scaling: value = raw * scale + offset
%                                 (default: chosen from the data's range)
%   sampleTimeMs  milliseconds per sample at the base rate
% Options (Name, Value):
%   'Markers'     struct array: sample (base-rate index from 0), channel
%                 (index into channels, 0 = all), type (4 chars, default
%                 'defl'), text
%   'Compressed'  true: one zlib stream per channel after the journal
%                 (needs Java); default false (interleaved samples)
%   'ByteOrder'   'le' (Windows, default) or 'be' (Mac); compressed data
%                 are little-endian in both
% Output:
%   out - struct: revision (84), nChannels, dataStart (byte offset of the
%         samples or of the markers when compressed), scale, offset
% Toolboxes: none (base MATLAB; also runs in Octave).
%
opt = struct('Markers', struct('sample', {}, 'channel', {}, 'type', {}, 'text', {}), ...
    'Compressed', false, 'ByteOrder', 'le');
for k = 1:2:numel(varargin), opt.(varargin{k}) = varargin{k+1}; end
mf = 'ieee-le';
if strcmpi(opt.ByteOrder, 'be'), mf = 'ieee-be'; end
nCh = numel(channels);
rev = 84; graphLen = 1564; chanLen = 1716;

% Channel settings and raw values
raw = cell(1, nCh); bytes = zeros(1, nCh); scale = ones(1, nCh); offset = zeros(1, nCh);
divs = ones(1, nCh); n = zeros(1, nCh);
for k = 1:nCh
    c = channels(k);
    v = double(c.data(:)');
    n(k) = numel(v);
    if isfield(c, 'divider') && ~isempty(c.divider), divs(k) = c.divider; end
    isDouble = isfield(c, 'type') && strcmpi(c.type, 'double');
    if isDouble
        bytes(k) = 8;
        raw{k} = v;
    else
        bytes(k) = 2;
        if isfield(c, 'scale') && ~isempty(c.scale)
            scale(k) = c.scale; offset(k) = c.offset;
        else
            lo = min(v); hi = max(v);
            if hi <= lo, hi = lo + 1; end
            offset(k) = (lo + hi) / 2;
            scale(k) = (hi - lo) / 65000;
        end
        raw{k} = int16(round((v - offset(k)) / scale(k)));
    end
end

fid = fopen(file, 'w', mf);
if fid < 0, error('NeuroAnalyzer:io:acq', 'Cannot write %s', file); end
c = onCleanup(@() fclose(fid));

% --- Graph header ---
fwrite(fid, zeros(1, graphLen), 'uint8');
putAt(fid, 2, rev, 'int32');
putAt(fid, 6, graphLen, 'int32');
putAt(fid, 10, nCh, 'int16');
putAt(fid, 14, 4, 'int16');                        % nCurChannel (as AcqKnowledge 4.1 writes)
putAt(fid, 16, sampleTimeMs, 'float64');
putAt(fid, 972, double(opt.Compressed), 'int32');

% --- Channel headers ---
for k = 1:nCh
    base = graphLen + (k - 1) * chanLen;
    fseek(fid, base, 'bof');
    fwrite(fid, zeros(1, chanLen), 'uint8');
    putAt(fid, base, chanLen, 'int32');
    putAt(fid, base + 4, k, 'int16');
    putText(fid, base + 6, channels(k).name, 40);
    putText(fid, base + 68, channels(k).units, 20);
    putAt(fid, base + 88, n(k), 'int32');
    putAt(fid, base + 92, scale(k), 'float64');
    putAt(fid, base + 100, offset(k), 'float64');
    putAt(fid, base + 108, k, 'int16');            % display order
    putAt(fid, base + 152, divs(k), 'int16');
end
pos = graphLen + nCh * chanLen;

% --- Foreign data (its int32 length includes itself), then the data types ---
fseek(fid, pos, 'bof');
fwrite(fid, 8, 'int32'); fwrite(fid, 0, 'int32');
for k = 1:nCh
    if bytes(k) == 8
        fwrite(fid, [8 1], 'int16');
    else
        fwrite(fid, [2 2], 'int16');
    end
end
dataStart = ftell(fid);

% --- Interleaved samples ---
if ~opt.Compressed
    seq = interleaveOrder(n, divs);
    sz = bytes(seq);
    stream = zeros(1, sum(sz), 'uint8');
    start = cumsum([0 sz(1:end-1)]);
    for k = 1:nCh
        B = sampleBytes(raw{k}, bytes(k), mf);       % bytes(k) x n(k)
        s0 = start(seq == k);
        stream(s0 + (1:bytes(k))') = B;
    end
    fwrite(fid, stream, 'uint8');
end

% --- Markers ---
mk = opt.Markers;
fwrite(fid, 25 + sum(arrayfun(@(m) 16 + numel(unicode2native(char(m.text), 'UTF-8')) + 1, mk)), 'int32');
fwrite(fid, numel(mk) + 1, 'int32');
fwrite(fid, numel(mk), 'int32');
fwrite(fid, [1 0 0 255 255 255], 'uint8');
fwrite(fid, uint8('defl'), 'uint8'); fwrite(fid, 0, 'uint8');
fwrite(fid, 256, 'int16');
for k = 1:numel(mk)
    m = mk(k);
    typ = 'defl';
    if isfield(m, 'type') && ~isempty(m.type), typ = m.type; end
    typ = [char(typ) blanks(4)];
    fwrite(fid, m.sample, 'uint32');
    fwrite(fid, [1 0 0 255], 'uint8');
    ch = -1;
    if m.channel > 0, ch = m.channel; end           % the display order equals the index here
    fwrite(fid, ch, 'int16');
    fwrite(fid, uint8(typ(1:4)), 'uint8');
    txt = [uint8(unicode2native(char(m.text), 'UTF-8')) 0];
    fwrite(fid, numel(txt), 'int16');
    fwrite(fid, txt, 'uint8');
end

% --- Journal: only its length (4 bytes: no journal text) ---
fwrite(fid, 4, 'int32');

% --- Compressed channel data ---
if opt.Compressed
    fwrite(fid, zeros(1, 52), 'uint8');               % main compression header, no strings
    for k = 1:nCh
        u = sampleBytes(raw{k}, bytes(k), 'ieee-le');
        z = zlibDeflate(u(:));
        lab = uint8(unicode2native(char(channels(k).name), 'UTF-8'));
        unt = uint8(unicode2native(char(channels(k).units), 'UTF-8'));
        fwrite(fid, zeros(1, 44), 'uint8');
        fwrite(fid, [numel(lab) numel(unt) numel(u) numel(z)], 'int32');
        fwrite(fid, lab, 'uint8'); fwrite(fid, unt, 'uint8');
        fwrite(fid, z, 'uint8');
    end
end
out = struct('revision', rev, 'nChannels', nCh, 'dataStart', dataStart, 'scale', scale, 'offset', offset);
end

%% ------------------------------------------------------------------------
function putAt(fid, pos, v, type)
fseek(fid, pos, 'bof');
fwrite(fid, v, type);
end

function putText(fid, pos, s, len)
b = uint8(unicode2native(char(s), 'UTF-8'));
b = b(1:min(numel(b), len - 1));
fseek(fid, pos, 'bof');
fwrite(fid, [b zeros(1, len - numel(b), 'uint8')], 'uint8');
end

%% interleaveOrder - Channel of each sample in the stream (base tick by base tick)
function seq = interleaveOrder(n, divs)
nCh = numel(n);
left = n;
seq = zeros(1, sum(n));
i = 0; tick = 0;
while any(left > 0)
    for k = 1:nCh
        if left(k) > 0 && mod(tick, divs(k)) == 0
            i = i + 1; seq(i) = k; left(k) = left(k) - 1;
        end
    end
    tick = tick + 1;
end
end

%% sampleBytes - bytes x n matrix of the samples in the given byte order
function B = sampleBytes(v, b, mf)
if b == 2
    B = reshape(typecast(int16(v(:)'), 'uint8'), 2, []);
else
    B = reshape(typecast(double(v(:)'), 'uint8'), 8, []);
end
if strcmp(mf, 'ieee-be'), B = flipud(B); end
end

%% zlibDeflate - zlib stream of bytes u (Java runtime of MATLAB or Octave)
function z = zlibDeflate(u)
if ~usejava('jvm')
    error('NeuroAnalyzer:io:acq', 'Writing a compressed .acq file needs Java.');
end
os = javaObject('java.io.ByteArrayOutputStream');
ds = javaObject('java.util.zip.DeflaterOutputStream', os);
ds.write(typecast(u(:)', 'int8'));
ds.close();
z = typecast(int8(os.toByteArray()), 'uint8');
z = z(:)';
end
