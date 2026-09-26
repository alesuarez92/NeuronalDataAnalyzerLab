%% readFieldTrip.m
% =========================================================================
% READ FIELDTRIP - FIELDTRIP RAW OR TIMELOCK DATA FROM A .mat FILE
% =========================================================================
% eeg = readFieldTrip(file)
% eeg = readFieldTrip(file, Name, Value, ...)
%
% Recognised structures (a variable with label, time and trial or avg):
%   raw       label, trial {chan x samples}, time {1 x samples}, fsample,
%             trialinfo (first column = condition code), sampleinfo, elec
%   timelock  avg (chan x time, dimord 'chan_time'): one averaged "trial";
%             trial (rpt x chan x time, dimord 'rpt_chan_time'): trials
% One trial starting at or after 0 s is read as a continuous recording;
% its events come from a variable called event (FieldTrip event struct:
% type, sample, value, duration) if the file has one.
% Condition names: the codes in trialinfo become 'Code 1', ... unless
% names are given (option) or the file has a text list called
% conditionNames (name k for code k).
% Positions: elec.elecpos (or chanpos / pnt) matched to the channels by
% name, with elec.coordsys and elec.unit.
% History: the cfg.previous chain in plain sentences
% (EEGSource.fieldtripHistory); nothing in it is run.
%
% Options:
%   'Variable'        name of the variable to read (default: 'data' if it
%                     is FieldTrip data, else the first one that is)
%   'ConditionNames'  cell of names, name k for trialinfo code k
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:eeg:notFieldTrip,
% NeuroAnalyzer:eeg:unknownVariable, NeuroAnalyzer:eeg:unequalTrials,
% NeuroAnalyzer:eeg:sizeMismatch. Toolboxes: none (FieldTrip is not needed).
% =========================================================================

