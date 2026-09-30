%% readIntanRHS.m
% =========================================================================
% READ INTAN RHS - INTAN RHS2000 STIMULATION / RECORDING (.rhs) AS A TDT-LIKE STRUCT
% =========================================================================
% rec = readIntanRHS(file)
%
% Intan Technologies' RHS2000 data file (the stim / record controller;
% published file format documentation), "traditional" single file,
% little-endian. Header: uint32 magic 0xD69127AC, int16 major / minor
% version, float32 sample rate, int16 DSP enabled, float32 x 8 (actual and
% desired DSP cutoff, lower, lower settle, upper bandwidth), int16 notch
% mode, float32 x 2 (impedance test frequencies), int16 amp settle mode,
% int16 charge recovery mode, float32 stim step size (A), float32 charge
% recovery current limit, float32 target voltage, 3 notes (QString), int16
% DC amplifier data saved, int16 board mode, QString reference channel,
% int16 number of signal groups; each group: QString name, prefix, int16
% enabled, channels, amplifier channels; per channel: QString native /
% custom name, int16 native order, custom order, signal type (0
% amplifier, 3 ADC in, 4 ADC out, 5 digital in, 6 digital out), enabled,
% chip channel, command stream, board stream, 4 spike-scope fields,
% float32 impedance magnitude / phase. (QString = uint32 byte length,
% 0xFFFFFFFF = empty, then UTF-16LE.)
% Blocks of 128 samples: 128 timestamps (int32), then per amplifier
% channel 128 samples (uint16), the DC amplifier samples when saved, a
% stimulation word per amplifier channel, ADC inputs, ADC outputs, one
% digital-input and one digital-output word (when such channels exist).
%   amplifier volts = 0.195e-6 x (value - 32768); DC volts = -0.01923 x
%   (value - 512); ADC volts = 312.5e-6 x (value - 32768); stimulation
%   current (A) = step size x (bits 0-7) x (-1 when bit 8 is set).
% Stimulus candidates: digital inputs (0/1, bit = native order), ADC
% inputs (volts), and the stimulation current of each channel that
% stimulated (A).
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:intan.
% Toolboxes: none; also runs in GNU Octave.
% =========================================================================

function rec = readIntanRHS(p)
if exist(p, 'file') ~= 2
    error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', p);
end
[~, base, ext] = fileparts(p);
fid = fopen(p, 'r', 'ieee-le');
c = onCleanup(@() fclose(fid));
fseek(fid, 0, 'eof'); nBytes = ftell(fid); fseek(fid, 0, 'bof');
magic = fread(fid, 1, 'uint32');
if magic ~= hex2dec('D69127AC')
    error('NeuroAnalyzer:io:intan', '%s%s is not an Intan RHS2000 file (magic number %08X).', base, ext, magic);
end
ver = fread(fid, [1 2], 'int16');
fs = fread(fid, 1, 'float32');
fread(fid, 1, 'int16'); fread(fid, 8, 'float32');
notch = fread(fid, 1, 'int16');
fread(fid, 2, 'float32'); fread(fid, 2, 'int16');
step = fread(fid, 1, 'float32');
fread(fid, 2, 'float32');
for k = 1:3, qstring(fid); end
dcSaved = fread(fid, 1, 'int16');
fread(fid, 1, 'int16');
qstring(fid);
nGroups = fread(fid, 1, 'int16');
amp = struct('name', {}, 'order', {}); adc = amp; dac = amp; din = amp; dout = amp;
for g = 1:nGroups
    qstring(fid); qstring(fid);
    enabled = fread(fid, 1, 'int16'); nCh = fread(fid, 1, 'int16'); fread(fid, 1, 'int16');
    if ~enabled, continue; end
    for k = 1:nCh
        native = qstring(fid); custom = qstring(fid);
        order = fread(fid, 2, 'int16');
        type = fread(fid, 1, 'int16'); en = fread(fid, 1, 'int16');
        fread(fid, 7, 'int16'); fread(fid, 2, 'float32');
        if ~en, continue; end
        if isempty(custom), custom = native; end
        e = struct('name', custom, 'order', order(1));
        switch type
            case 0, amp(end+1) = e; %#ok<AGROW>
            case 3, adc(end+1) = e; %#ok<AGROW>
            case 4, dac(end+1) = e; %#ok<AGROW>
            case 5, din(end+1) = e; %#ok<AGROW>
            case 6, dout(end+1) = e; %#ok<AGROW>
        end
    end
end
headerBytes = ftell(fid);
nA = numel(amp);
perBlock = 128 * (4 + 2 * (nA * (1 + (dcSaved ~= 0) + 1) + numel(adc) + numel(dac) + ...
    (numel(din) > 0) + (numel(dout) > 0)));
nBlocks = floor((nBytes - headerBytes) / perBlock);
if nBlocks < 1
    error('NeuroAnalyzer:io:intan', '%s%s holds no complete data block.', base, ext);
end
n = 128 * nBlocks;
A = zeros(nA, n); S = zeros(nA, n); X = zeros(numel(adc), n); D = zeros(1, n);
ts = zeros(1, n);
for b = 1:nBlocks
    i = (b - 1) * 128 + (1:128);
    ts(i) = fread(fid, 128, 'int32');
    if nA, A(:, i) = fread(fid, [128 nA], 'uint16')'; end
    if dcSaved && nA, fread(fid, [128 nA], 'uint16'); end
    if nA, S(:, i) = fread(fid, [128 nA], 'uint16')'; end
    if numel(adc), X(:, i) = fread(fid, [128 numel(adc)], 'uint16')'; end
    if numel(dac), fread(fid, [128 numel(dac)], 'uint16'); end
    if numel(din), D(i) = fread(fid, 128, 'uint16'); end
    if numel(dout), fread(fid, 128, 'uint16'); end
end
raw = 0.195e-6 * (A - 32768);
stim = []; stimNames = {}; stimKinds = {};
for k = 1:numel(din)
    stim(end+1, :) = bitget(D, din(k).order + 1); %#ok<AGROW>
    stimNames{end+1} = din(k).name; stimKinds{end+1} = 'digital'; %#ok<AGROW>
end
for k = 1:numel(adc)
    stim(end+1, :) = 312.5e-6 * (X(k, :) - 32768); %#ok<AGROW>
    stimNames{end+1} = adc(k).name; stimKinds{end+1} = 'analog'; %#ok<AGROW>
end
mag = bitand(S, 255);
sgn = 1 - 2 * (bitand(S, 256) ~= 0);
cur = step * mag .* sgn;
for k = 1:nA
    if any(cur(k, :))
        stim(end+1, :) = cur(k, :); %#ok<AGROW>
        stimNames{end+1} = sprintf('Stim current %s', amp(k).name); stimKinds{end+1} = 'analog'; %#ok<AGROW>
    end
end
info = struct('source', sprintf('Intan RHS2000 %d.%d', ver), 'format', 'intanrhs', 'file', p, ...
    'blockname', base, 'channelNames', {{amp.name}}, 'firstTimestamp', ts(1), ...
    'nGaps', sum(diff(ts) ~= 1), 'stimStepA', step, 'notchMode', notch);
if ~isempty(stimNames)
    info.stimNames = stimNames;
    info.stimKinds = stimKinds;
end
rec = EphysSource.makeRecording(raw, fs, stim, fs, info);
end

function s = qstring(fid)
len = fread(fid, 1, 'uint32');
if isempty(len) || len == hex2dec('FFFFFFFF') || len == 0, s = ''; return; end
u = fread(fid, [1 len / 2], 'uint16');
s = char(u(u < 65536));
end
