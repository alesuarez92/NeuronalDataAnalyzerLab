%% readABF.m
% =========================================================================
% READ ABF - AXON BINARY FORMAT 2 (pCLAMP 10+ / Clampex) AS A TDT-LIKE STRUCT
% =========================================================================
% rec = readABF(file)
%
% ABF 2 (Molecular Devices; layout as described by pyABF, Scott Harden,
% and used by python-neo), little-endian, 512-byte blocks:
%   @0 'ABF2', @4 version bytes, @12 lActualEpisodes (sweeps), @30
%   nDataFormat (0 int16, 1 float32); @76 the section map, 16 bytes per
%   section (uBlockIndex uint32, uBytes uint32, llNumEntries int64) in the
%   order Protocol, ADC, DAC, Epoch, ADCPerDAC, EpochPerDAC, UserList,
%   StatsRegion, Math, Strings, Data, Tag, Scope, Delta, VoiceTag,
%   SynchArray, Annotation, Stats.
%   Protocol: nOperationMode @0 (1 variable-length events, 2 / 5
%   fixed-length / episodic, 3 gap-free), fADCSequenceInterval @2 (us per
%   sample), fSynchTimeUnit @14, fADCRange @110, lADCResolution @118.
%   ADC entry per channel: nTelegraphEnable @2, fTelegraphAdditGain @6,
%   fADCProgrammableGain @28, fInstrumentScaleFactor @40,
%   fInstrumentOffset @44, fSignalGain @48, fSignalOffset @52,
%   lADCChannelNameIndex @74, lADCUnitsIndex @78 (indices into the strings
%   after the last double zero byte of the Strings section).
%   value = raw x fADCRange / (fInstrumentScaleFactor x fSignalGain x
%   fADCProgrammableGain x telegraph gain) / lADCResolution +
%   fInstrumentOffset - fSignalOffset (int16 data; float32 is used as is).
%   Samples of all channels interleaved; sweeps from the SynchArray
%   (offset, length) or one block (gap-free).
% Sweeps are put one after the other (info.sweepStarts: first sample of
% each, s; info.nSweeps). Channels in V / mV / uV become volts (neural
% channels); the others (pA, nA, digital inputs) are stimulus
% candidates, as well as channels named stim / trig / TTL.
% ABF 1 files ('ABF ') are refused: convert them with Clampfit.
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:abf.
% Toolboxes: none; also runs in GNU Octave.
% =========================================================================

function rec = readABF(p)
if exist(p, 'file') ~= 2
    error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', p);
end
[~, base, ext] = fileparts(p);
fid = fopen(p, 'r', 'ieee-le');
c = onCleanup(@() fclose(fid));
sig = fread(fid, [1 4], 'uint8=>char');
if strcmp(sig, 'ABF ')
    error('NeuroAnalyzer:io:abf', ['%s%s is an ABF 1 file (pCLAMP 9 or older): open it in Clampfit 10+ and ' ...
        'save it again (ABF 2), or export it as text.'], base, ext);
elseif ~strcmp(sig, 'ABF2')
    error('NeuroAnalyzer:io:abf', '%s%s is not an Axon ABF file.', base, ext);
