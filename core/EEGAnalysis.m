%% EEGAnalysis.m
% =========================================================================
% EEG ANALYSIS - HEADLESS CLEANING, ERPs PER CONDITION AND AMPLITUDE MEASURES
% =========================================================================
% The computations behind EEGAnalysisApp, without any UI, so scripts get
% exactly the same numbers as the window. Works on the EEG struct of
% core/io/EEGSource.m (channels x samples x trials, microvolts).
% Toolbox-free (base MATLAB).
%
% Every step adds a plain sentence to eeg.history. Bad channels (eeg.bad)
% are left out of the average reference, the trial rejection, the ERPs
% (NaN) and the measures.
%
%   [eeg, info] = EEGAnalysis.filter(eeg, Name, Value)
%       Zero-phase FIR filters designed and applied as in MNE-Python
%       (raw.filter / notch_filter, 'firwin', Hamming window; the same
%       design as EEGLAB pop_eegfiltnew): 'HighPass' Hz, 'LowPass' Hz (one
%       band-pass filter when both are given), 'Notch' Hz list (stop bands
%       freq / 200 Hz wide, 0.5 Hz transitions). Transition widths 'auto':
%       min(max(0.25 f, 2), f) below and min(max(0.25 f, 2), fs/2 - f)
%       above; length round(3.3 fs / narrowest transition), made odd.
%       Trials are filtered one by one. info.band / info.notch: the
%       designs (filterDesign / notchDesign).
%   d   = EEGAnalysis.filterDesign(fs, 'HighPass', Hz, 'LowPass', Hz)
%   d   = EEGAnalysis.notchDesign(fs, freqs)
%       kind, edges, transitions, -6 dB cutoffs, length, order and the
%       taps d.h. s = EEGAnalysis.describeFilter(d): one sentence.
%   eeg = EEGAnalysis.markBad(eeg, names)   bad channels (replaces the list)
%   bad = EEGAnalysis.badChannels(eeg)      logical row (all false without eeg.bad)
%   [names, info] = EEGAnalysis.suggestBadChannels(eeg)
%       Flat or very noisy channels (info.rule says how); only suggests.
%   eeg = EEGAnalysis.rereference(eeg, ref)
%       ref 'average' (mean of the good channels subtracted from every
%       good channel) or channel names (their mean, e.g. {'TP9', 'TP10'}
%       for linked mastoids; a single reference channel becomes 0). Bad
%       channels stay as recorded, as in MNE-Python.
%   ep  = EEGAnalysis.epoch(eeg, Name, Value)
%       Cuts a continuous recording into trials around its events.
%       'Window' [from to] in s around each event (default [-0.2 0.8]),
%       'Events' event types to use (default: all), 'Rename' {type, name;
%       ...}: condition names for event types (those events are used too).
%       Types match ignoring case and repeated spaces ('S 1' = 'S  1').
%       The condition of each trial is the (renamed) event type. Events too
%       close to either end are skipped, and trials across a gap (EEGLAB
%       'boundary' events) left out (ep.notes says how many).
%   [ep, info] = EEGAnalysis.rejectTrials(ep, Name, Value)
%       Leaves out trials whose 'PeakToPeak' (max - min) or 'Absolute'
%       amplitude (after subtracting the mean of 'Baseline' [from to] s,
%       when given) exceeds the threshold (uV) on any good channel within
%       'Window' [from to] s (default: the whole trial). info: rejected,
%       total, kept, conditions, before, after (trials per condition),
%       channels / channelCounts (the channels that caused rejections, most
%       first), sentence.
%   erp = EEGAnalysis.conditionERPs(eeg, Name, Value)
%       Average of the trials of each condition. 'Conditions' (default
%       eeg.conditions), 'Baseline' [from to] in s: the mean of that window
%       is subtracted from each channel of each trial first (default []:
%       none, the data are used as they are).
%       erp.mean / erp.sem: channels x time x conditions (uV; NaN for bad
%       channels); erp.n: trials per condition; erp.conditions, erp.times,
%       erp.labels, erp.fs, erp.baseline, erp.bad.
%   ga  = EEGAnalysis.grandAverage(erps)
%       Grand average of several participants' ERPs (a cell of
%       conditionERPs results with the same channels and times): the mean
%       of the participant averages, so every participant counts once.
%       ga.sem is the SEM across participants; ga.n the number of
%       participants per condition, ga.trials the trials in total. Only
%       the conditions every participant has are kept (ga.notes says which
%       were left out). A channel marked bad in a participant is averaged
%       over the others (ga.notes says so). One participant: its ERP as it is.
%   d   = EEGAnalysis.difference(erp, condA, condB)
%       Difference wave condA minus condB: d.mean (channels x time),
%       d.label ('Target minus Standard'), d.times, d.labels.
%   v   = EEGAnalysis.windowMean(erp, window, condA, condB)
%       The mean voltage of every channel (channels x 1, uV; NaN for bad
%       channels) of condition condA in window [from to] s, or of the
%       difference condA minus condB (for scalp maps, core/ScalpMap.m). A
%       window between two samples (e.g. [t t]) takes the nearest sample.
%   r   = EEGAnalysis.measure(erp, Name, Value)
%       One number per condition from the ERP averaged over 'Channels'
%       (names, default all; bad channels left out, NaN when none is left)
%       in 'Window' [from to] s (required):
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
% NeuroAnalyzer:eeg:badOption, NeuroAnalyzer:eeg:mismatch,
% NeuroAnalyzer:eeg:allRejected.
% =========================================================================

