%% SpikeTrains.m
% =========================================================================
% SPIKE TRAINS - STIMULUS-LOCKED RASTERS, PSTHs AND CORRELOGRAMS
% =========================================================================
% Headless analysis of spike times (s) of sorted units. All times are in
% seconds on the same clock as the stimulus.
%
%   onsets = SpikeTrains.stimulusOnsets(stim, t, threshold, minISI)
%       Rising crossings of stim above threshold (times from t); a crossing
%       within minISI s of the last kept onset is dropped (a pulse train
%       gives one onset; same rule as LDFPipeline.detectOnsets). Used by
%       "Segment by stimulation onsets" in MUA Analysis.
%   [raster, psth] = SpikeTrains.rasterPSTH(spikeTimes, onsets, window, binWidth, span)
%       window = [from to] around each onset (s), e.g. [-0.1 0.3];
%       binWidth (s). Optional span = [tStart tEnd] of the analysed
%       recording: onsets whose window does not fit inside it are left
%       out. raster: .trial and .time (s from onset) per spike, .nTrials,
%       .onsets (used), .window. psth: .edges, .centers (s), .counts
%       [nTrials x nBins], .rate (spikes/s, trial mean), .sem (spikes/s,
%       SD across trials / sqrt(nTrials)), .binWidth, .nTrials, .window.
%   [counts, centers, edges, rate] = SpikeTrains.correlogram(t1, t2, maxLag, binWidth)
%       Histogram of t2 - t1 for all spike pairs with |lag| < maxLag (s).
%       Bins are binWidth wide with an edge at 0 (e.g. [-1 0) and [0 1)
%       ms). Autocorrelogram: t2 = [] or t2 identical to t1; each spike's
%       pairing with itself (the zero-lag self-pair) is excluded, so a
%       refractory period shows as empty bins around 0. rate = counts /
%       (numel(t1) x binWidth): the rate of train 2 (spikes/s) at each lag
%       after a train-1 spike. Positive lag = t2 fires after t1.
%
% Method: the PSTH is the trial-averaged spike count per bin divided by
% the bin width (Gerstein & Kiang 1960); correlograms follow Perkel,
% Gerstein & Moore (1967). Pairs are found with sorted spike times and a
% stable merge-sort count, so the cost grows with the number of pairs
% inside the lag window rather than with the square of the spike count.
% Base MATLAB only (no toolboxes).
%
% References:
%   Gerstein GL, Kiang NY-S (1960). An approach to the quantitative
%     analysis of electrophysiological data from single neurons.
%     Biophysical Journal 1(1):15-28.
%   Perkel DH, Gerstein GL, Moore GP (1967). Neuronal spike trains and
%     stochastic point processes. I. The single spike train. II.
%     Simultaneous spike trains. Biophysical Journal 7(4):391-418, 419-440.
% =========================================================================

