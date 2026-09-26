%% EEGSource.m
% =========================================================================
% EEG SOURCE - ONE DATA SHAPE FOR EEG FROM EEGLAB, FIELDTRIP, BRAINVISION AND .MAT
% =========================================================================
% Every EEG file is read into one struct, so the EEG window (and anything
% after it) does not care where the data came from:
%   eeg.data         channels x samples x trials, single, microvolts
%   eeg.fs           sampling rate (Hz)
%   eeg.times        1 x samples, seconds (epoch time for trials: 0 = event)
%   eeg.labels       1 x channels cell of channel names
%   eeg.chanlocs     1 x channels struct: label, x, y, z, theta, radius
%                    (as stored in the file; NaN = no position)
%   eeg.coordSystem  what the positions mean, e.g. 'EEGLAB (x = nose, ...)'
%                    or 'FieldTrip (ras, mm)'; '' = no positions. Step 3 of
%                    the EEG plan converts all of them to one orientation.
%   eeg.isEpoched    true for data cut into trials
%   eeg.trials.condition  1 x trials cell: condition of each trial
%   eeg.conditions   condition names in order of first appearance
%   eeg.events       continuous data: struct array type, latency (s), duration (s)
%   eeg.reference    plain words, e.g. 'average of all channels', 'unknown'
%   eeg.history      1 x n cell of plain sentences: what was already done
%   eeg.notes        1 x n cell of plain sentences worth knowing (units, ...)
%   eeg.source, eeg.format, eeg.file
%
%   list  = EEGSource.formats()           struct array: key, label, filter, hint
%   fmt   = EEGSource.detect(path)        'eeglab' | 'fieldtrip' | 'brainvision' | 'matrix'
%   eeg   = EEGSource.open(path, fmt, map) read (fmt 'auto'/omitted: detect;
%                                          map only for 'matrix', see readEEGMatrix)
%   eeg   = EEGSource.make(data, fs, Name, Value, ...)   assemble + check
%   [ok, problems] = EEGSource.validate(eeg)
%   lines = EEGSource.describe(eeg)       overview in plain sentences
%   lines = EEGSource.describeHistory(eeg)
%   g     = EEGSource.guessMatrixMap(path) variables of a plain .mat file and
%                                          a suggested map (see readEEGMatrix)
%   [lines, info] = EEGSource.eeglabHistory(text, labels)
%   [lines, info] = EEGSource.fieldtripHistory(cfg, labels)
%
% The history of EEGLAB files is read from EEG.history and the history of
% FieldTrip files from the cfg.previous chain. Nothing in a file is ever
% run: the commands are only read as text.
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:unknownFormat,
% NeuroAnalyzer:eeg:invalid, NeuroAnalyzer:eeg:needsMap, NeuroAnalyzer:eeg:badOption.
% Toolboxes: none (EEGLAB and FieldTrip are not needed).
% =========================================================================

