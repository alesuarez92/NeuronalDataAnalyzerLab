%% EEGAnalysis.m
% =========================================================================
% EEG ANALYSIS - HEADLESS ERPs PER CONDITION AND AMPLITUDE MEASURES
% =========================================================================
% The computations behind EEGAnalysisApp, without any UI, so scripts get
% exactly the same numbers as the window. Works on the EEG struct of
% core/io/EEGSource.m (channels x samples x trials, microvolts).
% Toolbox-free (base MATLAB).
%
%   ep  = EEGAnalysis.epoch(eeg, Name, Value)
%       Cuts a continuous recording into trials around its events.
%       'Window' [from to] in s around each event (default [-0.2 0.8]),
%       'Events' event types to use (default: all). The condition of each
%       trial is the event type. Events too close to either end are
%       skipped (ep.notes says how many). The step is added to ep.history.
%   erp = EEGAnalysis.conditionERPs(eeg, Name, Value)
%       Average of the trials of each condition. 'Conditions' (default
%       eeg.conditions), 'Baseline' [from to] in s: the mean of that window
%       is subtracted from each channel of each trial first (default []:
%       none, the data are used as they are).
%       erp.mean / erp.sem: channels x time x conditions (uV); erp.n:
%       trials per condition; erp.conditions, erp.times, erp.labels,
%       erp.fs, erp.baseline.
%   ga  = EEGAnalysis.grandAverage(erps)
%       Grand average of several participants' ERPs (a cell of
%       conditionERPs results with the same channels and times): the mean
%       of the participant averages, so every participant counts once.
%       ga.sem is the SEM across participants; ga.n the number of
%       participants per condition, ga.trials the trials in total. Only
%       the conditions every participant has are kept (ga.notes says which
%       were left out). One participant: its ERP as it is.
%   d   = EEGAnalysis.difference(erp, condA, condB)
%       Difference wave condA minus condB: d.mean (channels x time),
%       d.label ('Target minus Standard'), d.times, d.labels.
%   r   = EEGAnalysis.measure(erp, Name, Value)
%       One number per condition from the ERP averaged over 'Channels'
%       (names, default all) in 'Window' [from to] s (required):
%       'Measure' 'mean' (mean amplitude, default) or 'peak' (largest
%       value of 'Polarity' 'positive' (default) or 'negative', with its
%       latency). r: struct array condition, value (uV), latency (s; NaN
%       for mean), atEdge (the peak lies on the window's edge, so it may
%       not be a real peak), n (trials).
%   T   = EEGAnalysis.measureTable(eegs, names, Name, Value)
%       Rows participant x condition for a list of EEG structs (one per
%       participant; names = participant names): the options of
%       conditionERPs and measure. Columns Participant, Condition,
%       Value, Latency, Trials, AtEdge (a table).
%   s   = EEGAnalysis.describeMeasure(opts)
%       The measure in one plain sentence (for the window and methods text).
%   idx = EEGAnalysis.channelIndex(labels, names)
%       Positions of channel names (any case); error listing the unknown ones.
%
% Errors: NeuroAnalyzer:eeg:notEpoched, NeuroAnalyzer:eeg:unknownChannel,
% NeuroAnalyzer:eeg:unknownCondition, NeuroAnalyzer:eeg:badWindow,
% NeuroAnalyzer:eeg:badOption, NeuroAnalyzer:eeg:mismatch.
% =========================================================================

