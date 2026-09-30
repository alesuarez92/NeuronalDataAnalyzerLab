%% readXDF.m
% =========================================================================
% READ XDF - LAB STREAMING LAYER RECORDINGS (.xdf, LabRecorder)
% =========================================================================
% [streams, header] = readXDF(file)
%
% Extensible Data Format (sccn/xdf specification), little-endian: 'XDF:'
% then chunks of [NumLengthBytes (1: 1, 4 or 8)][Length][Tag uint16]
% [Content], Length counting the tag and the content. Tags: 1 FileHeader
% (XML), 2 StreamHeader (uint32 stream id + XML <info>: name, type,
% channel_count, nominal_srate, channel_format, desc/channels/channel:
% label, unit, type), 3 Samples (stream id, [NumSampleBytes][NumSamples],
% then per sample: TimeStampBytes (0 = deduced from the previous stamp +
% 1 / nominal rate, 8 = a double follows), the values: float32, double64,
% int8 ... int64, or per channel a length-prefixed UTF-8 string), 4
% ClockOffset (stream id, collection time, offset; doubles), 5 Boundary,
% 6 StreamFooter.
% Clock offsets are applied as pyxdf does by default without its robust
% fit: time stamps + the straight line through the offsets (one offset:
% constant). Jitter is not removed; info.effectiveRate gives the rate
% from the time stamps.
%
% streams  struct array: id, name, type, format, fs (nominal, 0 =
%          irregular), nChannels, labels, units, channelTypes (1 x
%          channels cells), timeStamps (1 x samples, s), data (channels x
%          samples double, or a channels x samples cell of strings),
%          effectiveRate, nClockOffsets
% header   FileHeader XML text
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:xdf.
% Toolboxes: none; also runs in GNU Octave.
% =========================================================================

function [streams, header] = readXDF(p)
if exist(p, 'file') ~= 2
    error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', p);
end
[~, base, ext] = fileparts(p);
name = [base ext];
fid = fopen(p, 'r', 'ieee-le');
c = onCleanup(@() fclose(fid));
r = fread(fid, Inf, 'uint8=>uint8')';
if numel(r) < 4 || ~strcmp(char(r(1:4)), 'XDF:')
    error('NeuroAnalyzer:io:xdf', '%s is not an XDF file (no XDF: magic).', name);
end
header = '';
S = struct('id', {}, 'name', {}, 'type', {}, 'format', {}, 'fs', {}, 'nChannels', {}, 'labels', {}, ...
    'units', {}, 'channelTypes', {}, 'ts', {}, 'x', {}, 'ct', {}, 'cv', {}, 'last', {});
pos = 5;
N = numel(r);
while pos <= N
    [len, pos] = varlen(r, pos);
    if isempty(len) || pos + len - 1 > N, break; end            % cut short
    tag = double(r(pos)) + 256 * double(r(pos + 1));
    body = r(pos + 2:pos + len - 1);
    pos = pos + len;
    switch tag
        case 1
            header = char(body);
        case 2
            id = u32(body, 1);
            S(end + 1) = streamHeader(id, native(body(5:end))); %#ok<AGROW>
        case 3
            k = find([S.id] == u32(body, 1), 1);
            if isempty(k), continue; end
            [S(k), ok] = samples(S(k), body(5:end));
            if ~ok, break; end
        case 4
            k = find([S.id] == u32(body, 1), 1);
            if isempty(k) || numel(body) < 20, continue; end
            S(k).ct(end + 1) = typecast(body(5:12), 'double');
            S(k).cv(end + 1) = typecast(body(13:20), 'double');
    end
end
streams = struct('id', {}, 'name', {}, 'type', {}, 'format', {}, 'fs', {}, 'nChannels', {}, 'labels', {}, ...
    'units', {}, 'channelTypes', {}, 'timeStamps', {}, 'data', {}, 'effectiveRate', {}, 'nClockOffsets', {});
for k = 1:numel(S)
    s = S(k);
    ts = [s.ts{:}];
    if iscell(s.x), x = [s.x{:}]; else, x = s.x; end
    if numel(s.ct) == 1
        ts = ts + s.cv;
    elseif numel(s.ct) > 1
        b = polyfit(s.ct, s.cv, 1);
        ts = ts + polyval(b, ts);
    end
    er = NaN;
    if numel(ts) > 1, er = (numel(ts) - 1) / (ts(end) - ts(1)); end
    streams(end + 1) = struct('id', s.id, 'name', s.name, 'type', s.type, 'format', s.format, 'fs', s.fs, ...
        'nChannels', s.nChannels, 'labels', {s.labels}, 'units', {s.units}, 'channelTypes', {s.channelTypes}, ...
        'timeStamps', ts, 'data', {x}, 'effectiveRate', er, 'nClockOffsets', numel(s.ct)); %#ok<AGROW>