end
ver = fread(fid, [1 4], 'uint8');
nSweeps = at(fid, 12, 'uint32');
dataFormat = at(fid, 30, 'uint16');
sec = zeros(18, 3);
for s = 1:18
    fseek(fid, 76 + (s - 1) * 16, 'bof');
    sec(s, :) = [fread(fid, 2, 'uint32')' fread(fid, 1, 'int64')];
end
S = struct('protocol', sec(1, :), 'adc', sec(2, :), 'strings', sec(10, :), 'data', sec(11, :), ...
    'synch', sec(16, :));
P = S.protocol(1) * 512;
mode = at(fid, P, 'int16');
interval = at(fid, P + 2, 'float32');
synchUnit = at(fid, P + 14, 'float32');
adcRange = at(fid, P + 110, 'float32');
adcRes = at(fid, P + 118, 'int32');
nCh = S.adc(3);
if nCh < 1 || ~(interval > 0)
    error('NeuroAnalyzer:io:abf', '%s%s: no ADC channels or no sample interval.', base, ext);
end
fs = 1e6 / interval;
% Strings: after the last double zero byte (pyABF's rule)
fseek(fid, S.strings(1) * 512, 'bof');
blob = fread(fid, [1 S.strings(2)], 'uint8');
k = strfind(char(blob), char([0 0]));
strs = {};
if ~isempty(k)
    rest = blob(k(end):end);
    rest(rest == 181) = double('u');                    % micro sign -> u
    z = [0 find(rest == 0) numel(rest) + 1];
    for i = 1:numel(z) - 1, strs{end+1} = char(rest(z(i)+1:z(i+1)-1)); end %#ok<AGROW>
    strs = strs(2:end);
end
names = cell(1, nCh); units = cell(1, nCh); gain = zeros(nCh, 1); off = zeros(nCh, 1);
for ch = 1:nCh
    A = S.adc(1) * 512 + (ch - 1) * S.adc(2);
    tel = at(fid, A + 2, 'int16');
    addGain = at(fid, A + 6, 'float32');
    progGain = at(fid, A + 28, 'float32');
    instScale = at(fid, A + 40, 'float32');
    instOff = at(fid, A + 44, 'float32');
    sigGain = at(fid, A + 48, 'float32');
    sigOff = at(fid, A + 52, 'float32');
    ni = at(fid, A + 74, 'int32'); ui = at(fid, A + 78, 'int32');
    names{ch} = strAt(strs, ni, sprintf('IN %d', ch - 1));
    units{ch} = strAt(strs, ui, '');
    g = adcRange / (instScale * sigGain * progGain) / adcRes;
    if tel == 1 && addGain ~= 0, g = g / addGain; end
    gain(ch) = g;
    off(ch) = instOff - sigOff;
end
if dataFormat == 1, prec = 'float32'; else, prec = 'int16'; end
fseek(fid, S.data(1) * 512, 'bof');
x = fread(fid, [nCh floor(S.data(3) / nCh)], prec);
if dataFormat ~= 1, x = x .* gain + off; end
% Sweep starts
starts = 0;
if S.synch(3) > 0 && ~(mode == 3)
    fseek(fid, S.synch(1) * 512, 'bof');
    sy = fread(fid, [2 S.synch(3)], 'int32');
    t0 = sy(1, :);
    if synchUnit ~= 0, starts = t0 * synchUnit * 1e-6; else, starts = t0 / fs; end
end
% Neural (voltage) channels and stimulus candidates
toV = cellfun(@voltFactor, units);
isStim = ~isfinite(toV) | ~cellfun(@isempty, regexpi(names, 'stim|trig|ttl|digital', 'once'));
neural = find(~isStim);
if isempty(neural), neural = 1; isStim(1) = false; toV(1) = 1; end
raw = x(neural, :) .* toV(neural)';
stim = x(isStim, :);
info = struct('source', sprintf('Axon ABF %d.%d', ver(4), ver(3)), 'format', 'abf', 'file', p, ...
    'blockname', base, 'channelNames', {names(neural)}, 'channelUnits', {units(neural)}, ...
    'nSweeps', max(1, nSweeps), 'sweepStarts', starts, 'operationMode', mode);
if any(isStim)
    info.stimNames = names(isStim);
    info.stimKinds = repmat({'analog'}, 1, sum(isStim));
else
    stim = [];
end
if nSweeps > 1
    info.notes = {sprintf('%d sweeps put one after the other.', nSweeps)};
end
rec = EphysSource.makeRecording(raw, fs, stim, fs, info);
end

function v = at(fid, pos, prec)
fseek(fid, pos, 'bof');
v = fread(fid, 1, prec);
end

function s = strAt(strs, i, default)
s = default;
if i >= 0 && i < numel(strs) && ~isempty(strs{i + 1}), s = strs{i + 1}; end
end

function f = voltFactor(u)
switch lower(strtrim(u))
    case 'v', f = 1;
    case 'mv', f = 1e-3;
    case {'uv'}, f = 1e-6;
    case 'nv', f = 1e-9;
    otherwise, f = NaN;
end
end
