function acq = readBiopacACQ(p)
% readBiopacACQ - Read a BIOPAC AcqKnowledge .acq file (channels, rates, units, event markers).
%
% acq = readBiopacACQ(file)
%
% BIOPAC MP150 / MP160 systems (e.g. with the LDF100C laser Doppler
% amplifier) record with AcqKnowledge into .acq files. This reader handles
% AcqKnowledge 3.x (file revisions below 61) and 4.x / 5.x (revisions 61
% and above), Windows (little-endian) and Mac (big-endian) files,
% uncompressed and compressed (zlib per channel, read through the Java
% runtime that MATLAB includes).
%
% Layout (BIOPAC Application Note 156 for AcqKnowledge <= 3.9; later
% revisions as documented by bioread, MIT licence,
% https://github.com/uwmadison-chm/bioread, notes/file_format.md and
% bioread/headers.py; implemented from that description, not copied):
%   graph header (lVersion int32 @2 = file revision, which also tells the
%   byte order: read both ways, the smaller value is right; its length
%   lExtItemHeaderLen int32 @6; nChannels int16 @10; dSampleTime float64 @16
%   = ms per sample at the base rate; bCompressed int32 @1936 (revisions
%   41-60) or @972 (61+); from revision 124, hExpectedPaddings int16 @2398
%   40-byte padding headers follow, each starting with its length)
%   -> nChannels channel headers (lChanHeaderLen int32 @0, name char[40]
%   @6, units char[20] @68, lBufLength int32 @88 = samples, dAmplScale
%   float64 @92, dAmplOffset float64 @100, nChanOrder int16 @108, frequency
%   divider int16 @250 (revisions 38-60) or @152 (61+), 0 = 1)
%   -> foreign data header (int16 length for revisions < 61, else int32)
%   -> one data-type header per channel (int16 size, int16 type: 1 = float64,
%   2 = int16; the first position where every channel's pair is valid is
%   used, scanning forward up to 4096 bytes as some files have extra bytes)
%   -> uncompressed: the samples, interleaved by the channels' frequency
%   dividers (at base tick k channel c contributes a sample when
%   mod(k, divider(c)) == 0 and it still has samples; each channel has
%   exactly lBufLength samples)
%   -> event markers (sample index at the base rate, channel = display
%   order number or -1 for all, type code, text)
%   -> journal -> compressed files: one compression header per channel
%   (44 bytes, then int32 label, units, uncompressed and compressed
%   lengths), the label and units text, then the zlib data (little-endian).
% int16 samples are scaled: value = raw * dAmplScale + dAmplOffset;
% float64 samples are used as stored.
%
% Output struct acq:
%   channels  1 x nChannels struct: name, units, fs (Hz), data (1 x n
%             double), divider, order (AcqKnowledge display order)
%   events    struct array: time (s), channel (index into channels, 0 =
%             all channels), type (marker type code, e.g. 'stm'), text
%   info      struct: format 'acq', file, revision, version (e.g. '4.1'),
%             byteOrder ('le' | 'be'), compressed, sampleTimeMs, baseRate,
%             notes (cellstr, plain words)
%
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:acq (not an
% AcqKnowledge file, damaged header, or compressed data without Java).
% Base MATLAB only; also runs in GNU Octave (compressed files need Java).
%
if exist(p, 'file') ~= 2
    error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', p);
end
[rev, mf] = byteOrder(p);
fid = fopen(p, 'r', mf);
c = onCleanup(@() fclose(fid));
fileBytes = fileSize(fid);
post4 = rev >= 61;

% --- Graph header ---
g.extLen = readAt(fid, 6, 'int32');
g.nCh = readAt(fid, 10, 'int16');
g.dt = readAt(fid, 16, 'float64');
if g.nCh < 1 || g.nCh > 1024 || ~(g.dt > 0) || g.extLen < 20 || g.extLen > fileBytes
    error('NeuroAnalyzer:io:acq', ['%s does not look like an AcqKnowledge file (channels %d, sample ' ...
        'time %g ms): is it damaged?'], p, g.nCh, g.dt);
end
g.compressed = false;
if post4
    g.compressed = readAt(fid, 972, 'int32') ~= 0;
elseif rev >= 41
    g.compressed = readAt(fid, 1936, 'int32') ~= 0;
end
pos = g.extLen;
if rev >= 124
    nPad = readAt(fid, 2398, 'int16');
    for k = 1:nPad
        pos = pos + readAt(fid, pos, 'int32');
    end
end

