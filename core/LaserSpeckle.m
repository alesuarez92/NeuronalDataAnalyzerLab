%% LaserSpeckle.m
% =========================================================================
% LASER SPECKLE - CONTRAST, FLOW INDEX AND STIMULUS RESPONSES (NO WINDOW)
% =========================================================================
% The computations behind the Laser speckle window (LSCIAnalysisApp),
% without any window, so scripts, batch processing and tests get exactly
% the same numbers.
%
% Laser speckle contrast imaging (LSCI): a surface lit by a laser shows a
% grainy speckle pattern; moving red blood cells blur it during the camera
% exposure, so the local contrast K = sigma / mean of the intensity drops
% where blood flows faster (Briers & Webster 1996; Boas & Dunn 2010).
%
%   p = LaserSpeckle.defaults()
%       InputType  'raw' (speckle images) | 'contrast' (K images) |
%                  'flow' (perfusion / flux images from a commercial system)
%       Contrast   'spatial' (Window x Window pixels in each frame) |
%                  'temporal' (each pixel over Frames frames)
%       Window     7 (px, odd, 3-31)       Frames  1 (spatial: average K^2
%                  over this many frames; temporal: frames per K image, >= 3)
%       Dark       0 (camera dark level subtracted from raw intensities)
%       FlowModel  'invK2' (1/K^2, the speckle flow index) | 'tauc'
%                  (1/tau_c from the exposure model, needs ExposureMs)
%       Beta       1 (coherence factor of the model, 0 < Beta <= 1)
%       ExposureMs NaN (camera exposure, ms; needed by 'tauc')
%       Fps        NaN (frame rate of the images; from t when empty)
%       Onsets     [] (stimulus onsets, s)   PreSec 5   PostSec 15
%       ResponseSec [2 6] (window after onset for the response map, s)
%       BaselineSec [] (window for the continuous rCBF trace, s; [] = from
%                  the start to the first onset, or the whole recording)
%   [K2, tOut, info] = LaserSpeckle.contrastSquared(I, t, p)
%       Speckle contrast squared (H x W x M) of raw images I (H x W x N),
%       time of each output frame (s) and info (nIn, nOut, fps, fpsOut).
%   K = LaserSpeckle.spatialContrast(I, win)   per frame, windows cut at
%       the borders; NaN where the local mean is <= 0 or < 2 pixels.
%   K = LaserSpeckle.temporalContrast(I, n)    per pixel, non-overlapping
%       blocks of n frames (H x W x floor(N / n)).
%   g = LaserSpeckle.modelK2(x, beta)
%       K^2 of the exposure model beta * (exp(-2x) - 1 + 2x) / (2 x^2),
%       x = T / tau_c (Bandyopadhyay et al. 2005; Boas & Dunn 2010).
%   x = LaserSpeckle.invertModel(K2, beta)     x = T / tau_c from K^2
%       (inverse of modelK2 by interpolation on a fine log grid; K^2 >= beta
%       gives 0, no motion).
%   F = LaserSpeckle.flowFromK2(K2, p)         flow index: 1 ./ K2 ('invK2')
%       or 1 / tau_c in 1/s ('tauc')
%   R = LaserSpeckle.analyze(I, t, masks, p)
%       Everything the window shows: R.t (s), R.fps, R.flowMean (mean flow
%       map), R.K2Mean, R.meanImage, R.roiFlow (K x M, flow index per ROI),
%       R.roiRel (K x M, flow relative to the baseline window, 1 = baseline),
%       R.onsets (used, s), R.trialTime (1 x S, s from onset), R.trials
%       (K x nTrials x S, % change from each trial's pre-stimulus mean),
%       R.trialMean / R.trialSD (K x S), R.response (K x 1, mean % change
%       of the average trial in ResponseSec: robust to noise), R.peak (K x 1,
%       %, largest value of the average trial after onset: noise adds to
%       it) and R.peakTime (K x 1, s), R.responseMap (H x W, % change in
%       ResponseSec vs the pre-stimulus window), R.units, R.checks
%       (plain-language checks, cellstr) and R.params.
%   onsets = LaserSpeckle.onsetsFromStimulus(stim, t, minISI)
%       Rising edges of a stimulus trace (mid-range threshold, crossings
%       closer than minISI s to the last kept one are ignored), in s.
%   c = LaserSpeckle.checks(I, p, R)           plain-language quality checks
%   s = LaserSpeckle.flowLabel(p)              axis label of the flow index
%
% Errors: NeuroAnalyzer:LaserSpeckle:input, :window, :frames, :exposure,
% :beta, :masks. Base MATLAB only (conv2, interp1); also runs in GNU Octave.
% =========================================================================

classdef LaserSpeckle
    properties(Constant)
        GridLogX = linspace(-12, 12, 24001)   % log(x) grid for invertModel
    end

    methods(Static)

        %% defaults - Settings of the window on first open
        function p = defaults()
            p = struct('InputType', 'raw', 'Contrast', 'spatial', 'Window', 7, 'Frames', 1, ...
                'Dark', 0, 'FlowModel', 'invK2', 'Beta', 1, 'ExposureMs', NaN, 'Fps', NaN, ...
                'Onsets', [], 'PreSec', 5, 'PostSec', 15, 'ResponseSec', [2 6], 'BaselineSec', []);
        end

        %% spatialContrast - sigma / mean over a win x win neighbourhood, frame by frame
        function K = spatialContrast(I, win)
            LaserSpeckle.checkWindow(win);
            [H, W, N] = size(I);
            K = zeros(H, W, N);
            k = ones(win);
            cnt = conv2(ones(H, W), k, 'same');
            for n = 1:N
                f = double(I(:, :, n));
                s1 = conv2(f, k, 'same');
                s2 = conv2(f .^ 2, k, 'same');
                m = s1 ./ cnt;
                v = (s2 - s1 .^ 2 ./ cnt) ./ max(cnt - 1, 1);
                kk = sqrt(max(v, 0)) ./ m;
                kk(m <= 0 | cnt < 2) = NaN;
                K(:, :, n) = kk;
            end
        end

        %% temporalContrast - sigma / mean of each pixel over blocks of n frames
        function K = temporalContrast(I, n)
            if ~isscalar(n) || n < 3 || n ~= round(n)
                error('NeuroAnalyzer:LaserSpeckle:frames', ...
                    'Temporal contrast needs at least 3 frames per contrast image (got %g).', n);
            end
            [H, W, N] = size(I);
            M = floor(N / n);
            if M < 1
                error('NeuroAnalyzer:LaserSpeckle:frames', ...
                    'Temporal contrast over %d frames needs at least %d frames (the stack has %d).', n, n, N);
            end
            K = zeros(H, W, M);
            for b = 1:M
                blk = double(I(:, :, (b - 1) * n + (1:n)));
                m = mean(blk, 3);
                s = std(blk, 0, 3);
                kk = s ./ m;
                kk(m <= 0) = NaN;
                K(:, :, b) = kk;
            end
        end

        %% contrastSquared - K^2 images of raw frames (spatial or temporal), after the dark level
        function [K2, tOut, info] = contrastSquared(I, t, p)
            p = LaserSpeckle.complete(p);
            N = size(I, 3);
            [t, fps] = LaserSpeckle.timeAxis(t, N, p.Fps);
            I = LaserSpeckle.subtractDark(I, p.Dark);
            n = max(1, round(p.Frames));
            switch lower(p.Contrast)
                case 'temporal'
                    K = LaserSpeckle.temporalContrast(I, n);
                    K2 = K .^ 2;
                    tOut = LaserSpeckle.blockMean(t, n, size(K2, 3));
                otherwise
                    K2 = LaserSpeckle.spatialContrast(I, p.Window) .^ 2;
                    tOut = t;
                    if n > 1
                        M = floor(N / n);
                        if M < 1
                            error('NeuroAnalyzer:LaserSpeckle:frames', ...
                                'Averaging %d frames needs at least %d frames (the stack has %d).', n, n, N);
                        end
                        K2 = LaserSpeckle.blockAverage(K2, n);
                        tOut = LaserSpeckle.blockMean(t, n, M);
                    end
            end
            info = struct('nIn', N, 'nOut', size(K2, 3), 'fps', fps, ...
                'fpsOut', fps / n, 'framesPerValue', n);
        end

        %% modelK2 - K^2 of the exposure model for x = T / tau_c
        function g = modelK2(x, beta)
            if nargin < 2, beta = 1; end
            x = double(x);
            g = ones(size(x));
            big = x >= 1e-3;
            xb = x(big);
            g(big) = (expm1(-2 * xb) + 2 * xb) ./ (2 * xb .^ 2);
            xs = x(~big & x > 0);
            g(~big & x > 0) = 1 - (2 / 3) * xs + (1 / 3) * xs .^ 2;   % series, avoids cancellation
            g = beta * g;
        end

        %% invertModel - x = T / tau_c such that modelK2(x, beta) = K2
        function x = invertModel(K2, beta)
            if nargin < 2, beta = 1; end
            if ~isscalar(beta) || ~(beta > 0 && beta <= 1)
                error('NeuroAnalyzer:LaserSpeckle:beta', 'Beta must be between 0 and 1 (got %g).', beta);
            end
            lx = LaserSpeckle.GridLogX;
            lg = log(LaserSpeckle.modelK2(exp(lx), 1));      % decreasing in x
            r = double(K2) / beta;
            x = NaN(size(r));
            ok = isfinite(r) & r > 0;
            x(ok & r >= 1) = 0;                                % no decorrelation: no flow
            in = ok & r < 1;
            lr = log(r(in));
            lr = min(max(lr, lg(end)), lg(1));                 % beyond the grid: clamp
            x(in) = exp(interp1(fliplr(lg), fliplr(lx), lr, 'linear'));
        end

        %% flowFromK2 - Flow index from K^2 ('invK2': 1/K^2; 'tauc': 1/tau_c in 1/s)
        function F = flowFromK2(K2, p)
            p = LaserSpeckle.complete(p);
            switch lower(p.FlowModel)
                case 'tauc'
                    T = p.ExposureMs / 1000;
                    if ~(isfinite(T) && T > 0)
                        error('NeuroAnalyzer:LaserSpeckle:exposure', ...
                            'The correlation-time model needs the camera exposure time (ms).');
                    end
                    F = LaserSpeckle.invertModel(K2, p.Beta) / T;
                otherwise
                    F = 1 ./ double(K2);
                    F(~isfinite(F)) = NaN;
            end
        end

        %% analyze - Flow index, ROI traces, trials, response map and checks
        function R = analyze(I, t, masks, p)
            p = LaserSpeckle.complete(p);
            [H, W, N] = size(I);
            if N < 1 || ~isnumeric(I)
                error('NeuroAnalyzer:LaserSpeckle:input', 'The images must be a numeric H x W x N stack.');
            end
            if nargin < 3 || isempty(masks), masks = true(H, W); end
            masks = logical(masks);
            if size(masks, 1) ~= H || size(masks, 2) ~= W
                error('NeuroAnalyzer:LaserSpeckle:masks', 'Each ROI mask must be %d x %d (H x W).', H, W);
            end
            nR = size(masks, 3);
            R = struct();
            R.params = p;
            R.meanImage = mean(double(I), 3);

            % --- Values that average linearly: K^2 (raw / contrast) or the flow itself ---
            switch lower(p.InputType)
                case 'raw'
                    [V, R.t, info] = LaserSpeckle.contrastSquared(I, t, p);
                    R.fps = info.fpsOut;
                case 'contrast'
                    [tt, fps] = LaserSpeckle.timeAxis(t, N, p.Fps);
                    V = double(I) .^ 2;
                    n = max(1, round(p.Frames));
                    R.t = tt; R.fps = fps;
                    if n > 1 && floor(N / n) >= 1
                        V = LaserSpeckle.blockAverage(V, n);
                        R.t = LaserSpeckle.blockMean(tt, n, size(V, 3));
                        R.fps = fps / n;
                    end
                case 'flow'
                    [tt, fps] = LaserSpeckle.timeAxis(t, N, p.Fps);
                    V = double(I);
                    n = max(1, round(p.Frames));
                    R.t = tt; R.fps = fps;
                    if n > 1 && floor(N / n) >= 1
                        V = LaserSpeckle.blockAverage(V, n);
                        R.t = LaserSpeckle.blockMean(tt, n, size(V, 3));
                        R.fps = fps / n;
                    end
                otherwise
                    error('NeuroAnalyzer:LaserSpeckle:input', ...
                        'Unknown input type ''%s'' (raw, contrast or flow).', p.InputType);
            end
            isK2 = ~strcmpi(p.InputType, 'flow');
            toFlow = @(v) v;
            if isK2, toFlow = @(v) LaserSpeckle.flowFromK2(v, p); end
            M = size(V, 3);
            R.units = LaserSpeckle.flowLabel(p);

            % --- Maps ---
            vMean = mean(V, 3, 'omitnan');
            R.flowMean = toFlow(vMean);
            if isK2, R.K2Mean = vMean; else, R.K2Mean = []; end

            % --- ROI traces: average K^2 (or flow) over the ROI, then convert ---
            roiV = NaN(nR, M);
            Vr = reshape(V, H * W, M);
            for k = 1:nR
                m = masks(:, :, k);
                if ~any(m(:)), continue; end
                roiV(k, :) = mean(Vr(m(:), :), 1, 'omitnan');
            end
            R.roiFlow = toFlow(roiV);

            % --- Baseline for the continuous relative trace ---
            onsets = sort(p.Onsets(:)');
            onsets = onsets(isfinite(onsets));
            bw = p.BaselineSec;
            if isempty(bw)
                if ~isempty(onsets) && onsets(1) > R.t(1)
                    bw = [R.t(1), onsets(1)];
                else
                    bw = [R.t(1), R.t(end)];
                end
            end
            inB = R.t >= bw(1) & R.t <= bw(2);
            if ~any(inB), inB = true(1, M); end
            R.baselineSec = bw;
            R.roiRel = R.roiFlow ./ mean(R.roiFlow(:, inB), 2, 'omitnan');

            % --- Trials around each onset (% change from each trial's own pre-stimulus mean) ---
            fs = R.fps;
            nPre = round(p.PreSec * fs);
            nPost = round(p.PostSec * fs);
            R.trialTime = (-nPre:nPost) / fs;
            S = numel(R.trialTime);
            idx0 = round((onsets - R.t(1)) * fs) + 1;         % sample at each onset
            keep = idx0 - nPre >= 1 & idx0 + nPost <= M & nPre >= 1;
            R.onsets = onsets(keep);
            idx0 = idx0(keep);
            nT = numel(idx0);
            R.trials = NaN(nR, nT, S);
            inPre = R.trialTime < 0;
            for j = 1:nT
                seg = R.roiFlow(:, idx0(j) + (-nPre:nPost));
                base = mean(seg(:, inPre), 2, 'omitnan');
                R.trials(:, j, :) = reshape(100 * (seg ./ base - 1), nR, 1, S);
            end
            if nT > 0
                R.trialMean = reshape(mean(R.trials, 2, 'omitnan'), nR, S);
                if nT > 1
                    dev = R.trials - reshape(R.trialMean, nR, 1, S);
                    nOk = sum(isfinite(dev), 2);
                    dev(~isfinite(dev)) = 0;
                    R.trialSD = reshape(sqrt(sum(dev .^ 2, 2) ./ max(nOk - 1, 1)), nR, S);
                else
                    R.trialSD = zeros(nR, S);
                end
                inPost = R.trialTime > 0;
                tp = R.trialTime(inPost);
                [R.peak, ip] = max(R.trialMean(:, inPost), [], 2);
                R.peakTime = tp(ip)';
            else
                R.trialMean = NaN(nR, S); R.trialSD = NaN(nR, S);
                R.peak = NaN(nR, 1); R.peakTime = NaN(nR, 1);
            end
            R.response = NaN(nR, 1);
            rw = p.ResponseSec;
            inResp = numel(rw) == 2 & R.trialTime >= rw(1) & R.trialTime <= rw(2);
            if nT > 0 && any(inResp)
                R.response = mean(R.trialMean(:, inResp), 2, 'omitnan');
            end

            % --- Response map: mean value in the response window vs the pre-stimulus window ---
            R.responseMap = [];
            if nT > 0 && numel(rw) == 2 && rw(2) > rw(1)
                iResp = find(R.trialTime >= rw(1) & R.trialTime <= rw(2));
                iPre = find(inPre);
                if ~isempty(iResp)
                    vPre = zeros(H, W); vResp = zeros(H, W);
                    for j = 1:nT
                        vPre = vPre + mean(V(:, :, idx0(j) + iPre - nPre - 1), 3, 'omitnan');
                        vResp = vResp + mean(V(:, :, idx0(j) + iResp - nPre - 1), 3, 'omitnan');
                    end
                    R.responseMap = 100 * (toFlow(vResp / nT) ./ toFlow(vPre / nT) - 1);
                end
            end
            R.checks = LaserSpeckle.checks(I, p, R);
        end

        %% onsetsFromStimulus - Rising edges (s) of a stimulus trace sampled at times t
        function onsets = onsetsFromStimulus(stim, t, minISI)
            if nargin < 3 || isempty(minISI), minISI = 0; end
            stim = double(stim(:)');
            t = double(t(:)');
            onsets = zeros(1, 0);
            if numel(stim) < 2 || numel(t) ~= numel(stim) || max(stim) == min(stim), return; end
            thr = (min(stim) + max(stim)) / 2;
            idx = find(stim(1:end-1) < thr & stim(2:end) >= thr) + 1;
            last = -Inf;
            for i = idx
                if t(i) - last >= minISI
                    onsets(end + 1) = t(i); %#ok<AGROW>
                    last = t(i);
                end
            end
        end

        %% checks - Plain-language quality checks (what was found and why it matters)
        function c = checks(I, p, R)
            c = {};
            p = LaserSpeckle.complete(p);
            if strcmpi(p.InputType, 'raw')
                % Saturation: pixels at the top of the integer range
                if isinteger(I)
                    top = double(intmax(class(I)));
                    sat = mean(double(I(:)) >= top);
                    if sat > 0.001
                        c{end+1} = sprintf(['Warning: %.1f%% of the pixels are saturated (at %d). Saturated speckles ' ...
                            'lower the contrast and make flow look faster: reduce the laser power, the gain or the exposure.'], ...
                            100 * sat, top);
                    else
                        c{end+1} = 'OK: no saturated pixels.';
                    end
                end
                lo = double(min(I(:)));
                if p.Dark > 0 && lo < p.Dark
                    c{end+1} = sprintf(['Warning: some pixels (min %g) are below the dark level (%g): check the dark ' ...
                        'level (image the camera with the laser off).'], lo, p.Dark);
                elseif p.Dark == 0 && lo > 0
                    c{end+1} = sprintf(['Check: no dark level was subtracted (the darkest pixel is %g). A camera offset ' ...
                        'lowers the measured contrast; measure it with the laser off and type it in Dark level.'], lo);
                end
                if strcmpi(p.Contrast, 'spatial') && p.Window < 5
                    c{end+1} = sprintf(['Warning: a %d x %d window holds few speckles, so the contrast is biased low and ' ...
                        'noisy; 5 x 5 or 7 x 7 is usual.'], p.Window, p.Window);
                end
            end
            if isfield(R, 'K2Mean') && ~isempty(R.K2Mean)
                k = sqrt(R.K2Mean(isfinite(R.K2Mean)));
                if ~isempty(k)
                    mk = median(k);
                    if mk > 0.6
                        c{end+1} = sprintf(['Check: the median speckle contrast is high (K = %.2f): mostly static tissue, ' ...
                            'a very short exposure or speckles much larger than a pixel.'], mk);
                    elseif mk < 0.02
                        c{end+1} = sprintf(['Check: the median speckle contrast is very low (K = %.3f): the exposure may ' ...
                            'be too long, the speckles smaller than a pixel, or the images were already processed ' ...
                            '(choose the right "Images are" type).'], mk);
                    else
                        c{end+1} = sprintf('OK: median speckle contrast K = %.2f (typical for tissue: 0.05-0.5).', mk);
                    end
                    if any(k > 1.05)
                        c{end+1} = ['Check: some contrast values are above 1, which a speckle pattern cannot give: ' ...
                            'look for noise, edges of the image or a wrong dark level.'];
                    end
                end
            end
            if strcmpi(p.FlowModel, 'tauc')
                c{end+1} = sprintf(['Flow index = 1/tau_c from the exposure model (T = %g ms, beta = %g); relative ' ...
                    'changes do not depend on beta, absolute values do.'], p.ExposureMs, p.Beta);
            elseif ~strcmpi(p.InputType, 'flow')
                c{end+1} = ['Flow index = 1/K^2 (speckle flow index): relative changes are close to changes in flow, ' ...
                    'slightly smaller for large changes. Use the correlation-time model with the exposure for a closer estimate.'];
            end
            if isfield(R, 'onsets')
                nOn = numel(p.Onsets);
                nT = numel(R.onsets);
                if nOn == 0
                    c{end+1} = 'No stimulus onsets: no trials or response map (only the traces over time).';
                elseif nT < nOn
                    c{end+1} = sprintf(['Check: %d of %d stimuli were left out because their trial (%g s before to ' ...
                        '%g s after) does not fit in the recording.'], nOn - nT, nOn, p.PreSec, p.PostSec);
                end
                if nT > 0 && nT < 3
                    c{end+1} = sprintf(['Check: only %d trial(s): the average and its SD are unreliable; record more ' ...
                        'stimuli for a clear response.'], nT);
                elseif nT >= 3
                    c{end+1} = sprintf('OK: %d trials averaged.', nT);
                end
            end
        end

        %% flowLabel - Axis label of the flow index
        function s = flowLabel(p)
            p = LaserSpeckle.complete(p);
            if strcmpi(p.InputType, 'flow')
                s = 'Perfusion (as exported)';
            elseif strcmpi(p.FlowModel, 'tauc')
                s = '1/\tau_c (1/s)';
            else
                s = 'Flow index 1/K^2';
            end
        end
    end

    methods(Static, Hidden)

        %% complete - Fill missing settings with the defaults
        function p = complete(p)
            d = LaserSpeckle.defaults();
            if nargin < 1 || isempty(p), p = d; return; end
            f = fieldnames(d);
            for k = 1:numel(f)
                if ~isfield(p, f{k}), p.(f{k}) = d.(f{k}); end
            end
        end

        function checkWindow(win)
            if ~isscalar(win) || win < 3 || win > 31 || mod(win, 2) ~= 1
                error('NeuroAnalyzer:LaserSpeckle:window', ...
                    'The contrast window must be an odd number of pixels from 3 to 31 (got %g).', win);
            end
        end

        %% timeAxis - Frame times (s) and frame rate from t, or from fps
        function [t, fps] = timeAxis(t, N, fps)
            if ~isempty(t) && numel(t) == N && N > 1 && all(isfinite(t(:)))
                t = double(t(:)');
                fps = (N - 1) / (t(end) - t(1));
            else
                if ~(isfinite(fps) && fps > 0)
                    error('NeuroAnalyzer:LaserSpeckle:input', ...
                        'The frame rate is unknown: type it (frames per second) or give a time for each frame.');
                end
                t = (0:N-1) / fps;
            end
        end

        function I = subtractDark(I, dark)
            if isempty(dark) || (isscalar(dark) && dark == 0)
                I = double(I);
            else
                I = double(I) - double(dark);
            end
        end

        %% blockAverage - Mean of non-overlapping blocks of n frames (H x W x floor(N/n))
        function V = blockAverage(V, n)
            [H, W, N] = size(V);
            M = floor(N / n);
            V = reshape(mean(reshape(V(:, :, 1:M * n), H, W, n, M), 3, 'omitnan'), H, W, M);
        end

        function tb = blockMean(t, n, M)
            tb = mean(reshape(t(1:M * n), n, M), 1);
        end
    end
end
