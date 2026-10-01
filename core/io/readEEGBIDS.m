%% readEEGBIDS.m
% =========================================================================
% READ EEG-BIDS - ONE EEG RECORDING OF A BIDS DATASET WITH ITS SIDECAR FILES
% =========================================================================
% eeg = readEEGBIDS(path)    path: the *_eeg.edf / .bdf / .vhdr / .set file
%                            of a BIDS dataset, or the eeg folder holding it
%
% Brain Imaging Data Structure, EEG (Pernet et al. 2019; bids-
% specification.readthedocs.io). The recording is read with the reader of
% its format (EDF / BDF, BrainVision, EEGLAB), then the sidecar files
% next to it that share its name up to '_eeg' are applied:
%   *_channels.tsv     name, type, status: only type EEG channels are kept
%                      (the others are named in the notes); channels with
%                      status 'bad' are marked bad (eeg.bad) and listed in the notes
%   *_events.tsv       onset (s), duration, trial_type / value: the events
%                      (they replace the events inside the data file)
%   *_electrodes.tsv   name, x, y, z (the file of the same subject and
%                      session; with *_coordsystem.json: EEGCoordinateSystem
%                      and EEGCoordinateUnits)
%   *_eeg.json         EEGReference, PowerLineFrequency, SoftwareFilters,
%                      TaskName
% 'n/a' is read as missing. Returns the EEGSource struct (format 'bids').
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:bids.
% Toolboxes: none; also runs in GNU Octave (jsondecode: Octave 7+).
% =========================================================================

function eeg = readEEGBIDS(p)
f = dataFile(p);
[folder, name, ext] = fileparts(f);
prefix = regexprep(name, '_eeg$', '');
switch lower(ext)
    case {'.edf', '.bdf'}, raw = EEGSource.fromEDF(f);
    case '.vhdr',          raw = readBrainVision(f);
    case '.set',           raw = readEEGLAB(f);
    otherwise
        error('NeuroAnalyzer:io:bids', '%s%s: BIDS EEG data must be .edf, .bdf, .vhdr or .set.', name, ext);
end
notes = raw.notes;
labels = raw.labels;
keep = true(1, numel(labels));
bad = {};
% channels.tsv
T = readTSV(fullfile(folder, [prefix '_channels.tsv']));
if isfield(T, 'name') && isfield(T, 'type')
    isEEG = strcmpi(T.type, 'EEG');
    if any(isEEG)
        eegNames = T.name(isEEG);
        keep = ismember(labels, eegNames);
        other = labels(~keep);
        if ~isempty(other)
            notes{end + 1} = sprintf('Not EEG in channels.tsv (left out): %s.', strjoin(other, ', '));
        end
    end
    if isfield(T, 'status')
        bad = T.name(strcmpi(T.status, 'bad'));
        bad = bad(ismember(bad, labels(keep)));
        if ~isempty(bad)
            notes{end + 1} = sprintf('Marked bad in channels.tsv: %s (left out of the average reference and the trial rejection).', strjoin(bad, ', '));
        end
    end
end
if ~any(keep)
    error('NeuroAnalyzer:io:bids', '%s: no channel of the data file is an EEG channel in channels.tsv.', name);
end
labels = labels(keep);
data = raw.data(keep, :, :);
locs = raw.chanlocs(keep);
coord = raw.coordSystem;
% events.tsv
ev = raw.events;
E = readTSV(fullfile(folder, [prefix '_events.tsv']));
if isfield(E, 'onset')
    ev = struct('type', {}, 'latency', {}, 'duration', {});
    for k = 1:numel(E.onset)
        t = '';
        if isfield(E, 'trial_type'), t = E.trial_type{k}; end
        if isempty(t) && isfield(E, 'value'), t = E.value{k}; end
        if isempty(t), t = 'event'; end
        d = 0;
        if isfield(E, 'duration'), d = str2double(E.duration{k}); if ~isfinite(d), d = 0; end, end
        ev(end + 1) = struct('type', t, 'latency', str2double(E.onset{k}), 'duration', d); %#ok<AGROW>
    end
end
% electrodes.tsv (+ coordsystem.json)
ef = electrodesFile(folder, prefix);
if ~isempty(ef)
    P = readTSV(ef);
    if all(isfield(P, {'name', 'x', 'y', 'z'}))
        n = 0;
        for k = 1:numel(labels)
            i = find(strcmp(P.name, labels{k}), 1);
            if isempty(i), continue; end
            xyz = str2double([P.x(i) P.y(i) P.z(i)]);
            if any(~isfinite(xyz)), continue; end
            locs(k).x = xyz(1); locs(k).y = xyz(2); locs(k).z = xyz(3);
            locs(k).theta = NaN; locs(k).radius = NaN;
            n = n + 1;
        end
        if n > 0
            J = readJSON(regexprep(ef, '_electrodes\.tsv$', '_coordsystem.json'));
            cs = field(J, 'EEGCoordinateSystem', 'unknown system');
            un = field(J, 'EEGCoordinateUnits', 'unknown units');
            coord = sprintf('BIDS %s (%s)', cs, un);
        end
    end