% --- Channel headers ---
nCh = double(g.nCh);
enc = 'ISO-8859-1';
if post4, enc = 'UTF-8'; end
ch = struct('name', {}, 'units', {}, 'fs', {}, 'data', {}, 'divider', {}, 'order', {});
n = zeros(1, nCh); scale = zeros(1, nCh); offset = zeros(1, nCh);
for k = 1:nCh
    len = readAt(fid, pos, 'int32');
    ch(k).name = textAt(fid, pos + 6, 40, enc);
    ch(k).units = textAt(fid, pos + 68, 20, enc);
    n(k) = readAt(fid, pos + 88, 'int32');
    scale(k) = readAt(fid, pos + 92, 'float64');
    offset(k) = readAt(fid, pos + 100, 'float64');
    ch(k).order = readAt(fid, pos + 108, 'int16');
    div = 1;
    if post4
        div = readAt(fid, pos + 152, 'int16');
    elseif rev >= 38
        div = readAt(fid, pos + 250, 'int16');
    end
    if div <= 0, div = 1; end
    ch(k).divider = double(div);
    ch(k).fs = 1000 / g.dt / ch(k).divider;
    if len <= 0 || n(k) < 0
        error('NeuroAnalyzer:io:acq', 'Channel header %d of %s is damaged.', k, p);
    end
    pos = pos + len;
end

% --- Foreign data, then the data-type headers ---
if post4
    pos = pos + readAt(fid, pos, 'int32');
else
    pos = pos + readAt(fid, pos, 'int16');
end
dtype = [];
for s = 0:4095
    fseek(fid, pos + s, 'bof');
    v = fread(fid, [2 nCh], 'int16');
    if size(v, 2) < nCh, break; end
    ok = (v(1, :) == 8 & ismember(v(2, :), [0 1])) | (v(1, :) == 2 & v(2, :) == 2);
    if all(ok)
        dtype = v;
        pos = pos + s + 4 * nCh;
        break;
    end
end
if isempty(dtype)
    error('NeuroAnalyzer:io:acq', 'Could not find the channel data types in %s: the file may be damaged.', p);
end
bytes = dtype(1, :);
dataStart = pos;

% --- Samples (uncompressed: interleaved after the headers) ---
if ~g.compressed
    raw = readInterleaved(fid, dataStart, n, [ch.divider], bytes, mf);
    markerPos = dataStart + sum(n .* bytes);
    for k = 1:nCh
        if bytes(k) == 2
            ch(k).data = raw{k} * scale(k) + offset(k);
        else
            ch(k).data = raw{k};
        end
    end
else
    markerPos = dataStart;
end

% --- Event markers, then (compressed files) the journal and the channel data ---
[events, after] = readMarkers(fid, markerPos, rev, g.dt, enc, [ch.order]);
if g.compressed
    raw = readCompressed(fid, after, rev, n, bytes, nCh, p);
    for k = 1:nCh
        if bytes(k) == 2
            ch(k).data = raw{k} * scale(k) + offset(k);
        else
            ch(k).data = raw{k};
        end
    end
end

acq.channels = ch;
acq.events = events;
notes = {sprintf('BIOPAC AcqKnowledge %s file (revision %d), %s, %d channel(s), base rate %g Hz.', ...
    versionText(rev), rev, ifelse(g.compressed, 'compressed', 'uncompressed'), nCh, 1000 / g.dt)};
divs = unique([ch.divider]);
if numel(divs) > 1
    notes{end+1} = sprintf('Channels are sampled at different rates (%s Hz).', ...
        strjoin(arrayfun(@(x) sprintf('%g', x), unique([ch.fs]), 'UniformOutput', false), ', '));
end
if ~isempty(events)
    notes{end+1} = sprintf('%d event marker(s).', numel(events));
end
acq.info = struct('format', 'acq', 'file', p, 'revision', rev, 'version', versionText(rev), ...
    'byteOrder', ifelse(strcmp(mf, 'ieee-be'), 'be', 'le'), 'compressed', g.compressed, ...
    'sampleTimeMs', g.dt, 'baseRate', 1000 / g.dt, 'notes', {notes});
end

%% ------------------------------------------------------------------------
function [rev, mf] = byteOrder(p)
% The file revision is a small positive number: read it both ways, keep the smaller
fid = fopen(p, 'r', 'ieee-le');
if fid < 0
    error('NeuroAnalyzer:io:fileNotFound', 'Cannot open %s', p);
end
fseek(fid, 2, 'bof');
b = fread(fid, 4, 'uint8=>double')';
fclose(fid);
if numel(b) < 4
    error('NeuroAnalyzer:io:acq', '%s is too short to be an AcqKnowledge file.', p);
end
le = b * [1; 256; 65536; 16777216];
be = b * [16777216; 65536; 256; 1];
if le <= be
    rev = le; mf = 'ieee-le';
else
    rev = be; mf = 'ieee-be';
