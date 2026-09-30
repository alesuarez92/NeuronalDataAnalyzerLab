%% readOpenEphysLegacy.m
% =========================================================================
% READ OPEN EPHYS LEGACY - .continuous FILES (+ all_channels.events) AS A TDT-LIKE STRUCT
% =========================================================================
% rec = readOpenEphysLegacy(pathOrFolder)   a .continuous file (its folder
%                                           is read) or the folder
%
% The "Open Ephys" data format of the GUI before 0.6 (documented on
% open-ephys.github.io): one .continuous file per channel, each with a
% 1024-byte text header ("header.sampleRate = 30000; header.bitVolts =
% 0.195; header.channel = 'CH1'; ...") and records of: timestamp int64,
% number of samples uint16, recording number uint16 (little-endian), 1024
% samples int16 BIG-endian, 10 marker bytes (0 ... 9). bitVolts is in uV
% for CH channels and in V for ADC / AUX channels.
% all_channels.events: 1024-byte header, 16-byte records: timestamp int64
% (samples), sample position int16, event type uint8 (3 = TTL), processor
% uint8, event id uint8 (1 rising, 0 falling), channel uint8, recording
% number uint16.
% Neural channels: CH files, sorted by number (the first processor
% prefix); stimulus candidates: ADC channels (volts), then each TTL
% channel (0/1 square wave from its rising / falling events). Only the
% first recording number is used when there are several (info.notes).
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:openephys.
% Toolboxes: none; also runs in GNU Octave.
% =========================================================================

function rec = readOpenEphysLegacy(p)
if exist(p, 'dir') == 7, folder = p;
elseif exist(p, 'file') == 2, folder = fileparts(p);
else, error('NeuroAnalyzer:io:fileNotFound', 'File or folder not found: %s', p);
end
d = dir(fullfile(folder, '*.continuous'));
if isempty(d)
    error('NeuroAnalyzer:io:openephys', 'No .continuous files in %s.', folder);
end
names = {d.name};
tok = regexp(names, '^(\d+)_(CH|ADC|AUX)(\d+)(_\d+)?\.continuous$', 'tokens', 'once');
ok = ~cellfun(@isempty, tok);
if ~any(ok)
    error('NeuroAnalyzer:io:openephys', '%s has .continuous files, but none named <processor>_CH<n>.continuous.', folder);
end
names = names(ok); tok = tok(ok);
proc = cellfun(@(t) t{1}, tok, 'UniformOutput', false);
first = proc{1};
keep = strcmp(proc, first);
names = names(keep); tok = tok(keep);
kind = cellfun(@(t) t{2}, tok, 'UniformOutput', false);
num = cellfun(@(t) str2double(t{3}), tok);
notes = {};
if any(~keep), notes{end+1} = sprintf('Processor %s used (other processors'' files left out).', first); end
chFiles = sortBy(names(strcmp(kind, 'CH')), num(strcmp(kind, 'CH')));
adcFiles = sortBy(names(strcmp(kind, 'ADC')), num(strcmp(kind, 'ADC')));
if isempty(chFiles), chFiles = adcFiles; adcFiles = {}; end
[raw, fs, labels, ts0, nRec] = readSet(folder, chFiles);
if nRec > 1, notes{end+1} = sprintf('%d recordings in the files: the first is used.', nRec); end
n = size(raw, 2);
stim = []; stimNames = {}; stimKinds = {};
if ~isempty(adcFiles)
    [a, ~, al] = readSet(folder, adcFiles, n);
    stim = a; stimNames = al; stimKinds = repmat({'analog'}, 1, numel(al));
end
ev = fullfile(folder, 'all_channels.events');
if exist(ev, 'file') == 2
    fid = fopen(ev, 'r', 'ieee-le');
    fseek(fid, 0, 'eof'); nb = ftell(fid);
    nE = floor((nb - 1024) / 16);
    fseek(fid, 1024, 'bof');
    r = fread(fid, [16 nE], 'uint8=>uint8');
    fclose(fid);
    if ~isempty(r)
        t = zeros(1, nE);
        for i = 8:-1:1, t = t * 256 + double(r(i, :)); end
        type = r(11, :); id = r(13, :); chan = double(r(14, :));
        isTTL = type == 3;
        for c = unique(chan(isTTL))
            m = isTTL & chan == c;
            on = t(m & id == 1) - ts0 + 1;
            off = t(m & id == 0) - ts0 + 1;
            stim(end+1, :) = EphysSource.eventsToSquare(on, off, n); %#ok<AGROW>
            stimNames{end+1} = sprintf('TTL %d', c + 1); %#ok<AGROW>
            stimKinds{end+1} = 'digital'; %#ok<AGROW>
        end
    end
end
info = struct('source', 'Open Ephys (legacy .continuous)', 'format', 'openephyslegacy', 'file', folder, ...
    'blockname', lastPart(folder), 'channelNames', {labels}, 'firstTimestamp', ts0);
if ~isempty(notes), info.notes = notes; end
if ~isempty(stimNames)
    info.stimNames = stimNames;
    info.stimKinds = stimKinds;
end
rec = EphysSource.makeRecording(raw, fs, stim, fs, info);
end

function [x, fs, labels, ts0, nRec] = readSet(folder, files, nWant)
nCh = numel(files);
parts = cell(1, nCh); labels = cell(1, nCh); fsAll = zeros(1, nCh); t0 = zeros(1, nCh); nRec = 1;
for k = 1:nCh
    [parts{k}, H, t0(k), nr] = readContinuous(fullfile(folder, files{k}));
    fsAll(k) = H.sampleRate; labels{k} = H.channel; nRec = max(nRec, nr);
end
fs = fsAll(1); ts0 = t0(1);
n = min(cellfun(@numel, parts));
if nargin >= 3, n = min(n, nWant); end
x = zeros(nCh, n);
for k = 1:nCh, x(k, :) = parts{k}(1:n); end
if nargin >= 3 && n < nWant, x(:, end+1:nWant) = 0; end
end

function [v, H, t0, nRec] = readContinuous(f)
fid = fopen(f, 'r', 'ieee-le');
c = onCleanup(@() fclose(fid));
txt = fread(fid, [1 1024], 'uint8=>char');
H.sampleRate = key(txt, 'sampleRate', NaN);
bitVolts = key(txt, 'bitVolts', NaN);
tok = regexp(txt, 'channel\s*=\s*''([^'']*)''', 'tokens', 'once');
[~, b] = fileparts(f);
if isempty(tok), H.channel = b; else, H.channel = tok{1}; end
if ~(H.sampleRate > 0) || ~isfinite(bitVolts)
    error('NeuroAnalyzer:io:openephys', '%s: no sampleRate / bitVolts in the header.', [b '.continuous']);
end
isCH = ~isempty(regexp(b, '_CH\d+', 'once'));
if isCH, bitVolts = bitVolts * 1e-6; end              % uV per bit for CH, V for ADC / AUX
fseek(fid, 0, 'eof'); nb = ftell(fid);
recBytes = 8 + 2 + 2 + 2048 + 10;
nR = floor((nb - 1024) / recBytes);
fseek(fid, 1024, 'bof');
r = fread(fid, [recBytes nR], 'uint8=>uint8');
if isempty(r), v = []; t0 = 0; nRec = 1; return; end
t0 = 0;
for i = 8:-1:1, t0 = t0 * 256 + double(r(i, 1)); end
recNum = double(r(11, :)) + 256 * double(r(12, :));
nRec = numel(unique(recNum));
use = recNum == recNum(1);
nS = double(r(9, use)) + 256 * double(r(10, use));
s = r(13:12+2048, use);
s = double(s(1:2:end, :)) * 256 + double(s(2:2:end, :));     % big-endian
s(s >= 32768) = s(s >= 32768) - 65536;
keepS = false(1024, sum(use));
for k = 1:sum(use), keepS(1:min(1024, nS(k)), k) = true; end
v = bitVolts * s(keepS)';
end

function v = key(txt, name, default)
tok = regexp(txt, [name '\s*=\s*([-+0-9.eE]+)'], 'tokens', 'once');
if isempty(tok), v = default; else, v = str2double(tok{1}); end
end

function c = sortBy(c, k)
[~, o] = sort(k);
c = c(o);
end

function s = lastPart(p)
[~, a, b] = fileparts(p);
s = [a b];
end
