%% EEGAnalysis.m
% =========================================================================
% EEG ANALYSIS - HEADLESS CLEANING, ERPs PER CONDITION AND AMPLITUDE MEASURES
% =========================================================================
% The computations behind EEGAnalysisApp, without any UI, so scripts get
% exactly the same numbers as the window. Works on the EEG struct of
% core/io/EEGSource.m (channels x samples x trials, microvolts).
% Toolbox-free (base MATLAB). The quality checks (checks, interpolatedChannels)
% also run in GNU Octave.
%
% Every step adds a plain sentence to eeg.history. Bad channels (eeg.bad)
% are left out of the average reference, the trial rejection, the ERPs
% (NaN) and the measures.
%
%   [eeg, info] = EEGAnalysis.filter(eeg, Name, Value)
%       Zero-phase FIR filters (Hamming-windowed sinc) following Widmann,
%       Schroger & Maess (2015), J Neurosci Methods 250:34-46: 'HighPass'
%       Hz, 'LowPass' Hz (both: the high-pass and the low-pass combined
%       into one band-pass filter), 'Notch' Hz list (each line frequency
%       removed +-0.5 Hz, 1 Hz transitions). Transition widths: min(max(
%       0.25 f, 2), f) below and min(max(0.25 f, 2), fs/2 - f) above;
%       order 3.3 fs / transition, rounded up to even; cutoff (-6 dB) in
%       the middle of the transition. Trials are filtered one by one.
%       info.band / info.notch: the designs (filterDesign / notchDesign).
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
%       channels are not re-referenced: their data stay as recorded.
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
%       Value_uV, Latency_ms (peak only), Trials, PeakAtEdge (a table;
%       the same columns as the window's .csv and Batch).
%   s   = EEGAnalysis.describeMeasure(opts)
%       The measure in one plain sentence (for the window and methods text).
%   tf  = EEGAnalysis.timeFrequency(eeg, Name, Value)
%       Time-frequency of the trials of each condition, from complex Morlet
%       wavelets (TimeFrequency.morletTF: unit energy, truncated at +/- 3
%       SDs; each trial's mean removed first). 'Channels' (names, default
%       all; bad channels left out; several channels: their power and ITPC
%       are averaged), 'Frequencies' (Hz, default 4:40), 'Cycles' (one
%       number, or one per frequency; default 3), 'Baseline' [from to] s
%       (default from the trial start to 0), 'Bands' (nBands x 2 Hz,
%       default [8 13]) with 'BandNames' (default {'Alpha'}), 'Conditions'.
%       A value is kept only where the whole wavelet lies inside the trial
%       (tf.valid, freq x time; TimeFrequency.supportSamples), so it is the
%       same as from a longer recording; elsewhere it is NaN.
%         power  freq x time x condition: mean over trials (uV^2)
%         ersp   10*log10(power / B), B = the condition's mean power in the
%                baseline (its samples where the wavelet fits; NaN at a
%                frequency without such a sample, tf.baselineSamples = 0)
%         itpc   | mean over trials of coef / |coef| | (0..1); about
%                1/sqrt(trials) by chance
%         bandPct, bandSem  bands x time x condition: band power (the mean
%                power over the computed frequencies inside the band, valid
%                where all of them are; tf.bandValid) of each trial as %
%                change from the condition's mean baseline band power; mean
%                and SEM across trials
%       tf also holds conditions, times, fs, freqs, cycles, baseline,
%       channels (used), left (chosen but bad), n (trials per condition),
%       bands, bandNames.
%   ga  = EEGAnalysis.grandTimeFrequency(tfs)
%       Mean of several participants' timeFrequency results (same
%       frequencies, times, cycles, baseline and bands): ersp (dB), itpc,
%       power and bandPct averaged, every participant once; bandSem is the
%       SEM across participants. ga.n participants and ga.trials trials per
%       condition; conditions not in every participant are left out
%       (ga.notes). One participant: its result as it is.
%   s   = EEGAnalysis.describeTimeFrequency(tf)
%       The settings in one plain sentence, then what the trial length left
%       blank (lowest frequency with values, with a baseline).
%   [events, rename, problems] = EEGAnalysis.parseEvents(txt)
%       'S 1 = Standard, S 2 = Target, boundary' -> the event types to use
%       ({'boundary'}), the renames ({'S 1', 'Standard'; 'S 2', 'Target'})
%       and the parts that could not be read (e.g. 'a = b = c').
%   names = EEGAnalysis.mastoidChannels(labels)
%       The linked-mastoid pair of a recording: TP9 / TP10, else M1 / M2,
%       else A1 / A2 (any case); plain error when it has none of them.
%   f   = EEGAnalysis.notchFrequencies(notch, fs, lowPass)
%       The line frequency notch (Hz, 0 = off: []) and its harmonics below
%       fs/2 - 1.5 Hz and below the low-pass (when on); at least notch itself.
%   idx = EEGAnalysis.channelIndex(labels, names)
%       Positions of channel names (any case); error listing the unknown ones.
%   Q   = EEGAnalysis.checks(eegs, names, o)
%       Quality checks of the trials analysed (QualityChecks rows; one row
%       per check over every participant: the worst sets the level and the
%       text names the participants, worst first, up to 3). eegs: a cell of
%       EEG structs cut into trials (one per participant), names: their
%       names. o (struct, every field optional): rejections (the
%       rejectTrials info of each participant, a struct array or a cell
%       with [] where none ran; [] = no rejection here), measure ('mean' |
%       'peak' | '' not chosen; 'Mean amplitude' / 'Peak amplitude' too),
%       channels (measured; {} = the ERP channels), erpChannels ({} = all).
%       Limits in EEGAnalysis.CheckLimits. Never changes a result and never
%       throws: a check that cannot run gives no row.
%         Trials per condition  the fewest trials left in a condition:
%                         Check below 20, Warning below 10
%         Rejection balance     share of each condition rejected here:
%                         Check when two conditions differ by more than 20
%                         percentage points (and the larger lost at least 3
%                         trials), Warning above 40; a note when the trials
%                         were rejected before loading (history)
%         Condition balance     the most / the fewest trials of a condition:
%                         more than 2 times is a Check with the peak
%                         amplitude, OK with the mean amplitude
%         Bad channels          eeg.bad: Check above 10% of the channels,
%                         Warning above 20%
%         Interpolated channels interpolated before loading (the history):
%                         Warning when every measured channel was
%                         interpolated, Check when some were (or the history
%                         does not say which), else OK
%   [names, info] = EEGAnalysis.interpolatedChannels(eeg)
%       Channels interpolated before loading, from the history lines of
%       EEGSource (EEGLAB pop_interp, FieldTrip ft_channelrepair) or of
%       this toolbox. info.unknown: a line says channels were interpolated
%       but not which; info.where: 'in EEGLAB' (the file's source), 'here'
%       or 'before loading'; info.lines: the history lines.
%
% Errors: NeuroAnalyzer:eeg:notEpoched, NeuroAnalyzer:eeg:unknownChannel,
% NeuroAnalyzer:eeg:unknownCondition, NeuroAnalyzer:eeg:badWindow,
% NeuroAnalyzer:eeg:badOption, NeuroAnalyzer:eeg:mismatch,
% NeuroAnalyzer:eeg:allRejected.
% =========================================================================

classdef EEGAnalysis
    properties(Constant)
        % Limits of the quality checks (EEGAnalysis.checks): trials; percentage
        % points of a condition rejected; times as many trials; % of the channels
        CheckLimits = struct('trialsCheck', 20, 'trialsWarning', 10, 'rejectionCheck', 20, ...
            'rejectionWarning', 40, 'rejectionMinTrials', 3, 'countRatio', 2, 'badCheck', 10, 'badWarning', 20)
    end

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
            T = table(P, Cn, V, L * 1000, N, E, 'VariableNames', ...
                {'Participant', 'Condition', 'Value_uV', 'Latency_ms', 'Trials', 'PeakAtEdge'});
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

        %% timeFrequency - Morlet power, ERSP, ITPC and band power per condition
        function tf = timeFrequency(eeg, varargin)
            o = EEGSource.options(struct('Channels', {{}}, 'Frequencies', 4:40, 'Cycles', 3, 'Baseline', [], ...
                'Bands', [8 13], 'BandNames', {{'Alpha'}}, 'Conditions', {{}}), varargin);
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
            t = eeg.times;
            fs = eeg.fs;
            nS = numel(t);
            % Frequencies (increasing) and the cycles of each
            freqs = double(o.Frequencies(:)');
            if isempty(freqs) || any(~isfinite(freqs)) || any(freqs <= 0) || any(freqs >= fs / 2)
                error('NeuroAnalyzer:eeg:badOption', ['The frequencies must lie above 0 Hz and below half the ' ...
                    'sampling rate (%g Hz).'], fs / 2);
            end
            cyc = double(o.Cycles(:)');
            if isscalar(cyc)
                freqs = unique(freqs);
                cyc = repmat(cyc, size(freqs));
            elseif numel(cyc) ~= numel(freqs) || any(diff(freqs) <= 0)
                error('NeuroAnalyzer:eeg:badOption', ['Give one number of cycles, or one per frequency ' ...
                    '(frequencies increasing).']);
            end
            if any(~(cyc > 0)) || any(~isfinite(cyc))
                error('NeuroAnalyzer:eeg:badOption', 'The number of wavelet cycles must be above 0.');
            end
            % Baseline window (default: from the start of the trial to the event)
            bw = double(o.Baseline);
            if isempty(bw)
                if t(1) >= 0
                    error('NeuroAnalyzer:eeg:badWindow', ['The trials start at or after the event (%g ms), so ' ...
                        'there is no time before it to compare with. Give a baseline window.'], t(1) * 1000);
                end
                bw = [t(1) min(0, t(end))];
            end
            wb = EEGAnalysis.windowMask(t, bw, 'baseline');
            % Bands: the computed frequencies inside each
            bands = double(o.Bands);
            if isempty(bands), bands = zeros(0, 2); end
            if size(bands, 2) ~= 2 || any(bands(:, 1) >= bands(:, 2))
                error('NeuroAnalyzer:eeg:badOption', 'Each band must be [low high] in Hz with low < high.');
            end
            nB = size(bands, 1);
            bandNames = EEGSource.cellRow(o.BandNames);
            if numel(bandNames) ~= nB
                bandNames = arrayfun(@(k) sprintf('%g-%g Hz', bands(k, :)), 1:nB, 'UniformOutput', false);
            end
            inBand = cell(1, nB);
            for b = 1:nB
                inBand{b} = find(freqs >= bands(b, 1) - 1e-9 & freqs <= bands(b, 2) + 1e-9);
                if isempty(inBand{b})
                    error('NeuroAnalyzer:eeg:badOption', ['No frequency from %g to %g Hz is computed (%s band): ' ...
                        'the frequencies run from %g to %g Hz.'], bands(b, 1), bands(b, 2), bandNames{b}, freqs(1), freqs(end));
                end
            end
            % Channels: the chosen ones (default all) without the bad ones
            bad = EEGAnalysis.badChannels(eeg);
            chans = EEGSource.cellRow(o.Channels);
            if isempty(chans)
                ch = find(~bad);
            else
                ch = EEGAnalysis.channelIndex(eeg.labels, chans);
            end
            left = eeg.labels(ch(bad(ch)));
            ch = ch(~bad(ch));
            if isempty(ch) && isempty(chans)
                error('NeuroAnalyzer:eeg:badOption', 'Every channel is marked bad.');
            elseif isempty(ch)
                error('NeuroAnalyzer:eeg:badOption', 'Every chosen channel is marked bad (%s): choose other channels.', ...
                    EEGSource.listText(left));
            end
            % Where the whole wavelet lies inside the trial
            h = TimeFrequency.supportSamples(fs, freqs, cyc);
            k = 1:nS;
            valid = k >= 1 + h(:) & k <= nS - h(:);
            fu = find(any(valid, 2))';
            % Trials of each condition
            nTr = size(eeg.data, 3);
            C = numel(conds);
            trialCond = zeros(1, nTr);
            for c = 1:C
                trialCond(strcmp(eeg.trials.condition, conds{c})) = c;
            end
            n = arrayfun(@(c) sum(trialCond == c), 1:C);
            F = numel(freqs);
            pw = zeros(F, nS, C);
            ip = zeros(F, nS, C);
            bt = zeros(nB, nS, nTr);                 % band power of each trial (mean over channels)
            for c = ch
                if isempty(fu), break; end
                X = reshape(double(eeg.data(c, :, :)), nS, nTr).';
                coef = reshape(TimeFrequency.morletTF(X, fs, freqs(fu), cyc(fu)), numel(fu), nS, nTr);
                p = abs(coef) .^ 2;
                u = coef ./ max(abs(coef), realmin);
                for cc = 1:C
                    sel = trialCond == cc;
                    if ~any(sel), continue; end
                    pw(fu, :, cc) = pw(fu, :, cc) + mean(p(:, :, sel), 3);
                    ip(fu, :, cc) = ip(fu, :, cc) + abs(mean(u(:, :, sel), 3));
                end
                for b = 1:nB
                    [~, j] = ismember(inBand{b}, fu);        % 0: a frequency of the band never fits the trial
                    if all(j > 0), bt(b, :, :) = bt(b, :, :) + mean(p(j, :, :), 1); end
                end
            end
            nCh = numel(ch);
            pw = pw / nCh;
            ip = ip / nCh;
            bt = bt / nCh;
            out = repmat(~valid, [1 1 C]);
            pw(out) = NaN;
            ip(out) = NaN;
            % ERSP: dB against the condition's mean power in the baseline samples where the wavelet fits
            inBase = valid & wb;
            B = nan(F, 1, C);
            for i = find(any(inBase, 2))'
                B(i, 1, :) = mean(pw(i, inBase(i, :), :), 2);
            end
            ersp = 10 * log10(pw ./ B);
            % Band power: each trial as % change from its condition's mean baseline band power
            bandValid = false(nB, nS);
            bp = nan(nB, nS, C);
            bs = nan(nB, nS, C);
            for b = 1:nB
                bandValid(b, :) = all(valid(inBand{b}, :), 1);
                mb = bandValid(b, :) & wb;
                if ~any(mb), continue; end
                for cc = 1:C
                    sel = trialCond == cc;
                    if ~any(sel), continue; end
                    y = reshape(bt(b, :, sel), nS, []);       % samples x trials
                    pc = 100 * (y / mean(mean(y(mb, :), 1)) - 1);
                    pc(~bandValid(b, :), :) = NaN;
                    bp(b, :, cc) = mean(pc, 2)';
                    if sum(sel) > 1, bs(b, :, cc) = std(pc, 0, 2)' / sqrt(sum(sel)); end
                end
            end
            tf = struct('conditions', {conds}, 'times', t, 'fs', fs, 'freqs', freqs, 'cycles', cyc, ...
                'baseline', bw, 'channels', {eeg.labels(ch)}, 'left', {left}, 'n', n, 'power', pw, ...
                'ersp', ersp, 'itpc', ip, 'valid', valid, 'baselineSamples', sum(inBase, 2)', ...
                'bands', bands, 'bandNames', {bandNames}, 'bandPct', bp, 'bandSem', bs, 'bandValid', bandValid);
        end

        %% grandTimeFrequency - Mean of the participants' time-frequency results (each participant once)
        function ga = grandTimeFrequency(tfs)
            if isstruct(tfs), tfs = num2cell(tfs); end
            if isempty(tfs)
                error('NeuroAnalyzer:eeg:badOption', ['No time' char(8211) 'frequency results to average.']);
            end
            ref = tfs{1};
            ga = ref;
            ga.trials = ref.n;
            ga.notes = {};
            if numel(tfs) == 1, return; end
            same = @(a, b) numel(a) == numel(b) && all(abs(a(:) - b(:)) < 1e-9);
            for p = 2:numel(tfs)
                e = tfs{p};
                if ~same(e.times, ref.times) || ~same(e.freqs, ref.freqs) || ~same(e.cycles, ref.cycles) ...
                        || ~same(e.baseline, ref.baseline) || ~same(e.bands, ref.bands)
                    error('NeuroAnalyzer:eeg:mismatch', ['Participant %d has other trial times, frequencies, ' ...
                        'cycles, baseline or bands than participant 1.'], p);
                end
            end
            conds = ref.conditions;
            for p = 2:numel(tfs)
                conds = conds(ismember(conds, tfs{p}.conditions));
            end
            if isempty(conds)
                error('NeuroAnalyzer:eeg:unknownCondition', 'The participants have no condition in common.');
            end
            P = numel(tfs);
            C = numel(conds);
            [F, nS, ~] = size(ref.ersp);
            nB = size(ref.bands, 1);
            E = zeros(F, nS, C, P); I = E; W = E;
            Bp = zeros(nB, nS, C, P);
            N = zeros(P, C);
            for p = 1:P
                [~, j] = ismember(conds, tfs{p}.conditions);
                E(:, :, :, p) = tfs{p}.ersp(:, :, j);
                I(:, :, :, p) = tfs{p}.itpc(:, :, j);
                W(:, :, :, p) = tfs{p}.power(:, :, j);
                Bp(:, :, :, p) = tfs{p}.bandPct(:, :, j);
                N(p, :) = tfs{p}.n(j);
            end
            ga.conditions = conds;
            ga.ersp = mean(E, 4);
            ga.itpc = mean(I, 4);
            ga.power = mean(W, 4);
            ga.bandPct = mean(Bp, 4);
            ga.bandSem = std(Bp, 0, 4) / sqrt(P);
            ga.n = repmat(P, 1, C);
            ga.trials = sum(N, 1);
            every = cellfun(@(e) e.conditions, tfs, 'UniformOutput', false);
            every = [every{:}];
            leftOut = EEGSource.stableUnique(every(~ismember(every, conds)));
            if ~isempty(leftOut)
                ga.notes{end + 1} = sprintf('Left out of the grand average: %s (not recorded in every participant).', ...
                    EEGSource.listText(leftOut));
            end
            used = cellfun(@(e) e.channels, tfs, 'UniformOutput', false);
            if any(cellfun(@(c) ~isequal(sort(c), sort(ref.channels)), used))
                ga.channels = EEGSource.stableUnique([used{:}]);
                ga.notes{end + 1} = sprintf(['The channels marked bad differ between participants: each ' ...
                    'participant uses their good channels among %s.'], EEGSource.listText(ga.channels));
            end
            left = cellfun(@(e) e.left, tfs, 'UniformOutput', false);
            ga.left = EEGSource.stableUnique([{}, left{:}]);
        end

        %% describeTimeFrequency - Settings in one sentence, then what the trial length left blank
        function s = describeTimeFrequency(tf)
            f = tf.freqs;
            nc = unique(tf.cycles);
            if isscalar(nc), ct = sprintf('%g cycles', nc); else, ct = sprintf('%g to %g cycles', min(nc), max(nc)); end
            if isscalar(tf.channels), where = sprintf('at %s', tf.channels{1});
            else, where = sprintf('averaged over %d channels', numel(tf.channels)); end
            s = sprintf(['Morlet wavelets of %s, %g to %g Hz (%d frequencies), %s; ERSP in dB against the mean ' ...
                'power from %g to %g ms.'], ct, f(1), f(end), numel(f), where, tf.baseline * 1000);
            has = any(tf.valid, 2)';
            withBase = tf.baselineSamples > 0;
            span = sprintf('%g to %g ms', tf.times([1 end]) * 1000);
            if ~any(has)
                s = sprintf(['%s No value: at every frequency the wavelet is longer than the trials (%s). Cut ' ...
                    'longer trials, use fewer cycles or higher frequencies.'], s, span);
                return;
            end
            if ~has(1)
                s = sprintf('%s Below %g Hz the wavelets are longer than the trials (%s): no values.', s, ...
                    f(find(has, 1)), span);
            end
            if ~any(withBase)
                s = sprintf(['%s No ERSP: at no frequency does a whole wavelet fit inside the baseline. Cut ' ...
                    'trials that start earlier, or use fewer cycles.'], s);
            elseif find(withBase, 1) > find(has, 1)
                s = sprintf(['%s ERSP from %g Hz up: below, no whole wavelet fits inside the baseline ' ...
                    '(trials that start earlier would help).'], s, f(find(withBase, 1)));
            end
            if any(withBase)
                i = find(withBase, 1);
                tv = tf.times(tf.valid(i, :)) * 1000;
                s = sprintf(['%s At %g Hz the values run from %.0f to %.0f ms; nearer the trial edges the ' ...
                    'wavelet would leave the trial, so they stay blank.'], s, f(i), tv(1), tv(end));
            end
            % Band power: how much of the baseline its lowest frequency leaves
            inWin = tf.times >= tf.baseline(1) - 1e-9 & tf.times <= tf.baseline(2) + 1e-9;
            for b = 1:size(tf.bands, 1)
                mb = tf.bandValid(b, :) & inWin;
                lo = f(find(f >= tf.bands(b, 1) - 1e-9, 1));
                if ~any(mb)
                    s = sprintf(['%s No %s band power: at %g Hz no whole wavelet fits inside the baseline ' ...
                        '(longer trials needed).'], s, tf.bandNames{b}, lo);
                elseif sum(mb) < sum(inWin)
                    tv = tf.times(mb) * 1000;
                    s = sprintf(['%s %s band power: its baseline is only %.0f to %.0f ms (where the wavelet of ' ...
                        '%g Hz fits), so it is noisier.'], s, tf.bandNames{b}, tv(1), tv(end), lo);
                end
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
            % Transition widths (Widmann et al. 2015): a quarter of the passband edge, at
            % least 2 Hz, but never past 0 Hz or the Nyquist frequency.
            lt = [];
            ht = [];
            h = 1;
            if ~isempty(hp)
                lt = min(max(0.25 * hp, 2), hp);
                m = EEGAnalysis.firOrder(fs, lt);
                h = conv(h, EEGAnalysis.windowedSinc(m, fs, hp - lt / 2, 0));
            end
            if ~isempty(lp)
                ht = min(max(0.25 * lp, 2), nyq - lp);
                m = EEGAnalysis.firOrder(fs, ht);
                h = conv(h, EEGAnalysis.windowedSinc(m, fs, lp + ht / 2, 1));
            end
            % A band-pass is the high-pass and the low-pass applied one after the other,
            % merged into one filter (the convolution of their taps): each edge keeps its
            % own transition width, and the orders add up.
            N = numel(h);
            kind = 'band-pass';
            if isempty(lp), kind = 'high-pass'; elseif isempty(hp), kind = 'low-pass'; end
            d = struct('kind', kind, 'fs', fs, 'highPass', hp, 'lowPass', lp, 'highTransition', lt, ...
                'lowTransition', ht, 'highCutoff', hp - lt / 2, 'lowCutoff', lp + ht / 2, ...
                'notch', [], 'notchWidth', [], 'length', N, 'order', N - 1, 'h', h);
        end

        %% notchDesign - The FIR band-stop filter around each line-noise frequency
        % Each line frequency f is removed from f - 0.5 to f + 0.5 Hz (a 1 Hz stop band,
        % wide enough for the small drift of the mains frequency), with 1 Hz transitions on
        % both sides: -6 dB at f +- 1 Hz, everything outside f +- 1.5 Hz passed. All
        % frequencies share one band-stop filter (one Hamming window, Widmann et al. 2015).
        function d = notchDesign(fs, freqs)
            freqs = sort(double(freqs(:)'));
            nyq = fs / 2;
            sw = 1;                            % stop band width (Hz)
            tb = 1;                            % transition on each side (Hz)
            reach = sw / 2 + tb;               % from f to the passband edge
            if isempty(freqs) || any(~isfinite(freqs)) || any(freqs - reach <= 0) || any(freqs + reach >= nyq)
                error('NeuroAnalyzer:eeg:badOption', ['The notch frequencies must lie between %g Hz ' ...
                    'and %g Hz (half the sampling rate minus %g Hz).'], reach, nyq - reach, reach);
            end
            if any(diff(freqs) < 2 * reach)
                error('NeuroAnalyzer:eeg:badOption', 'The notch frequencies are too close together.');
            end
            cut = reshape([freqs - sw / 2 - tb / 2; freqs + sw / 2 + tb / 2], 1, []);
            h = EEGAnalysis.windowedSinc(EEGAnalysis.firOrder(fs, tb), fs, cut, 1);
            N = numel(h);
            d = struct('kind', 'notch', 'fs', fs, 'highPass', [], 'lowPass', [], 'highTransition', tb, ...
                'lowTransition', tb, 'highCutoff', [], 'lowCutoff', [], 'notch', freqs, ...
                'notchWidth', repmat(sw, size(freqs)), 'length', N, 'order', N - 1, 'h', h);
        end

        %% describeFilter - One plain sentence for a filter design
        function s = describeFilter(d)
            tail = sprintf('zero-phase FIR filter (Hamming-windowed sinc, %d taps, order %d)', d.length, d.order);
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
            eeg.data(~bad, :, :) = single(double(eeg.data(~bad, :, :)) - r);   % bad channels keep their data
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

        %% parseEvents - 'S 1 = Standard, S 2' -> event types, renames, unreadable parts
        function [events, rename, problems] = parseEvents(txt)
            events = {};
            rename = cell(0, 2);
            problems = {};
            parts = strtrim(strsplit(char(txt), {',', ';'}));
            for i = 1:numel(parts)
                x = parts{i};
                if isempty(x), continue; end
                eq = strfind(x, '=');
                if isempty(eq)
                    events{end + 1} = x; %#ok<AGROW>
                    continue;
                end
                type = strtrim(x(1:eq(1) - 1));
                name = strtrim(x(eq(1) + 1:end));
                if isempty(type) || isempty(name) || numel(eq) > 1
                    problems{end + 1} = x; %#ok<AGROW>
                else
                    rename(end + 1, :) = {type, name}; %#ok<AGROW>
                end
            end
        end

        %% mastoidChannels - TP9 / TP10, else M1 / M2, else A1 / A2 (as named in labels)
        function names = mastoidChannels(labels)
            pairs = {'TP9', 'TP10'; 'M1', 'M2'; 'A1', 'A2'};
            for i = 1:size(pairs, 1)
                [tf, j] = ismember(lower(pairs(i, :)), lower(labels));
                if all(tf), names = labels(j); return; end
            end
            error('NeuroAnalyzer:eeg:unknownChannel', ['Linked mastoids need the channels TP9 and TP10 (or M1 and M2, ' ...
                'or A1 and A2), and this recording has none of these pairs. Choose Channels and type the reference channels.']);
        end

        %% notchFrequencies - Line frequency and harmonics below Nyquist (and the low-pass)
        function f = notchFrequencies(notch, fs, lowPass)
            f = [];
            if ~isnumeric(notch) || isempty(notch) || notch <= 0, return; end
            f = notch * (1:floor(fs / 2 / notch));
            f = f(f < fs / 2 - 1.5);             % the notch passes from f + 1.5 Hz (notchDesign)
            if lowPass > 0, f = f(f < lowPass); end
            if isempty(f), f = notch; end      % at least the line frequency itself
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

        %% checks - Quality checks of the trials analysed, one row per check over every participant
        function Q = checks(eegs, names, o)
            Q = QualityChecks.none();
            if nargin < 2, names = {}; end
            if nargin < 3, o = []; end
            try
                if isstruct(eegs), eegs = num2cell(eegs); end
                if ~iscell(eegs) || isempty(eegs), return; end
                eegs = eegs(:)';
                P = numel(eegs);
                if ischar(names), names = {names}; end
                if ~iscell(names), names = {}; end
                names = names(:)';
                for p = 1:P
                    if p > numel(names) || ~ischar(names{p}) || isempty(names{p})
                        names{p} = sprintf('participant %d', p);
                    end
                end
                names = names(1:P);
                o = EEGAnalysis.checkOptions(o, P);
                C = cell(1, P);
                for p = 1:P
                    C{p} = EEGAnalysis.conditionCounts(eegs{p}, o.rejections{p});
                end
            catch
                return;                                  % odd input: no rows
            end
            for k = 1:5
                try
                    switch k
                        case 1, Q = EEGAnalysis.trialsCheck(Q, C, names);
                        case 2, Q = EEGAnalysis.rejectionCheck(Q, eegs, C, names);
                        case 3, Q = EEGAnalysis.balanceCheck(Q, C, names, o.measure);
                        case 4, Q = EEGAnalysis.badChannelsCheck(Q, eegs, names);
                        case 5, Q = EEGAnalysis.interpolationCheck(Q, eegs, names, o);
                    end
                catch
                    % a check that cannot run on this input gives no row
                end
            end
        end

        %% interpolatedChannels - Channels interpolated before, from the history lines
        function [names, info] = interpolatedChannels(eeg)
            names = {};
            info = struct('unknown', false, 'where', '', 'lines', {{}});
            if ~isstruct(eeg) || ~isfield(eeg, 'history'), return; end
            h = eeg.history;
            if ischar(h), h = {h}; end
            if ~iscell(h), return; end
            here = false;
            for k = 1:numel(h)
                if ~ischar(h{k}), continue; end
                s = strtrim(h{k});
                if ~strncmp(s, 'Interpolated ', 13), continue; end
                info.lines{end + 1} = s;
                here = here || ~isempty(regexp(s, '\(Neuronal Data Analyzer Lab\)\.?$', 'once'));
                t = regexprep(s, '\.$', '');
                t = regexprep(t, '\s*\([^()]*\)$', '');             % (pop_interp), (ft_channelrepair)
                t = regexprep(t, '\s+using\s.*$', '');              % using spherical splines / the spline method
                tok = regexp(t, '^Interpolated\s+(?:\d+\s+)?channels?\s+(.+)$', 'tokens', 'once');
                if isempty(tok)                                     % 'Interpolated bad channels': not named
                    info.unknown = true;
                    continue;
                end
                parts = strtrim(strsplit(regexprep(tok{1}, '\s+and\s+', ', '), ','));
                names = [names, parts(~cellfun(@isempty, parts))]; %#ok<AGROW>
            end
            if ~isempty(names), names = EEGSource.stableUnique(names); end
            if isempty(info.lines), return; end
            if here
                info.where = 'here';
            elseif isfield(eeg, 'source') && ischar(eeg.source) && ~isempty(eeg.source)
                info.where = ['in ' eeg.source];
            else
                info.where = 'before loading';
            end
        end
    end

    methods(Static, Hidden)

        %% checkOptions - Settings of checks with every field (rejections: one cell per participant)
        function d = checkOptions(o, P)
            d = struct('rejections', {{}}, 'measure', '', 'channels', {{}}, 'erpChannels', {{}});
            if isstruct(o) && isscalar(o)
                f = fieldnames(o);
                for k = 1:numel(f)
                    switch lower(f{k})
                        case {'rejections', 'rejection'}, d.rejections = o.(f{k});
                        case 'measure', d.measure = o.(f{k});
                        case {'channels', 'measurechannels'}, d.channels = o.(f{k});
                        case 'erpchannels', d.erpChannels = o.(f{k});
                    end
                end
            end
            r = d.rejections;
            if isstruct(r), r = num2cell(r); end
            if ~iscell(r), r = {}; end
            r = r(:)';
            r(end + 1:P) = {[]};
            d.rejections = r(1:P);
            m = '';
            if ischar(d.measure), m = lower(strtrim(d.measure)); end
            if strncmp(m, 'peak', 4)
                d.measure = 'peak';
            elseif strncmp(m, 'mean', 4)
                d.measure = 'mean';
            else
                d.measure = '';
            end
            d.channels = EEGAnalysis.nameCells(d.channels);
            d.erpChannels = EEGAnalysis.nameCells(d.erpChannels);
        end

        %% nameCells - 'Pz, Cz' or a cell -> {'Pz', 'Cz'} ({} when none)
        function c = nameCells(x)
            c = {};
            if isempty(x), return; end
            if ischar(x), x = strsplit(x, {',', ';'}); end
            if ~iscell(x), return; end
            x = x(cellfun(@ischar, x));
            c = strtrim(x(:)');
            c = c(~cellfun(@isempty, c));
        end

        %% conditionCounts - Conditions with their trials before and after the rejection
        % From the rejection info when given (known = true), else the trials of eeg.
        function c = conditionCounts(eeg, info)
            c = struct('conditions', {{}}, 'before', [], 'after', [], 'known', false);
            if isstruct(info) && isscalar(info) && all(isfield(info, {'conditions', 'before', 'after'})) ...
                    && numel(info.conditions) == numel(info.after) && numel(info.before) == numel(info.after)
                c.conditions = EEGSource.cellRow(info.conditions);
                c.before = double(info.before(:)');
                c.after = double(info.after(:)');
                c.known = true;
                return;
            end
            if ~isfield(eeg, 'trials') || ~isfield(eeg.trials, 'condition'), return; end
            tc = eeg.trials.condition;
            conds = {};
            if isfield(eeg, 'conditions'), conds = EEGSource.cellRow(eeg.conditions); end
            if isempty(conds), conds = EEGSource.stableUnique(tc); end
            if isempty(conds), return; end
            n = cellfun(@(x) sum(strcmp(tc, x)), conds);
            c.conditions = conds;
            c.before = n;
            c.after = n;
        end

        %% trialsCheck - The fewest trials left in a condition
        function Q = trialsCheck(Q, C, names)
            L = EEGAnalysis.CheckLimits;
            P = numel(C);
            nMin = inf(1, P);
            cMin = repmat({''}, 1, P);
            for p = 1:P
                if isempty(C{p}.after), continue; end
                [nMin(p), i] = min(C{p}.after);
                cMin{p} = C{p}.conditions{i};
            end
            if ~any(isfinite(nMin)), return; end
            topic = 'Trials per condition';
            rule = sprintf('check below %d, warning below %d', L.trialsCheck, L.trialsWarning);
            [worst, kw] = min(nMin);
            if worst >= L.trialsCheck
                Q = QualityChecks.add(Q, 'ok', topic, sprintf('Fewest trials in a condition: %s; %s.', ...
                    EEGAnalysis.countText(cMin{kw}, worst, names{kw}, P), rule));
                return;
            end
            low = find(nMin < L.trialsCheck);
            [~, order] = sort(nMin(low));
            low = low(order);
            parts = cell(1, min(3, numel(low)));
            for j = 1:numel(parts)
                parts{j} = EEGAnalysis.countText(cMin{low(j)}, nMin(low(j)), names{low(j)}, P);
            end
            if worst < L.trialsWarning
                level = 'warning';
                thr = L.trialsWarning;
                why = ['An ERP is the mean of its trials: from fewer than 10 trials it is mostly noise, so its ' ...
                    'peaks and mean amplitudes change a lot with every trial added or left out.'];
                action = ['Look at why trials were lost (the channels the rejection names): mark noisy channels ' ...
                    'bad, correct blinks (ICA in EEGLAB) instead of rejecting the trials, or leave the participant ' ...
                    'out; record more trials of rare conditions next time.'];
            else
                level = 'check';
                thr = L.trialsCheck;
                why = ['About 20 trials are enough for a large component such as the P300; smaller ones (N1, P1, ' ...
                    'N400 differences) need more (30 to 60) to stand out from the noise.'];
                action = 'Fine for a large component; for a small one, record more trials of that condition.';
            end
            found = ['Fewest trials in a condition: ' strjoin(parts, ', ')];
            if numel(low) > 3, found = [found ', ...']; end
            if P > 1
                found = sprintf('%s (below %d in %d of %d participants)', found, thr, sum(nMin < thr), P);
            end
            Q = QualityChecks.add(Q, level, topic, [found '.'], why, action);
        end

        %% rejectionCheck - Share of each condition the rejection left out
        function Q = rejectionCheck(Q, eegs, C, names)
            L = EEGAnalysis.CheckLimits;
            P = numel(C);
            topic = 'Rejection balance';
            known = cellfun(@(c) c.known, C);
            if ~any(known)
                prior = false(1, P);
                for p = 1:P
                    if isfield(eegs{p}, 'history') && iscell(eegs{p}.history)
                        prior(p) = any(strncmp(eegs{p}.history, 'Rejected', 8));
                    end
                end
                if any(prior)
                    Q = QualityChecks.add(Q, 'note', topic, sprintf(['Trials were rejected before loading%s (the ' ...
                        'history says so), not here: how many of each condition were left out is not known.'], ...
                        EEGAnalysis.whoText(find(prior), names, P)));
                end
                return;
            end
            d = -inf(1, P);
            hiS = zeros(1, P); loS = zeros(1, P); hi = ones(1, P); lo = ones(1, P); sev = zeros(1, P);
            share = cell(1, P);
            nRej = 0;
            for p = find(known)
                b = C{p}.before;
                a = C{p}.after;
                use = b > 0;
                nRej = nRej + sum(b(use) - a(use));
                if nnz(use) < 2, continue; end
                s = nan(size(b));
                s(use) = 100 * (b(use) - a(use)) ./ b(use);
                share{p} = s;
                [hiS(p), hi(p)] = max(s);
                [loS(p), lo(p)] = min(s);
                d(p) = hiS(p) - loS(p);
                if b(hi(p)) - a(hi(p)) >= L.rejectionMinTrials
                    if d(p) > L.rejectionWarning
                        sev(p) = 2;
                    elseif d(p) > L.rejectionCheck
                        sev(p) = 1;
                    end
                end
            end
            if nRej == 0
                Q = QualityChecks.add(Q, 'ok', topic, 'The rejection left out no trial.');
                return;
            end
            if ~any(isfinite(d)), return; end
            if ~any(sev)
                [dw, kw] = max(d);
                c = C{kw}.conditions;
                txt = cell(1, numel(c));
                for j = 1:numel(c)
                    txt{j} = sprintf('%s %.0f%%', c{j}, share{kw}(j));
                end
                who = '';
                if P > 1, who = [names{kw} ': ']; end
                few = '';
                if dw > L.rejectionCheck
                    nk = C{kw}.before(hi(kw)) - C{kw}.after(hi(kw));
                    few = sprintf(', but only %d %s %s', nk, C{kw}.conditions{hi(kw)}, EEGSource.plural(nk, 'trial'));
                end
                Q = QualityChecks.add(Q, 'ok', topic, sprintf(['Share of each condition rejected: %s%s (%.0f points ' ...
                    'apart%s); check above %d points (and %d trials).'], who, EEGSource.listText(txt(isfinite(share{kw}))), ...
                    dw, few, L.rejectionCheck, L.rejectionMinTrials));
                return;
            end
            flag = find(sev > 0);
            [~, order] = sortrows([-sev(flag)', -d(flag)']);
            flag = flag(order);
            parts = cell(1, min(3, numel(flag)));
            for j = 1:numel(parts)
                p = flag(j);
                parts{j} = sprintf('%.0f%% of %s trials but %.0f%% of %s', hiS(p), C{p}.conditions{hi(p)}, ...
                    loS(p), C{p}.conditions{lo(p)});
                if P > 1, parts{j} = sprintf('%s (%s)', parts{j}, names{p}); end
            end
            found = ['Rejection removed ' strjoin(parts, '; ')];
            if numel(flag) > 3, found = [found '; ...']; end
            level = 'check';
            if any(sev == 2), level = 'warning'; end
            Q = QualityChecks.add(Q, level, topic, [found '.'], ['When artefacts come with one condition (e.g. ' ...
                'blinks after targets), the trials kept differ between the conditions in more than the condition ' ...
                'itself, so they are no longer comparable.'], ['Look at what was rejected (the channels the ' ...
                'rejection names); prefer correcting blinks (ICA in EEGLAB) to rejecting the trials; check that the ' ...
                'effect stays the same with a stricter and a looser threshold.']);
        end

        %% balanceCheck - Trial counts across conditions against the measure
        function Q = balanceCheck(Q, C, names, measure)
            L = EEGAnalysis.CheckLimits;
            P = numel(C);
            r = nan(1, P);
            big = repmat({''}, 1, P); small = big;
            nBig = zeros(1, P); nSmall = zeros(1, P);
            for p = 1:P
                n = C{p}.after;
                use = n > 0;
                if nnz(use) < 2, continue; end
                cs = C{p}.conditions(use);
                n = n(use);
                [nBig(p), i] = max(n);
                [nSmall(p), j] = min(n);
                big{p} = cs{i};
                small{p} = cs{j};
                r(p) = nBig(p) / nSmall(p);
            end
            if all(isnan(r)), return; end
            topic = 'Condition balance';
            [worst, kw] = max(r);
            who = '';
            if P > 1, who = [', ' names{kw}]; end
            if worst <= L.countRatio
                if P > 1, who = sprintf(' (%s)', names{kw}); end
                Q = QualityChecks.add(Q, 'ok', topic, sprintf(['Similar trial counts in every condition: at most ' ...
                    '%.1f times as many in one as in another%s; check above %g times with the peak amplitude.'], ...
                    worst, who, L.countRatio));
                return;
            end
            if P > 1
                who = sprintf('%s; more than %g times in %d of %d participants', who, L.countRatio, ...
                    sum(r > L.countRatio), P);
            end
            ex = sprintf('%s has %.1f times as many trials as %s (%d vs %d%s)', big{kw}, worst, small{kw}, ...
                nBig(kw), nSmall(kw), who);
            switch measure
                case 'peak'
                    Q = QualityChecks.add(Q, 'check', topic, [ex ', and the peak amplitude is measured.'], ...
                        ['The average of fewer trials keeps more noise, and the largest value of a noisier wave lies ' ...
                        'further out: peaks of the conditions with fewer trials come out larger even when the brain ' ...
                        'response is the same.'], ['Use the mean amplitude, or measure the peaks on the same number ' ...
                        'of trials in each condition (a random subset of the larger one).']);
                case 'mean'
                    Q = QualityChecks.add(Q, 'ok', topic, sprintf(['%s: fine for the mean amplitude, which the ' ...
                        'number of trials does not bias (rare conditions are part of an oddball design); with the ' ...
                        'peak amplitude: check above %g times.'], ex, L.countRatio));
                otherwise
                    Q = QualityChecks.add(Q, 'note', topic, [ex ': fine for the mean amplitude; peak amplitudes ' ...
                        'would come out larger in the conditions with fewer trials.']);
            end
        end

        %% badChannelsCheck - Channels marked bad, per participant
        function Q = badChannelsCheck(Q, eegs, names)
            L = EEGAnalysis.CheckLimits;
            P = numel(eegs);
            nb = zeros(1, P); nc = zeros(1, P);
            lists = cell(1, P);
            for p = 1:P
                bad = EEGAnalysis.badChannels(eegs{p});
                nb(p) = nnz(bad);
                nc(p) = numel(bad);
                lists{p} = eegs{p}.labels(bad);
            end
            if ~any(nc > 0), return; end
            topic = 'Bad channels';
            pct = 100 * nb ./ max(nc, 1);
            rule = sprintf('check above %d%% of the channels, warning above %d%%', L.badCheck, L.badWarning);
            [worst, kw] = max(pct);
            if worst <= L.badCheck
                if worst == 0
                    found = sprintf('No channel marked bad (%s).', rule);
                else
                    who = '';
                    if P > 1, who = [', ' names{kw}]; end
                    found = sprintf('At most %d of %d channels marked bad (%.0f%%%s: %s); %s.', nb(kw), nc(kw), ...
                        worst, who, EEGAnalysis.shortList(lists{kw}, 8), rule);
                end
                Q = QualityChecks.add(Q, 'ok', topic, found);
                return;
            end
            flag = find(pct > L.badCheck);
            [~, order] = sort(pct(flag), 'descend');
            flag = flag(order);
            if P == 1
                found = sprintf('%d of %d channels marked bad (%.0f%%): %s.', nb, nc, pct, ...
                    EEGAnalysis.shortList(lists{1}, 8));
            else
                parts = cell(1, min(3, numel(flag)));
                for j = 1:numel(parts)
                    p = flag(j);
                    parts{j} = sprintf('%s: %d of %d (%.0f%%: %s)', names{p}, nb(p), nc(p), pct(p), ...
                        EEGAnalysis.shortList(lists{p}, 4));
                end
                found = ['Channels marked bad: ' strjoin(parts, '; ')];
                if numel(flag) > 3, found = [found '; ...']; end
                found = [found '.'];
            end
            level = 'check';
            if worst > L.badWarning, level = 'warning'; end
            Q = QualityChecks.add(Q, level, topic, found, ['Bad channels are left out of the ERPs, the measures and ' ...
                'the average reference: the reference and the scalp maps rest on fewer channels, and so many bad ' ...
                'channels often mean a poor recording (cap fit, gel, impedances).'], ['Check the cap, the gel and ' ...
                'the impedances for the next recordings; interpolate a few channels at most (in EEGLAB or ' ...
                'FieldTrip), or consider leaving the participant out.']);
        end

        %% interpolationCheck - Channels interpolated before loading against the measured channels
        function Q = interpolationCheck(Q, eegs, names, o)
            P = numel(eegs);
            if ~all(cellfun(@(e) isstruct(e) && isfield(e, 'labels'), eegs)), return; end
            interp = cell(1, P);
            unknown = false(1, P);
            where = repmat({''}, 1, P);
            for p = 1:P
                [interp{p}, info] = EEGAnalysis.interpolatedChannels(eegs{p});
                unknown(p) = info.unknown;
                where{p} = info.where;
            end
            topic = 'Interpolated channels';
            has = ~cellfun(@isempty, interp);
            if ~any(has) && ~any(unknown)
                Q = QualityChecks.add(Q, 'ok', topic, 'No interpolated channel (none in the history of the data).');
                return;
            end
            measured = o.channels;
            if isempty(measured), measured = o.erpChannels; end
            if isempty(measured), mText = 'all channels'; else, mText = EEGSource.listText(measured); end
            wh = EEGSource.stableUnique(where(has | unknown));
            whText = 'before loading';
            if numel(wh) == 1 && ~isempty(wh{1}), whText = wh{1}; end
            every = false(1, P);
            some = cell(1, P);
            for p = find(has)
                m = measured;
                if isempty(m), m = eegs{p}.labels(~EEGAnalysis.badChannels(eegs{p})); end
                hit = ismember(lower(m), lower(interp{p}));
                some{p} = m(hit);
                every(p) = ~isempty(m) && all(hit);
            end
            hitAny = ~cellfun(@isempty, some);
            why = ['An interpolated channel is an estimate made from its neighbours, not a recording: its peaks ' ...
                'are smoothed, and averaged with its neighbours it counts their signals twice.'];
            if any(every)
                ch = EEGSource.stableUnique([some{every}]);
                Q = QualityChecks.add(Q, 'warning', topic, sprintf('%s, the measured %s, %s interpolated (%s)%s.', ...
                    EEGSource.listText(ch), EEGSource.plural(numel(ch), 'channel'), EEGAnalysis.wasWere(numel(ch)), ...
                    whText, EEGAnalysis.whoText(find(every), names, P)), why, ['Measure at channels that were ' ...
                    'recorded (e.g. the neighbours of the interpolated one), or leave out the participants whose ' ...
                    'measured channels were interpolated.']);
            elseif any(hitAny) || any(unknown)
                parts = {};
                if any(hitAny)
                    ch = EEGSource.stableUnique([some{hitAny}]);
                    parts{end + 1} = sprintf('%s, among the measured channels (%s), %s interpolated (%s)%s.', ...
                        EEGSource.listText(ch), mText, EEGAnalysis.wasWere(numel(ch)), whText, ...
                        EEGAnalysis.whoText(find(hitAny), names, P));
                end
                if any(unknown)
                    parts{end + 1} = sprintf(['The history says bad channels were interpolated but not which%s: ' ...
                        'the measured channels (%s) may be estimates.'], EEGAnalysis.whoText(find(unknown), names, P), mText);
                end
                Q = QualityChecks.add(Q, 'check', topic, strjoin(parts, ' '), why, ['Check that the result stays ' ...
                    'the same without the interpolated channels, or measure at recorded channels only.']);
            else
                ch = EEGSource.stableUnique([interp{has}]);
                Q = QualityChecks.add(Q, 'ok', topic, sprintf('%s %s interpolated (%s)%s; not among the measured channels (%s).', ...
                    EEGSource.listText(ch), EEGAnalysis.wasWere(numel(ch)), whText, ...
                    EEGAnalysis.whoText(find(has), names, P), mText));
            end
        end

        %% countText - 'Target 6' or 'Target 6 (sub-01)' with several participants
        function s = countText(cond, n, name, P)
            s = sprintf('%s %d', cond, n);
            if P > 1, s = sprintf('%s (%s)', s, name); end
        end

        %% whoText - '' (one participant), ' in sub-01 and sub-02', ' in 8 participants', ' in 5 of 8 participants'
        function s = whoText(idx, names, P)
            s = '';
            if P <= 1 || isempty(idx), return; end
            if numel(idx) <= 3
                s = [' in ' EEGSource.listText(names(idx))];
            elseif numel(idx) == P
                s = sprintf(' in %d participants', P);
            else
                s = sprintf(' in %d of %d participants', numel(idx), P);
            end
        end

        %% wasWere - 'was' (one) or 'were'
        function s = wasWere(n)
            if n == 1, s = 'was'; else, s = 'were'; end
        end

        %% shortList - 'A, B and C' with at most n names, then ', ...'
        function s = shortList(c, n)
            if numel(c) <= n
                s = EEGSource.listText(c);
            else
                s = [strjoin(c(1:n), ', ') ', ...'];
            end
        end

        %% firOrder - Filter order for a transition width (Hamming window)
        % Widmann et al. (2015), Table 1: with a Hamming window the transition band is
        % about 3.3 / order of the sampling rate wide, so order = 3.3 fs / width. Rounded
        % up (the transition is never wider than asked) to an even order, so the filter
        % has an odd number of taps and a whole-sample delay of order / 2.
        function m = firOrder(fs, width)
            m = ceil(3.3 * fs / width - 1e-9);
            m = m + mod(m, 2);
        end

        %% windowedSinc - Linear-phase FIR from cutoff frequencies (windowed-sinc method)
        % The ideal (infinitely long) filter whose gain is g0 below the first cutoff and
        % flips between 1 and 0 at each cutoff fc (Hz, ascending) is a sum of sinc
        % functions: gain(f) = gEnd + sum_k (gain below fc_k - gain above fc_k) * LP_k(f),
        % LP_k the ideal low-pass at fc_k, whose impulse response is 2 fc sinc(2 fc n)
        % (fc in cycles per sample). It is cut to the samples n = -m/2..m/2 and tapered by
        % a Hamming window 0.54 + 0.46 cos(2 pi n / m) (Widmann et al. 2015). Each low-pass
        % part is scaled to a gain of exactly 1 at 0 Hz, so a high-pass removes a constant
        % offset completely and a low-pass keeps it unchanged. Each cutoff lies in the
        % middle of its transition band (-6 dB).
        function h = windowedSinc(m, fs, fc, g0)
            n = -m / 2:m / 2;
            w = 0.54 + 0.46 * cos(2 * pi * n / max(m, 1));
            h = zeros(size(n));
            g = g0;
            for k = 1:numel(fc)
                v = 2 * fc(k) / fs;                     % 2 fc in cycles per sample
                lowpass = v * EEGAnalysis.sinc(v * n) .* w;
                lowpass = lowpass / sum(lowpass);
                h = h + (g - (1 - g)) * lowpass;        % +LP when the gain drops, -LP when it rises
                g = 1 - g;
            end
            if g == 1                                   % gain at the Nyquist frequency
                h(m / 2 + 1) = h(m / 2 + 1) + 1;
            end
        end

        %% sinc - sin(pi x) / (pi x), 1 at x = 0
        function y = sinc(x)
            y = ones(size(x));
            k = x ~= 0;
            y(k) = sin(pi * x(k)) ./ (pi * x(k));
        end

        %% applyFIR - Zero-phase FIR along the samples of every channel and trial
        % The taps are symmetric (linear phase), so the filter only delays the signal by
        % half its order; that delay is removed by taking the output centred on each
        % input sample (Widmann et al. 2015), which leaves the phase unchanged.
        % Edges: near each end the filter needs order / 2 samples beyond the recording.
        % They are made by mirroring the signal about its first (last) sample and turning
        % the mirror image upside down (2 x(1) - x(1 + k)), so the level and the slope
        % continue smoothly across the edge and an offset or slow drift does not produce a
        % step there. When the recording is shorter than that, the last mirrored value is
        % held for the rest of the padding.
        function y = applyFIR(x, h)
            [nCh, nS, nTr] = size(x);
            N = numel(h);
            P = (N - 1) / 2;                           % padding at each end = the delay
            r = min(P, nS - 1);                        % samples that can be mirrored
            y = zeros(nCh, nS, nTr, 'single');
            nfft = 2 ^ nextpow2(nS + 2 * P + N - 1);
            H = fft(h(:)', nfft);
            for k = 1:nTr
                X = double(x(:, :, k));
                if P > 0
                    before = 2 * X(:, 1) - X(:, r + 1:-1:2);           % x(1 - r) .. x(0)
                    after = 2 * X(:, end) - X(:, end - 1:-1:end - r);  % x(nS + 1) .. x(nS + r)
                    if r < P
                        if r == 0, before = X(:, 1); after = X(:, end); end
                        before = [repmat(before(:, 1), 1, P - size(before, 2)), before];
                        after = [after, repmat(after(:, end), 1, P - size(after, 2))];
                    end
                    X = [before, X, after];
                end
                Y = real(ifft(fft(X, nfft, 2) .* H, [], 2));
                y(:, :, k) = single(Y(:, 2 * P + (1:nS)));     % sample i of the input: P + i, plus the delay P
            end
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
