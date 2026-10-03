%% PerfusionChecks.m
% =========================================================================
% PERFUSION CHECKS - QUALITY CHECKS SHARED BY EVERY BLOOD-FLOW SOURCE
% =========================================================================
% Checks of one or more blood-flow traces over time, whatever measured
% them: the needle probe (laser Doppler flowmetry, a trace in PU), laser
% speckle (the flow index of each ROI) or the perfusion / flux images of a
% commercial imager (the perfusion of each ROI). No check assumes one
% source: values are judged relative to the trace's own baseline, and
% times in seconds. LDFPipeline.checks and LaserSpeckle.checks add the
% checks that only apply to their source.
%
%   o = PerfusionChecks.options()   settings of the checks:
%       names       {} | one name per trace (rows of Y); texts name the
%                   traces when there are several
%       onsets      [] stimulus onsets found or given (s)
%       trialOnsets NaN | onsets of the trials kept (s; NaN: all onsets)
%       preSec, postSec   trial window (s before / after each onset)
%       responseSec [] response window (s after onset; [] = 0 to postSec)
%       ceiling     NaN | the device's top value (e.g. 3000 PU); NaN: the
%                   largest value of the trace
%   Q = PerfusionChecks.run(Y, t, o, Q)
%       All the checks below for traces Y (K x N, one trace per row) at
%       times t (1 x N, s); rows appended to Q (QualityChecks rows; [] or
%       omitted: new rows).
%   Q = PerfusionChecks.drift(Q, Y, t, o)
%       Baseline drift (%/min of the baseline mean, linear fit) before the
%       first stimulus when that part lasts at least DriftMinSec (60 s:
%       shorter parts follow vasomotion), else across the trial baselines
%       (mean before each onset, >= 4 trials over >= DriftTrialSec, 120 s).
%       Check above DriftCheck (3), Warning above DriftWarning (10) %/min;
%       a note when the recording is too short to tell.
%   Q = PerfusionChecks.artefacts(Q, Y, t, o)
%       Movement artefacts: jumps of the trace away from its ~1 s moving
%       median by more than ArtefactSD robust SDs and ArtefactFraction of
%       the baseline. Count, times and the trials they fall in; Warning
%       when they fall in a trial (they enter the average), else Check.
%   Q = PerfusionChecks.stuck(Q, Y, o)
%       Signal stuck at 0 (values <= 0) or at the ceiling (runs of >= 3
%       identical samples at the top): Warning above StuckFraction of the
%       samples.
%   Q = PerfusionChecks.trials(Q, o)
%       Stimuli left out (their trial does not fit), too few trials (< 3),
%       no stimuli (a note).
%   Q = PerfusionChecks.trialBaseline(Q, dt, o)
%       Baseline of each trial shorter than 2 s or 5 samples: Check.
%   Q = PerfusionChecks.timeResolution(Q, dt, o, extra)
%       One value every dt s: Check above 0.5 s (latency and rise time
%       known to within dt), Warning above 2 s or with fewer than 2
%       samples in the response window. extra: text added to the finding
%       (e.g. ' after downsampling by 10').
%   ev = PerfusionChecks.events(y, t)
%       Artefact events of one trace: struct array start, stop (s), size
%       (largest jump, in the trace's units).
%   [rate, how, span, n] = PerfusionChecks.driftRate(y, t, o)
%       Drift of one trace (%/min; NaN when it cannot tell), how
%       ('before the first stimulus' | 'trial baselines' | ''), the time
%       span used (s) and the number of trial baselines.
%
% Base MATLAB only (movmedian, polyfit); also runs in GNU Octave.
% =========================================================================

classdef PerfusionChecks
    properties(Constant)
        DriftCheck = 3            % %/min
        DriftWarning = 10         % %/min
        DriftMinSec = 60          % s before the first stimulus needed to judge drift
        DriftTrialSec = 120       % or s spanned by >= 4 trial baselines
        ArtefactSD = 8            % robust SDs from the moving median
        ArtefactFraction = 0.25   % and this fraction of the baseline
        StuckFraction = 0.001     % of the samples
    end

    methods(Static)

        %% options - Default settings of the checks
        function o = options()
            o = struct('names', {{}}, 'onsets', [], 'trialOnsets', NaN, 'preSec', 5, 'postSec', 20, ...
                'responseSec', [], 'ceiling', NaN);
        end

        %% run - Every shared check of traces Y (K x N) at times t (s)
        function Q = run(Y, t, o, Q)
            if nargin < 4 || isempty(Q), Q = QualityChecks.none(); end
            o = PerfusionChecks.complete(o);
            t = double(t(:)');
            dt = PerfusionChecks.interval(t);
            Q = PerfusionChecks.trials(Q, o);
            Q = PerfusionChecks.trialBaseline(Q, dt, o);
            Q = PerfusionChecks.timeResolution(Q, dt, o);
            Q = PerfusionChecks.drift(Q, Y, t, o);
            Q = PerfusionChecks.artefacts(Q, Y, t, o);
            Q = PerfusionChecks.stuck(Q, Y, o);
        end

        %% drift - Baseline drift (%/min) before the first stimulus or across trial baselines
        function Q = drift(Q, Y, t, o)
            o = PerfusionChecks.complete(o);
            K = size(Y, 1);
            rate = NaN(K, 1); how = repmat({''}, K, 1); span = NaN(K, 1); nb = zeros(K, 1);
            for k = 1:K
                [rate(k), how{k}, span(k), nb(k)] = PerfusionChecks.driftRate(Y(k, :), t, o);
            end
            ok = isfinite(rate);
            if ~any(ok)
                if any(isfinite(Y(:)))
                    Q = QualityChecks.add(Q, 'note', 'Baseline drift', sprintf(['Too short to judge the drift: ' ...
                        'less than %g s before the first stimulus and fewer than 4 trials over %g s.'], ...
                        PerfusionChecks.DriftMinSec, PerfusionChecks.DriftTrialSec), '', ...
                        sprintf('Record at least %g s of baseline before the first stimulus.', PerfusionChecks.DriftMinSec));
                end
                return;
            end
            [worst, kw] = max(abs(rate) .* ok);
            where = PerfusionChecks.driftWhere(how{kw}, span(kw), nb(kw));
            list = PerfusionChecks.nameValues(o, find(ok), rate(ok), '%+.1f%%/min');
            if worst > PerfusionChecks.DriftCheck
                level = 'check';
                if worst > PerfusionChecks.DriftWarning, level = 'warning'; end
                Q = QualityChecks.add(Q, level, 'Baseline drift', sprintf('The baseline drifts by %s (%s).', ...
                    list, where), ['Drift moves the baseline under the responses: the % change of each trial and ' ...
                    'the average shift with it.'], ['Let the signal settle before the first stimulus; check that ' ...
                    'the probe holder, the head or the camera do not move; a high-pass filter well below the ' ...
                    'response (< 0.02 Hz) removes slow drift.']);
            else
                Q = QualityChecks.add(Q, 'ok', 'Baseline drift', sprintf('Baseline drift %s (%s; check above %g%%/min).', ...
                    list, where, PerfusionChecks.DriftCheck));
            end
        end

        %% artefacts - Movement artefacts: jumps away from the moving median
        function Q = artefacts(Q, Y, t, o)
            o = PerfusionChecks.complete(o);
            t = double(t(:)');
            K = size(Y, 1);
            ev = cell(K, 1);
            any0 = false;
            for k = 1:K
                if ~any(isfinite(Y(k, :))), continue; end
                any0 = true;
                ev{k} = PerfusionChecks.events(Y(k, :), t);
            end
            if ~any0, return; end
            n = cellfun(@numel, ev);
            rule = sprintf('jumps of more than %g robust SDs and %g%% of the baseline', ...
                PerfusionChecks.ArtefactSD, 100 * PerfusionChecks.ArtefactFraction);
            if ~any(n)
                Q = QualityChecks.add(Q, 'ok', 'Movement artefacts', sprintf('No movement artefacts (%s).', rule));
                return;
            end
            [inTrial, trialList] = PerfusionChecks.trialsHit(ev, o);
            parts = {};
            for k = find(n(:)')
                times = arrayfun(@(e) sprintf('%.1f', e.start), ev{k}, 'UniformOutput', false);
                if numel(times) > 5, times = [times(1:5), {'...'}]; end
                s = sprintf('%s at %s s', PerfusionChecks.plural(n(k), 'jump'), strjoin(times, ', '));
                if K > 1, s = [PerfusionChecks.traceName(o, k) ': ' s]; end
                parts{end+1} = s; %#ok<AGROW>
            end
            found = [strjoin(parts, '; ') '.'];
            if inTrial
                level = 'warning';
                found = sprintf('%s (in %s).', found(1:end-1), trialList);
            else
                level = 'check';
                found = sprintf('%s (outside the trials).', found(1:end-1));
            end
            Q = QualityChecks.add(Q, level, 'Movement artefacts', found, ...
                sprintf(['Probe, tissue or camera movement gives %s that are not flow; in a trial they enter ' ...
                'the average.'], rule), ['Look at those times in the trace; leave the trials out (cut them before ' ...
                'segmenting) and fix the probe or the head better.']);
        end

        %% stuck - Signal stuck at 0 or at the ceiling
        function Q = stuck(Q, Y, o)
            o = PerfusionChecks.complete(o);
            K = size(Y, 1);
            fz = NaN(K, 1); ft = NaN(K, 1); top = NaN(K, 1);
            for k = 1:K
                y = double(Y(k, :));
                y = y(isfinite(y));
                if isempty(y), continue; end
                fz(k) = mean(y <= 0);
                if isfinite(o.ceiling), top(k) = o.ceiling; else, top(k) = max(y); end
                ft(k) = 0;
                if max(y) > min(y)                    % a flat trace has no top to be stuck at
                    ft(k) = PerfusionChecks.topRuns(y, top(k)) / numel(y);
                end
            end
            if all(isnan(fz)), return; end
            lim = PerfusionChecks.StuckFraction;
            bad = find(fz > lim | ft > lim);
            if isempty(bad)
                Q = QualityChecks.add(Q, 'ok', 'Signal range', 'The signal is never stuck at 0 or at its top value.');
                return;
            end
            parts = {};
            for k = bad(:)'
                s = {};
                if fz(k) > lim, s{end+1} = sprintf('%.3g%% of the samples at 0 or below', 100 * fz(k)); end %#ok<AGROW>
                if ft(k) > lim, s{end+1} = sprintf('%.3g%% stuck at the top (%.4g)', 100 * ft(k), top(k)); end %#ok<AGROW>
                s = strjoin(s, ', ');
                if K > 1, s = [PerfusionChecks.traceName(o, k) ': ' s]; end
                parts{end+1} = s; %#ok<AGROW>
            end
            Q = QualityChecks.add(Q, 'warning', 'Signal range', [PerfusionChecks.upperFirst(strjoin(parts, '; ')) '.'], ...
                ['At 0 the probe has lost contact or the signal dropped out; at the top the device or the ' ...
                'export range is saturated: the true flow there is unknown.'], ['Check the probe contact and ' ...
                'the device range (gain, export limits); leave out the trials where it happens.']);
        end

        %% trials - Stimuli left out, too few trials, no stimuli
        function Q = trials(Q, o)
            o = PerfusionChecks.complete(o);
            nOn = numel(o.onsets);
            nT = numel(o.trialOnsets);
            if nOn == 0
                Q = QualityChecks.add(Q, 'note', 'Trials', ...
                    'No stimulus onsets: no trials or response map (only the traces over time).');
                return;
            end
            if nT < nOn
                Q = QualityChecks.add(Q, 'check', 'Trials', sprintf(['%d of %d stimuli were left out because ' ...
                    'their trial (%g s before to %g s after) does not fit in the recording.'], nOn - nT, nOn, ...
                    o.preSec, o.postSec), '', 'Shorten Before / After to keep them.');
            end
            if nT > 0 && nT < 3
                Q = QualityChecks.add(Q, 'check', 'Trials', sprintf('Only %d trial(s).', nT), ...
                    'The average and its SD are unreliable.', 'Record more stimuli for a clear response.');
            elseif nT >= 3
                Q = QualityChecks.add(Q, 'ok', 'Trials', sprintf('%d trials averaged.', nT));
            end
        end

        %% trialBaseline - Baseline of each trial: at least 2 s and 5 samples
        function Q = trialBaseline(Q, dt, o)
            o = PerfusionChecks.complete(o);
            if isempty(o.trialOnsets) || ~(isfinite(dt) && dt > 0), return; end
            n = round(o.preSec / dt);
            if o.preSec < 2 || n < 5
                Q = QualityChecks.add(Q, 'check', 'Trial baseline', sprintf(['The baseline of each trial is %g s ' ...
                    '(%d samples).'], o.preSec, n), ['Each trial''s % change is relative to the mean before its ' ...
                    'onset: a short baseline is noisy (vasomotion near 0.1 Hz lasts about 10 s).'], ...
                    'Keep at least 2-5 s (and 5 samples) before each onset.');
            else
                Q = QualityChecks.add(Q, 'ok', 'Trial baseline', sprintf('%g s (%d samples) before each onset.', ...
                    o.preSec, n));
            end
        end

        %% timeResolution - Sample or frame interval vs the response time course
        function Q = timeResolution(Q, dt, o, extra)
            if nargin < 4, extra = ''; end
            o = PerfusionChecks.complete(o);
            if ~(isfinite(dt) && dt > 0), return; end
            rw = o.responseSec;
            if numel(rw) ~= 2, rw = [0 o.postSec]; end
            nResp = floor((rw(2) - rw(1)) / dt + 1e-9) + 1;
            found = sprintf('One value every %s (%s)%s.', PerfusionChecks.seconds(dt), PerfusionChecks.hertz(1 / dt), extra);
            if dt > 2 || (~isempty(o.trialOnsets) && nResp < 2)
                Q = QualityChecks.add(Q, 'warning', 'Time resolution', sprintf('%s Only %d value(s) in the response window (%g-%g s).', ...
                    found(1:end-1), nResp, rw(1), rw(2)), ['A blood-flow response rises in 1-2 s and lasts a few ' ...
                    'seconds: with so few values its peak, latency and duration are not measured.'], ...
                    'Record or export at least 2 values per second (a shorter frame interval or less averaging).');
            elseif dt > 0.5
                Q = QualityChecks.add(Q, 'check', 'Time resolution', found, sprintf(['Latency and rise time are ' ...
                    'known only to within %s.'], PerfusionChecks.seconds(dt)), ...
                    'Downsample less, average fewer frames or record faster for timing measures.');
            else
                Q = QualityChecks.add(Q, 'ok', 'Time resolution', [found(1:end-1) ': enough for responses that rise in 1-2 s.']);
            end
        end

        %% events - Artefact events of one trace (start, stop in s; size)
        function ev = events(y, t)
            ev = struct('start', {}, 'stop', {}, 'size', {});
            y = double(y(:)');
            t = double(t(:)');
            okv = isfinite(y);
            if nnz(okv) < 10, return; end
            dt = PerfusionChecks.interval(t);
            w = max(5, 2 * floor(round(1 / dt) / 2) + 1);           % ~1 s, odd, >= 5 samples
            yy = y;
            yy(~okv) = median(y(okv));
            r = yy - PerfusionChecks.movingMedian(yy, t, dt, w);
            r(~okv) = 0;
            sd = 1.4826 * median(abs(r(okv) - median(r(okv))));
            base = abs(median(y(okv)));
            thr = max(PerfusionChecks.ArtefactSD * sd, PerfusionChecks.ArtefactFraction * base);
            if ~(thr > 0), return; end
            bad = abs(r) > thr;
            if ~any(bad), return; end
            idx = find(bad);
            br = [0, find(diff(idx) > w)];                          % merge flags closer than the window
            for j = 1:numel(br)
                a = idx(br(j) + 1);
                if j < numel(br), b = idx(br(j + 1)); else, b = idx(end); end
                ev(end + 1) = struct('start', t(a), 'stop', t(b), 'size', max(abs(r(a:b)))); %#ok<AGROW>
            end
        end

        %% driftRate - %/min of one trace, how it was measured, span (s), trial baselines
        function [rate, how, span, n] = driftRate(y, t, o)
            o = PerfusionChecks.complete(o);
            y = double(y(:)');
            t = double(t(:)');
            rate = NaN; how = ''; span = NaN; n = 0;
            if numel(y) ~= numel(t) || numel(y) < 3, return; end
            ons = sort(o.onsets(:)');
            if isempty(ons), pre = true(size(t)); else, pre = t < ons(1); end
            pre = pre & isfinite(y);
            if nnz(pre) >= 3 && t(find(pre, 1, 'last')) - t(find(pre, 1)) >= PerfusionChecks.DriftMinSec
                tp = t(pre); yp = y(pre);
                c = polyfit(tp - tp(1), yp, 1);
                rate = 100 * 60 * c(1) / mean(yp);
                span = tp(end) - tp(1);
                if isempty(ons), how = 'over the recording'; else, how = 'before the first stimulus'; end
                return;
            end
            to = sort(o.trialOnsets(:)');
            b = NaN(size(to));
            for j = 1:numel(to)
                in = t >= to(j) - o.preSec & t < to(j) & isfinite(y);
                if any(in), b(j) = mean(y(in)); end
            end
            okb = isfinite(b);
            n = nnz(okb);
            if n >= 4 && to(find(okb, 1, 'last')) - to(find(okb, 1)) >= PerfusionChecks.DriftTrialSec
                c = polyfit(to(okb) - to(1), b(okb), 1);
                rate = 100 * 60 * c(1) / mean(b(okb));
                span = to(find(okb, 1, 'last')) - to(find(okb, 1));
                how = 'trial baselines';
            end
        end
    end

    methods(Static, Hidden)

        %% complete - Missing settings from the defaults; trialOnsets NaN = all onsets
        function o = complete(o)
            d = PerfusionChecks.options();
            if nargin < 1 || isempty(o), o = d; end
            f = fieldnames(d);
            for k = 1:numel(f)
                if ~isfield(o, f{k}), o.(f{k}) = d.(f{k}); end
            end
            o.onsets = double(o.onsets(:)');
            o.onsets = o.onsets(isfinite(o.onsets));
            if isscalar(o.trialOnsets) && isnan(o.trialOnsets), o.trialOnsets = o.onsets; end
            o.trialOnsets = double(o.trialOnsets(:)');
            if ischar(o.names), o.names = {o.names}; end
        end

        %% interval - Median time between samples (s); NaN when unknown
        function dt = interval(t)
            t = double(t(:)');
            if numel(t) < 2, dt = NaN; return; end
            dt = median(diff(t));
        end

        %% movingMedian - ~1 s moving median; fast traces (> 40 Hz) through 50 ms block medians
        function m = movingMedian(y, t, dt, w)
            b = round(0.05 / dt);
            if b < 2
                m = movmedian(y, w);
                return;
            end
            nb = floor(numel(y) / b);
            if nb < 5
                m = movmedian(y, w);
                return;
            end
            blocks = median(reshape(y(1:nb * b), b, nb), 1);
            tc = mean(reshape(t(1:nb * b), b, nb), 1);
            mb = movmedian(blocks, max(5, 2 * floor(round(1 / (b * dt)) / 2) + 1));
            m = interp1(tc, mb, t, 'linear', 'extrap');
        end

        %% topRuns - Samples in runs of >= 3 identical values at (or above) the top
        function n = topRuns(y, top)
            at = y >= top - 1e-9 * max(abs(top), 1);
            d = diff([0, at, 0]);
            s = find(d == 1); e = find(d == -1) - 1;
            len = e - s + 1;
            n = 0;
            for j = find(len >= 3)
                if all(y(s(j):e(j)) == y(s(j))), n = n + len(j); end
            end
        end

        %% trialsHit - Whether events fall in trials, and 'trials 2 and 5'
        function [hit, txt] = trialsHit(ev, o)
            to = o.trialOnsets;
            hits = false(1, numel(to));
            for k = 1:numel(ev)
                for j = 1:numel(ev{k})
                    hits = hits | (ev{k}(j).stop >= to - o.preSec & ev{k}(j).start <= to + o.postSec);
                end
            end
            hit = any(hits);
            idx = find(hits);
            if numel(idx) == 1
                txt = sprintf('trial %d', idx);
            elseif numel(idx) > 1
                txt = sprintf('trials %s and %d', strjoin(arrayfun(@num2str, idx(1:end-1), 'UniformOutput', false), ', '), idx(end));
            else
                txt = '';
            end
        end

        %% driftWhere - 'before the first stimulus, 60 s' | 'trial baselines: 8 trials over 210 s'
        function s = driftWhere(how, span, n)
            if strcmp(how, 'trial baselines')
                s = sprintf('from the baselines of %d trials over %.0f s', n, span);
            else
                s = sprintf('%s, %.0f s', how, span);
            end
        end

        %% nameValues - '+6.6%/min' or 'Vessel +6.6%/min, Cortex +1.2%/min' (worst first, up to 3)
        function s = nameValues(o, idx, v, fmt)
            if numel(idx) == 1 && (numel(o.names) <= 1)
                s = sprintf(fmt, v(1));
                return;
            end
            [~, order] = sort(abs(v), 'descend');
            order = order(1:min(3, numel(order)));
            parts = cell(1, numel(order));
            for j = 1:numel(order)
                parts{j} = [PerfusionChecks.traceName(o, idx(order(j))) ' ' sprintf(fmt, v(order(j)))];
            end
            s = strjoin(parts, ', ');
            if numel(idx) > 3, s = [s ', ...']; end
        end

        function s = traceName(o, k)
            if k <= numel(o.names) && ~isempty(o.names{k})
                s = o.names{k};
            else
                s = sprintf('Trace %d', k);
            end
        end

        function s = plural(n, word)
            if n == 1, s = sprintf('1 %s', word); else, s = sprintf('%d %ss', n, word); end
        end

        function s = seconds(dt)
            if dt < 0.1
                s = sprintf('%.3g ms', 1000 * dt);
            else
                s = sprintf('%.3g s', dt);
            end
        end

        function s = hertz(f)
            s = sprintf('%.4g Hz', f);
        end

        function s = upperFirst(s)
            if ~isempty(s), s(1) = upper(s(1)); end
        end
    end
end