classdef EEGSource
    methods(Static)

        %% formats - Supported sources, in dropdown order
        function list = formats()
            list = struct( ...
                'key',    {'eeglab', 'fieldtrip', 'brainvision', 'matrix'}, ...
                'label',  {'EEGLAB dataset (.set)', 'FieldTrip data (.mat)', 'BrainVision (.vhdr)', 'MATLAB matrix (.mat)'}, ...
                'filter', {{'*.set;*.mat', 'EEGLAB dataset (*.set, *.mat)'}, ...
                           {'*.mat', 'FieldTrip data (*.mat)'}, ...
                           {'*.vhdr', 'BrainVision header (*.vhdr)'}, ...
                           {'*.mat', 'MATLAB file (*.mat)'}}, ...
                'hint',   {'An EEGLAB .set file (with its .fdt file in the same folder, if there is one), or a .mat file holding an EEG variable', ...
                           'A .mat file holding a FieldTrip structure (label, trial, time) or an average (label, avg, time)', ...
                           'Brain Products BrainVision Recorder or Analyzer: the .vhdr file, with its .vmrk and .eeg files in the same folder', ...
                           'Any .mat file with the EEG as a number array: you say which variable holds what'});
        end

        %% label - Display label of a format key
        function s = label(fmt)
            list = EEGSource.formats();
            k = find(strcmpi({list.key}, fmt), 1);
            if isempty(k), s = fmt; else, s = list(k).label; end
        end

        %% detect - Guess the format of a file
        function fmt = detect(p)
            if ~(exist(p, 'file') == 2)
                error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', p);
            end
            [~, ~, ext] = fileparts(p);
            switch lower(ext)
                case '.set', fmt = 'eeglab'; return;
                case '.vhdr', fmt = 'brainvision'; return;
                case {'.vmrk', '.eeg'}
                    error('NeuroAnalyzer:io:unknownFormat', ['%s is one part of a BrainVision recording ' ...
                        '(markers or numbers). Choose the .vhdr file with the same name instead; it ' ...
                        'reads all three parts.'], p);
                case '.fdt'
                    error('NeuroAnalyzer:io:unknownFormat', ['%s holds only the numbers of an EEGLAB ' ...
                        'dataset. Choose the .set file with the same name instead.'], p);
            end
            s = EEGSource.loadMat(p);
            if EEGSource.isEEGLABStruct(s)
                fmt = 'eeglab';
            elseif ~isempty(EEGSource.fieldtripVariables(s))
                fmt = 'fieldtrip';
            elseif any(structfun(@(v) isnumeric(v) && numel(v) > 1, s))
                fmt = 'matrix';
            else
                error('NeuroAnalyzer:io:unknownFormat', ['%s holds no EEG data that could be ' ...
                    'recognised (no EEGLAB or FieldTrip structure and no number array).'], p);
            end
        end

        %% open - Read a file with the reader for its format
        function eeg = open(p, fmt, map)
            if nargin < 2 || isempty(fmt) || strcmpi(fmt, 'auto')
                fmt = EEGSource.detect(p);
            end
            switch lower(fmt)
                case 'eeglab',    eeg = readEEGLAB(p);
                case 'fieldtrip', eeg = readFieldTrip(p);
                case 'brainvision', eeg = readBrainVision(p);
                case 'matrix'
                    if nargin < 3 || isempty(map)
                        g = EEGSource.guessMatrixMap(p);
                        if g.ambiguous
                            error('NeuroAnalyzer:eeg:needsMap', ['The file does not make clear which ' ...
                                'variable holds the EEG or how it is arranged: %s Say which variable ' ...
                                'holds the data, the sampling rate and the order of channels, samples ' ...
                                'and trials.'], strjoin(g.problems, ' '));
                        end
                        map = g.map;
                    end
                    eeg = readEEGMatrix(p, map);
                otherwise
                    error('NeuroAnalyzer:io:unknownFormat', ...
                        'Unknown format ''%s'' (use eeglab, fieldtrip, brainvision or matrix).', fmt);
            end
        end

        %% make - Assemble the common struct and check it
        % data: channels x samples (x trials). Name/Value options:
        %   Times, Labels, Chanlocs, CoordSystem, Conditions (one per trial;
        %   numbers become 'Code 1', ...), Events, Reference, History, Notes,
        %   Unit ('auto' | 'uV' | 'mV' | 'V'; 'auto' treats values smaller
        %   than 0.01 as volts), Source, Format, File, IsEpoched.
        function eeg = make(data, fs, varargin)
            o = struct('Times', [], 'Labels', {{}}, 'Chanlocs', [], 'CoordSystem', '', ...
                'Conditions', {{}}, 'Events', [], 'Reference', 'unknown', 'History', {{}}, ...
                'Notes', {{}}, 'Unit', 'auto', 'Source', '', 'Format', '', 'File', '', 'IsEpoched', []);
            o = EEGSource.options(o, varargin);
            if ~isnumeric(data) || isempty(data) || ndims(data) > 3
                error('NeuroAnalyzer:eeg:invalid', ['The EEG must be a number array of channels x ' ...
                    'samples, or channels x samples x trials.']);
            end
            if ~(isnumeric(fs) && isscalar(fs) && isfinite(fs) && fs > 0)
                error('NeuroAnalyzer:eeg:invalid', 'The sampling rate must be one positive number (Hz).');
            end
            [nCh, nS, nTr] = size(data);
            [data, unitNote] = EEGSource.toMicrovolts(data, o.Unit);

            times = double(o.Times(:)');
            if isempty(times), times = (0:nS - 1) / fs; end
            labels = EEGSource.cellRow(o.Labels);
            if isempty(labels)
                labels = arrayfun(@(c) sprintf('Ch %d', c), 1:nCh, 'UniformOutput', false);
            end
            locs = EEGSource.normaliseChanlocs(o.Chanlocs, labels);
            isEp = o.IsEpoched;
            if isempty(isEp), isEp = nTr > 1 || (~isempty(times) && times(1) < 0); end

            cond = o.Conditions;
            if isnumeric(cond) || islogical(cond)
                cond = arrayfun(@(c) sprintf('Code %g', c), double(cond(:)'), 'UniformOutput', false);
            end
            cond = EEGSource.cellRow(cond);
            if isEp && isempty(cond), cond = repmat({'All trials'}, 1, nTr); end
            if ~isEp, cond = {}; end

            ev = o.Events;
            if isempty(ev), ev = struct('type', {}, 'latency', {}, 'duration', {}); end

            notes = EEGSource.cellRow(o.Notes);
            if ~isempty(unitNote), notes{end + 1} = unitNote; end

            eeg = struct();
            eeg.data = data;
            eeg.fs = double(fs);
            eeg.times = times;
            eeg.labels = labels;
            eeg.chanlocs = locs;
            eeg.coordSystem = o.CoordSystem;
            if ~any(isfinite([locs.x])), eeg.coordSystem = ''; end
            eeg.isEpoched = logical(isEp);
            eeg.trials = struct('condition', {cond});
            eeg.conditions = EEGSource.stableUnique(cond);
            eeg.events = ev;
            eeg.reference = o.Reference;
            eeg.history = EEGSource.cellRow(o.History);
            eeg.notes = notes;
            eeg.source = o.Source;
            eeg.format = o.Format;
            eeg.file = o.File;
            [ok, problems] = EEGSource.validate(eeg);
            if ~ok
                error('NeuroAnalyzer:eeg:invalid', '%s', strjoin(problems, ' '));
            end
            if numel(EEGSource.stableUnique(lower(labels))) < numel(labels)
                eeg.notes{end + 1} = 'Some channel names appear more than once.';
            end
        end

        %% validate - Problems with an EEG struct, in plain sentences
        function [ok, problems] = validate(eeg)
            problems = {};
            need = {'data', 'fs', 'times', 'labels', 'chanlocs', 'isEpoched', 'trials', ...
                'conditions', 'events', 'reference', 'history'};
            missing = need(~isfield(eeg, need));
            if ~isempty(missing)
                problems{end + 1} = sprintf('Missing parts: %s.', strjoin(missing, ', '));
                ok = false;
                return;
            end
            [nCh, nS, nTr] = size(eeg.data);
            if ~isnumeric(eeg.data)
                problems{end + 1} = 'The data are not numbers.';
            end
            if ~(isscalar(eeg.fs) && eeg.fs > 0)
                problems{end + 1} = 'The sampling rate must be one positive number.';
            end
            if numel(eeg.labels) ~= nCh
                problems{end + 1} = sprintf('There are %d channel names for %d channels.', numel(eeg.labels), nCh);
            end
            if numel(eeg.chanlocs) ~= nCh
                problems{end + 1} = sprintf('There are %d channel positions for %d channels.', numel(eeg.chanlocs), nCh);
            end
            if numel(eeg.times) ~= nS
                problems{end + 1} = sprintf('There are %d time points for %d samples.', numel(eeg.times), nS);
            elseif nS > 1 && any(diff(eeg.times) <= 0)
                problems{end + 1} = 'The time points do not increase steadily.';
            end
            if eeg.isEpoched && numel(eeg.trials.condition) ~= nTr
                problems{end + 1} = sprintf('There are %d trial conditions for %d trials.', ...
                    numel(eeg.trials.condition), nTr);
            end
            if ~eeg.isEpoched && nTr > 1
                problems{end + 1} = 'Continuous data must have a single trial.';
            end
            ok = isempty(problems);
        end

        %% describe - Overview in plain sentences
        function lines = describe(eeg)
            [nCh, nS, nTr] = size(eeg.data);
            lines = {};
            if eeg.isEpoched
                lines{end + 1} = sprintf('%d channels at %g Hz, %d trials from %.3g to %.3g s around the event.', ...
                    nCh, eeg.fs, nTr, eeg.times(1), eeg.times(end));
                counts = cellfun(@(c) sum(strcmp(eeg.trials.condition, c)), eeg.conditions);
                parts = arrayfun(@(k) sprintf('%s (%d)', eeg.conditions{k}, counts(k)), ...
                    1:numel(counts), 'UniformOutput', false);
                lines{end + 1} = sprintf('Trials per condition: %s.', EEGSource.listText(parts));
            else
                lines{end + 1} = sprintf('%d channels at %g Hz, a continuous recording of %.1f s.', ...
                    nCh, eeg.fs, nS / eeg.fs);
                if isempty(eeg.events)
                    lines{end + 1} = 'No events are marked in the recording.';
                else
                    types = EEGSource.stableUnique({eeg.events.type});
                    lines{end + 1} = sprintf('%d events marked (%s).', numel(eeg.events), EEGSource.listText(types));
                end
            end
            lines{end + 1} = sprintf('Reference: %s.', eeg.reference);
            nPos = sum(isfinite([eeg.chanlocs.x]));
            if nPos == 0
                lines{end + 1} = 'The file has no electrode positions.';
            else
                lines{end + 1} = sprintf('Electrode positions for %d of %d channels, %s.', nPos, nCh, eeg.coordSystem);
            end
            lines = [lines, eeg.notes];
        end

        %% describeHistory - What was done before, in plain sentences
        function lines = describeHistory(eeg)
            lines = eeg.history;
            if isempty(lines)
                lines = {'The file does not say how the data were processed before.'};
            end
        end

        %% guessMatrixMap - Variables of a plain .mat file and a suggested map
        % g.variables: struct array name, size, class, text ('double, 65 x 32 x 250')
        % g.map: fields for readEEGMatrix (data, fs, dims, labels, times,
        %        conditions, events, unit)
        % g.notes: what was guessed and why; g.problems: what is unclear;
        % g.ambiguous: true when the map should be checked by a person.
        function g = guessMatrixMap(p)
            s = EEGSource.loadMat(p);
            names = fieldnames(s)';
            vars = struct('name', {}, 'size', {}, 'class', {}, 'text', {});
            for k = 1:numel(names)
                v = s.(names{k});
                sz = size(v);
                vars(end + 1) = struct('name', names{k}, 'size', sz, 'class', class(v), ...
                    'text', sprintf('%s, %s', class(v), strjoin(arrayfun(@num2str, sz, 'UniformOutput', false), ' x '))); %#ok<AGROW>
            end
            g = struct('variables', vars, 'map', struct(), 'notes', {{}}, 'problems', {{}}, 'ambiguous', false);
            map = struct('data', '', 'fs', [], 'dims', {{}}, 'labels', '', 'times', '', ...
                'conditions', '', 'events', '', 'unit', 'auto');

            % Data: the numeric variable with the most values
            isArr = cellfun(@(n) isnumeric(s.(n)) && numel(s.(n)) > 1 && ~isvector(s.(n)), names);
            if ~any(isArr)
                g.problems{end + 1} = 'No variable holds a table of numbers (channels x samples).';
                g.ambiguous = true;
                g.map = map;
                return;
            end
            cand = names(isArr);
            [~, k] = max(cellfun(@(n) numel(s.(n)), cand));
            map.data = cand{k};
            sz = size(s.(map.data));
            nd = numel(sz);
            g.notes{end + 1} = sprintf('Data: ''%s'' (%s).', map.data, ...
                strjoin(arrayfun(@num2str, sz, 'UniformOutput', false), ' x '));

            % Sampling rate: a single number with a usual name
            fsNames = '^(fs|srate|sfreq|fsample|samplerate|sampling_?rate|sr|samplingfrequency)$';
            for n = names
                v = s.(n{1});
                if isnumeric(v) && isscalar(v) && v > 0 && ~isempty(regexpi(n{1}, fsNames, 'once'))
                    map.fs = n{1};
                    g.notes{end + 1} = sprintf('Sampling rate: ''%s'' (%g Hz).', n{1}, v);
                    break;
                end
            end
            if isempty(map.fs)
                g.problems{end + 1} = 'No variable gives the sampling rate (for example fs or srate).';
            end

            % Time, channel names, conditions and events: vectors whose length matches a data dimension
            used = [];
            timeDim = [];
            for n = names
                v = s.(n{1});
                if isnumeric(v) && isvector(v) && numel(v) > 2 && any(numel(v) == sz) ...
                        && all(diff(double(v(:))) > 0) && ~isempty(regexpi(n{1}, '^(t|time|times|tvec|timevec|time_s|lat\w*)$', 'once'))
                    map.times = n{1};
                    timeDim = find(sz == numel(v), 1);
                    g.notes{end + 1} = sprintf('Time: ''%s'' (%d points, dimension %d).', n{1}, numel(v), timeDim);
                    break;
                end
            end
            if isempty(timeDim)
                [~, timeDim] = max(sz);
                g.notes{end + 1} = sprintf('Time: the longest dimension (%d, %d samples).', timeDim, sz(timeDim));
            end
            used(end + 1) = timeDim;
            chanDim = [];
            for n = names
                v = s.(n{1});
                if ischar(v) && size(v, 1) > 1, v = cellstr(v); end
                if iscellstr(v) && ~isempty(regexpi(n{1}, '(label|chan|electrode|sensor|name)', 'once'))
                    d = find(sz == numel(v));
                    d = setdiff(d, used);
                    if ~isempty(d)
                        map.labels = n{1};
                        chanDim = d(1);
                        g.notes{end + 1} = sprintf('Channel names: ''%s'' (%d names, dimension %d).', n{1}, numel(v), chanDim);
                        break;
                    end
                end
            end
            trialDim = [];
            for n = names
                v = s.(n{1});
                if strcmp(n{1}, map.labels) || strcmp(n{1}, map.data), continue; end
                if (iscellstr(v) || (isnumeric(v) && isvector(v))) && ...
                        ~isempty(regexpi(n{1}, '(cond|trialinfo|trial_?type|class|stim_?type|category)', 'once'))
                    d = setdiff(find(sz == numel(v)), [used, chanDim]);
                    if ~isempty(d) && nd >= 3
                        map.conditions = n{1};
                        trialDim = d(1);
                        g.notes{end + 1} = sprintf('Conditions: ''%s'' (%d trials, dimension %d).', n{1}, numel(v), trialDim);
                        break;
                    end
                end
            end
            used = [used, chanDim, trialDim];
            rest = setdiff(1:nd, used);
            if nd == 2
                if isempty(chanDim), chanDim = rest(1); end
            else
                if isempty(chanDim) && isempty(trialDim)
                    [~, i] = sort(sz(rest));
                    chanDim = rest(i(1));
                    trialDim = rest(i(2));
                    g.notes{end + 1} = sprintf(['Channels: dimension %d and trials: dimension %d ' ...
                        '(fewer channels than trials assumed).'], chanDim, trialDim);
                    if sz(chanDim) == sz(trialDim)
                        g.problems{end + 1} = 'The channel and trial dimensions have the same size.';
                    end
                elseif isempty(chanDim)
                    chanDim = rest(1);
                elseif isempty(trialDim)
                    trialDim = rest(1);
                end
            end
            if sum(sz == sz(timeDim)) > 1 && isempty(map.times)
                g.problems{end + 1} = 'Two dimensions have the same length, so the time dimension is unclear.';
            end
            dims = cell(1, nd);
            dims{chanDim} = 'channel';
            dims{timeDim} = 'time';
            if nd >= 3, dims{trialDim} = 'trial'; end
            map.dims = dims;

            for n = names
                v = s.(n{1});
                if isnumeric(v) && isvector(v) && ~strcmp(n{1}, map.times) && ~strcmp(n{1}, map.conditions) ...
                        && ~isempty(regexpi(n{1}, '(event|onset|stim|flash|trigger|marker)', 'once'))
                    map.events = n{1};
                    g.notes{end + 1} = sprintf('Event times (s): ''%s'' (%d events).', n{1}, numel(v));
                    break;
                end
            end
            g.map = map;
            g.ambiguous = ~isempty(g.problems);
        end

        %% eeglabHistory - Plain sentences from EEGLAB's EEG.history text
        % info.reference: the last reference set in the history ('' if none).
        function [lines, info] = eeglabHistory(txt, labels)
            if nargin < 2, labels = {}; end
            lines = {};
            info = struct('reference', '');
            if isempty(txt), return; end
            if iscell(txt)
                rows = txt(:)';
            else
                if size(txt, 1) > 1, txt = strjoin(cellstr(txt)', newline); end
                rows = regexp(char(txt), '\r?\n', 'split');
            end
            skip = {'pop_loadset', 'pop_saveset', 'eeg_checkset', 'pop_newset', 'eeg_store', ...
                'pop_editset', 'eeglab', 'pop_biosig', 'pop_fileio', 'pop_loadbv', 'pop_readegi', ...
                'pop_mffimport', 'eeg_retrieve', 'pop_delset'};
            for r = 1:numel(rows)
                s = strtrim(rows{r});
                if isempty(s) || s(1) == '%', continue; end
                % Bookkeeping lines (EEG.etc.eeglabvers = ..., EEG.setname = ...) say nothing about processing
                if ~isempty(regexp(s, '^EEG\.(etc|setname|filename|filepath|subject|group|condition|session|comments)\>', 'once'))
                    continue;
                end
                [fn, a] = EEGSource.parseCall(s);
                if isempty(fn)
                    lines{end + 1} = ['Other step (as written in the file): ' s]; %#ok<AGROW>
                    continue;
                end
                if ismember(fn, skip), continue; end
                if ~isempty(a) && ~isempty(regexp(a{1}, '^(EEG|ALLEEG)\w*$', 'once')), a = a(2:end); end
                v = cellfun(@EEGSource.parseValue, a, 'UniformOutput', false);
                line = '';
                switch fn
                    case {'pop_eegfiltnew', 'pop_eegfilt', 'pop_firws', 'pop_basicfilter'}
                        lo = EEGSource.named(v, 'locutoff');
                        hi = EEGSource.named(v, 'hicutoff');
                        rev = EEGSource.named(v, 'revfilt');
                        if isempty(lo) && isempty(hi) && ~isempty(v) && isnumeric(v{1})
                            lo = v{1};
                            if numel(v) >= 2 && isnumeric(v{2}), hi = v{2}; end
                            if strcmp(fn, 'pop_eegfilt') && numel(v) >= 4 && isnumeric(v{4}), rev = v{4}; end
                            if strcmp(fn, 'pop_eegfiltnew') && numel(v) >= 4 && isnumeric(v{4}), rev = v{4}; end
                        end
                        line = EEGSource.filterText(lo, hi, ~isempty(rev) && isnumeric(rev) && any(rev));
                    case 'pop_reref'
                        ref = [];
                        if ~isempty(v), ref = v{1}; end
                        if isempty(ref)
                            info.reference = 'average of all channels';
                            line = 'Re-referenced to the average of all channels';
                        else
                            names = EEGSource.channelNames(ref, labels);
                            info.reference = EEGSource.listText(names);
                            line = ['Re-referenced to ' info.reference];
                        end
                    case 'pop_subcomp'
                        if ~isempty(v) && isnumeric(v{1}) && ~isempty(v{1})
                            line = sprintf('Removed ICA %s %s', EEGSource.plural(numel(v{1}), 'component'), ...
                                EEGSource.listText(EEGSource.numText(v{1})));
                        else
                            line = 'Removed ICA components';
                        end
                    case 'pop_rejepoch'
                        n = 0;
                        if ~isempty(v) && isnumeric(v{1}), n = EEGSource.countSelected(v{1}); end
                        line = sprintf('Rejected %d %s', n, EEGSource.plural(n, 'trial'));
                    case 'pop_interp'
                        if ~isempty(v) && (isnumeric(v{1}) || iscell(v{1})) && ~isempty(v{1})
                            names = EEGSource.channelNames(v{1}, labels);
                            line = sprintf('Interpolated %s %s', EEGSource.plural(numel(names), 'channel'), ...
                                EEGSource.listText(names));
                        else
                            line = 'Interpolated bad channels';
                        end
                        if numel(v) >= 2 && ischar(v{2}) && strcmpi(v{2}, 'spherical')
                            line = [line ' using spherical splines'];
                        elseif numel(v) >= 2 && ischar(v{2})
                            line = sprintf('%s using the %s method', line, v{2});
                        end
                    case 'pop_resample'
                        if ~isempty(v) && isnumeric(v{1}), line = sprintf('Resampled to %g Hz', v{1}); end
                    case 'pop_epoch'
                        line = 'Cut into trials';
                        if numel(v) >= 2 && isnumeric(v{2}) && numel(v{2}) == 2
                            line = sprintf('%s from %g to %g s', line, v{2}(1), v{2}(2));
                        end
                        if ~isempty(v) && iscell(v{1}) && ~isempty(v{1})
                            line = sprintf('%s around the events %s', line, EEGSource.listText(v{1}));
                        end
                    case 'pop_rmbase'
                        line = 'Removed the baseline';
                        if ~isempty(v) && isnumeric(v{1}) && numel(v{1}) == 2
                            line = sprintf('%s, the mean from %g to %g ms', line, v{1}(1), v{1}(2));
                        end
                    case 'pop_runica'
                        t = EEGSource.named(v, 'icatype');
                        if ~ischar(t) || isempty(t), t = 'runica'; end
                        line = sprintf('Computed ICA with %s', t);
                    case 'pop_select'
                        parts = {};
                        x = EEGSource.named(v, 'nochannel');
                        if isempty(x), x = EEGSource.named(v, 'rmchannel'); end
                        if ~isempty(x), parts{end + 1} = EEGSource.channelText('removed', x, labels); end
                        x = EEGSource.named(v, 'channel');
                        if ~isempty(x), parts{end + 1} = EEGSource.channelText('kept', x, labels); end
                        x = EEGSource.named(v, 'notrial');
                        if isempty(x), x = EEGSource.named(v, 'rmtrial'); end
                        if ~isempty(x), parts{end + 1} = sprintf('removed %d trials', EEGSource.countSelected(x)); end
                        x = EEGSource.named(v, 'trial');
                        if ~isempty(x), parts{end + 1} = sprintf('kept %d trials', EEGSource.countSelected(x)); end
                        if isempty(parts), parts = {'selected part of the data'}; end
                        line = strjoin(parts, ', ');
                        line(1) = upper(line(1));
                    case 'pop_chanedit'
                        line = 'Set or edited the channel positions';
                    case {'clean_rawdata', 'pop_clean_rawdata', 'clean_artifacts'}
                        line = 'Cleaned automatically with clean_rawdata (bad channels and bursts)';
                    case 'pop_iclabel'
                        line = 'Classified the ICA components with ICLabel';
                    case 'pop_icflag'
                        line = 'Flagged ICA components for removal from their ICLabel classes';
                    case 'pop_cleanline'
                        line = 'Removed line noise (CleanLine)';
                end
                if isempty(line)
                    lines{end + 1} = ['Other step (as written in the file): ' s]; %#ok<AGROW>
                else
                    lines{end + 1} = sprintf('%s (%s).', line, fn); %#ok<AGROW>
                end
            end
        end

        %% fieldtripHistory - Plain sentences from a FieldTrip cfg / cfg.previous chain
        function [lines, info] = fieldtripHistory(cfg, labels)
            if nargin < 2, labels = {}; end %#ok<NASGU>
            lines = {};
            info = struct('reference', '');
            chain = {};
            c = cfg;
            while isstruct(c) && ~isempty(c) && numel(chain) < 200
                chain{end + 1} = c(1); %#ok<AGROW>
                if ~isfield(c, 'previous') || isempty(c.previous), break; end
                c = c.previous;
                if iscell(c), c = c{1}; end
            end
            for k = numel(chain):-1:1
                [steps, ref] = EEGSource.fieldtripStep(chain{k});
                lines = [lines, steps]; %#ok<AGROW>
                if ~isempty(ref), info.reference = ref; end
            end
        end
    end

    methods(Static, Hidden)

        %% fieldtripStep - Sentences for one cfg of the chain (oldest first)
        function [lines, ref] = fieldtripStep(c)
            lines = {};
            ref = '';
            fn = '';
            if isfield(c, 'version') && isstruct(c.version) && isfield(c.version, 'name')
                fn = char(c.version.name);
            end
            if EEGSource.isYes(c, 'bpfilter') && isfield(c, 'bpfreq')
                lines{end + 1} = EEGSource.filterText(c.bpfreq(1), c.bpfreq(2), false);
            end
            if EEGSource.isYes(c, 'hpfilter') && isfield(c, 'hpfreq')
                lines{end + 1} = EEGSource.filterText(c.hpfreq, [], false);
            end
            if EEGSource.isYes(c, 'lpfilter') && isfield(c, 'lpfreq')
                lines{end + 1} = EEGSource.filterText([], c.lpfreq, false);
            end
            if EEGSource.isYes(c, 'bsfilter') && isfield(c, 'bsfreq')
                lines{end + 1} = EEGSource.filterText(c.bsfreq(1), c.bsfreq(2), true);
            end
            if EEGSource.isYes(c, 'dftfilter')
                f = 50;
                if isfield(c, 'dftfreq'), f = c.dftfreq; end
                lines{end + 1} = sprintf('Removed line noise at %s Hz', EEGSource.listText(EEGSource.numText(f)));
            end
            if EEGSource.isYes(c, 'reref')
                r = 'all';
                if isfield(c, 'refchannel'), r = c.refchannel; end
                if ischar(r), r = {r}; end
                if any(strcmpi(r, 'all'))
                    ref = 'average of all channels';
                    lines{end + 1} = 'Re-referenced to the average of all channels';
                else
                    ref = EEGSource.listText(r);
                    lines{end + 1} = ['Re-referenced to ' ref];
                end
            end
            if isfield(c, 'resamplefs') && isnumeric(c.resamplefs) && ~isempty(c.resamplefs)
                lines{end + 1} = sprintf('Resampled to %g Hz', c.resamplefs);
            end
            if strcmp(fn, 'ft_componentanalysis')
                m = 'runica';
                if isfield(c, 'method') && ischar(c.method), m = c.method; end
                lines{end + 1} = sprintf('Computed ICA with %s', m);
            end
            if isfield(c, 'component') && isnumeric(c.component) && ~isempty(c.component) ...
                    && ~strcmp(fn, 'ft_componentanalysis')
                lines{end + 1} = sprintf('Removed ICA %s %s', EEGSource.plural(numel(c.component), 'component'), ...
                    EEGSource.listText(EEGSource.numText(c.component)));
            end
            bad = {};
            for f = {'badchannel', 'missingchannel'}
                if isfield(c, f{1}) && ~isempty(c.(f{1}))
                    x = c.(f{1});
                    if ischar(x), x = {x}; end
                    bad = [bad, x(:)']; %#ok<AGROW>
                end
            end
            if ~isempty(bad)
                line = sprintf('Interpolated %s %s', EEGSource.plural(numel(bad), 'channel'), EEGSource.listText(bad));
                if isfield(c, 'method') && ischar(c.method), line = sprintf('%s using the %s method', line, c.method); end
                lines{end + 1} = line;
            end
            if isfield(c, 'trl') && isnumeric(c.trl) && ~isempty(c.trl)
                lines{end + 1} = sprintf('Cut into %d trials', size(c.trl, 1));
            end
            if isfield(c, 'artfctdef') && isstruct(c.artfctdef)
                for t = fieldnames(c.artfctdef)'
                    a = c.artfctdef.(t{1});
                    if isstruct(a) && isfield(a, 'artifact') && ~isempty(a.artifact)
                        n = size(a.artifact, 1);
                        lines{end + 1} = sprintf('Rejected the trials with %d %s marked by the %s check', ...
                            n, EEGSource.plural(n, 'artifact'), t{1}); %#ok<AGROW>
                    end
                end
            end
            if EEGSource.isYes(c, 'demean')
                if isfield(c, 'baselinewindow') && isnumeric(c.baselinewindow) && numel(c.baselinewindow) == 2
                    lines{end + 1} = sprintf('Removed the baseline, the mean from %g to %g s', c.baselinewindow);
                else
                    lines{end + 1} = 'Removed the mean of each trial';
                end
            end
            if strcmp(fn, 'ft_timelockanalysis')
                lines{end + 1} = 'Averaged the trials';
            end
            if isempty(lines) && ~isempty(fn) && ~ismember(fn, {'ft_preprocessing', 'ft_definetrial', ...
                    'ft_appenddata', 'ft_selectdata', 'ft_redefinetrial'})
                lines{end + 1} = 'Other step, no settings recognised';
            end
            if ~isempty(fn)
                lines = cellfun(@(l) sprintf('%s (%s).', l, fn), lines, 'UniformOutput', false);
            else
                lines = cellfun(@(l) [l '.'], lines, 'UniformOutput', false);
            end
        end

        %% toMicrovolts - Scale to microvolts; note says what was done
        function [data, note] = toMicrovolts(data, unit)
            note = '';
            uV = [char(181) 'V'];
            switch lower(strrep(unit, char(181), 'u'))
                case {'uv', 'microvolt', 'microvolts'}
                    data = single(data);
                case {'mv', 'millivolt', 'millivolts'}
                    data = single(double(data) * 1e3);
                    note = sprintf('The values were in millivolts; they were multiplied by 1,000 to give %s.', uV);
                case {'v', 'volt', 'volts'}
                    data = single(double(data) * 1e6);
                    note = sprintf('The values were in volts; they were multiplied by 1,000,000 to give %s.', uV);
                case 'auto'
                    m = max(abs(double(data(isfinite(data)))));
                    if ~isempty(m) && m > 0 && m < 0.01
                        data = single(double(data) * 1e6);
                        note = sprintf(['The values were very small (largest %.3g), so they were stored ' ...
                            'in volts; they were multiplied by 1,000,000 to give %s.'], m, uV);
                    else
                        data = single(data);
                    end
                otherwise
                    error('NeuroAnalyzer:eeg:badOption', 'Unknown unit ''%s'' (use auto, uV, mV or V).', unit);
            end
        end

        %% normaliseChanlocs - 1 x n struct with label, x, y, z, theta, radius
        function locs = normaliseChanlocs(in, labels)
            n = numel(labels);
            locs = struct('label', labels, 'x', NaN, 'y', NaN, 'z', NaN, 'theta', NaN, 'radius', NaN);
            if isempty(in), return; end
            if numel(in) ~= n
                error('NeuroAnalyzer:eeg:invalid', 'There are %d channel positions for %d channels.', numel(in), n);
            end
            for k = 1:n
                for f = {'x', 'y', 'z', 'theta', 'radius'}
                    if isfield(in, f{1}) && isnumeric(in(k).(f{1})) && isscalar(in(k).(f{1}))
                        locs(k).(f{1}) = double(in(k).(f{1}));
                    end
                end
            end
        end

        %% options - Name/Value pairs into a defaults struct (case-insensitive names)
        function o = options(o, args)
            if mod(numel(args), 2) ~= 0
                error('NeuroAnalyzer:eeg:badOption', 'Options must come in Name, Value pairs.');
            end
            f = fieldnames(o);
            for k = 1:2:numel(args)
                i = find(strcmpi(f, args{k}), 1);
                if isempty(i)
                    error('NeuroAnalyzer:eeg:badOption', 'Unknown option ''%s''.', args{k});
                end
                o.(f{i}) = args{k + 1};
            end
        end

        %% loadMat - load a MAT file with a plain error
        function s = loadMat(p)
            if ~(exist(p, 'file') == 2)
                error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', p);
            end
            try
                s = load(p, '-mat');
            catch err
                error('NeuroAnalyzer:io:unknownFormat', 'Could not read %s as a MATLAB file (%s).', p, err.message);
            end
        end

        %% isEEGLABStruct - An EEG variable, or EEGLAB fields saved at the top level
        function tf = isEEGLABStruct(s)
            tf = (isfield(s, 'EEG') && isstruct(s.EEG) && isfield(s.EEG, 'data')) || ...
                (isfield(s, 'data') && isfield(s, 'srate') && isfield(s, 'nbchan'));
        end

        %% fieldtripVariables - Names of variables holding FieldTrip data
        function names = fieldtripVariables(s)
            names = {};
            for n = fieldnames(s)'
                v = s.(n{1});
                if isstruct(v) && isscalar(v) && isfield(v, 'label') && ...
                        (isfield(v, 'trial') || isfield(v, 'avg')) && isfield(v, 'time')
                    names{end + 1} = n{1}; %#ok<AGROW>
                end
            end
        end

        %% parseCall - Function name and argument texts of 'EEG = fn(a, b, ...);'
        function [fn, args] = parseCall(s)
            fn = '';
            args = {};
            [tok, i0] = regexp(s, '([A-Za-z]\w*)\s*\(', 'tokens', 'end', 'once');
            if isempty(tok), return; end
            fn = tok{1};
            depth = 1;
            q = false;
            i = i0 + 1;
            while i <= numel(s) && depth > 0
                ch = s(i);
                if ch == ''''
                    q = ~q;
                elseif ~q && any(ch == '([{')
                    depth = depth + 1;
                elseif ~q && any(ch == ')]}')
                    depth = depth - 1;
                end
                i = i + 1;
            end
            args = EEGSource.splitArgs(s(i0 + 1:i - 2));
        end

        %% splitArgs - Split an argument list at top-level commas
        function parts = splitArgs(s)
            parts = {};
            depth = 0;
            q = false;
            start = 1;
            for i = 1:numel(s)
                ch = s(i);
                if ch == ''''
                    q = ~q;
                elseif ~q && any(ch == '([{')
                    depth = depth + 1;
                elseif ~q && any(ch == ')]}')
                    depth = depth - 1;
                elseif ~q && depth == 0 && ch == ','
                    parts{end + 1} = strtrim(s(start:i - 1)); %#ok<AGROW>
                    start = i + 1;
                end
            end
            last = strtrim(s(start:end));
            if ~isempty(last), parts{end + 1} = last; end
        end

        %% parseValue - Text of one argument to a value, without running it
        % 'abc' -> char; {'a' 'b'} -> cell; [1 2 5:7] / 3 / [] -> numbers;
        % anything else stays as its text.
        function v = parseValue(s)
            s = strtrim(s);
            v = s;
            if isempty(s), return; end
            if numel(s) >= 2 && s(1) == '''' && s(end) == ''''
                v = strrep(s(2:end-1), '''''', '''');
                return;
            end
            if s(1) == '{'
                t = regexp(s, '''((?:[^'']|'''')*)''', 'tokens');
                if ~isempty(t)
                    v = cellfun(@(x) strrep(x{1}, '''''', ''''), t, 'UniformOutput', false);
                else
                    inner = EEGSource.parseValue(regexprep(s, '^\{|\}$', ''));
                    if isnumeric(inner), v = num2cell(inner); end
                end
                return;
            end
            if any(strcmpi(s, {'true', 'false'}))
                v = strcmpi(s, 'true');
                return;
            end
            body = strtrim(regexprep(s, '^\[|\]$', ''));
            if isempty(body), v = []; return; end
            if isempty(regexp(body, '^[\d\s\.,;:eE+\-]*$', 'once')), return; end
            toks = regexp(strtrim(regexprep(body, '[,;]', ' ')), '\s+', 'split');
            out = [];
            for k = 1:numel(toks)
                t = toks{k};
                if isempty(t), continue; end
                c = regexp(t, ':', 'split');
                n = str2double(c);
                if any(isnan(n)), return; end
                switch numel(n)
                    case 1, out = [out, n]; %#ok<AGROW>
                    case 2, out = [out, n(1):n(2)]; %#ok<AGROW>
                    case 3, out = [out, n(1):n(2):n(3)]; %#ok<AGROW>
                    otherwise, return;
                end
            end
            v = out;
        end

        %% named - Value after a 'name' argument ([] if absent)
        function x = named(v, key)
            x = [];
            for k = 1:numel(v) - 1
                if ischar(v{k}) && strcmpi(v{k}, key)
                    x = v{k + 1};
                    return;
                end
            end
        end

        %% filterText - 'Band-pass filtered 0.1 to 30 Hz' and friends
        function s = filterText(lo, hi, stop)
            if isempty(lo) || (isnumeric(lo) && all(lo == 0)), lo = []; end
            if isempty(hi) || (isnumeric(hi) && all(hi == 0)), hi = []; end
            if stop && ~isempty(lo) && ~isempty(hi)
                s = sprintf('Removed %g to %g Hz with a band-stop filter', lo, hi);
            elseif ~isempty(lo) && ~isempty(hi)
                s = sprintf('Band-pass filtered %g to %g Hz', lo, hi);
            elseif ~isempty(lo)
                s = sprintf('High-pass filtered above %g Hz', lo);
            elseif ~isempty(hi)
                s = sprintf('Low-pass filtered below %g Hz', hi);
            else
                s = 'Filtered, settings not recorded';
            end
        end

        %% channelNames - Channel indices (or names) to names
        function names = channelNames(x, labels)
            if iscell(x)
                names = cellfun(@EEGSource.valueText, x, 'UniformOutput', false);
                return;
            end
            if ischar(x), names = {x}; return; end
            names = cell(1, numel(x));
            for k = 1:numel(x)
                if x(k) >= 1 && x(k) <= numel(labels) && x(k) == round(x(k))
                    names{k} = labels{x(k)};
                else
                    names{k} = sprintf('channel %g', x(k));
                end
            end
        end

        %% channelText - 'removed channels A and B'
        function t = channelText(verb, x, labels)
            names = EEGSource.channelNames(x, labels);
            t = sprintf('%s %s %s', verb, EEGSource.plural(numel(names), 'channel'), EEGSource.listText(names));
        end

        %% valueText - Number or text to text
        function t = valueText(x)
            if isnumeric(x) || islogical(x)
                t = strjoin(EEGSource.numText(x), ' ');
            else
                t = strtrim(char(x));
            end
        end

        %% countSelected - Count of a 0/1 mask or of an index list
        function n = countSelected(x)
            x = x(:)';
            if numel(x) > 2 && all(x == 0 | x == 1)
                n = sum(x);
            else
                n = numel(x);
            end
        end

        %% isYes - cfg.(f) is 'yes' or true
        function tf = isYes(c, f)
            tf = isfield(c, f) && ((ischar(c.(f)) && strcmpi(c.(f), 'yes')) || ...
                ((islogical(c.(f)) || isnumeric(c.(f))) && isscalar(c.(f)) && c.(f) == 1));
        end

        %% numText - Numbers as a cell of short texts
        function c = numText(x)
            c = arrayfun(@(v) sprintf('%g', v), x(:)', 'UniformOutput', false);
        end

        %% listText - {'a','b','c'} -> 'a, b and c'
        function s = listText(c)
            if ischar(c), c = {c}; end
            c = cellfun(@char, c, 'UniformOutput', false);
            switch numel(c)
                case 0, s = '';
                case 1, s = c{1};
                otherwise, s = [strjoin(c(1:end-1), ', ') ' and ' c{end}];
            end
        end

        %% plural - 'trial' / 'trials'
        function s = plural(n, word)
            if n == 1, s = word; else, s = [word 's']; end
        end

        %% cellRow - Char matrix, string array or cell to a 1 x n cell of char
        function c = cellRow(x)
            if isempty(x), c = {}; return; end
            if ischar(x), x = cellstr(x); end
            if isa(x, 'string'), x = cellstr(x); end
            if isnumeric(x), x = arrayfun(@(v) sprintf('%g', v), x, 'UniformOutput', false); end
            c = cellfun(@(v) strtrim(char(v)), x(:)', 'UniformOutput', false);
        end

        %% stableUnique - Unique texts in order of first appearance
        function u = stableUnique(c)
            if isempty(c), u = {}; return; end
            [~, i] = unique(c, 'first');
            u = c(sort(i));
            u = u(:)';
        end
    end
end
