function writePlexon(file, data, fs, varargin)
% writePlexon - Write a synthetic Plexon .plx file for tests and demos.
%
% writePlexon(file, data, fs, Name, Value, ...)
%
% data   channels x samples in volts: continuous (slow) channels WB01 ...
% Options: 'Names' (continuous channel names, default WB01 ...), 'AI'
%          (rows in volts: AI01 ..., same rate), 'Events' struct(channel,
%          sample): event channel number and 1-based samples, 'Spikes'
%          struct(channel, unit, sample) with 32-point waveforms of zeros,
%          'ADFrequency' (timestamp clock, default 40000 Hz), 'Version'
%          (default 107; 102 uses the older gain formula), 'BlockSize'
%          (samples per data block, default 1000), 'Start' (first
%          timestamp in ticks, default 0), 'GapAfter' (a block index after
%          which the next block starts 'GapTicks' later)
% Neural channels: gain 1 x preamp 1000; AI channels: gain 1 x preamp 1;
% 16 bits, SlowMaxMagnitudeMV 5000. Layout as readPlexon reads it (the
% .plx layout of Plexon's SDK, as python-neo reads it). Base MATLAB only;
% also runs in GNU Octave.
%
[nCh, n] = size(data);
o = struct('Names', {{}}, 'AI', zeros(0, n), 'Events', struct('channel', {}, 'sample', {}), ...
    'Spikes', struct('channel', {}, 'unit', {}, 'sample', {}), 'ADFrequency', 40000, ...
    'Version', 107, 'BlockSize', 1000, 'Start', 0, 'GapAfter', 0, 'GapTicks', 0);
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
nAI = size(o.AI, 1);
names = o.Names;
for c = numel(names)+1:nCh, names{c} = sprintf('WB%02d', c); end
for c = 1:nAI, names{nCh + c} = sprintf('AI%02d', c); end
x = [data; o.AI];
preamp = [1000 * ones(1, nCh), ones(1, nAI)];
bits = 16; maxMV = 5000;
if o.Version >= 103
    mvPerBit = maxMV ./ (0.5 * 2^bits * preamp);
else
    mvPerBit = 5000 ./ (2048 * preamp);
end
q = round(x * 1e3 ./ mvPerBit');
q = max(-32768, min(32767, q));
dspCh = unique([o.Spikes.channel]);
evCh = unique([o.Events.channel]);
tick = o.ADFrequency / fs;

fid = fopen(file, 'w', 'ieee-le');
if fid < 0, error('NeuroAnalyzer:io:plexon', 'Cannot write %s', file); end
c = onCleanup(@() fclose(fid));
% Global header (7504 bytes)
G = zeros(1, 7504, 'uint8');
G = putv(G, 0, hex2dec('58454C50'), 'uint32');            % 'PLEX'
G = putv(G, 4, o.Version, 'int32');
G = puts(G, 8, 'NDAL synthetic recording', 128);
G = putv(G, 136, [o.ADFrequency numel(dspCh) numel(evCh) nCh + nAI 32 8 2026 9 30 12 0 0 0 o.ADFrequency], 'int32');
G = putv(G, 192, o.Start + (n - 1) * tick, 'double');
G = putv(G, 200, [1 1 bits bits], 'uint8');
G = putv(G, 204, [3000 maxMV 1000], 'uint16');
G = puts(G, 210, 'NDAL', 18);
ts = zeros(130, 5); ev = zeros(1, 512);
for s = o.Spikes
    if s.channel < 130 && s.unit < 5, ts(s.channel + 1, s.unit + 1) = ts(s.channel + 1, s.unit + 1) + numel(s.sample); end
end
for e = o.Events
    if e.channel < 300, ev(e.channel + 1) = ev(e.channel + 1) + numel(e.sample); end
end
for k = 1:nCh + nAI, ev(300 + k) = n; end
G = putv(G, 256, reshape(ts', 1, []), 'int32');
G = putv(G, 2856, reshape(ts', 1, []), 'int32');
G = putv(G, 5456, ev, 'int32');
fwrite(fid, G, 'uint8');
% Channel headers
for k = 1:numel(dspCh)
    H = zeros(1, 1020, 'uint8');
    H = puts(H, 0, sprintf('SPK%02d', dspCh(k)), 32);
    H = puts(H, 32, sprintf('SIG%03d', dspCh(k)), 32);
    H = putv(H, 64, [dspCh(k) o.ADFrequency dspCh(k) 0 1 0 0 0 1], 'int32');
    fwrite(fid, H, 'uint8');
end
for k = 1:numel(evCh)
    H = zeros(1, 296, 'uint8');
    nm = sprintf('EVT%02d', evCh(k));
    if evCh(k) == 257, nm = 'Strobed'; end
    H = puts(H, 0, nm, 32);
    H = putv(H, 32, evCh(k), 'int32');
    fwrite(fid, H, 'uint8');
end
for k = 1:nCh + nAI
    H = zeros(1, 296, 'uint8');
    H = puts(H, 0, names{k}, 32);
    H = putv(H, 32, [k - 1, fs, 1, 1, preamp(k), 0], 'int32');
    fwrite(fid, H, 'uint8');
end
% Data blocks in time order: 1 spike, 4 event, 5 continuous
B = {};                                                   % {timestamp, bytes}
nB = ceil(n / o.BlockSize);
off = 0;
for b = 1:nB
    i = (b - 1) * o.BlockSize + 1:min(n, b * o.BlockSize);
    t = o.Start + round((i(1) - 1) * tick) + off;
    for k = 1:nCh + nAI
        B(end+1, :) = {t, [blockHeader(5, t, k - 1, 0, 1, numel(i)), typecast(int16(q(k, i)), 'uint8')]}; %#ok<AGROW>
    end
    if b == o.GapAfter, off = off + o.GapTicks; end
end
for e = o.Events
    for j = 1:numel(e.sample)
        t = o.Start + round((e.sample(j) - 1) * tick);
        B(end+1, :) = {t, blockHeader(4, t, e.channel, 0, 0, 0)}; %#ok<AGROW>
    end
end
for s = o.Spikes
    for j = 1:numel(s.sample)
        t = o.Start + round((s.sample(j) - 1) * tick);
        B(end+1, :) = {t, [blockHeader(1, t, s.channel, s.unit, 1, 32), zeros(1, 64, 'uint8')]}; %#ok<AGROW>
    end
end
if ~isempty(B)
    [~, order] = sort([B{:, 1}]);
    fwrite(fid, [B{order, 2}], 'uint8');
end
end

function h = blockHeader(type, t, ch, unit, nWf, nWords)
h = [typecast(uint16([type floor(t / 2^32)]), 'uint8'), typecast(uint32(mod(t, 2^32)), 'uint8'), ...
    typecast(uint16([ch unit nWf nWords]), 'uint8')];
end

function b = putv(b, at, v, prec)
switch prec
    case 'uint8', u = uint8(v);
    case 'uint16', u = typecast(uint16(v), 'uint8');
    case 'uint32', u = typecast(uint32(v), 'uint8');
    case 'int32', u = typecast(int32(v), 'uint8');
    case 'double', u = typecast(double(v), 'uint8');
end
b(at + (1:numel(u))) = u;
end

function b = puts(b, at, s, len)
s = uint8(s(1:min(end, len - 1)));
b(at + (1:numel(s))) = s;
end
