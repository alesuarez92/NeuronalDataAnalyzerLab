%% LDFPipeline.m
% =========================================================================
% LDF PIPELINE - HEADLESS DOWNSAMPLING, FILTERING AND TRIAL SEGMENTATION
% =========================================================================
% The computations behind LDF Processing (ProcessingLDFApp), without any
% window, so scripts and batch processing get exactly the same numbers as
% the app. ProcessingLDFApp calls these functions.
%
%   p = LDFPipeline.defaultParams()
%       Processing settings as LDFProcessingParamsApp returns them
%       (downsample 1, filterType 1 = none, designType 1, filterOrder 4,
%       cutoffLow / cutoffHigh NaN) plus the segmentation settings of the
%       app's step 3 (threshold 0.5, preSec 2, postSec 4, minISI 1 s).
%   s = LDFPipeline.loadCropped(filePath)
%       Loads a cropped LDF .mat (as saved by Extract LDF: stim, LDF, t,
%       Fs). Throws 'NeuroAnalyzer:LDFPipeline:missingVars' when a
%       variable is missing (message lists them).
%   msg = LDFPipeline.validateProcessing(p, Fs)
%       '' when the filter settings are usable at the post-downsample
%       rate, else the message the app shows (cutoff >= Nyquist, low >=
%       high for band-pass / notch, order <= 0).
%   [LDF, stim, t, Fs, b, a] = LDFPipeline.process(LDF, stim, t, Fs, p)
%       Downsample and filter. The LDF is decimated (decimate: anti-alias
%       low-pass + downsample, length ceil(N/r), orientation kept); the
%       TTL stimulus keeps the maximum of each block of r samples
%       (downsampleTrigger: pulses shorter than r are not lost), the time
%       vector is sample-picked (downsample), and all three are trimmed
%       to a common length; Fs becomes Fs/r.
%       The filter (p.filterType 1 none, 2 low-pass, 3 high-pass,
%       4 band-pass, 5 notch/band-stop; p.designType 1 Butterworth,
%       2 Chebyshev I with 0.5 dB ripple, 3 FIR (fir1)) is designed at the
%       new rate with cutoffs in Hz (cutoffLow / cutoffHigh) and applied
%       zero-phase (filtfilt). b, a: filter coefficients ([] when no
%       filter). Does not validate: call validateProcessing first.
%   mode = LDFPipeline.filterMode(filterType)
%       'low' | 'high' | 'bandpass' | 'stop' (butter / cheby1 / fir1 mode).
%   onsets = LDFPipeline.detectOnsets(stim, Fs, threshold, minISI)
%       Sample indices (row) of the rising edges of stim > threshold; an
%       edge is kept only if at least round(minISI * Fs) samples after the
%       last accepted one (debounces pulse trains). [] when none.
%   [seg, tSeg, onsets, bounds] = LDFPipeline.segment(ldf, stim, Fs, threshold, preSec, postSec, minISI)
%       Cuts one trial per onset from onset - round(preSec*Fs) to onset +
%       round(postSec*Fs) samples. Trials that do not fit completely in
%       the recording are skipped. seg: trials x samples (0 rows when no
%       trial fits), tSeg = (-preSamp:postSamp) / Fs (s, 0 = onset),
%       onsets: all accepted onsets (samples), bounds: [start end] sample
%       of each kept trial.
%   r = LDFPipeline.run(LDF, stim, t, Fs, p)
%       process + segment in one call. r: segmentedLDF, segmentedTime, Fs
%       (after downsampling), onsets (samples of the processed signal),
%       nOnsets, nTrials, LDF, stim, t (processed signals). Throws
%       'NeuroAnalyzer:LDFPipeline:invalidFilter' (validateProcessing
%       message) or 'NeuroAnalyzer:LDFPipeline:noTrials'.
%
% Requires the Signal Processing Toolbox when downsampling (decimate,
% downsample) or filtering (butter, cheby1, fir1, filtfilt).
% =========================================================================

