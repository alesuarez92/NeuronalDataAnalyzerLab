function f = writeEEGBIDS(root, eeg, varargin)
% writeEEGBIDS - Write one continuous EEG recording as an EEG-BIDS dataset (tests, demos, sharing).
%
% f = writeEEGBIDS(root, eeg, Name, Value, ...)    f: the *_eeg data file
%
% eeg      EEGSource struct (continuous: data channels x samples in uV,
%          fs, labels, chanlocs, events, reference)
% Options: 'Subject' ('01'), 'Session' ('' = none), 'Task' ('rest'),
%          'Run' ('' = none), 'Format' ('edf' default, or 'bdf'),
%          'Types' (one BIDS channel type per channel, default all
%          'EEG'), 'Bad' (channel names with status bad), 'LineFrequency'
%          (Hz, default 50), 'CoordSystem' ('Other'), 'CoordUnits' ('mm'),
%          'Description' (dataset name)
% Writes dataset_description.json and participants.tsv at the root, then
% sub-<S>/[ses-<E>/]eeg/: the data (writeEDF), *_eeg.json, *_channels.tsv,
% *_events.tsv and, when the channels have x / y / z, *_electrodes.tsv
% with *_coordsystem.json. Layout as readEEGBIDS reads it (BIDS 1.9).
% Base MATLAB only; also runs in GNU Octave 7+ (jsonencode).
%
o = struct('Subject', '01', 'Session', '', 'Task', 'rest', 'Run', '', 'Format', 'edf', 'Types', {{}}, ...
    'Bad', {{}}, 'LineFrequency', 50, 'CoordSystem', 'Other', 'CoordUnits', 'mm', ...
    'Description', 'Neuronal Data Analyzer Lab EEG');
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
if ndims(eeg.data) > 2 && size(eeg.data, 3) > 1 %#ok<ISMAT>
    error('NeuroAnalyzer:io:bids', 'BIDS EEG holds continuous recordings: this EEG is cut into trials.');
end
nCh = numel(eeg.labels);
types = o.Types;
if isempty(types), types = repmat({'EEG'}, 1, nCh); end
if ~exist(root, 'dir'), mkdir(root); end
writeText(fullfile(root, 'dataset_description.json'), jsonencode(struct('Name', o.Description, ...
    'BIDSVersion', '1.9.0', 'DatasetType', 'raw')));
writeText(fullfile(root, 'participants.tsv'), sprintf('participant_id\nsub-%s\n', o.Subject));
parts = {['sub-' o.Subject]};
folder = fullfile(root, ['sub-' o.Subject]);
if ~isempty(o.Session)
    parts{end+1} = ['ses-' o.Session];
    folder = fullfile(folder, ['ses-' o.Session]);
end
parts{end+1} = ['task-' o.Task];
if ~isempty(o.Run), parts{end+1} = ['run-' o.Run]; end
folder = fullfile(folder, 'eeg');
if ~exist(folder, 'dir'), mkdir(folder); end
prefix = strjoin(parts, '_');
% Data
fmt = lower(o.Format);
f = fullfile(folder, [prefix '_eeg.' fmt]);
sig = struct('label', eeg.labels, 'units', 'uV', 'fs', eeg.fs, 'data', num2cell(double(eeg.data), 2)');
if strcmp(fmt, 'bdf'), writeEDF(f, sig, 'Format', 'BDF'); else, writeEDF(f, sig, 'Format', 'EDF'); end
% Sidecars
ref = eeg.reference;
if isempty(ref) || strcmpi(ref, 'unknown'), ref = 'n/a'; end
J = struct('TaskName', o.Task, 'SamplingFrequency', eeg.fs, 'PowerLineFrequency', o.LineFrequency, ...
    'SoftwareFilters', 'n/a', 'EEGReference', ref, 'RecordingType', 'continuous', ...
    'RecordingDuration', size(eeg.data, 2) / eeg.fs, 'EEGChannelCount', sum(strcmpi(types, 'EEG')));
writeText(fullfile(folder, [prefix '_eeg.json']), jsonencode(J));
rows = cell(1, nCh);
for k = 1:nCh
    st = 'good';
    if any(strcmp(o.Bad, eeg.labels{k})), st = 'bad'; end
    rows{k} = sprintf('%s\t%s\tuV\t%g\t%s', eeg.labels{k}, types{k}, eeg.fs, st);
end
writeText(fullfile(folder, [prefix '_channels.tsv']), ...
    sprintf('name\ttype\tunits\tsampling_frequency\tstatus\n%s\n', strjoin(rows, newline)));
ev = eeg.events;
rows = cell(1, numel(ev));
for k = 1:numel(ev)
    rows{k} = sprintf('%.6f\t%.6f\t%s\t%d', ev(k).latency, ev(k).duration, ev(k).type, round(ev(k).latency * eeg.fs));
end
txt = sprintf('onset\tduration\ttrial_type\tsample\n');
if ~isempty(rows), txt = [txt strjoin(rows, newline) newline]; end
writeText(fullfile(folder, [prefix '_events.tsv']), txt);
if isfield(eeg, 'chanlocs') && ~isempty(eeg.chanlocs) && any(isfinite([eeg.chanlocs.x]))
    ep = strjoin(parts(~strncmp(parts, 'task-', 5) & ~strncmp(parts, 'run-', 4)), '_');
    rows = cell(1, nCh);
    for k = 1:nCh
        c = eeg.chanlocs(k);
        rows{k} = sprintf('%s\t%s\t%s\t%s', eeg.labels{k}, num(c.x), num(c.y), num(c.z));
    end
    writeText(fullfile(folder, [ep '_electrodes.tsv']), sprintf('name\tx\ty\tz\n%s\n', strjoin(rows, newline)));
    writeText(fullfile(folder, [ep '_coordsystem.json']), jsonencode(struct('EEGCoordinateSystem', o.CoordSystem, ...
        'EEGCoordinateUnits', o.CoordUnits, 'EEGCoordinateSystemDescription', 'Positions as stored in the EEG struct')));
end
end

function s = num(v)
if isfinite(v), s = sprintf('%.6g', v); else, s = 'n/a'; end
end

function writeText(f, s)
fid = fopen(f, 'w');
if fid < 0, error('NeuroAnalyzer:io:bids', 'Cannot write %s', f); end
fwrite(fid, s, 'char');
fclose(fid);
end