classdef SpikeTrains
    methods(Static)

        %% stimulusOnsets - Rising threshold crossings separated by > minISI
        function onsets = stimulusOnsets(stim, t, threshold, minISI)
            aboveThresh = stim > threshold;
            onsetIdx = find(diff([0; aboveThresh(:)]) == 1);
            onsets = t(onsetIdx(:));
            onsets = onsets(:);
            if isempty(onsets), return; end
            % Keep a crossing only if it comes more than minISI after the last
            % KEPT onset (as LDF): a pulse train gives one onset per train
            keep = false(size(onsets));
            last = -Inf;
            for i = 1:numel(onsets)
                if onsets(i) - last > minISI
                    keep(i) = true;
                    last = onsets(i);
                end
            end
            onsets = onsets(keep);
        end

        %% rasterPSTH - Spikes around each onset and their trial-averaged rate
        function [raster, psth] = rasterPSTH(spikeTimes, onsets, window, binWidth, span)
            if numel(window) ~= 2 || ~(window(2) > window(1))
                error('NeuroAnalyzer:SpikeTrains:window', 'window must be [from to] with to > from (s).');
            end
            if ~(binWidth > 0)
                error('NeuroAnalyzer:SpikeTrains:bin', 'binWidth must be positive (s).');
            end
            nBins = max(1, round((window(2) - window(1)) / binWidth));
            edges = window(1) + (0:nBins) * binWidth;
            onsets = onsets(:);
            if nargin >= 5 && ~isempty(span)
                onsets = onsets(onsets + window(1) >= span(1) & onsets + window(2) <= span(2));
            end
            st = sort(double(spikeTimes(:)));
            nTr = numel(onsets);
            % First / last spike inside [onset + from, onset + to) per trial
            lo = SpikeTrains.countBelow(st, onsets + edges(1)) + 1;
            hi = SpikeTrains.countBelow(st, onsets + edges(end));
            nPer = max(hi - lo + 1, 0);
            trial = SpikeTrains.repeatIndex(nPer);
            J = SpikeTrains.pairIndex(nPer, lo);
            rel = st(J) - onsets(trial);
            b = floor((rel - edges(1)) / binWidth) + 1;
            ok = b >= 1 & b <= nBins;
            counts = zeros(nTr, nBins);
            if any(ok)
                counts = accumarray([trial(ok), b(ok)], 1, [nTr nBins]);
            end
            % Raster = the spikes counted in the PSTH (same bins, same trials)
            raster = struct('trial', trial(ok), 'time', rel(ok), 'nTrials', nTr, ...
                'onsets', onsets, 'window', window(:)');
            if ~any(ok)
                raster.trial = zeros(0, 1); raster.time = zeros(0, 1);
            end
            rateTrials = counts / binWidth;
            if nTr > 0
                rate = mean(rateTrials, 1);
                sem = std(rateTrials, 0, 1) / sqrt(nTr);
            else
                rate = zeros(1, nBins); sem = zeros(1, nBins);
            end
            psth = struct('edges', edges, 'centers', edges(1:end-1) + binWidth / 2, ...
                'counts', counts, 'rate', rate, 'sem', sem, 'binWidth', binWidth, ...
                'nTrials', nTr, 'window', window(:)');
        end

        %% correlogram - Auto- (t2 empty or = t1) or cross-correlogram of spike times
        function [counts, centers, edges, rate] = correlogram(t1, t2, maxLag, binWidth)
            if ~(maxLag > 0) || ~(binWidth > 0)
                error('NeuroAnalyzer:SpikeTrains:correlogram', 'maxLag and binWidth must be positive (s).');
            end
            t1 = double(t1(:));
            isAuto = isempty(t2) || isequal(double(t2(:)), t1);
            nb = max(1, round(maxLag / binWidth));
            L = nb * binWidth;
            edges = (-nb:nb) * binWidth;
            centers = edges(1:end-1) + binWidth / 2;
            a = sort(t1);
            if isAuto
                b = a;
            else
                b = sort(double(t2(:)));
            end
            lo = SpikeTrains.countBelow(b, a - L) + 1;
            hi = SpikeTrains.countBelow(b, a + L);
            nPer = max(hi - lo + 1, 0);
            I = SpikeTrains.repeatIndex(nPer);
            J = SpikeTrains.pairIndex(nPer, lo);
            if isAuto
                keep = I ~= J;   % drop each spike paired with itself
                I = I(keep); J = J(keep);
            end
            lag = b(J) - a(I);
            % Bin from the lag itself so a zero lag always falls in [0, binWidth)
            k = floor(lag / binWidth) + nb + 1;
            k = k(k >= 1 & k <= 2 * nb);
            counts = zeros(1, 2 * nb);
            if ~isempty(k)
                counts = accumarray(k(:), 1, [2 * nb 1])';
            end
            rate = counts / max(numel(t1), 1) / binWidth;
        end
    end

    methods(Static, Access = private)

        %% countBelow - For each q, how many elements of sorted x are < q
        % A stable sort puts each q before x values equal to it, so the
        % number of x elements preceding q is the count strictly below.
        function c = countBelow(x, q)
            nq = numel(q);
            c = zeros(nq, 1);
            if nq == 0, return; end
            [~, ord] = sort([q(:); x(:)]);
            isQ = ord <= nq;
            nBefore = cumsum(~isQ);
            c(ord(isQ)) = nBefore(isQ);
        end

        %% repeatIndex - [1 x n(1), 2 x n(2), ...] as a column
        function I = repeatIndex(n)
            n = n(:);
            I = zeros(sum(n), 1);
            if isempty(I), return; end
            starts = cumsum([1; n(1:end-1)]);
            use = n > 0;
            I(starts(use)) = 1;
            I = cumsum(I);
            % Rows with n = 0 were skipped by the cumsum; map back to their index
            idx = find(use);
            I = idx(I);
        end

        %% pairIndex - lo(i), lo(i)+1, ..., lo(i)+n(i)-1 for each i, as a column
        function J = pairIndex(n, lo)
            n = n(:); lo = lo(:);
            I = SpikeTrains.repeatIndex(n);
            if isempty(I), J = zeros(0, 1); return; end
            firstPos = cumsum([1; n(1:end-1)]);
            J = (1:numel(I))' - firstPos(I) + lo(I);
        end
    end
end
