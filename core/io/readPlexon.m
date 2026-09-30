%% readPlexon.m
% =========================================================================
% READ PLEXON - PLEXON .plx (OmniPlex / MAP) AS A TDT-LIKE STRUCT
% =========================================================================
% rec = readPlexon(file)
%
% Plexon .plx data file (layout of Plexon's SDK, as python-neo reads it),
% little-endian:
%   global header, 7504 bytes: magic 'PLEX' (0x58454C50), version @4,
%   comment @8, ADFrequency (timestamp clock, Hz) @136, numbers of spike
%   (DSP), event and slow channels @140 / 144 / 148, date @160, bits per
%   spike / slow sample @202 / 203, SpikeMaxMagnitudeMV @204,
%   SlowMaxMagnitudeMV @206, SpikePreAmpGain @208 (version 105+);
%   then 1020 bytes per spike channel, 296 per event channel (name,
%   channel @32) and 296 per slow channel (name, channel @32, ADFreq @36,
%   Gain @40, PreampGain @48);
%   then data blocks: 16-byte header (type uint16: 1 spike, 4 event, 5
%   continuous; upper timestamp byte uint16; timestamp uint32 in ticks of
%   ADFrequency; channel, unit, number of waveforms, words per waveform,
%   uint16) and the int16 samples.
%   Continuous mV per bit: version 103+: SlowMaxMagnitudeMV / (0.5 x
%   2^BitsPerSlowSample x Gain x PreampGain); 102: 5000 / (2048 x Gain x
%   PreampGain); 100-101: 5000 / (2048 x Gain x 1000).
% Neural channels: the continuous channels of one group, by name prefix
% (WB wideband first, then SPKC, FP, or the largest group, e.g. AD in MAP
% files), in volts, placed by their block timestamps (gaps filled with
% zeros, info.nGaps). Stimulus candidates: AI / AIF channels (volts, put
% on the neural time base) and each event channel with events (a 1 ms
% pulse at each event; start / stop and strobed events are left out).
% Sorted spike times go to info.spikes (channel, unit, times in s from
% the first sample; unit 0 = unsorted).
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:plexon.
% Toolboxes: none; also runs in GNU Octave.
% =========================================================================

function rec = readPlexon(p)
if exist(p, 'file') ~= 2
    error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', p);
end
[~, base, ext] = fileparts(p);
fid = fopen(p, 'r', 'ieee-le');
c = onCleanup(@() fclose(fid));
r = fread(fid, Inf, 'uint8=>uint8')';
if numel(r) < 7504 || u32(r, 0) ~= hex2dec('58454C50')
    error('NeuroAnalyzer:io:plexon', '%s%s is not a Plexon .plx file.', base, ext);
end
ver = i32(r, 4);
adFreq = i32(r, 136);
nDsp = i32(r, 140); nEv = i32(r, 144); nSlow = i32(r, 148);
bitsSlow = double(r(204)); maxMV = u16(r, 206);
if bitsSlow == 0, bitsSlow = double(r(203)); end
at = 7504 + 1020 * nDsp;
evNames = cell(1, nEv); evChan = zeros(1, nEv);
for k = 1:nEv
    h = at + (k - 1) * 296;
    evNames{k} = str(r, h, 32); evChan(k) = i32(r, h + 32);
end
at = at + 296 * nEv;
S = struct('name', cell(1, nSlow), 'chan', 0, 'fs', 0, 'mvPerBit', 0);
for k = 1:nSlow
    h = at + (k - 1) * 296;
    S(k).name = str(r, h, 32);
    S(k).chan = i32(r, h + 32);
    S(k).fs = i32(r, h + 36);
    gain = i32(r, h + 40); pre = i32(r, h + 48);
    if ver >= 103
        S(k).mvPerBit = maxMV / (0.5 * 2^bitsSlow * gain * pre);
    elseif ver == 102
        S(k).mvPerBit = 5000 / (2048 * gain * pre);
    else
        S(k).mvPerBit = 5000 / (2048 * gain * 1000);
    end
end
at = at + 296 * nSlow;
% Walk the data blocks
cap = 1024; nB = 0;
B = zeros(cap, 6);                                        % type, ticks, channel, unit, first byte, words
pos = at;
N = numel(r);
while pos + 16 <= N
    q = double(r(pos + (1:16)));
    words = (q(13) + 256 * q(14)) * (q(15) + 256 * q(16));
    if pos + 16 + 2 * words > N, break; end
    nB = nB + 1;
    if nB > cap, cap = 2 * cap; B(cap, 1) = 0; end
    t = (q(3) + 256 * q(4)) * 2^32 + q(5) + 256 * q(6) + 65536 * q(7) + 16777216 * q(8);
    B(nB, :) = [q(1) + 256 * q(2), t, q(9) + 256 * q(10), q(11) + 256 * q(12), pos + 17, words];
    pos = pos + 16 + 2 * words;
end
B = B(1:nB, :);
% Continuous channels with samples, grouped by name prefix
cont = B(B(:, 1) == 5, :);
has = arrayfun(@(s) any(cont(:, 3) == s.chan), S);
S = S(has);
if isempty(S)
    error('NeuroAnalyzer:io:plexon', '%s%s has no continuous channels with samples.', base, ext);
end
pre = cell(1, numel(S));
for k = 1:numel(S)
    tok = regexp(S(k).name, '^\D+', 'match', 'once');
    if isempty(tok), tok = S(k).name; end
    pre{k} = tok;
end
isAI = ismember(upper(pre), {'AI', 'AIF'});
groups = unique(pre(~isAI));
notes = {};
if isempty(groups)
    groups = unique(pre); isAI(:) = false;
end
pick = '';
for g = {'WB', 'SPKC', 'SP', 'FP', 'FPL'}
    m = strcmpi(groups, g{1});
    if any(m), pick = groups{find(m, 1)}; break; end
end
if isempty(pick)
    cnt = cellfun(@(g) sum(strcmp(pre, g)), groups);
    [~, i] = max(cnt); pick = groups{i};
end
neural = find(strcmp(pre, pick) & ~isAI);
fsN = mode([S(neural).fs]);
neural = neural([S(neural).fs] == fsN);
left = setdiff(groups, {pick});
if ~isempty(left)
    notes{end+1} = sprintf('%s channels used; %s left out.', pick, strjoin(left, ', '));
end
tickN = adFreq / fsN;
first = inf;
for k = neural, first = min(first, min(cont(cont(:, 3) == S(k).chan, 2))); end
t0 = first;
[x, nGaps] = channel(r, cont(cont(:, 3) == S(neural(1)).chan, :), t0, tickN, 0);
n = numel(x);
raw = zeros(numel(neural), n);
for j = 1:numel(neural)
    v = channel(r, cont(cont(:, 3) == S(neural(j)).chan, :), t0, tickN, n);
    raw(j, :) = v * S(neural(j)).mvPerBit * 1e-3;
end
% Stimulus candidates
stim = []; stimNames = {}; stimKinds = {};
tN = t0 + (0:n-1) * tickN;
for k = find(isAI)
    tk = adFreq / S(k).fs;
    blk = cont(cont(:, 3) == S(k).chan, :);
    t0k = min(blk(:, 2));
    v = channel(r, blk, t0k, tk, 0) * S(k).mvPerBit * 1e-3;
    tv = t0k + (0:numel(v)-1) * tk;
    if numel(v) > 1
        s = interp1(tv, v, tN, 'nearest', 0);
    else
        s = zeros(1, n);
    end
    stim(end+1, :) = s; %#ok<AGROW>
    stimNames{end+1} = S(k).name; stimKinds{end+1} = 'analog'; %#ok<AGROW>
end
evB = B(B(:, 1) == 4, :);
w = max(1, round(fsN * 1e-3));
for k = 1:nEv
    if any(evChan(k) == [257 258 259]), continue; end
    t = evB(evB(:, 3) == evChan(k), 2);
    if isempty(t), continue; end
    on = round((t' - t0) / tickN) + 1;
    on = on(on >= 1 & on <= n);
    stim(end+1, :) = EphysSource.eventsToSquare(on, on + w, n); %#ok<AGROW>
    nm = evNames{k};
    if isempty(nm), nm = sprintf('Event %d', evChan(k)); end
    stimNames{end+1} = nm; stimKinds{end+1} = 'digital'; %#ok<AGROW>
end
% Spike times
spB = B(B(:, 1) == 1, :);
spikes = struct('channel', {}, 'unit', {}, 'times', {});
if ~isempty(spB)
    cu = unique(spB(:, 3:4), 'rows');
    for k = 1:size(cu, 1)
        m = spB(:, 3) == cu(k, 1) & spB(:, 4) == cu(k, 2);
        spikes(end+1) = struct('channel', cu(k, 1), 'unit', cu(k, 2), 'times', (spB(m, 2)' - t0) / adFreq); %#ok<AGROW>
    end
end
info = struct('source', sprintf('Plexon .plx (version %d)', ver), 'format', 'plexon', 'file', p, ...
    'blockname', base, 'channelNames', {{S(neural).name}}, 'nGaps', nGaps, ...
    'firstTimestamp', t0 / adFreq, 'spikes', spikes);
if ~isempty(notes), info.notes = notes; end
if ~isempty(stimNames)
    info.stimNames = stimNames;
    info.stimKinds = stimKinds;
end
rec = EphysSource.makeRecording(raw, fsN, stim, fsN, info);
end

function [x, nGaps] = channel(r, blk, t0, tick, n)
% Samples of one continuous channel placed by block timestamps
[~, o] = sort(blk(:, 2)); blk = blk(o, :);
idx = round((blk(:, 2) - t0) / tick) + 1;
if n == 0, n = max(idx + blk(:, 6) - 1); end
x = zeros(1, n);
for b = 1:size(blk, 1)
    v = double(typecast(r(blk(b, 5) + (0:2 * blk(b, 6) - 1)), 'int16'));
    i = idx(b) + (0:numel(v) - 1);
    ok = i >= 1 & i <= n;
    x(i(ok)) = v(ok);
end
nGaps = sum(idx(2:end) ~= idx(1:end-1) + blk(1:end-1, 6));
end

function v = u16(r, at), v = double(r(at + 1)) + 256 * double(r(at + 2)); end
function v = u32(r, at), v = double(typecast(r(at + (1:4)), 'uint32')); end
function v = i32(r, at), v = double(typecast(r(at + (1:4)), 'int32')); end
function s = str(r, at, len)
b = r(at + (1:len));
z = find(b == 0, 1);
if ~isempty(z), b = b(1:z - 1); end
s = strtrim(char(b));
end