end
if rev < 30 || rev > 1000
    error('NeuroAnalyzer:io:acq', ['%s is not an AcqKnowledge file (or a revision this reader does not ' ...
        'know: %d).'], p, rev);
end
end

function v = readAt(fid, pos, type)
fseek(fid, pos, 'bof');
v = fread(fid, 1, [type '=>double']);
if isempty(v)
    error('NeuroAnalyzer:io:acq', 'The file ends before its header does: it may be truncated.');
end
end

function s = textAt(fid, pos, len, enc)
fseek(fid, pos, 'bof');
b = fread(fid, len, 'uint8=>uint8')';
z = find(b == 0, 1);
if ~isempty(z), b = b(1:z-1); end
try
    s = strtrim(native2unicode(b, enc));
catch
    s = strtrim(char(b));
end
s = s(:)';
if isempty(s), s = ''; end
end

function n = fileSize(fid)
fseek(fid, 0, 'eof');
n = ftell(fid);
fseek(fid, 0, 'bof');
end

%% readInterleaved - Split the interleaved block into channels (see the header comment)
function out = readInterleaved(fid, pos, n, divs, bytes, mf)
nCh = numel(n);
out = cell(1, nCh);
fseek(fid, pos, 'bof');
if all(divs == divs(1)) && all(bytes == bytes(1)) && all(n == n(1))
    % Every channel at the same rate and type: plain frames
    type = ifelse(bytes(1) == 2, 'int16', 'float64');
    m = fread(fid, [nCh n(1)], [type '=>double']);
    if size(m, 2) < n(1)
        error('NeuroAnalyzer:io:acq', 'The data end early: the file is truncated.');
    end
    for k = 1:nCh, out{k} = m(k, :); end
    return;