classdef LDFPipeline
    methods(Static)

        %% defaultParams - Processing (none) + segmentation defaults of the app
        function p = defaultParams()
            p = struct('downsample', 1, 'filterType', 1, 'designType', 1, 'filterOrder', 4, ...
                'cutoffLow', NaN, 'cutoffHigh', NaN, ...
                'threshold', 0.5, 'preSec', 2, 'postSec', 4, 'minISI', 1);
        end

        %% loadCropped - Load and validate a cropped LDF .mat (stim, LDF, t, Fs)
        function s = loadCropped(filePath)
            s = load(filePath);
            required = {'stim', 'LDF', 't', 'Fs'};
            missing = required(~isfield(s, required));
            if ~isempty(missing)
                error('NeuroAnalyzer:LDFPipeline:missingVars', ...
                    'Invalid LDF file. Missing variable(s): %s.', strjoin(missing, ', '));
            end
        end

        %% validateProcessing - '' or the reason the filter settings are unusable
        function msg = validateProcessing(p, Fs)
            msg = '';
            FsNew = Fs;
            if p.downsample > 1, FsNew = Fs / p.downsample; end
            if p.filterType ~= 1
                if any([p.cutoffLow, p.cutoffHigh] >= FsNew/2)
                    msg = sprintf('Cutoff frequency must be below Nyquist (Fs/2 = %g Hz).', FsNew/2);
                elseif p.cutoffLow >= p.cutoffHigh && ismember(p.filterType, [4, 5])
                    msg = 'For band-pass and notch filters, Low cutoff must be < High cutoff.';
                elseif p.filterOrder <= 0 || isnan(p.filterOrder)
                    msg = 'Filter order must be a positive number.';
                end
            end
        end

        %% process - Decimate LDF (sample-pick stim, t), then zero-phase filter
        function [LDF, stim, t, Fs, b, a] = process(LDF, stim, t, Fs, p)
            % Downsample
            if p.downsample > 1
                % decimate = anti-alias lowpass + downsample (length ceil(N/r))
                LDFdec = decimate(double(LDF(:)), p.downsample);
                if isrow(LDF), LDFdec = LDFdec.'; end  % keep original orientation
                LDF = LDFdec;
                % Stim is a TTL: keep the maximum of each block of samples, so
                % pulses shorter than the factor are not lost (edges stay sharp)
                stim = LDFPipeline.downsampleTrigger(stim, p.downsample);
                t = downsample(t, p.downsample);
                n = min([numel(LDF), numel(stim), numel(t)]);
                LDF = LDF(1:n); stim = stim(1:n); t = t(1:n);
                Fs = Fs / p.downsample;
            end

            % Filter (skip if no filtering)
            b = []; a = [];
            if p.filterType ~= 1
                Wn = [];  % Normalized cutoff
                switch p.filterType
                    case 2  % Low-pass
                        Wn = p.cutoffHigh / (Fs/2);
                    case 3  % High-pass
                        Wn = p.cutoffLow / (Fs/2);
                    case 4  % Band-pass
                        Wn = [p.cutoffLow p.cutoffHigh] / (Fs/2);
                    case 5  % Notch
                        Wn = [p.cutoffLow p.cutoffHigh] / (Fs/2);
                end
                mode = LDFPipeline.filterMode(p.filterType);
                switch p.designType
                    case 1  % Butterworth
                        [b, a] = butter(p.filterOrder, Wn, mode);
                    case 2  % Chebyshev I
                        [b, a] = cheby1(p.filterOrder, 0.5, Wn, mode);
                    case 3  % FIR
                        b = fir1(p.filterOrder, Wn, mode);
                        a = 1;
                end
                % Apply filter (zero-phase)
                LDF = filtfilt(b, a, LDF);
            end
        end

        %% downsampleTrigger - Downsample a trigger without losing short pulses
        % Output sample k is the maximum of the r input samples ending at
        % input sample (k-1)*r + 1, the sample plain downsampling keeps
        % (sample 1 alone for k = 1). Long pulses give the same onsets as
        % downsample(stim, r); pulses shorter than r samples, which plain
        % downsampling can skip, still appear. Length ceil(N / r),
        % orientation kept. Base MATLAB.
        function y = downsampleTrigger(stim, r)
            x = double(stim(:));
            n = numel(x);
            m = ceil(n / r);
            padded = [-Inf(r - 1, 1); x; -Inf(m * r - n, 1)];
            y = max(reshape(padded(1:m * r), r, m), [], 1);
            if iscolumn(stim), y = y(:); end
        end

        %% filterMode - filterType index -> butter/cheby1/fir1 mode string
        function mode = filterMode(filterType)
            switch filterType
                case 2
                    mode = 'low';
                case 3
                    mode = 'high';
                case 4
                    mode = 'bandpass';
                case 5
                    mode = 'stop';
                otherwise
                    mode = 'low';
            end
        end

        %% detectOnsets - Debounced rising edges of stim > threshold (samples)
        function onsets = detectOnsets(stim, Fs, threshold, minISI)
            stimLogic = stim > threshold;
            stimLogic = stimLogic(:);  % ensure column vector
            rawOnsets = find(diff([0; stimLogic]) == 1);  % all rising edges
            % Debounce: only keep one onset per pulse
            minISI_samp = round(minISI * Fs);
            onsets = [];
            lastAccepted = -inf;
            for i = 1:length(rawOnsets)
                if rawOnsets(i) - lastAccepted >= minISI_samp
                    onsets(end+1) = rawOnsets(i); %#ok<AGROW>
                    lastAccepted = rawOnsets(i);
                end
            end
        end

        %% segment - Cut [-pre, +post] trials around each onset (complete ones only)
        function [seg, tSeg, onsets, bounds] = segment(ldf, stim, Fs, threshold, preSec, postSec, minISI)
            onsets = LDFPipeline.detectOnsets(stim, Fs, threshold, minISI);
            preSamp = round(preSec * Fs);
            postSamp = round(postSec * Fs);
            segLength = preSamp + postSamp + 1;

            bounds = zeros(0, 2);
            for i = 1:length(onsets)
                idx = onsets(i);
                startIdx = idx - preSamp;
                endIdx = idx + postSamp;
                if startIdx > 0 && endIdx <= length(ldf)
                    bounds = [bounds; startIdx endIdx]; %#ok<AGROW>
                end
            end

            nTrials = size(bounds, 1);
            seg = zeros(nTrials, segLength);
            for i = 1:nTrials
                seg(i,:) = ldf(bounds(i,1):bounds(i,2));
            end
            tSeg = (-preSamp:postSamp) / Fs;
        end

        %% run - Process and segment one recording (throws when nothing to keep)
        function r = run(LDF, stim, t, Fs, p)
            d = LDFPipeline.defaultParams();
            fn = fieldnames(d);
            for i = 1:numel(fn)
                if ~isfield(p, fn{i}), p.(fn{i}) = d.(fn{i}); end
            end
            msg = LDFPipeline.validateProcessing(p, Fs);
            if ~isempty(msg)
                error('NeuroAnalyzer:LDFPipeline:invalidFilter', '%s', msg);
            end
            [LDF, stim, t, Fs] = LDFPipeline.process(LDF, stim, t, Fs, p);
            [seg, tSeg, onsets] = LDFPipeline.segment(LDF, stim, Fs, p.threshold, p.preSec, p.postSec, p.minISI);
            if isempty(seg)
                if isempty(onsets)
                    error('NeuroAnalyzer:LDFPipeline:noTrials', ...
                        'No stimulus onsets found above threshold %g.', p.threshold);
                end
                error('NeuroAnalyzer:LDFPipeline:noTrials', ...
                    '%d onsets found, but no complete trial fits with Pre = %g s and Post = %g s.', ...
                    numel(onsets), p.preSec, p.postSec);
            end
            r = struct('segmentedLDF', seg, 'segmentedTime', tSeg, 'Fs', Fs, ...
                'onsets', onsets, 'nOnsets', numel(onsets), 'nTrials', size(seg, 1), ...
                'LDF', LDF, 'stim', stim, 't', t);
        end
    end
end
