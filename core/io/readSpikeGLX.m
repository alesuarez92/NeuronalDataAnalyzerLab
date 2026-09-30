%% readSpikeGLX.m
% =========================================================================
% READ SPIKEGLX - SPIKEGLX .bin + .meta RECORDING AS A TDT-LIKE STRUCT
% =========================================================================
% rec = readSpikeGLX(file)        file: the .bin or .meta (imec .ap / .lf,
%                                 or .nidq)
%
% SpikeGLX (Bill Karsh, Janelia; documented in its Metadata guide) saves
% int16 samples of all saved channels interleaved in a .bin, and the
% settings as key=value lines in a .meta next to it. Scaling:
%   imec (Neuropixels) volts = value x imAiRangeMax / imMaxInt / gain;
%       1.0 probes: imMaxInt 512, the gain of each channel in ~imroTbl
%       (entries "chan bank ref apGain lfGain ...": AP gain for .ap, LF
%       gain for .lf); 2.0 probes (entries without gains): imMaxInt 8192
%       and gain imChan0apGain (default 80). The last channel is the sync
%       word (snsApLfSy = AP,LF,SY).
%   nidq volts = value x niAiRangeMax / 32768 / gain, gain niMNGain for
%       MN channels, niMAGain for MA, 1 for XA; DW channels are digital
%       words (snsMnMaXaDw = MN,MA,XA,DW counts).
% Neural channels: AP (or LF) for imec, MN + MA for nidq (XA when there
% are none). Stimulus candidates: nidq XA channels (volts), then each
% digital bit that changes (0/1: nidq DW words, imec SY word).
% rec as EphysSource.makeRecording: streams.xRAW (volts), streams.Whis,
% info (source 'SpikeGLX', format 'spikeglx', channelNames, stimNames,
% stimKinds, meta).
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:spikeglx.
% Toolboxes: none; also runs in GNU Octave.
% =========================================================================

function rec = readSpikeGLX(p)
[folder, base, ext] = fileparts(p);
if strcmpi(ext, '.meta')
    metaFile = p;
    binFile = fullfile(folder, [base '.bin']);
else
    binFile = p;
    metaFile = fullfile(folder, [base '.meta']);
end
if exist(binFile, 'file') ~= 2
    error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', binFile);
end
if exist(metaFile, 'file') ~= 2
    error('NeuroAnalyzer:io:spikeglx', 'The SpikeGLX .meta file next to %s is missing: %s', [base '.bin'], metaFile);
end
M = readMeta(metaFile);
nCh = num(M, 'nSavedChans', NaN);
if ~(nCh >= 1)
    error('NeuroAnalyzer:io:spikeglx', '%s has no nSavedChans.', metaFile);
end
isImec = isfield(M, 'imSampRate') || isfield(M, 'snsApLfSy');
if isImec, fs = num(M, 'imSampRate', NaN); else, fs = num(M, 'niSampRate', NaN); end
if ~(fs > 0)
    error('NeuroAnalyzer:io:spikeglx', '%s has no sample rate (imSampRate / niSampRate).', metaFile);
end
d = dir(binFile);
n = floor(d.bytes / (2 * nCh));
fid = fopen(binFile, 'r', 'ieee-le');
c = onCleanup(@() fclose(fid));
x = fread(fid, [nCh n], '*int16');
isLF = ~isempty(regexp(lower(base), '\.lf$', 'once'));
stim = []; stimNames = {}; stimKinds = {};
if isImec
    cnt = nums(M, 'snsApLfSy', [nCh - 1 0 1]);
    nNeural = cnt(1) + cnt(2);
    nSync = cnt(3);
    range = num(M, 'imAiRangeMax', 0.6);
    [gain, maxInt, probe] = imecGains(M, nNeural, isLF);
    raw = double(x(1:nNeural, :)) .* (range ./ maxInt ./ gain(:));
    names = arrayfun(@(k) sprintf('%s%d', ifelse(isLF, 'LF', 'AP'), k - 1), 1:nNeural, 'UniformOutput', false);
    if nSync > 0
        [stim, stimNames] = bitLines(x(nNeural + 1, :), 'SY');
        stimKinds = repmat({'digital'}, 1, numel(stimNames));
    end
    src = sprintf('SpikeGLX imec (%s)', probe);
