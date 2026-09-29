%% SignalFeatures.m
% =========================================================================
% SIGNAL FEATURES - EXTRACT RESPONSE FEATURES FROM PROCESSED SIGNALS
% =========================================================================
% Static helpers for signal characterization: FWHM, peak latency, onset
% delay, areas under the curve (positive/negative), rise/decay times,
% peak amplitude, and stimulation-response integration. All methods assume
% time vector t (seconds) and signal y; optional baseline value. Used by
% SignalCharacterizationApp.
%
% Conventions shared by every method:
%   t0        - stimulus onset (s). The response is searched for t >= t0.
%   direction - 'max' (positive-going response) or 'min' (negative-going).
%   baseline  - scalar reference level. When omitted or empty, it is the
%               mean of the pre-stimulus samples (t < t0); if there are
%               none, the mean of the first 5 post-onset samples.
% Features that cannot be computed (no samples after t0, response never
% crosses the required level) return NaN rather than erroring.
% =========================================================================

classdef SignalFeatures
    methods(Static)
        %% peakLatency - Time from t0 to maximum (or minimum) value
        % t, y: vectors; t0: optional start time (e.g. stimulus onset). direction: 'max' or 'min'
        % OUTPUT: lat - latency (s) relative to t0; amp - raw peak value (not baseline-corrected)
        function [lat, amp] = peakLatency(t, y, t0, direction)
            if nargin < 3 || isempty(t0), t0 = t(1); end
            if nargin < 4, direction = 'max'; end
            [t_, y_] = SignalFeatures.window(t, y, t0);
            if isempty(t_), lat = NaN; amp = NaN; return; end
            [amp, i] = SignalFeatures.extremum(y_, direction);
            lat = t_(i) - t0;
        end

        %% onsetDelay - Time from t0 until the response first reaches frac of its peak
        % frac is measured from baseline to peak (0.5 = 50% of peak amplitude).
        function delay = onsetDelay(t, y, t0, frac, direction, baseline)
            if nargin < 4 || isempty(frac), frac = 0.5; end
            if nargin < 5, direction = 'max'; end
            if nargin < 6, baseline = []; end
            [t_, y_] = SignalFeatures.window(t, y, t0);
            if isempty(t_), delay = NaN; return; end
            base = SignalFeatures.resolveBaseline(t, y, t0, baseline);
            [amp, iPk] = SignalFeatures.extremum(y_, direction);
            thr = base + frac * (amp - base);
            cross = SignalFeatures.firstReach(y_(1:iPk), thr, direction);
            if isempty(cross), delay = NaN; return; end
            delay = t_(cross) - t0;
        end

        %% fwhm - Full width at half maximum (s) of the response lobe containing the peak
        % Half maximum is halfway between baseline and peak. Only the contiguous
        % run of samples around the peak counts, so later unrelated excursions
        % do not inflate the width.
        function w = fwhm(t, y, t0, direction, baseline)
            if nargin < 4, direction = 'max'; end
            if nargin < 5, baseline = []; end
            [t_, y_] = SignalFeatures.window(t, y, t0);
            if isempty(t_), w = NaN; return; end
            base = SignalFeatures.resolveBaseline(t, y, t0, baseline);
            [amp, iPk] = SignalFeatures.extremum(y_, direction);
            if amp == base, w = NaN; return; end
            half = base + 0.5 * (amp - base);
            [i1, i2] = SignalFeatures.lobe(y_, iPk, half, direction);
            w = t_(i2) - t_(i1);
        end

        %% aucPositive - Area under the curve for y > baseline (trapz)
        function a = aucPositive(t, y, baseline)
            if nargin < 3 || isempty(baseline), baseline = SignalFeatures.defaultAucBaseline(y); end
            y_ = y - baseline;
            y_(y_ < 0) = 0;
            a = trapz(t, y_);
        end

        %% aucNegative - Area under the curve for y < baseline (absolute value)
        function a = aucNegative(t, y, baseline)
            if nargin < 3 || isempty(baseline), baseline = SignalFeatures.defaultAucBaseline(y); end
            y_ = baseline - y;
            y_(y_ < 0) = 0;
            a = trapz(t, y_);
        end

        %% riseTime - Time from 10% to 90% of the baseline-to-peak amplitude (from t0)
        % Both crossings are searched on the rising edge, i.e. before the peak.
        function rt = riseTime(t, y, t0, direction, baseline)
            if nargin < 4, direction = 'max'; end
            if nargin < 5, baseline = []; end
            [t_, y_] = SignalFeatures.window(t, y, t0);
            if isempty(t_), rt = NaN; return; end
            base = SignalFeatures.resolveBaseline(t, y, t0, baseline);
            [amp, iPk] = SignalFeatures.extremum(y_, direction);
            if amp == base, rt = NaN; return; end
            rising = y_(1:iPk);
            iLo = SignalFeatures.firstReach(rising, base + 0.1 * (amp - base), direction);
            iHi = SignalFeatures.firstReach(rising, base + 0.9 * (amp - base), direction);
            if isempty(iLo) || isempty(iHi), rt = NaN; return; end
            rt = t_(iHi) - t_(iLo);
        end

        %% decayTime - Time from peak to 50% return toward baseline (after t0)
        function dt = decayTime(t, y, t0, direction, baseline)
            if nargin < 4, direction = 'max'; end
            if nargin < 5, baseline = []; end
            [t_, y_] = SignalFeatures.window(t, y, t0);
            if isempty(t_), dt = NaN; return; end
            base = SignalFeatures.resolveBaseline(t, y, t0, baseline);
            [amp, iPk] = SignalFeatures.extremum(y_, direction);
            if amp == base, dt = NaN; return; end
            half = base + 0.5 * (amp - base);
            % Decay = first sample after the peak that falls back past half.
            if strcmpi(direction, 'min')
                back = find(y_(iPk:end) >= half, 1);
            else
                back = find(y_(iPk:end) <= half, 1);
            end
            if isempty(back), dt = NaN; return; end
            dt = t_(iPk + back - 1) - t_(iPk);
        end

        %% peakAmplitude - Max or min value relative to baseline (after t0)
        function [amp, tPeak] = peakAmplitude(t, y, t0, direction, baseline)
            if nargin < 4, direction = 'max'; end
            if nargin < 5, baseline = []; end
            [t_, y_] = SignalFeatures.window(t, y, t0);
            if isempty(t_), amp = NaN; tPeak = NaN; return; end
            base = SignalFeatures.resolveBaseline(t, y, t0, baseline);
            [v, i] = SignalFeatures.extremum(y_, direction);
            amp = v - base;
            tPeak = t_(i);
        end

        %% stimResponseIntegration - Integral of the response from t0 (trapz)
        % stim is accepted for API compatibility but not used: the value is
        % the integral of response over t >= t0.
        function val = stimResponseIntegration(t, stim, response, t0) %#ok<INUSL>
            if nargin < 4 || isempty(t0), t0 = t(1); end
            idx = t >= t0;
            if nnz(idx) < 2, val = NaN; return; end
            val = trapz(t(idx), response(idx));
        end
    end

    methods(Static, Access = private)
        %% window - Samples with t >= t0, as column vectors
        function [t_, y_] = window(t, y, t0)
            t = t(:); y = y(:);
            idx = t >= t0;
            t_ = t(idx); y_ = y(idx);
        end

        %% resolveBaseline - Explicit baseline, else pre-onset mean, else first post-onset samples
        function base = resolveBaseline(t, y, t0, baseline)
            if ~isempty(baseline) && isfinite(baseline)
                base = baseline;
                return;
            end
            t = t(:); y = y(:);
            pre = y(t < t0);
            if ~isempty(pre)
                base = mean(pre);
            else
                post = y(t >= t0);
                base = mean(post(1:min(5, numel(post))));
            end
        end

        %% defaultAucBaseline - Mean of the first 10% of samples (at least one)
        function base = defaultAucBaseline(y)
            n = max(1, round(numel(y) / 10));
            base = mean(y(1:min(n, numel(y))));
        end

        %% extremum - Peak value and index for the requested direction
        function [v, i] = extremum(y, direction)
            if strcmpi(direction, 'min')
                [v, i] = min(y);
            else
                [v, i] = max(y);
            end
        end

        %% firstReach - First index where y reaches level in the response direction
        function i = firstReach(y, level, direction)
            if strcmpi(direction, 'min')
                i = find(y <= level, 1);
            else
                i = find(y >= level, 1);
            end
        end

        %% lobe - Contiguous index range around iPk where y stays past level
        function [i1, i2] = lobe(y, iPk, level, direction)
            if strcmpi(direction, 'min')
                past = y <= level;
            else
                past = y >= level;
            end
            i1 = iPk;
            while i1 > 1 && past(i1 - 1), i1 = i1 - 1; end
            i2 = iPk;
            while i2 < numel(y) && past(i2 + 1), i2 = i2 + 1; end
        end
    end
end