end
% eeg.json
J = readJSON(fullfile(folder, [prefix '_eeg.json']));
ref = field(J, 'EEGReference', raw.reference);
if isempty(ref), ref = 'unknown'; end
task = field(J, 'TaskName', '');
if ~isempty(task), notes{end + 1} = sprintf('Task: %s.', task); end
line = field(J, 'PowerLineFrequency', []);
if isnumeric(line) && isscalar(line), notes{end + 1} = sprintf('Power line frequency: %g Hz.', line); end
sw = field(J, 'SoftwareFilters', '');
if ischar(sw) && ~isempty(sw), notes{end + 1} = sprintf('Software filters: %s.', sw); end
cond = {};
if raw.isEpoched, cond = raw.trials.condition; end
eeg = EEGSource.make(data, raw.fs, 'Times', raw.times, 'Labels', labels, 'Chanlocs', locs, ...
    'CoordSystem', coord, 'Conditions', cond, 'Events', ev, 'Reference', ref, 'History', raw.history, ...
    'Notes', notes, 'Unit', 'uV', 'Source', sprintf('EEG-BIDS (%s)', raw.source), 'Format', 'bids', ...
    'File', f, 'IsEpoched', raw.isEpoched, 'Bad', bad);
end

function f = dataFile(p)
% The *_eeg.<ext> file itself, or the only / first one in a folder
if exist(p, 'file') == 2
    f = p;
    return;
end
if exist(p, 'dir') ~= 7
    error('NeuroAnalyzer:io:fileNotFound', 'File or folder not found: %s', p);
end
cands = {};
for e = {'edf', 'bdf', 'vhdr', 'set'}
    d = dir(fullfile(p, ['*_eeg.' e{1}]));
    cands = [cands, fullfile(p, {d.name})]; %#ok<AGROW>
end
if isempty(cands)
    d = dir(fullfile(p, 'eeg'));
    if ~isempty(d), f = dataFile(fullfile(p, 'eeg')); return; end
    error('NeuroAnalyzer:io:bids', 'No *_eeg.edf / .bdf / .vhdr / .set file in %s.', p);
end
f = cands{1};
end

function ef = electrodesFile(folder, prefix)
% *_electrodes.tsv of the same subject (and session) in the folder
ef = '';
d = dir(fullfile(folder, '*_electrodes.tsv'));
if isempty(d), return; end
ent = @(s, key) regexp(s, ['(?:^|_)' key '-([^_]+)'], 'tokens', 'once');
for k = 1:numel(d)
    ok = true;
    for key = {'sub', 'ses'}
        a = ent(prefix, key{1}); b = ent(d(k).name, key{1});
        if ~isempty(b) && (isempty(a) || ~strcmp(a{1}, b{1})), ok = false; end
    end
    if ok, ef = fullfile(folder, d(k).name); return; end
end
end

function T = readTSV(f)
% Columns of a tab-separated file with a header row, as cellstr; 'n/a' -> ''
T = struct();
if exist(f, 'file') ~= 2, return; end
txt = fileread(f);
if ~isempty(txt) && double(txt(1)) == 65279, txt = txt(2:end); end    % BOM
lines = regexp(txt, '\r?\n', 'split');
lines = lines(~cellfun(@(s) isempty(strtrim(s)), lines));
if isempty(lines), return; end
head = strtrim(strsplit(lines{1}, sprintf('\t')));
rows = cellfun(@(s) strsplit(s, sprintf('\t')), lines(2:end), 'UniformOutput', false);
for c = 1:numel(head)
    col = cell(1, numel(rows));
    for r = 1:numel(rows)
        v = '';
        if numel(rows{r}) >= c, v = strtrim(rows{r}{c}); end
        if strcmpi(v, 'n/a'), v = ''; end
        col{r} = v;
    end
    key = matlab.lang.makeValidName(head{c});
    T.(key) = col;
end
end

function J = readJSON(f)
J = struct();
if exist(f, 'file') ~= 2, return; end
try
    J = jsondecode(fileread(f));
catch
end
end

function v = field(J, name, default)
v = default;
if isstruct(J) && isfield(J, name)
    v = J.(name);
    if ischar(v) && strcmpi(strtrim(v), 'n/a'), v = default; end
end
end
