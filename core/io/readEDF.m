%% readEDF.m
% =========================================================================
% READ EDF - EUROPEAN DATA FORMAT (EDF, EDF+, BDF, BDF+) RECORDINGS
% =========================================================================
% E = readEDF(file)
%
% EDF (Kemp et al. 1992) and EDF+ (Kemp & Olivan 2003; edfplus.info), and
% BioSemi's 24-bit BDF / BDF+. ASCII header of 256 bytes: version (8;
% '0', or byte 255 + 'BIOSEMI' for BDF), patient (80), recording (80),
% start date dd.mm.yy (8), start time hh.mm.ss (8), header bytes (8),
% reserved (44: 'EDF+C' / 'EDF+D' / 'BDF+C' / 'BDF+D' / '24BIT'), number
% of data records (8), record duration in s (8), number of signals (4);
% then per signal (each field for all signals in turn): label (16),
% transducer (80), physical dimension (8), physical min / max (8 + 8),
% digital min / max (8 + 8), prefiltering (80), samples per record (8),
% reserved (32). Data records hold each signal's samples in turn: int16
% (EDF) or int24 (BDF), little-endian.
%   physical = (digital - digMin) x (physMax - physMin) / (digMax -
%   digMin) + physMin
% EDF+ annotation signals ('EDF Annotations' / 'BDF Annotations') hold
% time-stamped annotation lists: '+onset' [0x15 duration] 0x14 text 0x14
% ... 0x00; the first of each record gives the record's start time. In
% EDF+D files the records are placed at those times (gaps filled with
% zeros, E.nGaps). The BDF 'Status' channel is returned as its trigger
% word (low 16 bits), not scaled.
%
% E.signals      struct array: label, units, fs, data (1 x samples,
%                physical units), transducer, prefilter, physMin, physMax,
%                digMin, digMax
% E.annotations  struct array: onset (s from the start), duration (s, NaN
%                when not given), text
% E.startTime    'yyyy-mm-dd HH:MM:SS' ('' when the header has none)
% E.format       'EDF', 'EDF+C', 'EDF+D', 'BDF', 'BDF+C' or 'BDF+D'
% E.patient, E.recording, E.recordDuration, E.nRecords, E.nGaps,
% E.recordStarts (s), E.notes (plain sentences), E.file
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:edf.
% Toolboxes: none; also runs in GNU Octave.
% =========================================================================

function E = readEDF(p)
if exist(p, 'file') ~= 2
    error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', p);
end
[~, base, ext] = fileparts(p);
name = [base ext];
fid = fopen(p, 'r', 'ieee-le');
c = onCleanup(@() fclose(fid));
h = fread(fid, [1 256], 'uint8=>char');
if numel(h) < 256
    error('NeuroAnalyzer:io:edf', '%s is too short for an EDF header.', name);
end
isBDF = double(h(1)) == 255 && strcmp(h(2:8), 'BIOSEMI');
if ~isBDF && ~strcmp(strtrim(h(1:8)), '0')
    error('NeuroAnalyzer:io:edf', '%s is not an EDF or BDF file (version field "%s").', name, strtrim(h(1:8)));
end
E = struct('file', p, 'patient', strtrim(h(9:88)), 'recording', strtrim(h(89:168)));
reserved = strtrim(h(193:236));
headerBytes = num(h(185:192));
nRec = num(h(237:244));
recDur = num(h(245:252));
ns = num(h(253:256));
if ~isfinite(ns) || ns < 1 || ~isfinite(headerBytes)
    error('NeuroAnalyzer:io:edf', '%s: the header has no signals.', name);
end
S = fread(fid, [1 ns * 256], 'uint8=>char');
if numel(S) < ns * 256
    error('NeuroAnalyzer:io:edf', '%s: the header is cut short.', name);
end
len = [16 80 8 8 8 8 8 80 8];
at = [0 cumsum(len * ns)];
F = cell(numel(len), ns);
for f = 1:numel(len)
    for k = 1:ns, F{f, k} = strtrim(S(at(f) + (k - 1) * len(f) + (1:len(f)))); end
end
label = F(1, :); transducer = F(2, :); units = F(3, :);
physMin = str2double(F(4, :)); physMax = str2double(F(5, :));
digMin = str2double(F(6, :)); digMax = str2double(F(7, :));
prefilter = F(8, :); nsr = str2double(F(9, :));
if any(~isfinite(nsr))
    error('NeuroAnalyzer:io:edf', '%s: samples per record missing for a signal.', name);
end
bps = 2 + isBDF;
recBytes = sum(nsr) * bps;
fseek(fid, 0, 'eof'); fileBytes = ftell(fid);
nFit = floor((fileBytes - headerBytes) / recBytes);
notes = {};
if ~isfinite(nRec) || nRec < 0
    nRec = nFit;
elseif nRec > nFit
    notes{end+1} = sprintf('The header lists %d data records but the file holds %d: the file is cut short.', nRec, nFit);
    nRec = nFit;
end
if isBDF
    if strncmp(reserved, 'BDF+', 4), E.format = reserved(1:5); else, E.format = 'BDF'; end
else
    if strncmp(reserved, 'EDF+', 4), E.format = reserved(1:5); else, E.format = 'EDF'; end