end
% General case: the sequence of channels in the stream, tick by tick
L = 1;
for k = 1:nCh, L = lcm(L, divs(k)); end
slot = repmat((0:L-1)', 1, nCh);
use = mod(slot, repmat(divs, L, 1)) == 0;          % L x nCh: channel sampled at this tick
[cc, ~] = find(use');                              % channel of each sample, in tick order
pat = uint16(cc(:)');
per = sum(use, 1);                                 % samples per pattern, per channel
nFull = min(floor(n ./ per));
seq = repmat(pat, 1, nFull);
left = n - nFull * per;
tick = 0;
tail = zeros(1, 0, 'uint16');
while any(left > 0)
    for k = 1:nCh
        if left(k) > 0 && mod(tick, divs(k)) == 0
            tail(end+1) = k; %#ok<AGROW>
            left(k) = left(k) - 1;
        end
    end
    tick = tick + 1;
    if tick > 1e7
        error('NeuroAnalyzer:io:acq', 'The channel sample counts do not fit their rates: the file is damaged.');
    end
end
seq = [seq tail];
sz = uint8(bytes(seq));
total = sum(double(sz));
rawb = fread(fid, total, 'uint8=>uint8');
if numel(rawb) < total
    error('NeuroAnalyzer:io:acq', 'The data end early: the file is truncated.');
end
start = cumsum([0 double(sz(1:end-1))]);          % byte offset of every sample
for k = 1:nCh
    s0 = start(seq == k);
    b = bytes(k);
    B = rawb(s0 + (1:b)');                         % b x n bytes, file order
    if strcmp(mf, 'ieee-be'), B = flipud(B); end
    if b == 2
        out{k} = double(typecast(B(:), 'int16'))';
    else
        out{k} = typecast(B(:), 'double')';
    end
end
end

%% readMarkers - Event markers; returns the position after them (and the journal, for compressed files)
function [ev, pos] = readMarkers(fid, pos, rev, dt, enc, orders)
ev = struct('time', {}, 'channel', {}, 'type', {}, 'text', {});
fseek(fid, pos, 'bof');
if rev >= 61
    if rev >= 128, hdrLen = 41; elseif rev >= 121, hdrLen = 33; else, hdrLen = 25; end
    nMk = readAt(fid, pos + 4, 'int32') - 1;           % lMarkersExtra - 1
    pos = pos + hdrLen;
    if rev >= 128, itemLen = 32; elseif rev >= 121, itemLen = 24; else, itemLen = 16; end
    for k = 1:max(0, nMk)
        smp = readAt(fid, pos, 'uint32');
        chn = readAt(fid, pos + 8, 'int16');
        typ = textAt(fid, pos + 10, 4, enc);
        tl = readAt(fid, pos + itemLen - 2, 'int16');
        txt = textAt(fid, pos + itemLen, max(0, tl), enc);
        ev(end+1) = struct('time', smp * dt / 1000, 'channel', chanIndex(chn, orders), ...
            'type', typ, 'text', txt); %#ok<AGROW>
        pos = pos + itemLen + max(0, tl);
    end
    % Journal: an int32 with the length of the whole journal section (itself included)
    pos = pos + readAt(fid, pos, 'int32');
else
    nMk = readAt(fid, pos + 4, 'int32');
    pos = pos + 8;
    itemLen = ifelse(rev >= 36, 12, 10);
    for k = 1:max(0, nMk)
        smp = readAt(fid, pos, 'int32');
        tl = readAt(fid, pos + itemLen - 2, 'int16');
        if rev >= 36, tl = tl + 1; end
        txt = textAt(fid, pos + itemLen, max(0, tl), enc);
        ev(end+1) = struct('time', smp * dt / 1000, 'channel', 0, 'type', '', 'text', txt); %#ok<AGROW>
        pos = pos + itemLen + max(0, tl);
    end
    journalTag = [68 51 34 17];                        % 0x44332211
    if rev >= 41
        fseek(fid, pos, 'bof');
        tag = fread(fid, 4, 'uint8=>double')';
        if ~isequal(tag, journalTag)
            pos = pos + 84 + 28 * nMk;                 % marker metadata (colour, tag)
        end
    end
    if rev >= 38
        fseek(fid, pos, 'bof');
        tag = fread(fid, 4, 'uint8=>double')';
        if isequal(tag, journalTag)
            pos = pos + 10 + readAt(fid, pos + 6, 'int32');
        end
    end
end
end

function k = chanIndex(order, orders)
k = 0;
if order >= 0
    j = find(orders == order, 1);
    if ~isempty(j), k = j; end
end
end

%% readCompressed - One zlib stream per channel after the main compression header
function out = readCompressed(fid, pos, rev, n, bytes, nCh, p)
if rev >= 61
    s1 = readAt(fid, pos + 24, 'int32');
    s2 = readAt(fid, pos + 28, 'int32');
    pos = pos + 52 + ifelse(rev >= 108, 6, 0) + s1 + s2;
else
    pos = pos + 38 + readAt(fid, pos + 34, 'int32');
end
out = cell(1, nCh);
for k = 1:nCh
    labLen = readAt(fid, pos + 44, 'int32');
    unitLen = readAt(fid, pos + 48, 'int32');
    compLen = readAt(fid, pos + 56, 'int32');
    fseek(fid, pos + 60 + labLen + unitLen, 'bof');
    z = fread(fid, compLen, 'uint8=>uint8');
    u = zlibInflate(z, p);
    if bytes(k) == 2
        v = double(typecast(u(1:2 * floor(numel(u) / 2)), 'int16'));
    else
        v = typecast(u(1:8 * floor(numel(u) / 8)), 'double');
    end
    out{k} = v(1:min(n(k), numel(v)))';
    pos = pos + 60 + labLen + unitLen + compLen;
end
end

%% zlibInflate - Inflate a zlib stream with the Java runtime (MATLAB's JVM, or Octave's)
function u = zlibInflate(z, p)
if ~usejava('jvm')
    error('NeuroAnalyzer:io:acq', ['%s is a compressed AcqKnowledge file and reading it needs Java, which ' ...
        'is not running. Start MATLAB with Java, or save the file uncompressed in AcqKnowledge ' ...
        '(File > Save As, uncheck compression).'], p);
end
% javaObject / javaMethod rather than java.x.y(...) so the same code runs in Octave
in = javaObject('java.util.zip.InflaterInputStream', ...
    javaObject('java.io.ByteArrayInputStream', typecast(z(:), 'int8')));
os = javaObject('java.io.ByteArrayOutputStream');
done = false;
try
    javaMethod('copy', 'org.apache.commons.io.IOUtils', in, os);   % MATLAB ships Apache Commons IO
    done = true;
catch
end
if ~done
    try
        isc = javaMethod('getInterruptibleStreamCopier', 'com.mathworks.mlwidgets.io.InterruptibleStreamCopier');
        isc.copyStream(in, os);
        done = true;
    catch
    end
end
if done
    u = typecast(int8(os.toByteArray()), 'uint8');
else
    u = typecast(int8(in.readAllBytes()), 'uint8');      % Java 9 and later
end
u = u(:);
end

function t = versionText(rev)
known = [38 45 61 68 84 108 124 128 132];
names = {'3.7', '3.9', '4.0 (beta)', '4.0', '4.1', '4.2', '4.3', '4.4', '5.0'};
if rev < 38
    t = '3.x or earlier';
elseif rev > 132
    t = '5.x or later';
else
    t = names{find(known <= rev, 1, 'last')};
end
end

function v = ifelse(c, a, b)
if c, v = a; else, v = b; end
end