function eeg = readFieldTrip(file, varargin)
    o = EEGSource.options(struct('Variable', '', 'ConditionNames', {{}}), varargin);
    s = EEGSource.loadMat(file);
    cand = EEGSource.fieldtripVariables(s);
    if ~isempty(o.Variable)
        if ~isfield(s, o.Variable)
            error('NeuroAnalyzer:eeg:unknownVariable', 'The file has no variable called ''%s''. Variables in the file: %s.', ...
                o.Variable, strjoin(fieldnames(s)', ', '));
        end
        if ~any(strcmp(cand, o.Variable))
            error('NeuroAnalyzer:eeg:notFieldTrip', ['The variable ''%s'' is not FieldTrip data ' ...
                '(it needs label, time and trial or avg).'], o.Variable);
        end
        name = o.Variable;
    elseif isempty(cand)
        error('NeuroAnalyzer:eeg:notFieldTrip', ['%s does not hold FieldTrip data (a variable ' ...
            'with label, time and trial or avg).'], file);
    elseif any(strcmp(cand, 'data'))
        name = 'data';
    else
        name = cand{1};
    end
    d = s.(name);
    notes = {};
    if numel(cand) > 1
        notes{end + 1} = sprintf('The file holds %d FieldTrip variables (%s); ''%s'' is used.', ...
            numel(cand), strjoin(cand, ', '), name);
    end
    labels = EEGSource.cellRow(d.label);
    nCh = numel(labels);
    codes = [];
    cond = {};
    if isfield(d, 'trial') && iscell(d.trial)
        % ---- raw ----
        nTr = numel(d.trial);
        lens = cellfun(@(x) size(x, 2), d.trial);
        if any(lens ~= lens(1))
            error('NeuroAnalyzer:eeg:unequalTrials', ['The trials have different lengths (from %d to ' ...
                '%d samples). Cut them to the same time window in FieldTrip (ft_redefinetrial with ' ...
                'toilim) and save again.'], min(lens), max(lens));
        end
        data = cat(3, d.trial{:});
        tt = d.time;
        if iscell(tt), tt = tt{1}; end
        times = double(tt(:)');
        isEp = nTr > 1 || times(1) < 0;
        codes = trialCodes(d, nTr);
    elseif isfield(d, 'avg')
        % ---- timelock average ----
        data = d.avg;
        if isfield(d, 'dimord') && strcmp(d.dimord, 'time_chan'), data = data.'; end
        times = double(d.time(:)');
        isEp = true;
        cond = {'Average'};
        notes{end + 1} = ['The file holds an average over trials, not the single trials. ' ...
            'Measures that need single trials cannot be computed.'];
    elseif isfield(d, 'trial') && isnumeric(d.trial)
        % ---- timelock with keeptrials ----
        if isfield(d, 'dimord') && ~strcmp(d.dimord, 'rpt_chan_time')
            error('NeuroAnalyzer:eeg:sizeMismatch', 'Trials stored as ''%s'' are not supported (expected rpt_chan_time).', d.dimord);
        end
        data = permute(d.trial, [2 3 1]);
        times = double(d.time(:)');
        isEp = true;
        codes = trialCodes(d, size(data, 3));
    else
        error('NeuroAnalyzer:eeg:notFieldTrip', 'The trials in ''%s'' are neither a list of trials nor a number array.', name);
    end
    if size(data, 1) ~= nCh
        error('NeuroAnalyzer:eeg:sizeMismatch', 'The data have %d channels but %d channel names.', size(data, 1), nCh);
    end
    if size(data, 2) ~= numel(times)
        error('NeuroAnalyzer:eeg:sizeMismatch', 'The data have %d samples but %d time points.', size(data, 2), numel(times));
    end
    if isfield(d, 'fsample') && isnumeric(d.fsample) && isscalar(d.fsample)
        fs = double(d.fsample);
    else
        fs = 1 / median(diff(times));
    end

    % ---- Conditions ----
    if isEp && isempty(cond)
        names = o.ConditionNames;
        if isempty(names)
            for f = {'conditionNames', 'condition_names', 'conditionLabels'}
                if isfield(s, f{1}), names = EEGSource.cellRow(s.(f{1})); break; end
            end
        end
        if iscell(codes)
            cond = codes;
        elseif ~isempty(codes)
            cond = cell(1, numel(codes));
            for k = 1:numel(codes)
                c = codes(k);
                if ~isempty(names) && c >= 1 && c <= numel(names) && c == round(c)
                    cond{k} = names{c};
                else
                    cond{k} = sprintf('Code %g', c);
                end
            end
            if isempty(names)
                notes{end + 1} = 'The trials are labelled with the numbers found in trialinfo.';
            end
        end
    end

    % ---- Events (continuous) ----
    events = [];
    if ~isEp
        ev = [];
        if isfield(s, 'event') && isstruct(s.event), ev = s.event; end
        if isempty(ev) && isfield(d, 'cfg') && isfield(d.cfg, 'event') && isstruct(d.cfg.event), ev = d.cfg.event; end
        if ~isempty(ev) && isfield(ev, 'sample')
            events = struct('type', {}, 'latency', {}, 'duration', {});
            first = 1;
            if isfield(d, 'sampleinfo') && ~isempty(d.sampleinfo), first = double(d.sampleinfo(1, 1)); end
            for k = 1:numel(ev)
                dur = 0;
                if isfield(ev, 'duration') && isnumeric(ev(k).duration) && ~isempty(ev(k).duration)
                    dur = double(ev(k).duration) / fs;
                end
                events(end + 1) = struct('type', eventName(ev(k)), ...
                    'latency', (double(ev(k).sample) - first) / fs + times(1), 'duration', dur); %#ok<AGROW>
            end
        end
    end

    % ---- Positions ----
    locs = struct('label', labels, 'x', NaN, 'y', NaN, 'z', NaN, 'theta', NaN, 'radius', NaN);
    coord = '';
    if isfield(d, 'elec') && isstruct(d.elec) && isfield(d.elec, 'label')
        e = d.elec;
        pos = [];
        for f = {'elecpos', 'chanpos', 'pnt'}
            if isfield(e, f{1}) && ~isempty(e.(f{1})), pos = double(e.(f{1})); break; end
        end
        el = EEGSource.cellRow(e.label);
        if ~isempty(pos) && size(pos, 1) == numel(el)
            for k = 1:nCh
                i = find(strcmpi(el, labels{k}), 1);
                if ~isempty(i)
                    locs(k).x = pos(i, 1); locs(k).y = pos(i, 2); locs(k).z = pos(i, 3);
                end
            end
            cs = 'unknown axes';
            if isfield(e, 'coordsys') && ~isempty(e.coordsys), cs = char(e.coordsys); end
            un = 'unknown unit';
            if isfield(e, 'unit') && ~isempty(e.unit), un = char(e.unit); end
            coord = sprintf('FieldTrip (%s, %s)', cs, un);
        end
    end

    % ---- History ----
    lines = {};
    ref = 'unknown';
    if isfield(d, 'cfg')
        [lines, info] = EEGSource.fieldtripHistory(d.cfg, labels);
        if ~isempty(info.reference), ref = info.reference; end
    end

    eeg = EEGSource.make(data, fs, 'Times', times, 'Labels', labels, 'Chanlocs', locs, ...
        'CoordSystem', coord, 'Conditions', cond, 'Events', events, 'Reference', ref, ...
        'History', lines, 'Notes', notes, 'Unit', 'auto', 'IsEpoched', isEp, ...
        'Source', 'FieldTrip', 'Format', 'fieldtrip', 'File', file);
end

%% trialCodes - First column of trialinfo (numbers, or texts from a table)
function codes = trialCodes(d, nTr)
    codes = [];
    if ~isfield(d, 'trialinfo') || isempty(d.trialinfo), return; end
    ti = d.trialinfo;
    if isa(ti, 'table')
        v = ti{:, 1};
        if isnumeric(v), codes = double(v(:)'); else, codes = EEGSource.cellRow(cellstr(v)); end
    elseif isnumeric(ti)
        codes = double(ti(:, 1)');
    end
    if numel(codes) ~= nTr
        error('NeuroAnalyzer:eeg:sizeMismatch', 'trialinfo has %d rows for %d trials.', numel(codes), nTr);
    end
end

%% eventName - FieldTrip event: its value if it has one, else its type
function t = eventName(ev)
    t = '';
    if isfield(ev, 'value') && ~isempty(ev.value)
        if ischar(ev.value)
            t = strtrim(ev.value);
        elseif isnumeric(ev.value)
            t = sprintf('%s %g', char(ev.type), ev.value(1));
        end
    end
    if isempty(t), t = strtrim(char(ev.type)); end
end