classdef EEGAnalysis
    methods(Static)

        %% epoch - Continuous recording -> trials around its events
        function ep = epoch(eeg, varargin)
            o = EEGSource.options(struct('Window', [-0.2 0.8], 'Events', {{}}, 'Rename', {cell(0, 2)}), varargin);
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
            keys = EEGAnalysis.eventKey(types);
            isGap = strcmp(keys, 'boundary');              % EEGLAB marks removed data and joins with 'boundary'
            ren = o.Rename;
            if isempty(ren), ren = cell(0, 2); end
            if size(ren, 2) ~= 2
                error('NeuroAnalyzer:eeg:badOption', 'Rename must be a list of {event type, condition name} pairs.');
            end
            want = [EEGSource.cellRow(o.Events), ren(:, 1)'];
            use = ~isGap;
            if ~isempty(want)
                use = ismember(keys, EEGAnalysis.eventKey(want)) & ~isGap;
                if ~any(use)
                    error('NeuroAnalyzer:eeg:unknownCondition', 'No events of type %s. Types in the recording: %s.', ...
                        EEGSource.listText(want), EEGSource.listText(EEGSource.stableUnique(types(~isGap))));
                end
            end
            [hit, j] = ismember(keys, EEGAnalysis.eventKey(ren(:, 1)'));
            newName = types;
            newName(hit) = EEGSource.cellRow(ren(j(hit), 2)');
            fs = eeg.fs;
            i0 = round(w(1) * fs);
            i1 = round(w(2) * fs);
            rel = i0:i1;
            nS = size(eeg.data, 2);
            idx = find(use);
            keep = false(size(idx));
            starts = zeros(size(idx));
            gapAt = round(([ev(isGap).latency] - eeg.times(1)) * fs) + 1;
            crosses = false(size(idx));
            for k = 1:numel(idx)
                c = round((ev(idx(k)).latency - eeg.times(1)) * fs) + 1;   % sample of the event
                starts(k) = c;
                crosses(k) = any(gapAt > c + i0 & gapAt <= c + i1);
                keep(k) = c + i0 >= 1 && c + i1 <= nS && ~crosses(k);
            end
            nGap = sum(crosses);
            idx = idx(keep);
            starts = starts(keep);
            if isempty(idx)
                error('NeuroAnalyzer:eeg:badWindow', 'Every event is too close to the start or end for this window.');
            end
            data = zeros(size(eeg.data, 1), numel(rel), numel(idx), 'single');
            for k = 1:numel(idx)
                data(:, :, k) = eeg.data(:, starts(k) + rel);
            end
            cond = newName(idx);
            notes = eeg.notes;
            if nGap > 0
                notes{end + 1} = sprintf(['%d %s across a gap in the recording (an EEGLAB ''boundary'' ' ...
                    'event) and left out.'], nGap, EEGSource.plural(nGap, 'trial'));
            end
            skipped = sum(use) - numel(idx) - nGap;
            if skipped > 0
                verb = 'event was';
                if skipped > 1, verb = 'events were'; end
                notes{end + 1} = sprintf(['%d %s too close to the start or end of the recording ' ...
                    'for this window and left out.'], skipped, verb);
            end
            named = EEGSource.stableUnique(types(idx));
            for k = 1:numel(named)
                nk = newName{find(strcmp(types, named{k}), 1)};
                if ~strcmp(nk, named{k}), named{k} = sprintf('%s (%s)', strtrim(named{k}), nk); end
            end
            hist = [eeg.history, {sprintf('Cut into %d trials from %g to %g s around the events %s (Neuronal Data Analyzer Lab).', ...
                numel(idx), rel(1) / fs, rel(end) / fs, EEGSource.listText(named))}];
            ep = EEGSource.make(data, fs, 'Times', rel / fs, 'Labels', eeg.labels, 'Chanlocs', ...
                eeg.chanlocs, 'CoordSystem', eeg.coordSystem, 'Conditions', cond, 'Reference', ...
                eeg.reference, 'History', hist, 'Notes', notes, 'Unit', 'uV', 'IsEpoched', true, ...
                'Source', eeg.source, 'Format', eeg.format, 'File', eeg.file, 'Bad', EEGAnalysis.badChannels(eeg));
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
            unknown = conds(~ismember(conds, eeg.conditions));
            if ~isempty(unknown)
                error('NeuroAnalyzer:eeg:unknownCondition', 'Unknown %s %s. Conditions in the data: %s.', ...
                    EEGSource.plural(numel(unknown), 'condition'), EEGSource.listText(unknown), EEGSource.listText(eeg.conditions));
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
            bad = EEGAnalysis.badChannels(eeg);
            erp = struct('conditions', {conds}, 'times', t, 'labels', {eeg.labels}, 'fs', eeg.fs, ...
                'baseline', b, 'mean', zeros(nCh, nS, C), 'sem', zeros(nCh, nS, C), 'n', zeros(1, C), 'bad', bad);
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
            erp.mean(bad, :, :) = NaN;                         % bad channels have no ERP
            erp.sem(bad, :, :) = NaN;
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
            ga.bad = all(isnan(ref.mean(:, :)), 2)';
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
            ok = ~isnan(X);                                    % bad channels are NaN in their participant
            nn = sum(ok, 4);
            X(~ok) = 0;
            ga.conditions = conds;
            ga.mean = sum(X, 4) ./ nn;
            ga.sem = sqrt(sum(((X - ga.mean) .* ok) .^ 2, 4) ./ (nn - 1)) ./ sqrt(nn);
            ga.sem(nn < 2) = NaN;
            ga.n = repmat(P, 1, C);
            ga.trials = sum(T, 1);
            nBad = P - min(reshape(nn, nCh, []), [], 2)';
            ga.bad = nBad == P;
            if ~isempty(left)
                ga.notes = {sprintf('Left out of the grand average: %s (not recorded in every participant).', ...
                    EEGSource.listText(left))};
            end
            part = find(nBad > 0 & nBad < P);
            if ~isempty(part)
                txt = arrayfun(@(c) sprintf('%s in %d', ref.labels{c}, nBad(c)), part, 'UniformOutput', false);
                ga.notes{end + 1} = sprintf(['Marked bad in some participants (their average uses the ' ...
                    'others): %s of %d.'], EEGSource.listText(txt), P);
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

        %% windowMean - Mean of every channel in a window (scalp maps)
        function v = windowMean(erp, win, a, b)
            if nargin < 4, b = ''; end
            ia = find(strcmp(erp.conditions, a), 1);
            ib = [];
            if ~isempty(b), ib = find(strcmp(erp.conditions, b), 1); end
            if isempty(ia) || (~isempty(b) && isempty(ib))
                error('NeuroAnalyzer:eeg:unknownCondition', 'Unknown condition: choose from %s.', ...
                    EEGSource.listText(erp.conditions));
            end
            t = erp.times;
            tol = 1e-9;
            ok = isnumeric(win) && numel(win) == 2 && win(1) <= win(2);
            w = false(size(t));
            if ok, w = t >= win(1) - tol & t <= win(2) + tol; end
            if ~any(w) && ok && win(1) >= t(1) - tol && win(2) <= t(end) + tol
                [~, i] = min(abs(t - mean(win)));      % between two samples: the nearest one
                w = false(size(t));
                w(i) = true;
            elseif ~any(w)
                w = EEGAnalysis.windowMask(t, win, 'map');
            end
            Y = erp.mean(:, w, ia);
            if ~isempty(ib), Y = Y - erp.mean(:, w, ib); end
            v = mean(Y, 2);
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
                Y = erp.mean(ch, w, c);
                Y = Y(~all(isnan(Y), 2), :);                     % bad channels are left out
                if isempty(Y), continue; end
                y = mean(Y, 1);
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

        %% filter - Zero-phase FIR high-pass / low-pass / band-pass and notch
        function [eeg, info] = filter(eeg, varargin)
            o = EEGSource.options(struct('HighPass', [], 'LowPass', [], 'Notch', []), varargin);
            info = struct('band', [], 'notch', []);
            hist = {};
            if ~isempty(o.HighPass) || ~isempty(o.LowPass)
                info.band = EEGAnalysis.filterDesign(eeg.fs, 'HighPass', o.HighPass, 'LowPass', o.LowPass);
                eeg.data = EEGAnalysis.applyFIR(eeg.data, info.band.h);
                hist{end + 1} = EEGAnalysis.describeFilter(info.band);
            end
            if ~isempty(o.Notch)
                info.notch = EEGAnalysis.notchDesign(eeg.fs, o.Notch);
                eeg.data = EEGAnalysis.applyFIR(eeg.data, info.notch.h);
                hist{end + 1} = EEGAnalysis.describeFilter(info.notch);
            end
            if isempty(hist), return; end
            nS = size(eeg.data, 2);
            longest = max([0, arrayfun(@(d) d.length, [info.band, info.notch])]);
            if longest > nS
                what = 'recording';
                if eeg.isEpoched, what = 'trial'; end
                eeg.notes{end + 1} = sprintf(['The filter (%d samples, %.3g s) is longer than each %s ' ...
                    '(%d samples), so its edges are mostly padding; filter the continuous recording ' ...
                    'before cutting it into trials.'], longest, longest / eeg.fs, what, nS);
            end
            eeg.history = [eeg.history, hist];
        end

        %% filterDesign - The FIR filter for a high-pass, low-pass or band-pass
        function d = filterDesign(fs, varargin)
            o = EEGSource.options(struct('HighPass', [], 'LowPass', []), varargin);
            nyq = fs / 2;
            hp = o.HighPass;
            lp = o.LowPass;
            EEGAnalysis.checkFrequency(hp, nyq, 'high-pass');
            EEGAnalysis.checkFrequency(lp, nyq, 'low-pass');
            if isempty(hp) && isempty(lp)
                error('NeuroAnalyzer:eeg:badOption', 'Say a high-pass or a low-pass frequency (Hz).');
            end
            if ~isempty(hp) && ~isempty(lp) && hp >= lp
                error('NeuroAnalyzer:eeg:badOption', ['The high-pass frequency (%g Hz) must be below ' ...
                    'the low-pass frequency (%g Hz).'], hp, lp);
            end
            lt = [];
            ht = [];
            f = [0 nyq];
            g = [1 1];
            if ~isempty(hp)
                lt = min(max(0.25 * hp, 2), hp);
                f = [hp - lt, hp, nyq];
                g = [0 1 1];
                if hp - lt ~= 0, f = [0 f]; g = [0 g]; end
            end
            if ~isempty(lp)
                ht = min(max(0.25 * lp, 2), nyq - lp);
                if isempty(hp)
                    f = [0 lp lp + ht];
                    g = [1 1 0];
                else
                    f = [f(1:end - 1), lp, lp + ht];
                    g = [g(1:end - 1), 1, 0];
                end
                if lp + ht ~= nyq, f = [f nyq]; g = [g 0]; end
            end
            N = EEGAnalysis.oddLength(3.3 * fs / min([lt, ht]));
            kind = 'band-pass';
            if isempty(lp), kind = 'high-pass'; elseif isempty(hp), kind = 'low-pass'; end
            d = struct('kind', kind, 'fs', fs, 'highPass', hp, 'lowPass', lp, 'highTransition', lt, ...
                'lowTransition', ht, 'highCutoff', hp - lt / 2, 'lowCutoff', lp + ht / 2, ...
                'notch', [], 'notchWidth', [], 'length', N, 'order', N - 1, ...
                'h', EEGAnalysis.firwinDesign(N, f, g, fs));
        end

        %% notchDesign - The FIR band-stop filter around each line-noise frequency
        function d = notchDesign(fs, freqs)
            freqs = sort(double(freqs(:)'));
            nyq = fs / 2;
            nw = freqs / 200;                  % stop band width (MNE-Python default)
            tb = 0.5;                          % transition on each side
            lows = freqs - nw / 2 - tb;        % passband edges
            highs = freqs + nw / 2 + tb;
            if isempty(freqs) || any(~isfinite(freqs)) || any(lows <= 0) || any(highs >= nyq)
                error('NeuroAnalyzer:eeg:badOption', ['The notch frequencies must lie between 1 Hz ' ...
                    'and just below half the sampling rate (%g Hz).'], nyq);
            end
            f = reshape([lows; lows + tb; highs - tb; highs], 1, []);
            g = repmat([1 0 0 1], 1, numel(freqs));
            if any(diff(f) < 0)
                error('NeuroAnalyzer:eeg:badOption', 'The notch frequencies are too close together.');
            end
            f = [0 f nyq];
            g = [1 g 1];
            N = EEGAnalysis.oddLength(3.3 * fs / tb);
            d = struct('kind', 'notch', 'fs', fs, 'highPass', [], 'lowPass', [], 'highTransition', tb, ...
                'lowTransition', tb, 'highCutoff', [], 'lowCutoff', [], 'notch', freqs, 'notchWidth', nw, ...
                'length', N, 'order', N - 1, 'h', EEGAnalysis.firwinDesign(N, f, g, fs));
        end

        %% describeFilter - One plain sentence for a filter design
        function s = describeFilter(d)
            tail = sprintf(['zero-phase FIR filter (Hamming-windowed sinc, %d taps, order %d, ' ...
                'as in MNE-Python and EEGLAB pop_eegfiltnew)'], d.length, d.order);
            switch d.kind
                case 'notch'
                    s = sprintf(['Notch filter at %s Hz (stop band %s Hz wide, transitions %g Hz): %s.'], ...
                        EEGAnalysis.numList(d.notch), EEGAnalysis.numList(d.notchWidth), d.highTransition, tail);
                case 'high-pass'
                    s = sprintf(['High-pass filter: passband edge %g Hz, transition %g Hz, -6 dB cutoff ' ...
                        '%g Hz; %s.'], d.highPass, d.highTransition, d.highCutoff, tail);
                case 'low-pass'
                    s = sprintf(['Low-pass filter: passband edge %g Hz, transition %g Hz, -6 dB cutoff ' ...
                        '%g Hz; %s.'], d.lowPass, d.lowTransition, d.lowCutoff, tail);
                otherwise
                    s = sprintf(['Band-pass filter %g-%g Hz: transitions %g and %g Hz, -6 dB cutoffs %g ' ...
                        'and %g Hz; %s.'], d.highPass, d.lowPass, d.highTransition, d.lowTransition, ...
                        d.highCutoff, d.lowCutoff, tail);
            end
        end

        %% markBad - Mark channels bad (replaces the earlier list)
        function eeg = markBad(eeg, names)
            names = EEGSource.cellRow(names);
            bad = false(1, numel(eeg.labels));
            if ~isempty(names), bad(EEGAnalysis.channelIndex(eeg.labels, names)) = true; end
            if isequal(bad, EEGAnalysis.badChannels(eeg)), eeg.bad = bad; return; end
            eeg.bad = bad;
            if any(bad)
                eeg.history{end + 1} = sprintf('Marked bad: %s (left out of the average reference, trial rejection, ERPs and measures).', ...
                    EEGSource.listText(eeg.labels(bad)));
            end
        end

        %% badChannels - Logical row of the bad channels (all false without eeg.bad)
        function bad = badChannels(eeg)
            n = numel(eeg.labels);
            bad = false(1, n);
            if isfield(eeg, 'bad') && numel(eeg.bad) == n, bad = logical(eeg.bad(:)'); end
        end

        %% suggestBadChannels - Flat or very noisy channels (only suggests)
        function [names, info] = suggestBadChannels(eeg)
            x = double(eeg.data);
            [nCh, nS, nTr] = size(x);
            if ~eeg.isEpoched
                seg = max(1, round(eeg.fs));
                nSeg = floor(nS / seg);
                if nSeg >= 1
                    x = reshape(x(:, 1:nSeg * seg), nCh, seg, nSeg);
                end
            end
            nSeg = size(x, 3);
            s = zeros(nCh, nSeg);
            for k = 1:nSeg
                s(:, k) = std(x(:, :, k), 0, 2);
            end
            spread = median(s, 2)';
            ls = log(max(spread, eps));
            m = median(ls);
            mad = 1.4826 * median(abs(ls - m));
            z = (ls - m) / max(mad, 0.1);
            flagged = z > 5 | z < -5 | spread < 0.5;
            names = eeg.labels(flagged);
            info = struct('spread', spread, 'z', z, 'flagged', flagged, 'nTrials', nTr, 'rule', ...
                ['Suggested as bad: channels whose typical spread (the median over 1-s pieces, or over ' ...
                'trials, of the standard deviation) lies more than 5 robust z-scores (median and MAD of ' ...
                'the log spread across channels) from the other channels, or below 0.5 uV (flat).']);
        end

        %% rereference - Average, one channel or the mean of several channels
        function eeg = rereference(eeg, ref)
            bad = EEGAnalysis.badChannels(eeg);
            if ischar(ref) && strcmpi(ref, 'average')
                use = ~bad;
                if ~any(use)
                    error('NeuroAnalyzer:eeg:badOption', 'Every channel is marked bad, so there is no average reference.');
                end
                if any(bad)
                    words = sprintf('average of the %d good channels (%s marked bad and left out)', sum(use), ...
                        EEGSource.listText(eeg.labels(bad)));
                else
                    words = sprintf('average of all %d channels', sum(use));
                end
            else
                names = EEGSource.cellRow(ref);
                if isempty(names)
                    error('NeuroAnalyzer:eeg:badOption', 'Say the reference: ''average'' or channel names.');
                end
                idx = EEGAnalysis.channelIndex(eeg.labels, names);
                use = false(1, numel(eeg.labels));
                use(idx) = true;
                names = eeg.labels(idx);
                if any(bad(idx))
                    error('NeuroAnalyzer:eeg:badOption', 'The reference channel %s is marked bad.', ...
                        EEGSource.listText(eeg.labels(idx(bad(idx)))));
                end
                if numel(names) == 1
                    words = ['channel ' names{1}];
                else
                    words = sprintf('mean of %s', EEGSource.listText(names));
                    if all(ismember(lower(names), {'tp9', 'tp10'})) || all(ismember(lower(names), {'m1', 'm2'})) ...
                            || all(ismember(lower(names), {'a1', 'a2'}))
                        words = [words ' (linked mastoids)'];
                    end
                end
            end
            r = mean(double(eeg.data(use, :, :)), 1);
            eeg.data(~bad, :, :) = single(double(eeg.data(~bad, :, :)) - r);   % bad channels as recorded (as MNE-Python)
            eeg.history{end + 1} = sprintf('Re-referenced to the %s (was: %s).', words, eeg.reference);
            eeg.reference = words;
        end

        %% rejectTrials - Leave out trials whose amplitude is too large on a good channel
        function [ep, info] = rejectTrials(ep, varargin)
            o = EEGSource.options(struct('PeakToPeak', [], 'Absolute', [], 'Window', [], 'Baseline', []), varargin);
            if ~ep.isEpoched
                error('NeuroAnalyzer:eeg:notEpoched', 'Cut the recording into trials before rejecting trials.');
            end
            if isempty(o.PeakToPeak) && isempty(o.Absolute)
                error('NeuroAnalyzer:eeg:badOption', 'Say a peak-to-peak or an absolute threshold (uV).');
            end
            for v = {o.PeakToPeak, o.Absolute}
                if ~isempty(v{1}) && ~(isnumeric(v{1}) && isscalar(v{1}) && v{1} > 0)
                    error('NeuroAnalyzer:eeg:badOption', 'A threshold must be one positive number (uV).');
                end
            end
            good = find(~EEGAnalysis.badChannels(ep));
            if isempty(good)
                error('NeuroAnalyzer:eeg:badOption', 'Every channel is marked bad.');
            end
            t = ep.times;
            win = o.Window;
            if isempty(win), win = [t(1) t(end)]; end
            w = EEGAnalysis.windowMask(t, win, 'rejection');
            x = double(ep.data(good, :, :));
            nG = numel(good);
            nTr = size(x, 3);
            fail = false(nG, nTr);
            if ~isempty(o.PeakToPeak)
                pp = reshape(max(x(:, w, :), [], 2) - min(x(:, w, :), [], 2), nG, nTr);
                fail = fail | pp > o.PeakToPeak;
            end
            if ~isempty(o.Absolute)
                xb = x;
                if ~isempty(o.Baseline)
                    xb = x - mean(x(:, EEGAnalysis.windowMask(t, o.Baseline, 'baseline'), :), 2);
                end
                aa = reshape(max(abs(xb(:, w, :)), [], 2), nG, nTr);
                fail = fail | aa > o.Absolute;
            end
            rej = any(fail, 1);
            conds = ep.conditions;
            before = cellfun(@(c) sum(strcmp(ep.trials.condition, c)), conds);
            after = cellfun(@(c) sum(strcmp(ep.trials.condition(~rej), c)), conds);
            byCh = sum(fail, 2)';
            [cnt, order] = sort(byCh, 'descend');
            order = order(cnt > 0);
            info = struct('rejected', find(rej), 'total', nTr, 'kept', sum(~rej), 'conditions', {conds}, ...
                'before', before, 'after', after, 'channels', {ep.labels(good(order))}, ...
                'channelCounts', byCh(order), 'peakToPeak', o.PeakToPeak, 'absolute', o.Absolute, ...
                'window', win, 'baseline', o.Baseline, 'sentence', '');
            info.sentence = EEGAnalysis.describeRejection(info);
            if all(rej)
                error('NeuroAnalyzer:eeg:allRejected', ['Every trial exceeds the threshold (most often on %s). ' ...
                    'Mark noisy channels bad, filter the recording or raise the threshold.'], ...
                    EEGSource.listText(info.channels(1:min(3, end))));
            end
            ep.data = ep.data(:, :, ~rej);
            ep.trials.condition = ep.trials.condition(~rej);
            ep.conditions = EEGSource.stableUnique(ep.trials.condition);
            ep.history{end + 1} = info.sentence;
        end

        %% describeRejection - The rejection in one plain sentence
        function s = describeRejection(info)
            rules = {};
            if ~isempty(info.peakToPeak)
                rules{end + 1} = sprintf('a peak-to-peak amplitude above %g uV', info.peakToPeak);
            end
            if ~isempty(info.absolute)
                a = sprintf('an absolute amplitude above %g uV', info.absolute);
                if ~isempty(info.baseline)
                    a = sprintf('%s (after subtracting the mean from %g to %g ms)', a, info.baseline * 1000);
                end
                rules{end + 1} = a;
            end
            per = arrayfun(@(k) sprintf('%s %d of %d', info.conditions{k}, info.before(k) - info.after(k), ...
                info.before(k)), 1:numel(info.conditions), 'UniformOutput', false);
            s = sprintf(['Rejected %d of %d trials with %s on any good channel from %g to %g ms ' ...
                '(%s).'], info.total - info.kept, info.total, strjoin(rules, ' or '), info.window * 1000, ...
                EEGSource.listText(per));
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

        %% firwinDesign - Windowed-sinc FIR from band edges and gains (as MNE-Python _firwin_design)
        % f: band edges in Hz from 0 to fs/2, g: gain 0 or 1 at each edge. Each change of gain adds
        % or subtracts a Hamming-windowed sinc low-pass cut off in the middle of that transition,
        % as long as the transition needs (3.3 * fs / width taps), centred in the N taps.
        function h = firwinDesign(N, f, g, fs)
            h = zeros(1, N);
            if g(end) == 1, h((N + 1) / 2) = 1; end
            pf = f(end);
            pg = g(end);
            for k = numel(f) - 1:-1:1
                if g(k) ~= pg
                    M = EEGAnalysis.oddLength(3.3 * fs / (pf - f(k)));
                    if M > N
                        error('NeuroAnalyzer:eeg:badOption', 'The filter is too short for this transition.');
                    end
                    fc = (pf + f(k)) / 2 / fs;                  % cutoff in cycles per sample
                    m = (0:M - 1) - (M - 1) / 2;
                    x = 2 * fc * m;
                    s = ones(1, M);
                    nz = x ~= 0;
                    s(nz) = sin(pi * x(nz)) ./ (pi * x(nz));
                    win = ones(1, M);
                    if M > 1, win = 0.54 - 0.46 * cos(2 * pi * (0:M - 1) / (M - 1)); end
                    hk = 2 * fc * s .* win;
                    hk = hk / sum(hk);
                    off = (N - M) / 2;
                    if g(k) == 0
                        h(off + 1:N - off) = h(off + 1:N - off) - hk;
                    else
                        h(off + 1:N - off) = h(off + 1:N - off) + hk;
                    end
                end
                pg = g(k);
                pf = f(k);
            end
        end

        %% applyFIR - Zero-phase FIR along the samples of every channel and trial
        % Each channel is padded at both ends with its odd reflection (MNE-Python
        % 'reflect_limited', min(N, samples) - 1 samples), convolved by FFT and
        % shifted back by (N - 1) / 2.
        function y = applyFIR(x, h)
            [nCh, nS, nTr] = size(x);
            N = numel(h);
            e = min(N, nS) - 1;
            y = zeros(nCh, nS, nTr, 'single');
            L = nS + 2 * e + N - 1;
            nfft = 2 ^ nextpow2(L);
            H = fft(h(:)', nfft);
            for k = 1:nTr
                X = double(x(:, :, k));
                if e > 0
                    X = [2 * X(:, 1) - X(:, e + 1:-1:2), X, 2 * X(:, end) - X(:, end - 1:-1:end - e)];
                end
                Y = real(ifft(fft(X, nfft, 2) .* H, [], 2));
                y(:, :, k) = single(Y(:, e + (N - 1) / 2 + (1:nS)));
            end
        end

        %% oddLength - round(n), made odd by adding 1
        function n = oddLength(n)
            n = max(1, round(n));
            n = n + 1 - mod(n, 2);
        end

        %% checkFrequency - [] or one frequency between 0 and Nyquist
        function checkFrequency(f, nyq, what)
            if isempty(f), return; end
            if ~(isnumeric(f) && isscalar(f) && isfinite(f) && f > 0 && f < nyq)
                error('NeuroAnalyzer:eeg:badOption', ['The %s frequency must be one number between 0 ' ...
                    'and half the sampling rate (%g Hz).'], what, nyq);
            end
        end

        %% numList - [50 100] -> '50 and 100'
        function s = numList(x)
            s = EEGSource.listText(EEGSource.numText(x));
        end

        %% eventKey - Event type names to compare ignoring case and repeated spaces
        function k = eventKey(c)
            k = lower(regexprep(strtrim(EEGSource.cellRow(c)), '\s+', ' '));
        end

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