end
end

function s = streamHeader(id, xml)
s.id = id;
s.name = tag(xml, 'name');
s.type = tag(xml, 'type');
s.format = lower(tag(xml, 'channel_format'));
s.fs = str2double(tag(xml, 'nominal_srate'));
if ~isfinite(s.fs), s.fs = 0; end
s.nChannels = str2double(tag(xml, 'channel_count'));
n = s.nChannels;
s.labels = arrayfun(@(k) sprintf('Ch %d', k), 1:n, 'UniformOutput', false);
s.units = repmat({''}, 1, n);
s.channelTypes = repmat({''}, 1, n);
C = regexp(xml, '<channel>(.*?)</channel>', 'tokens');
for k = 1:min(n, numel(C))
    l = tag(C{k}{1}, 'label');
    if ~isempty(l), s.labels{k} = l; end
    s.units{k} = tag(C{k}{1}, 'unit');
    s.channelTypes{k} = tag(C{k}{1}, 'type');
end
s.ts = {};
s.x = {};
s.ct = []; s.cv = [];
s.last = 0;
end

function [s, ok] = samples(s, b)
% One Samples chunk (after the stream id)
ok = true;
[n, i] = varlen(b, 1);
if isempty(n), ok = false; return; end
nc = s.nChannels;
dt = 0;
if s.fs > 0, dt = 1 / s.fs; end
if strcmp(s.format, 'string')
    ts = zeros(1, n); x = cell(nc, n);
    for k = 1:n
        [ts(k), i, s.last] = stamp(b, i, s.last, dt);
        for ch = 1:nc
            [L, i] = varlen(b, i);
            x{ch, k} = native(b(i:i + L - 1));
            i = i + L;
        end
    end
    s.ts{end + 1} = ts;
    s.x{end + 1} = x;
    return;
end
[prec, bps] = precision(s.format);
w = nc * bps;
m = numel(b) - i + 1;
% Fast paths: every sample with a stamp (9 + w bytes) or none (1 + w)
for flag = [8 0]
    stride = 1 + flag + w;
    if m == n * stride && all(b(i + (0:n - 1) * stride) == flag)
        B = reshape(b(i:i + n * stride - 1), stride, n);
        if flag == 8
            ts = typecast(reshape(B(2:9, :), 1, []), 'double');
        else
            ts = s.last + (1:n) * dt;
        end
        s.last = ts(end);
        vals = double(typecast(reshape(B(end - w + 1:end, :), 1, []), prec));
        s.ts{end + 1} = ts;
        s.x{end + 1} = reshape(vals, nc, n);
        return;
    end
end
ts = zeros(1, n); vals = zeros(nc, n);
for k = 1:n
    [ts(k), i, s.last] = stamp(b, i, s.last, dt);
    vals(:, k) = double(typecast(b(i:i + w - 1), prec))';
    i = i + w;
end
s.ts{end + 1} = ts;
s.x{end + 1} = vals;
end

function [t, i, last] = stamp(b, i, last, dt)
if b(i) == 8
    t = typecast(b(i + 1:i + 8), 'double');
    i = i + 9;
else
    t = last + dt;
    i = i + 1;
end
last = t;
end

function [prec, bps] = precision(fmt)
switch fmt
    case 'float32', prec = 'single'; bps = 4;
    case 'double64', prec = 'double'; bps = 8;
    case 'int8', prec = 'int8'; bps = 1;
    case 'int16', prec = 'int16'; bps = 2;
    case 'int32', prec = 'int32'; bps = 4;
    case 'int64', prec = 'int64'; bps = 8;
    otherwise
        error('NeuroAnalyzer:io:xdf', 'Unknown XDF channel format ''%s''.', fmt);
end
end

function [v, i] = varlen(b, i)
% [NumLengthBytes][value]; v = [] when the bytes run out
v = [];
if i > numel(b), return; end
nb = double(b(i));
if ~any(nb == [1 4 8]) || i + nb > numel(b), return; end
v = sum(double(b(i + 1:i + nb)) .* 256 .^ (0:nb - 1));
i = i + 1 + nb;
end

function v = u32(b, i)
v = double(typecast(b(i:i + 3), 'uint32'));
end

function s = native(b)
try
    s = native2unicode(uint8(b), 'UTF-8');
catch
    s = char(b);
end
s = s(:)';
end

function v = tag(xml, name)
t = regexp(xml, ['<' name '>([^<]*)</' name '>'], 'tokens', 'once');
if isempty(t), v = ''; else, v = strtrim(t{1}); end
end