classdef EEGAnalysis
    methods(Static)

        %% epoch - Continuous recording -> trials around its events
        function ep = epoch(eeg, varargin)
            o = EEGSource.options(struct('Window', [-0.2 0.8], 'Events', {{}}), varargin);
            if eeg.isEpoched
                error('NeuroAnalyzer:eeg:badOption', 'The data are already cut into trials.');
            end
            if isempty(eeg.events)
                error('NeuroAnalyzer:eeg:notEpoched', ['The recording has no events, so it cannot ' ...
                    'be cut into trials.']);
            end
            w = o.Window;
            if numel(w) ~= 2 || w(2) <= w(1)
                error('NeuroAnalyzer:eeg:badWindow', 'The trial window must be [from to] with from < to (s).');
            end
            ev = eeg.events;
            types = {ev.type};
            use = true(1, numel(ev));
            if ~isempty(o.Events)
                want = EEGSource.cellRow(o.Events);
                use = ismember(types, want);
                if ~any(use)
                    error('NeuroAnalyzer:eeg:unknownCondition', 'No events of type %s. Types in the recording: %s.', ...
                        EEGSource.listText(want), EEGSource.listText(EEGSource.stableUnique(types)));
                end
            end
            fs = eeg.fs;
            i0 = round(w(1) * fs);
            i1 = round(w(2) * fs);
            rel = i0:i1;
            nS = size(eeg.data, 2);
            idx = find(use);
            keep = false(size(idx));
            starts = zeros(size(idx));
            for k = 1:numel(idx)
                c = round((ev(idx(k)).latency - eeg.times(1)) * fs) + 1;   % sample of the event
                starts(k) = c;
                keep(k) = c + i0 >= 1 && c + i1 <= nS;
            end
            idx = idx(keep);
            starts = starts(keep);
            if isempty(idx)
                error('NeuroAnalyzer:eeg:badWindow', 'Every event is too close to the start or end for this window.');
            end
            data = zeros(size(eeg.data, 1), numel(rel), numel(idx), 'single');
            for k = 1:numel(idx)
                data(:, :, k) = eeg.data(:, starts(k) + rel);
            end
            cond = types(idx);
            notes = eeg.notes;
            skipped = sum(use) - numel(idx);
            if skipped > 0
                verb = 'event was';
                if skipped > 1, verb = 'events were'; end
                notes{end + 1} = sprintf(['%d %s too close to the start or end of the recording ' ...
                    'for this window and left out.'], skipped, verb);
            end
            hist = [eeg.history, {sprintf('Cut into %d trials from %g to %g s around the events %s (NeuroAnalyzer).', ...
                numel(idx), rel(1) / fs, rel(end) / fs, EEGSource.listText(EEGSource.stableUnique(cond)))}];
            ep = EEGSource.make(data, fs, 'Times', rel / fs, 'Labels', eeg.labels, 'Chanlocs', ...
                eeg.chanlocs, 'CoordSystem', eeg.coordSystem, 'Conditions', cond, 'Reference', ...
                eeg.reference, 'History', hist, 'Notes', notes, 'Unit', 'uV', 'IsEpoched', true, ...
                'Source', eeg.source, 'Format', eeg.format, 'File', eeg.file);
            % make() keeps positions only through Chanlocs fields x/y/z/theta/radius (same struct shape)
        end

        %% conditionERPs - Mean and SEM of the trials of each condition
        function erp = conditionERPs(eeg, varargin)
            o = EEGSource.options(struct('Conditions', {{}}, 'Baseline', []), varargin);
            if ~eeg.isEpoched
                error('NeuroAnalyzer:eeg:notEpoched', ['The data are one continuous recording. Cut ' ...
                    'them into trials around the events first.']);
            end
            conds = EEGSource.cellRow(o.Conditions);
            if isempty(conds), conds = eeg.conditions; end
            bad = conds(~ismember(conds, eeg.conditions));
            if ~isempty(bad)
                error('NeuroAnalyzer:eeg:unknownCondition', 'Unknown %s %s. Conditions in the data: %s.', ...
                    EEGSource.plural(numel(bad), 'condition'), EEGSource.listText(bad), EEGSource.listText(eeg.conditions));
            end
            x = double(eeg.data);
            t = eeg.times;
            b = o.Baseline;
            if ~isempty(b)
                wb = EEGAnalysis.windowMask(t, b, 'baseline');
                x = x - mean(x(:, wb, :), 2);
            end
            [nCh, nS, ~] = size(x);
            C = numel(conds);
            erp = struct('conditions', {conds}, 'times', t, 'labels', {eeg.labels}, 'fs', eeg.fs, ...
                'baseline', b, 'mean', zeros(nCh, nS, C), 'sem', zeros(nCh, nS, C), 'n', zeros(1, C));
            for c = 1:C
                sel = strcmp(eeg.trials.condition, conds{c});
                n = sum(sel);
                erp.n(c) = n;
                erp.mean(:, :, c) = mean(x(:, :, sel), 3);
                if n > 1
                    erp.sem(:, :, c) = std(x(:, :, sel), 0, 3) / sqrt(n);
                else
                    erp.sem(:, :, c) = NaN;
                end
            end
        end

        %% grandAverage - Mean of the participants' ERPs (each participant once)
        function ga = grandAverage(erps)
            if isstruct(erps), erps = num2cell(erps); end
            if isempty(erps)
                error('NeuroAnalyzer:eeg:badOption', 'No ERPs to average.');
            end
            ref = erps{1};
            ga = ref;
            ga.trials = ref.n;
            ga.notes = {};
            if numel(erps) == 1, return; end
            for p = 2:numel(erps)
                e = erps{p};
                if numel(e.labels) ~= numel(ref.labels) || ~all(strcmpi(e.labels, ref.labels))
                    error('NeuroAnalyzer:eeg:mismatch', ['Participant %d has other channels than participant 1 ' ...
                        '(the channel names and their order must be the same to average them).'], p);
                end
                if numel(e.times) ~= numel(ref.times) || max(abs(e.times - ref.times)) > 1e-6
                    error('NeuroAnalyzer:eeg:mismatch', ['Participant %d has other trial times than participant 1 ' ...
                        '(%g to %g s at %g Hz instead of %g to %g s at %g Hz).'], p, e.times(1), e.times(end), ...
                        e.fs, ref.times(1), ref.times(end), ref.fs);
                end
            end
            conds = ref.conditions;
            for p = 2:numel(erps)
                conds = conds(ismember(conds, erps{p}.conditions));
            end
            if isempty(conds)
                error('NeuroAnalyzer:eeg:unknownCondition', 'The participants have no condition in common.');
            end
            every = cellfun(@(e) e.conditions, erps, 'UniformOutput', false);
            every = [every{:}];
            left = EEGSource.stableUnique(every(~ismember(every, conds)));
            P = numel(erps);
            C = numel(conds);
            [nCh, nS, ~] = size(ref.mean);
            X = zeros(nCh, nS, C, P);
            T = zeros(P, C);
            for p = 1:P
                [~, j] = ismember(conds, erps{p}.conditions);
                X(:, :, :, p) = erps{p}.mean(:, :, j);
                T(p, :) = erps{p}.n(j);
            end
            ga.conditions = conds;
            ga.mean = mean(X, 4);
            ga.sem = std(X, 0, 4) / sqrt(P);
            ga.n = repmat(P, 1, C);
            ga.trials = sum(T, 1);
            if ~isempty(left)
                ga.notes = {sprintf('Left out of the grand average: %s (not recorded in every participant).', ...
                    EEGSource.listText(left))};
            end
        end

        %% difference - condA minus condB
        function d = difference(erp, a, b)
            ia = find(strcmp(erp.conditions, a), 1);
            ib = find(strcmp(erp.conditions, b), 1);
            if isempty(ia) || isempty(ib)
                error('NeuroAnalyzer:eeg:unknownCondition', 'Choose two of the conditions %s.', ...
                    EEGSource.listText(erp.conditions));
            end
            d = struct('label', sprintf('%s minus %s', a, b), 'mean', erp.mean(:, :, ia) - erp.mean(:, :, ib), ...
                'times', erp.times, 'labels', {erp.labels});
        end

        %% measure - Mean or peak amplitude per condition in a window
        function r = measure(erp, varargin)
            o = EEGSource.options(struct('Channels', {{}}, 'Window', [], 'Measure', 'mean', ...
                'Polarity', 'positive'), varargin);
            if isempty(o.Window)
                error('NeuroAnalyzer:eeg:badWindow', 'Say the time window to measure in, [from to] in s.');
            end
            ch = 1:numel(erp.labels);
            if ~isempty(o.Channels), ch = EEGAnalysis.channelIndex(erp.labels, o.Channels); end
            w = EEGAnalysis.windowMask(erp.times, o.Window, 'measurement');
            tw = erp.times(w);
            kind = lower(o.Measure);
            if ~any(strcmp(kind, {'mean', 'peak'}))
                error('NeuroAnalyzer:eeg:badOption', 'Unknown measure ''%s'' (mean or peak).', o.Measure);
            end
            pol = lower(o.Polarity);
            if ~any(strcmp(pol, {'positive', 'negative'}))
                error('NeuroAnalyzer:eeg:badOption', 'Unknown polarity ''%s'' (positive or negative).', o.Polarity);
            end
            C = numel(erp.conditions);
            r = struct('condition', erp.conditions, 'value', NaN, 'latency', NaN, 'atEdge', false, ...
                'n', num2cell(erp.n));
            for c = 1:C
                y = mean(erp.mean(ch, w, c), 1);
                if strcmp(kind, 'mean')
                    r(c).value = mean(y);
                else
                    if strcmp(pol, 'positive'), [v, i] = max(y); else, [v, i] = min(y); end
                    r(c).value = v;
                    r(c).latency = tw(i);
                    r(c).atEdge = numel(y) > 1 && (i == 1 || i == numel(y));
                end
            end
        end

        %% measureTable - Participant x condition rows for several participants
        function T = measureTable(eegs, names, varargin)
            [erpOpts, measOpts] = EEGAnalysis.splitOptions(varargin);
            if isstruct(eegs), eegs = num2cell(eegs); end
            P = {};
            Cn = {};
            V = [];
            L = [];
            N = [];
            E = false(0, 1);
            for p = 1:numel(eegs)
                erp = EEGAnalysis.conditionERPs(eegs{p}, erpOpts{:});
                r = EEGAnalysis.measure(erp, measOpts{:});
                for c = 1:numel(r)
                    P{end + 1, 1} = names{p}; %#ok<AGROW>
                    Cn{end + 1, 1} = r(c).condition; %#ok<AGROW>
                    V(end + 1, 1) = r(c).value; %#ok<AGROW>
                    L(end + 1, 1) = r(c).latency; %#ok<AGROW>
                    N(end + 1, 1) = r(c).n; %#ok<AGROW>
                    E(end + 1, 1) = r(c).atEdge; %#ok<AGROW>
                end
            end
            T = table(P, Cn, V, L, N, E, 'VariableNames', ...
                {'Participant', 'Condition', 'Value', 'Latency', 'Trials', 'AtEdge'});
        end

        %% describeMeasure - One plain sentence for a measure's settings
        function s = describeMeasure(o)
            w = o.Window * 1000;
            if isfield(o, 'Channels') && ~isempty(o.Channels)
                chans = EEGSource.cellRow(o.Channels);
                where = sprintf('averaged over %s', EEGSource.listText(chans));
                if numel(chans) == 1, where = sprintf('at %s', chans{1}); end
            else
                where = 'averaged over all channels';
            end
            if strcmpi(o.Measure, 'peak')
                s = sprintf('Largest %s value (peak amplitude and its latency) from %g to %g ms, %s.', ...
                    lower(o.Polarity), w(1), w(2), where);
            else
                s = sprintf('Mean amplitude from %g to %g ms, %s.', w(1), w(2), where);
            end
        end

        %% channelIndex - Positions of channel names (any case)
        function idx = channelIndex(labels, names)
            names = EEGSource.cellRow(names);
            idx = zeros(1, numel(names));
            for k = 1:numel(names)
                i = find(strcmpi(labels, names{k}), 1);
                if isempty(i)
                    unknown = names(~ismember(lower(names), lower(labels)));
                    error('NeuroAnalyzer:eeg:unknownChannel', 'Unknown %s %s.', ...
                        EEGSource.plural(numel(unknown), 'channel'), EEGSource.listText(unknown));
                end
                idx(k) = i;
            end
        end
    end

    methods(Static, Hidden)

        %% windowMask - Samples inside [from to]; plain error when there are none
        function w = windowMask(t, win, what)
            if numel(win) ~= 2 || win(2) < win(1)
                error('NeuroAnalyzer:eeg:badWindow', 'The %s window must be [from to] with from <= to (s).', what);
            end
            tol = 1e-9;
            w = t >= win(1) - tol & t <= win(2) + tol;
            if ~any(w)
                error('NeuroAnalyzer:eeg:badWindow', ['The %s window %g to %g s is outside the data ' ...
                    '(%g to %g s).'], what, win(1), win(2), t(1), t(end));
            end
        end

        %% splitOptions - measureTable options into conditionERPs / measure options
        function [a, b] = splitOptions(args)
            a = {};
            b = {};
            for k = 1:2:numel(args)
                if any(strcmpi(args{k}, {'Conditions', 'Baseline'}))
                    a = [a, args(k:k + 1)]; %#ok<AGROW>
                else
                    b = [b, args(k:k + 1)]; %#ok<AGROW>
                end
            end
        end
    end
end