end
isPlus = numel(E.format) > 3;
E.startTime = startTime(h(169:176), h(177:184), E.recording);
E.recordDuration = recDur;
E.nRecords = nRec;
fseek(fid, headerBytes, 'bof');
R = fread(fid, [recBytes nRec], 'uint8=>uint8');
off = [0 cumsum(nsr * bps)];
isAnn = isPlus & (strcmp(label, 'EDF Annotations') | strcmp(label, 'BDF Annotations'));
% Annotations (and each record's start time)
ann = struct('onset', {}, 'duration', {}, 'text', {});
starts = (0:nRec - 1) * recDur;
for a = find(isAnn)
    for r = 1:nRec
        bytes = R(off(a) + (1:nsr(a) * bps), r)';
        [tals, t0] = parseTAL(bytes);
        if a == find(isAnn, 1) && isfinite(t0), starts(r) = t0; end
        ann = [ann, tals]; %#ok<AGROW>
    end
end
if nRec > 0 && any(isAnn)
    first = starts(1);
    starts = starts - first;
    for k = 1:numel(ann), ann(k).onset = ann(k).onset - first; end
end
E.recordStarts = starts;
% Signals
sig = find(~isAnn);
E.signals = struct('label', {}, 'units', {}, 'fs', {}, 'data', {}, 'transducer', {}, 'prefilter', {}, ...
    'physMin', {}, 'physMax', {}, 'digMin', {}, 'digMax', {});
nGaps = 0;
contiguous = ~strcmp(E.format(max(1, end - 1):end), '+D') || nRec < 2 ...
    || all(abs(diff(starts) - recDur) < 1e-6 * max(1, recDur));
for k = sig
    b = R(off(k) + (1:nsr(k) * bps), :);
    if isBDF
        b = double(reshape(b, 3, []));
        d = b(1, :) + 256 * b(2, :) + 65536 * b(3, :);
    else
        d = double(typecast(reshape(b, 1, []), 'int16'));
    end
    fs = nsr(k) / recDur;
    if isBDF && strcmp(label{k}, 'Status')
        x = mod(d, 65536);                                % trigger word
        u = '';
    else
        if isBDF, d(d >= 2^23) = d(d >= 2^23) - 2^24; end
        g = (physMax(k) - physMin(k)) / (digMax(k) - digMin(k));
        if ~isfinite(g) || g == 0
            x = d; notes{end+1} = sprintf('%s: no valid physical / digital range, raw values kept.', label{k}); %#ok<AGROW>
        else
            x = (d - digMin(k)) * g + physMin(k);
        end
        u = units{k};
    end
    if ~contiguous && recDur > 0
        n = round((starts(end) + recDur) * fs);
        y = zeros(1, n);
        for r = 1:nRec
            i = round(starts(r) * fs) + (1:nsr(k));
            y(i(i <= n)) = x((r - 1) * nsr(k) + find(i <= n));
        end
        x = y;
    end
    E.signals(end+1) = struct('label', label{k}, 'units', u, 'fs', fs, 'data', x, ...
        'transducer', transducer{k}, 'prefilter', prefilter{k}, 'physMin', physMin(k), ...
        'physMax', physMax(k), 'digMin', digMin(k), 'digMax', digMax(k)); %#ok<AGROW>
end
if ~contiguous
    nGaps = sum(abs(diff(starts) - recDur) > 1e-6 * max(1, recDur));
    notes{end+1} = sprintf('Discontinuous recording (EDF+D): %d gap(s) filled with zeros.', nGaps);
end
E.nGaps = nGaps;
E.annotations = ann;
E.notes = notes;
end

function [tals, t0] = parseTAL(bytes)
% Time-stamped annotation lists of one record; t0 = the record's time keeping
tals = struct('onset', {}, 'duration', {}, 'text', {});
t0 = NaN;
z = [0 find(bytes == 0)];
for k = 1:numel(z) - 1
    t = bytes(z(k) + 1:z(k + 1) - 1);
    if isempty(t), continue; end
    parts = splitBytes(t, 20);
    head = parts{1};
    d = find(head == 21, 1);
    if isempty(d)
        onset = str2double(char(head)); dur = NaN;
    else
        onset = str2double(char(head(1:d - 1))); dur = str2double(char(head(d + 1:end)));
    end
    texts = parts(2:end);
    texts = texts(~cellfun(@isempty, texts));
    if isempty(texts)
        if isnan(t0), t0 = onset; end                     % time-keeping TAL
        continue;
    end
    for j = 1:numel(texts)
        tals(end+1) = struct('onset', onset, 'duration', dur, 'text', utf8(texts{j})); %#ok<AGROW>
    end
end
end

function parts = splitBytes(b, sep)
i = [0 find(b == sep) numel(b) + 1];
parts = cell(1, numel(i) - 1);
for k = 1:numel(i) - 1, parts{k} = b(i(k) + 1:i(k + 1) - 1); end
end

function s = utf8(b)
try
    s = native2unicode(uint8(b), 'UTF-8');
catch
    s = char(b);
end
s = s(:)';
end

function v = num(s)
v = str2double(strtrim(s));
end

function s = startTime(d, t, recording)
% dd.mm.yy + hh.mm.ss; EDF+ 'Startdate dd-MMM-yyyy' gives the full year
s = '';
dv = sscanf(strrep(d, '.', ' '), '%d');
tv = sscanf(strrep(t, '.', ' '), '%d');
if numel(dv) ~= 3 || numel(tv) ~= 3, return; end
y = dv(3) + 1900 + 100 * (dv(3) < 85);
tok = regexp(recording, 'Startdate \d{2}-[A-Z]{3}-(\d{4})', 'tokens', 'once');
if ~isempty(tok), y = str2double(tok{1}); end
s = sprintf('%04d-%02d-%02d %02d:%02d:%02d', y, dv(2), dv(1), tv);
end