else
    cnt = nums(M, 'snsMnMaXaDw', [0 0 nCh 0]);
    range = num(M, 'niAiRangeMax', 5);
    g = ones(1, nCh);
    g(1:cnt(1)) = num(M, 'niMNGain', 1);
    g(cnt(1) + (1:cnt(2))) = num(M, 'niMAGain', 1);
    volts = @(idx) double(x(idx, :)) .* (range / 32768 ./ g(idx)');
    nNeural = cnt(1) + cnt(2);
    xa = nNeural + (1:cnt(3));
    if nNeural > 0
        raw = volts(1:nNeural);
        names = [arrayfun(@(k) sprintf('MN%d', k - 1), 1:cnt(1), 'UniformOutput', false), ...
            arrayfun(@(k) sprintf('MA%d', k - 1), 1:cnt(2), 'UniformOutput', false)];
    else
        raw = volts(xa);
        names = arrayfun(@(k) sprintf('XA%d', k - 1), 1:cnt(3), 'UniformOutput', false);
    end
    if cnt(3) > 0 && nNeural > 0
        stim = volts(xa);
        stimNames = arrayfun(@(k) sprintf('XA%d', k - 1), 1:cnt(3), 'UniformOutput', false);
        stimKinds = repmat({'analog'}, 1, cnt(3));
    end
    for w = 1:cnt(4)
        [s, nm] = bitLines(x(nNeural + cnt(3) + w, :), sprintf('DW%d', w - 1));
        stim = [stim; s]; stimNames = [stimNames nm]; stimKinds = [stimKinds repmat({'digital'}, 1, numel(nm))]; %#ok<AGROW>
    end
    src = 'SpikeGLX nidq';
end
if isempty(stimNames), stim = []; end
% Channel names from ~snsChanMap ('(counts)(AP0;0:0)(AP1;1:1)...') when present
if isfield(M, 'snsChanMap') && iscell(M.snsChanMap) && numel(M.snsChanMap) > numel(names)
    map = cellfun(@(e) strtok(e, ';'), M.snsChanMap(2:end), 'UniformOutput', false);
    if ~isImec && nNeural == 0, first = cnt(1) + cnt(2); else, first = 0; end
    if numel(map) >= first + numel(names), names = map(first + (1:numel(names))); end
end
info = struct('source', src, 'format', 'spikeglx', 'file', binFile, 'blockname', base, ...
    'channelNames', {names}, 'meta', M);
if ~isempty(stimNames)
    info.stimNames = stimNames;
    info.stimKinds = stimKinds;
end
rec = EphysSource.makeRecording(raw, fs, stim, fs, info);
end

%% readMeta - key=value lines; '~' keys hold '(a)(b)...' lists (cellstr, header entry kept first)
function M = readMeta(f)
M = struct();
lines = regexp(fileread(f), '\r?\n', 'split');
for k = 1:numel(lines)
    i = find(lines{k} == '=', 1);
    if isempty(i), continue; end
    key = strtrim(lines{k}(1:i-1));
    val = strtrim(lines{k}(i+1:end));
    if isempty(key), continue; end
    if key(1) == '~'
        key = key(2:end);
        val = regexp(val, '\(([^)]*)\)', 'tokens');
        val = cellfun(@(c) c{1}, val, 'UniformOutput', false);
    end
    key = matlab.lang.makeValidName(key);
    M.(key) = val;
end
end

function v = num(M, key, default)
v = default;
if isfield(M, key) && ischar(M.(key))
    x = str2double(M.(key));
    if isfinite(x), v = x; end
end
end

function v = nums(M, key, default)
v = default;
if isfield(M, key) && ischar(M.(key))
    x = str2double(strsplit(M.(key), ','));
    if all(isfinite(x)) && numel(x) == numel(default), v = x; end
end
end

%% imecGains - Per-channel gain and max int of an imec stream (1.0: from imroTbl; 2.0: fixed)
function [gain, maxInt, probe] = imecGains(M, nNeural, isLF)
gain = []; maxInt = 512; probe = 'Neuropixels 1.0';
if isfield(M, 'imroTbl') && iscell(M.imroTbl) && numel(M.imroTbl) > 1
    entries = M.imroTbl(2:end);                      % the first entry is (type,nChannels)
    f = str2double(strsplit(strtrim(entries{1}), ' '));
    if numel(f) >= 5 && f(4) > 1                        % chan bank ref apGain lfGain ...
        col = 4 + isLF;
        gain = zeros(1, nNeural);
        for k = 1:min(nNeural, numel(entries))
            e = str2double(strsplit(strtrim(entries{k}), ' '));
            gain(k) = e(col);
        end
        gain(gain <= 0) = 1;
        if numel(entries) < nNeural, gain(numel(entries)+1:end) = gain(1); end
    end
end
if isempty(gain)
    probe = 'Neuropixels 2.0';
    maxInt = num(M, 'imMaxInt', 8192);
    gain = repmat(num(M, 'imChan0apGain', 80), 1, nNeural);
else
    maxInt = num(M, 'imMaxInt', 512);
end
end

%% bitLines - The bits of a digital word that change, as 0/1 rows
function [s, names] = bitLines(w, prefix)
u = typecast(w(:)', 'uint16');
s = []; names = {};
for b = 0:15
    v = bitget(u, b + 1);
    if any(v ~= v(1))
        s(end+1, :) = double(v); %#ok<AGROW>
        names{end+1} = sprintf('%s bit %d', prefix, b); %#ok<AGROW>
    end
end
end

function s = ifelse(c, a, b)
if c, s = a; else, s = b; end
end
