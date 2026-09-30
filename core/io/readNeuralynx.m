%% readNeuralynx.m
% =========================================================================
% READ NEURALYNX - NEURALYNX .ncs CHANNELS (+ Events.nev TTLs) AS A TDT-LIKE STRUCT
% =========================================================================
% rec = readNeuralynx(pathOrFolder)    a .ncs file (every .ncs of its folder
%                                      is read) or the session folder
%
% Neuralynx (Cheetah / Pegasus), little-endian; each file starts with a
% 16384-byte text header of '-Key value' lines:
%   .ncs  one channel: -SamplingFrequency, -ADBitVolts (volts per bit),
%         -InputInverted (True: the sign is flipped), -AcqEntName; then
%         1044-byte records: timestamp uint64 (us), channel uint32, sample
%         rate uint32, number of valid samples uint32, 512 x int16.
%   .nev  events: 184-byte records: 3 x int16, timestamp uint64 (us),
%         event id int16, TTL value int16, crc, 2 dummies (int16), 8 x
%         int32 extra, 128-char text.
% Channels are sorted by name (CSC1, CSC2 ... CSC10) and cut to the
% shortest. Stimulus candidates: each TTL bit that changes in Events.nev
% (0/1, held until the next event), on the channels' time base. Record
% gaps are counted (info.nGaps) and the samples kept contiguous.
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:neuralynx.
% Toolboxes: none; also runs in GNU Octave.
% =========================================================================

function rec = readNeuralynx(p)
if exist(p, 'dir') == 7
    folder = p;
elseif exist(p, 'file') == 2
    folder = fileparts(p);
else
    error('NeuroAnalyzer:io:fileNotFound', 'File or folder not found: %s', p);
end
d = dir(fullfile(folder, '*.ncs'));
d = d([d.bytes] > 16384);
if isempty(d)
    error('NeuroAnalyzer:io:neuralynx', 'No .ncs files with samples in %s.', folder);
end
names = {d.name};
[~, o] = sort(naturalKey(names));
names = names(o);
nCh = numel(names);
data = cell(1, nCh); labels = cell(1, nCh); fsAll = zeros(1, nCh); t0 = zeros(1, nCh); nGaps = 0;
for k = 1:nCh
    [data{k}, H, ts] = readNcs(fullfile(folder, names{k}));
    fsAll(k) = H.fs;
    labels{k} = H.name;
    t0(k) = ts(1);
    step = 512 / H.fs * 1e6;
    nGaps = max(nGaps, sum(abs(diff(ts) - step) > step / 2));
end
if numel(unique(round(fsAll))) > 1
    error('NeuroAnalyzer:io:neuralynx', 'The .ncs files have different sample rates (%s Hz).', mat2str(unique(fsAll)));
end
fs = fsAll(1);
n = min(cellfun(@numel, data));
raw = zeros(nCh, n);
for k = 1:nCh, raw(k, :) = data{k}(1:n); end
stim = []; stimNames = {}; stimKinds = {};
nev = fullfile(folder, 'Events.nev');
if exist(nev, 'file') ~= 2
    e = dir(fullfile(folder, '*.nev'));
    if ~isempty(e), nev = fullfile(folder, e(1).name); end
end
if exist(nev, 'file') == 2
    [ets, ttl] = readNev(nev);
    if ~isempty(ets)
        idx = round((ets - t0(1)) * fs / 1e6) + 1;
        vals = mod(double(ttl), 65536);                   % TTL words are stored as int16
        for b = 0:15
            bit = bitget(vals, b + 1);
            if ~any(bit), continue; end
            s = zeros(1, n);
            for k = 1:numel(idx)
                if idx(k) > n, break; end
                s(max(1, idx(k)):n) = bit(k);
            end
            stim(end+1, :) = s; %#ok<AGROW>
            stimNames{end+1} = sprintf('TTL bit %d', b); %#ok<AGROW>
            stimKinds{end+1} = 'digital'; %#ok<AGROW>
        end
    end
end
info = struct('source', 'Neuralynx', 'format', 'neuralynx', 'file', folder, ...
    'blockname', lastPart(folder), 'channelNames', {labels}, 'nGaps', nGaps, 'firstTimestampUs', t0(1));
if ~isempty(stimNames)
    info.stimNames = stimNames;
    info.stimKinds = stimKinds;
end
rec = EphysSource.makeRecording(raw, fs, stim, fs, info);
end

function [v, H, ts] = readNcs(f)
fid = fopen(f, 'r', 'ieee-le');
c = onCleanup(@() fclose(fid));
txt = fread(fid, [1 16384], 'uint8=>char');
H.fs = key(txt, 'SamplingFrequency', NaN);
bitVolts = key(txt, 'ADBitVolts', NaN);
tok = regexp(txt, '-AcqEntName\s+([^\r\n]*)', 'tokens', 'once');
[~, b] = fileparts(f);
if isempty(tok), H.name = b; else, H.name = strtrim(tok{1}); end
inv = regexp(txt, '-InputInverted\s+(\S+)', 'tokens', 'once');
sgn = 1;
if ~isempty(inv) && strcmpi(inv{1}, 'true'), sgn = -1; end
fseek(fid, 0, 'eof'); nB = ftell(fid);
nRec = floor((nB - 16384) / 1044);
fseek(fid, 16384, 'bof');
r = fread(fid, [1044 nRec], 'uint8=>uint8');
ts = zeros(1, nRec);
for i = 8:-1:1, ts = ts * 256 + double(r(i, :)); end
fsRec = double(typecast(reshape(r(13:16, :), 1, []), 'uint32'));
nValid = double(typecast(reshape(r(17:20, :), 1, []), 'uint32'));
s = reshape(typecast(reshape(r(21:end, :), 1, []), 'int16'), 512, nRec);
if ~isfinite(H.fs) && ~isempty(fsRec), H.fs = fsRec(1); end
if ~isfinite(bitVolts)
    error('NeuroAnalyzer:io:neuralynx', '%s has no -ADBitVolts in its header.', f);
end
keep = false(512, nRec);
for k = 1:nRec, keep(1:min(512, nValid(k)), k) = true; end
v = sgn * bitVolts * double(s(keep))';
end

function [ts, ttl] = readNev(f)
fid = fopen(f, 'r', 'ieee-le');
c = onCleanup(@() fclose(fid));
fseek(fid, 0, 'eof'); nB = ftell(fid);
nRec = floor((nB - 16384) / 184);
fseek(fid, 16384, 'bof');
r = fread(fid, [184 nRec], 'uint8=>uint8');
if isempty(r), ts = []; ttl = []; return; end
ts = zeros(1, nRec);
for i = 14:-1:7, ts = ts * 256 + double(r(i, :)); end
ttl = double(typecast(reshape(r(17:18, :), 1, []), 'int16'));
end

function v = key(txt, name, default)
tok = regexp(txt, ['-' name '\s+([-+0-9.eE]+)'], 'tokens', 'once');
if isempty(tok), v = default; else, v = str2double(tok{1}); end
end

function k = naturalKey(names)
% Pad every run of digits so 'CSC10' sorts after 'CSC9'
k = cell(size(names));
for i = 1:numel(names)
    [tok, rest] = regexp(names{i}, '\d+', 'match', 'split');
    s = rest{1};
    for j = 1:numel(tok), s = [s sprintf('%012d', str2double(tok{j})) rest{j+1}]; end %#ok<AGROW>
    k{i} = lower(s);
end
end

function s = lastPart(p)
[~, a, b] = fileparts(p);
s = [a b];
end
