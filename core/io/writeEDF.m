function writeEDF(file, signals, varargin)
% writeEDF - Write an EDF / EDF+ / BDF / BDF+ file (tests, demos and exports).
%
% writeEDF(file, signals, Name, Value, ...)
%
% signals  struct array: label, units, fs, data (1 x samples, physical
%          units); optional physMin, physMax (default: the data range).
%          In BDF files a signal labelled 'Status' holds trigger words
%          (written as they are).
% Options: 'Format' ('EDF' default, 'EDF+C', 'EDF+D', 'BDF', 'BDF+C',
%          'BDF+D'), 'Annotations' struct(onset, duration (NaN: none),
%          text) (EDF+ / BDF+ only), 'RecordDuration' (s, default 1;
%          fs x duration must be whole numbers), 'RecordStarts' (EDF+D:
%          start of each record, s), 'StartTime' ('yyyy-mm-dd HH:MM:SS'),
%          'Patient' (default 'X X X X'), 'Recording' (default EDF+
%          'Startdate dd-MMM-yyyy X X X')
% Samples are rounded to the digital range (16 bits EDF, 24 bits BDF);
% signals are padded with zeros to whole records. Layout as readEDF reads
% it (edfplus.info). Base MATLAB only; also runs in GNU Octave.
%
o = struct('Format', 'EDF', 'Annotations', struct('onset', {}, 'duration', {}, 'text', {}), ...
    'RecordDuration', 1, 'RecordStarts', [], 'StartTime', '2026-09-30 12:00:00', ...
    'Patient', 'X X X X', 'Recording', '');
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
fmt = upper(o.Format);
isBDF = strncmp(fmt, 'BDF', 3);
isPlus = numel(fmt) > 3;
if isBDF, dr = [-8388608 8388607]; bps = 3; else, dr = [-32768 32767]; bps = 2; end
T = sscanf(regexprep(o.StartTime, '[-: ]', ' '), '%d')';
months = {'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'};
rec = o.Recording;
if isempty(rec)
    if isPlus, rec = sprintf('Startdate %02d-%s-%04d X X X', T(3), months{T(2)}, T(1)); else, rec = 'NDAL synthetic recording'; end
end
D = o.RecordDuration;
ns = numel(signals);
spr = zeros(1, ns); nRec = 0;
for k = 1:ns
    spr(k) = round(signals(k).fs * D);
    if abs(spr(k) - signals(k).fs * D) > 1e-9
        error('NeuroAnalyzer:io:edf', '%s: %g Hz x %g s is not a whole number of samples.', signals(k).label, signals(k).fs, D);
    end
    nRec = max(nRec, ceil(numel(signals(k).data) / spr(k)));
end
starts = (0:nRec - 1) * D;
if ~isempty(o.RecordStarts), starts = o.RecordStarts(:)'; nRec = numel(starts); end
% Annotation signal: one TAL list per record
tal = {};
if isPlus
    ann = o.Annotations;
    for r = 1:nRec
        b = [uint8(sprintf('+%s', numStr(starts(r)))) 20 20 0];
        if r < nRec, hi = starts(r + 1); else, hi = inf; end
        if r == 1, lo = -inf; else, lo = starts(r); end
        for a = ann(:)'
            if a.onset >= lo && a.onset < hi
                h = sprintf('%s%s', signOf(a.onset), numStr(abs(a.onset)));
                if isfinite(a.duration), h = [h char(21) numStr(a.duration)]; end %#ok<AGROW>
                b = [b uint8(h) 20 unicode2bytes(a.text) 20 0]; %#ok<AGROW>
            end
        end
        tal{r} = b; %#ok<AGROW>
    end
    nb = max(cellfun(@numel, tal));
    nAnn = ceil(nb / bps);
end
% Header
lab = {signals.label}; uni = {signals.units};
pmin = zeros(1, ns); pmax = zeros(1, ns); dmin = dr(1) * ones(1, ns); dmax = dr(2) * ones(1, ns);
for k = 1:ns
    x = signals(k).data;
    if isBDF && strcmp(lab{k}, 'Status')
        pmin(k) = dr(1); pmax(k) = dr(2);
        continue;
    end
    if isfield(signals, 'physMin') && ~isempty(signals(k).physMin)
        pmin(k) = signals(k).physMin; pmax(k) = signals(k).physMax;
    else
        pmin(k) = min(x); pmax(k) = max(x);
        if pmin(k) == pmax(k), pmin(k) = pmin(k) - 1; pmax(k) = pmax(k) + 1; end
        pmin(k) = str2double(numStr(pmin(k), 'floor')); pmax(k) = str2double(numStr(pmax(k), 'ceil'));
    end
