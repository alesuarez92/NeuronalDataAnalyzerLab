%% readMFF.m
% =========================================================================
% READ MFF - EGI / MAGSTIM EGI GEODESIC NET RECORDINGS (.mff FOLDER)
% =========================================================================
% eeg = readMFF(path)    path: the .mff folder (or a file inside it)
%
% The meta-file format of Net Station (EGI; the layout mffpy, MNE-Python
% and EEGLAB's MFFMatlabIO read), a folder holding:
%   info.xml         recordTime (ISO 8601 with microseconds and time zone)
%   info<n>.xml      fileDataType of signal<n>.bin (EEG or PNSData) and
%                    calibrations (GCAL gains per channel)
%   signal<n>.bin    blocks, little-endian: int32 flag (1 = a header
%                    follows, 0 = same layout as the previous block); header:
%                    header bytes, data bytes, channel count, per-channel
%                    byte offsets, per-channel rate (upper 24 bits) and
%                    depth (low byte, 32 = float32), optional header; then
%                    each channel's samples in turn (float32, uV)
%   epochs.xml       continuous pieces: beginTime / endTime (us), first and
%                    last block (pieces after a pause are placed at their
%                    times; gaps filled with zeros, noted)
%   coordinates.xml  (or sensorLayout.xml) sensors: number, type (0 EEG,
%                    1 reference, 2 fiducial), x / y / z (cm)
%   Events*.xml      event tracks: beginTime (ISO), duration (ns), code
% Channels: E1 ... En, the reference as named in the layout ('Vertex
% Reference'); events: the code as the type, latency from recordTime.
% Segmented files (categories.xml) are read as one continuous piece
% (noted). Returns the EEGSource struct (format 'mff').
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:mff.
% Toolboxes: none; also runs in GNU Octave.
% =========================================================================

function eeg = readMFF(p)
if exist(p, 'file') == 2 && exist(p, 'dir') ~= 7, p = fileparts(p); end
if exist(p, 'dir') ~= 7
    error('NeuroAnalyzer:io:fileNotFound', 'Folder not found: %s', p);
end
[~, b, x] = fileparts(regexprep(p, '[\\/]+$', ''));
name = [b x];
if exist(fullfile(p, 'info.xml'), 'file') ~= 2
    error('NeuroAnalyzer:io:mff', '%s is not an EGI .mff folder (no info.xml).', name);
end
notes = {};
t0 = isoSeconds(tag(fileread(fullfile(p, 'info.xml')), 'recordTime'));
% The EEG signal file
sigFile = ''; gains = [];
for k = 1:9
    f = fullfile(p, sprintf('signal%d.bin', k));
    if exist(f, 'file') ~= 2, continue; end
    info = '';
    fi = fullfile(p, sprintf('info%d.xml', k));
    if exist(fi, 'file') == 2, info = fileread(fi); end
    if isempty(info) || ~isempty(regexp(info, '<EEG\s*/?>', 'once'))
        sigFile = f;
        gains = calibration(info, 'GCAL');
        break;
    end
end
if isempty(sigFile)
    error('NeuroAnalyzer:io:mff', '%s has no EEG signal file (signal1.bin).', name);
end
[blocks, fs] = readBlocks(sigFile, name);
nCh = size(blocks{1}, 1);
if ~isempty(gains) && numel(gains) >= nCh
    for k = 1:numel(blocks), blocks{k} = blocks{k} .* gains(1:nCh)'; end
    notes{end + 1} = 'Channel gains (GCAL calibration) applied.';
end
% Pieces (epochs.xml): place each at its begin time
ep = [];
fe = fullfile(p, 'epochs.xml');
if exist(fe, 'file') == 2
    txt = fileread(fe);
    bt = str2double(tags(txt, 'beginTime'));
    fb = str2double(tags(txt, 'firstBlock'));
    lb = str2double(tags(txt, 'lastBlock'));
    if ~isempty(bt) && numel(fb) == numel(bt) && numel(lb) == numel(bt), ep = [bt(:) fb(:) lb(:)]; end
end
if isempty(ep), ep = [0 1 numel(blocks)]; end
starts = round(ep(:, 1)' * 1e-6 * fs);
lens = arrayfun(@(r) sum(cellfun(@(c) size(c, 2), blocks(ep(r, 2):ep(r, 3)))), 1:size(ep, 1));
N = max(starts + lens);
X = zeros(nCh, N);
for r = 1:size(ep, 1)
    X(:, starts(r) + (1:lens(r))) = [blocks{ep(r, 2):ep(r, 3)}];
end
nGaps = sum(starts(2:end) ~= starts(1:end-1) + lens(1:end-1));
if nGaps > 0
    notes{end + 1} = sprintf('The recording was paused %d time(s); the pauses are filled with zeros.', nGaps);
end
if exist(fullfile(p, 'categories.xml'), 'file') == 2
    notes{end + 1} = 'The file is segmented (categories.xml); the segments are read one after the other.';
end
% Sensors
labels = arrayfun(@(k) sprintf('E%d', k), 1:nCh, 'UniformOutput', false);
locs = struct('label', labels, 'x', NaN, 'y', NaN, 'z', NaN, 'theta', NaN, 'radius', NaN);
coord = '';
ref = 'unknown';
fc = fullfile(p, 'coordinates.xml');
if exist(fc, 'file') ~= 2, fc = fullfile(p, 'sensorLayout.xml'); end
if exist(fc, 'file') == 2
    S = regexp(fileread(fc), '<sensor>(.*?)</sensor>', 'tokens');
    for k = 1:numel(S)
        s = S{k}{1};
        num = str2double(tag(s, 'number'));
        typ = str2double(tag(s, 'type'));
        if ~isfinite(num) || num < 1 || num > nCh || ~any(typ == [0 1]), continue; end
        xyz = str2double({tag(s, 'x'), tag(s, 'y'), tag(s, 'z')});
        if all(isfinite(xyz))
            locs(num).x = xyz(1); locs(num).y = xyz(2); locs(num).z = xyz(3);
            coord = 'EGI (x = right ear, y = nose, z = up; cm)';
        end
        if typ == 1
            nm = regexprep(strtrim(tag(s, 'name')), '\s+', ' ');
            if isempty(nm), nm = 'VREF'; end
            labels{num} = nm;
            locs(num).label = nm;
            ref = sprintf('vertex reference (%s)', nm);
        end
    end
end
% Events
ev = struct('type', {}, 'latency', {}, 'duration', {});
d = dir(fullfile(p, 'Events*.xml'));
for k = 1:numel(d)
    E = regexp(fileread(fullfile(p, d(k).name)), '<event>(.*?)</event>', 'tokens');
    for j = 1:numel(E)
        e = E{j}{1};
        code = strtrim(tag(e, 'code'));
        if isempty(code), code = strtrim(tag(e, 'label')); end
        du = str2double(tag(e, 'duration')) * 1e-9;
        if ~isfinite(du), du = 0; end
        ev(end + 1) = struct('type', code, 'latency', isoSeconds(tag(e, 'beginTime')) - t0, 'duration', du); %#ok<AGROW>
    end
end
if ~isempty(ev)
    [~, o] = sort([ev.latency]);
    ev = ev(o);
end
eeg = EEGSource.make(X, fs, 'Labels', labels, 'Chanlocs', locs, 'CoordSystem', coord, 'Events', ev, ...
    'Reference', ref, 'Notes', notes, 'Unit', 'uV', 'Source', 'EGI Net Station (.mff)', 'Format', 'mff', ...
    'File', p, 'IsEpoched', false);
end

function [blocks, fs] = readBlocks(f, name)
% Blocks of channels x samples (float32)
fid = fopen(f, 'r', 'ieee-le');
c = onCleanup(@() fclose(fid));
blocks = {};
fs = NaN; nCh = 0; dataBytes = 0;
while true
    flag = fread(fid, 1, 'int32');
    if isempty(flag), break; end
    if flag == 1
        h = fread(fid, 3, 'int32');                        % header bytes, data bytes, channels
        dataBytes = h(2); nCh = h(3);
        fread(fid, nCh, 'int32');                          % byte offsets
        rd = fread(fid, nCh, 'int32');
        depth = mod(rd(1), 256);
        fs = floor(rd(1) / 256);
        if depth ~= 32
            error('NeuroAnalyzer:io:mff', '%s: %d-bit samples (only 32-bit float is read).', name, depth);
        end
        opt = fread(fid, 1, 'int32');                      % optional header bytes
        if opt > 0, fread(fid, opt, 'uint8'); end
    elseif flag ~= 0 || nCh == 0
        error('NeuroAnalyzer:io:mff', '%s: signal1.bin is not in the MFF block layout.', name);
    end
    x = fread(fid, dataBytes / 4, 'float32=>double');
    if numel(x) < dataBytes / 4, break; end              % cut short
    blocks{end + 1} = reshape(x, [], nCh)'; %#ok<AGROW>
end
if isempty(blocks)
    error('NeuroAnalyzer:io:mff', '%s: no data blocks in signal1.bin.', name);
end
end

function g = calibration(info, type)
% Gains of one calibration type: <calibration><type>GCAL</type><channels><ch n="1">1.0</ch>...
g = [];
C = regexp(info, '<calibration>(.*?)</calibration>', 'tokens');
for k = 1:numel(C)
    if ~strcmp(strtrim(tag(C{k}{1}, 'type')), type), continue; end
    t = regexp(C{k}{1}, '<ch n="(\d+)">([^<]*)</ch>', 'tokens');
    for j = 1:numel(t), g(str2double(t{j}{1})) = str2double(t{j}{2}); end %#ok<AGROW>
end
end

function v = tag(txt, name)
t = regexp(txt, ['<' name '>([^<]*)</' name '>'], 'tokens', 'once');
if isempty(t), v = ''; else, v = t{1}; end
end

function v = tags(txt, name)
t = regexp(txt, ['<' name '>([^<]*)</' name '>'], 'tokens');
v = cellfun(@(c) c{1}, t, 'UniformOutput', false);
end

function s = isoSeconds(t)
% 'YYYY-MM-DDTHH:MM:SS.ffffff+HH:MM' -> seconds (UTC) from 2 Aug 1998 (small numbers, us precision)
s = NaN;
v = regexp(t, '(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d+)?([+-])(\d{2}):?(\d{2})', 'tokens', 'once');
if isempty(v), return; end
n = str2double(v([1:6 9 10]));
frac = 0;
if ~isempty(v{7}), frac = str2double(v{7}); end
tz = (n(7) * 3600 + n(8) * 60) * (1 - 2 * strcmp(v{8}, '-'));
s = (datenum(n(1), n(2), n(3)) - 730000) * 86400 + n(4) * 3600 + n(5) * 60 + n(6) + frac - tz;
end