end
nsAll = ns + isPlus;
if isPlus
    lab{end+1} = sprintf('%s Annotations', fmt(1:3)); uni{end+1} = '';
    pmin(end+1) = -1; pmax(end+1) = 1; dmin(end+1) = dr(1); dmax(end+1) = dr(2); spr(end+1) = nAnn;
end
reserved = '';
if isPlus, reserved = fmt; elseif isBDF, reserved = '24BIT'; end
if isBDF, ver = [char(255) 'BIOSEMI']; else, ver = pad('0', 8); end
H = [ver, pad(o.Patient, 80), pad(rec, 80), sprintf('%02d.%02d.%02d', T(3), T(2), mod(T(1), 100)), ...
    sprintf('%02d.%02d.%02d', T(4), T(5), T(6)), pad(sprintf('%d', 256 * (nsAll + 1)), 8), pad(reserved, 44), ...
    pad(sprintf('%d', nRec), 8), pad(numStr(D), 8), pad(sprintf('%d', nsAll), 4)];
cols = {lab, 16; repmat({''}, 1, nsAll), 80; uni, 8; arrayfun(@numStr, pmin, 'UniformOutput', false), 8; ...
    arrayfun(@numStr, pmax, 'UniformOutput', false), 8; arrayfun(@(v) sprintf('%d', v), dmin, 'UniformOutput', false), 8; ...
    arrayfun(@(v) sprintf('%d', v), dmax, 'UniformOutput', false), 8; repmat({''}, 1, nsAll), 80; ...
    arrayfun(@(v) sprintf('%d', v), spr, 'UniformOutput', false), 8; repmat({''}, 1, nsAll), 32};
for f = 1:size(cols, 1)
    for k = 1:nsAll, H = [H pad(cols{f, 1}{k}, cols{f, 2})]; end %#ok<AGROW>
end
% Data records
fid = fopen(file, 'w', 'ieee-le');
if fid < 0, error('NeuroAnalyzer:io:edf', 'Cannot write %s', file); end
c = onCleanup(@() fclose(fid));
fwrite(fid, uint8(H), 'uint8');
q = cell(1, ns);
for k = 1:ns
    x = signals(k).data(:)';
    x(end+1:nRec * spr(k)) = 0;
    if isBDF && strcmp(lab{k}, 'Status')
        d = x;
    else
        d = round((x - pmin(k)) * (dmax(k) - dmin(k)) / (pmax(k) - pmin(k)) + dmin(k));
    end
    q{k} = max(dr(1), min(dr(2), d));
end
parts = cell(ns + isPlus, nRec);
for k = 1:ns
    b = reshape(bytesOf(q{k}, isBDF), spr(k) * bps, nRec);
    for r = 1:nRec, parts{k, r} = b(:, r)'; end
end
for r = 1:nRec * isPlus
    b = tal{r}; b(end+1:nAnn * bps) = 0;
    parts{end, r} = b;
end
fwrite(fid, [parts{:}], 'uint8');
end

function b = bytesOf(d, isBDF)
if isBDF
    d = mod(d, 2^24);
    b = uint8([mod(d, 256); mod(floor(d / 256), 256); floor(d / 65536)]);
    b = b(:)';
else
    b = typecast(int16(d), 'uint8');
end
end

function s = pad(s, n)
s = s(1:min(end, n));
s = [s repmat(' ', 1, n - numel(s))];
end

function s = signOf(v)
if v < 0, s = '-'; else, s = '+'; end
end

function s = numStr(v, mode)
% Shortest text of at most 8 characters (rounded outwards for ranges)
if nargin < 2, mode = 'round'; end
for p = 8:-1:1
    s = sprintf('%.*g', p, v);
    if numel(s) <= 8 && isempty(strfind(s, 'e')), break; end
end
if ~isempty(strfind(s, 'e'))                              % very small or large: fixed point
    s = sprintf('%.7f', v); s = s(1:min(end, 8));
end
w = str2double(s);
if strcmp(mode, 'floor') && w > v || strcmp(mode, 'ceil') && w < v
    d = 10^(floor(log10(abs(v) + eps)) - p + 1);
    if strcmp(mode, 'floor'), w = w - d; else, w = w + d; end
    s = sprintf('%.*g', p, w);
end
end

function b = unicode2bytes(t)
try
    b = unicode2native(t, 'UTF-8');
catch
    b = uint8(t);
end
b = b(:)';
end
