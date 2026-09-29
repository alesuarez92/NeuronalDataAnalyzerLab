%% MUAPipeline.m
% =========================================================================
% MUA PIPELINE - HEADLESS SPIKE DETECTION, ALIGNMENT, FEATURES, CLUSTERING
% =========================================================================
% The spike sorting used by MUA Analysis, without any window, so it can be
% scripted or run in batch on many channels / files. MUAAnalysisApp calls
% exactly this code; results are identical to the window's SpikeResults.
%
%   p = MUAPipeline.defaultParams()      default settings (see below)
%   p = MUAPipeline.completeParams(p)    fill missing fields with defaults
%   [results, info] = MUAPipeline.sort(x, t, fs, params, stageFcn)
%       x: one channel (vector), t: its time vector (s), fs: sampling rate
%       (Hz). stageFcn (optional): called with a progress message before
%       each stage. results has the fields of MUAAnalysisApp.SpikeResults:
%         segmentedMUA, segmentedTime  trace the spikes were detected on
%         waveformsAligned, waveformsRaw  snippets after / before peak
%                                      alignment (all detected spikes)
%         spikeTimes, clusterIdx       one row per spike (0 = noise)
%         waveforms                    cell, one [n x samples] per cluster
%                                      in unique(clusterIdx) order
%         isiViolationRate, snr(k), noiseSNR, rejectedClusters(k)
%       info: locs (sample index of each spike in x), threshLines
%       (thresholds on the x scale), qc (per-cluster struct: id, n, snr,
%       isiPct, isiMs, rejected, reason), waves (aligned waveform of each
%       spike, same order as clusterIdx), labelsBeforeMerge and mergeLog
%       (auto-merge; see ClusterTools.autoMerge).
%       Failures throw 'NeuroAnalyzer:MUAPipeline:<stage>' errors whose
%       message says what to change; MUAPipeline.errorTitle(id) gives a
%       short title for an alert.
%   [results, qc] = MUAPipeline.qualityMetrics(results, labels, waves, locs, t, fs, params)
%       (Re)compute per-cluster waveforms, SNR and ISI checks, e.g. after
%       merging or splitting clusters.
%
% Settings (defaultParams): detectMethod ('Standard' | 'MAD' | 'NEO' |
% 'Rolling MAD' | 'Percentile'), threshold (k), polarity ('positive' |
% 'negative' | 'both'), refractoryMs (QC only), alignWinMs, filter / bpLow
% / bpHigh (Butterworth band-pass before detection), featureMethod ('PCA'
% | 'ICA' | 'Waveform' | 'Wavelet' | 't-SNE'), numComponents, normalize,
% clusterMethod ('K-means' | 'GMM' | 'DBSCAN'), minSpikesPerCluster,
% dbscanEpsilon (NaN = auto), enableDriftCorrection, driftMethod ('Time
% Binning' | 'Dynamic Clustering'), driftBinWidth (s),
% enableGridSearchCheck, autoMerge (merge over-split clusters after
% clustering), mergeThreshold (min shape correlation, 0.95),
% mergeMinAmpRatio (min amplitude ratio, 0.85) and randomSeed (0; MUA
% Analysis sets rng(randomSeed, 'twister') before sort and restores the
% previous state after, so a window run is reproducible; sort itself does
% not touch the random generator, callers such as Batch seed it).
%
% Method: threshold detection (dead time 0.3 ms) -> snippets re-centred
% on their extremum (duplicate detections dropped) -> features -> K-means /
% GMM (2-10 clusters, best mean silhouette) or DBSCAN -> optional drift
% correction -> optional auto-merge -> QC (SNR = peak-to-peak / (2 x
% baseline SD), rejected if < 2; rejected if > 2% ISIs < refractory).
% NEO: psi[n] = x[n]^2 - x[n-1] x[n+1].
% Requires: Signal Processing Toolbox (findpeaks; butter/filtfilt when
% filtering) and Statistics and Machine Learning Toolbox (pca, kmeans,
% fitgmdist, dbscan, silhouette, prctile, knnsearch, tsne). ICA needs
% FastICA, Wavelet the Wavelet Toolbox.
% =========================================================================

classdef MUAPipeline
    methods(Static)

        %% defaultParams - Spike sorting defaults (same as the original dialog)
        function p = defaultParams()
            p = struct();
            p.detectMethod = 'Standard';
            p.clusterMethod = 'K-means';
            p.threshold = 3.5;
            p.refractoryMs = 1.0;
            p.alignWinMs = 1.5;
            p.polarity = 'positive';
            p.filter = 0;
            p.bpLow = 300;
            p.bpHigh = 3000;
            p.featureMethod = 'PCA';
            p.numComponents = 3;
            p.normalize = 1;
            p.minSpikesPerCluster = 20;
            p.randomSeed = 0;   % MUA Analysis sets rng(randomSeed) before sorting (reproducible)
            p.enableDriftCorrection = 0;
            p.driftMethod = 'Time Binning';
            p.driftBinWidth = 30;
            p.enableGridSearchCheck = 0;
            p.dbscanEpsilon = NaN;  % auto-tune
            p.autoMerge = 1;           % merge over-split clusters after clustering
            p.mergeThreshold = 0.95;   % min correlation of mean waveforms
            p.mergeMinAmpRatio = 0.85; % min smaller/larger peak-to-peak amplitude
        end

        %% completeParams - Missing fields taken from defaultParams
        function p = completeParams(p)
            d = MUAPipeline.defaultParams();
            if isempty(p), p = d; return; end
            fn = fieldnames(d);
            for i = 1:numel(fn)
                if ~isfield(p, fn{i}), p.(fn{i}) = d.(fn{i}); end
            end
        end

        %% errorTitle - Short alert title for a MUAPipeline error identifier
        function s = errorTitle(identifier)
            switch identifier
                case 'NeuroAnalyzer:MUAPipeline:filter',         s = 'Filter Error';
                case 'NeuroAnalyzer:MUAPipeline:noSpikes',       s = 'Detection Error';
                case 'NeuroAnalyzer:MUAPipeline:unknownFeature', s = 'Spike sorting';
                otherwise,                                       s = 'Clustering Error';
            end
        end

        %% sort - Detection, alignment, features, clustering, auto-merge, QC
        function [results, info] = sort(x, t, fs, params, stageFcn)
            if nargin < 5 || isempty(stageFcn), stageFcn = @(msg) []; end
            params = MUAPipeline.completeParams(params);
            results = struct();
            results.segmentedMUA = x;
            results.segmentedTime = t;

            % --- Optional bandpass filter before detection (zero-phase) ---
            if params.filter
                nyq = fs / 2;
                if ~(isfinite(params.bpLow) && isfinite(params.bpHigh) && params.bpLow > 0 && ...
                        params.bpHigh > params.bpLow && params.bpHigh < nyq)
                    MUAPipeline.fail('filter', sprintf('Invalid bandpass range. Require 0 < low < high < %.0f Hz (Nyquist).', nyq));
                end
                stageFcn(sprintf('Filtering %g-%g Hz...', params.bpLow, params.bpHigh));
                [bFilt, aFilt] = butter(3, [params.bpLow params.bpHigh] / nyq, 'bandpass');
                x = filtfilt(bFilt, aFilt, double(x));
                results.segmentedMUA = x;
            end

            % --- Spike detection based on method and polarity ---
            % Detection uses a short dead time (~0.3 ms) so that sub-refractory
            % ISIs stay visible to the ISI quality check; the refractory period
            % is used for QC only. Double detections of the same spike are
            % removed after alignment (same extremum).
            deadSamples = max(1, round(0.3e-3 * fs));

            stageFcn(sprintf('Detecting spikes (%s)...', params.detectMethod));
            isNEO = strcmpi(params.detectMethod, 'neo');
            if isNEO
                % Nonlinear Energy Operator: psi[n] = x[n]^2 - x[n-1]*x[n+1].
                % Spikes of either sign give large positive psi, so the NEO
                % output is searched directly irrespective of polarity.
                xd = double(x);
                psi = zeros(size(xd));
                psi(2:end-1) = xd(2:end-1).^2 - xd(1:end-2) .* xd(3:end);
                searchSigns = 1;
            else
                switch lower(params.polarity)
                    case 'negative', searchSigns = -1;
                    case 'positive', searchSigns = 1;
                    otherwise,       searchSigns = [1 -1];  % 'both'
                end
            end

            locs = [];
            threshLines = [];  % thresholds on the MUA amplitude scale (for plotting)
            for sgn = searchSigns
                if isNEO
                    dataToSearch = psi;
                    % Threshold on the NEO scale
                    thr = mean(psi) + params.threshold * std(psi);
                else
                    % Search the sign-flipped signal; threshold computed on it
                    dataToSearch = sgn * double(x);
                    switch lower(params.detectMethod)
                        case {'mad', 'rolling mad'}
                            med = median(dataToSearch);
                            madVal = 1.4826 * median(abs(dataToSearch - med));
                            thr = med + params.threshold * madVal;
                        case 'percentile'
                            thr = prctile(abs(dataToSearch), 99.9);  % 99.9th percentile
                        otherwise  % 'standard'
                            thr = mean(dataToSearch) + params.threshold * std(dataToSearch);
                    end
                    threshLines(end+1) = sgn * thr; %#ok<AGROW>
                end

                if strcmpi(params.detectMethod, 'rolling mad')
                    initialIdx = find(dataToSearch > thr);
                    sgnLocs = [];
                    last = -Inf;
                    searchWindow = round(0.5 * fs / 1000 * params.alignWinMs);  % 0.5 ms in samples
                    for i = 1:length(initialIdx)
                        if initialIdx(i) - last > deadSamples
                            winStart = max(1, initialIdx(i) - searchWindow);
                            winEnd = min(length(dataToSearch), initialIdx(i) + searchWindow);
                            [~, peakRel] = max(dataToSearch(winStart:winEnd));
                            sgnLocs(end+1,1) = winStart + peakRel - 1; %#ok<AGROW>
                            last = sgnLocs(end);
                        end
                    end
                else
                    % Global threshold
                    [~, sgnLocs] = findpeaks(dataToSearch, 'MinPeakHeight', thr, ...
                        'MinPeakDistance', deadSamples);
                end
                locs = [locs; sgnLocs(:)]; %#ok<AGROW>
            end
            locs = unique(locs);  % sorted; merges coincident detections

            spikeTimes = t(locs);
            spikeTimes = spikeTimes(:);

            fprintf('[Detection] Method: %s | Polarity: %s | Spikes: %d\n', ...
                lower(params.detectMethod), lower(params.polarity), numel(locs));

            % Exit if no spikes or too few
            if isempty(locs)
                MUAPipeline.fail('noSpikes', ['No spikes detected with the current threshold. ' ...
                    'Try a lower threshold multiplier or another polarity.']);
            end
            if numel(spikeTimes) < params.minSpikesPerCluster * 2
                MUAPipeline.fail('tooFewSpikes', sprintf(['Too few spikes for clustering (%d detected; need at least 2 x %d). ' ...
                    'Lower the threshold or the minimum spikes per cluster.'], numel(spikeTimes), ...
                    params.minSpikesPerCluster));
            end

            %% Align waveforms around spike locations
            stageFcn(sprintf('Aligning %d waveforms...', numel(locs)));

            win = round(params.alignWinMs / 1000 * fs);  % half window for output (symmetric)
            preAlignMs = 0.5 * params.alignWinMs;
            postAlignMs = 1.0 * params.alignWinMs;

            preSearch = round(preAlignMs / 1000 * fs);
            postSearch = round(postAlignMs / 1000 * fs);

            alignedWaves = nan(length(locs), 2*win + 1);
            validIdx = false(size(locs));
            peakLocs = nan(size(locs));

            for i = 1:length(locs)
                center = locs(i);
                searchLeft = center - preSearch;
                searchRight = center + postSearch;
                if searchLeft > 0 && searchRight <= length(x)
                    snip = x(searchLeft:searchRight);
                    switch lower(params.polarity)
                        case 'negative', [~, peakIdx] = min(snip);
                        case 'positive', [~, peakIdx] = max(snip);
                        case 'both',     [~, peakIdx] = max(abs(snip));
                    end
                    peakLoc = searchLeft + peakIdx - 1;
                    leftFinal = peakLoc - win;
                    rightFinal = peakLoc + win;
                    if leftFinal > 0 && rightFinal <= length(x)
                        alignedWaves(i,:) = x(leftFinal:rightFinal);
                        validIdx(i) = true;
                        peakLocs(i) = peakLoc;
                    end
                end
            end

            % Drop double detections of the same spike (snapped to the same extremum)
            validPos = find(validIdx);
            [~, keepPos] = unique(peakLocs(validPos), 'stable');
            validIdx(:) = false;
            validIdx(validPos(keepPos)) = true;

            % Filter only valid waveform rows
            alignedWaves = alignedWaves(validIdx, :);
            locs = locs(validIdx);  % spike indices
            spikeTimes = spikeTimes(validIdx);  % spike times aligned with waveforms
            if numel(locs) < params.minSpikesPerCluster * 2
                MUAPipeline.fail('tooFewWaveforms', 'Too few spikes with complete waveforms for clustering.');
            end

            % Store original waveforms (centered at detection locs)
            preAlignedWaves = nan(length(locs), 2*win + 1);
            for i = 1:length(locs)
                if locs(i)-win > 0 && locs(i)+win <= length(x)
                    preAlignedWaves(i,:) = x(locs(i)-win : locs(i)+win);
                end
            end

            % Save both raw and aligned waveforms for diagnostics
            results.waveformsAligned = alignedWaves;
            results.waveformsRaw = preAlignedWaves;

            %% Feature extraction for clustering
            stageFcn(sprintf('Extracting features (%s)...', params.featureMethod));

            switch lower(params.featureMethod)
                case 'pca'
                    maxComp = min(params.numComponents, size(alignedWaves,2));
                    coeff = pca(alignedWaves);
                    features = alignedWaves * coeff(:, 1:maxComp);
                case 'ica'
                    try
                        [icasig, ~, ~] = fastica(alignedWaves', 'numOfIC', params.numComponents);
                        features = icasig(1:params.numComponents, :)';
                    catch
                        warning('ICA failed, using zeros.');
                        features = zeros(size(alignedWaves,1), params.numComponents);
                    end
                case 'waveform'
                    maxComp = min(params.numComponents, size(alignedWaves,2));
                    features = alignedWaves(:, 1:maxComp);
                case 'wavelet'
                    wv = cell(size(alignedWaves,1), 1);  % preallocate
                    for i = 1:size(alignedWaves,1)
                        [c,~] = wavedec(alignedWaves(i,:), 3, 'haar');
                        nComp = min(params.numComponents, length(c));
                        wv{i} = c(1:nComp);  % truncate to fixed length
                    end

                    try
                        features = cell2mat(wv);  % results in N x numComponents
                    catch
                        warning('Wavelet features inconsistent in size. Falling back to zeros.');
                        features = zeros(size(alignedWaves,1), params.numComponents);
                    end
                case 't-sne'
                    maxComp = min(params.numComponents, 3);
                    try
                        features = tsne(alignedWaves, 'NumDimensions', maxComp);
                    catch
                        warning('t-SNE failed, using zeros.');
                        features = zeros(size(alignedWaves,1), maxComp);
                    end
                otherwise
                    MUAPipeline.fail('unknownFeature', 'Unknown feature method.');
            end
            % Enforce feature matrix shape [N x numComponents]
            [N, ~] = size(alignedWaves);
            if size(features, 1) ~= N
                warning('Feature shape mismatch. Forcing consistent rows.');
                features = reshape(features, N, []);
            end
            % Optional z-score normalization of features (helps clustering)
            if isfield(params, 'normalize') && params.normalize
                mu = mean(features, 1);
                sig = std(features, 0, 1);
                sig(sig < 1e-8) = 1;
                features = (features - mu) ./ sig;
            end

            %% Running clustering
            stageFcn(sprintf('Clustering (%s)...', params.clusterMethod));

            % DRIFT CORRECTION: time binning strategy
            if params.enableDriftCorrection && strcmpi(params.driftMethod, 'Time Binning')
                % Compute bin IDs for filtered spikeTimes (aligned to features)
                fullStart = t(1);
                fullEnd = t(end);
                % Add one extra bin edge to guarantee coverage of fullEnd
                nBins = ceil((fullEnd - fullStart) / params.driftBinWidth);
                binEdges = linspace(fullStart, fullStart + nBins * params.driftBinWidth, nBins + 1);
                % Use right-edge inclusion for final bin coverage
                binIDs = discretize(spikeTimes, binEdges, 'IncludedEdge', 'right');
                binIDs(isnan(binIDs)) = 1;   % a spike exactly at the first edge belongs to bin 1
                uniqueBins = unique(binIDs(~isnan(binIDs)));
                numBins = numel(uniqueBins);
                minSpikesPerBin = max(2, ceil(params.minSpikesPerCluster / numBins));  % minimum 2 to allow 1 cluster
                fprintf('[Auto] Using minSpikesPerBin = %d (from global %d across %d bins)\n', ...
                            minSpikesPerBin, params.minSpikesPerCluster, numBins);

                % Initialize
                waveformBins = {};
                labelBins = {};
                timeBins = {};

                for b = uniqueBins(:)'  % loop over bins
                    binIdx = (binIDs == b);
                    fprintf('[DEBUG] Bin %d: %d spikes\n', b, sum(binIdx));
                    binFeatures = features(binIdx, :);
                    binWaveforms = alignedWaves(binIdx, :);
                    binTimes = spikeTimes(binIdx);
                    if sum(binIdx) < minSpikesPerBin
                        % Too few spikes to cluster: keep them as noise (0), not dropped
                        waveformBins{end+1} = binWaveforms; %#ok<AGROW>
                        labelBins{end+1} = zeros(sum(binIdx), 1); %#ok<AGROW>
                        timeBins{end+1} = binTimes; %#ok<AGROW>
                        continue;
                    end

                    switch lower(params.clusterMethod)
                        case 'k-means', [labels, valid] = MUAPipeline.tryKMeans(binFeatures, minSpikesPerBin);
                        case 'gmm',    [labels, valid] = MUAPipeline.tryGMM(binFeatures, minSpikesPerBin);
                        case 'dbscan', [labels, valid] = MUAPipeline.tryDBSCAN(binFeatures, minSpikesPerBin, params.dbscanEpsilon);
                    end

                    if ~valid
                        labels = zeros(sum(binIdx), 1);   % clustering failed: noise, not dropped
                    end
                    waveformBins{end+1} = binWaveforms; %#ok<AGROW>
                    labelBins{end+1} = labels; %#ok<AGROW>
                    timeBins{end+1} = binTimes; %#ok<AGROW>
                    fprintf('[DEBUG] Bin %d → valid: %d | #clusters: %d\n', ...
                        b, valid, numel(unique(labels)));
                end

                if all(cellfun(@(L) all(L == 0), labelBins))
                    MUAPipeline.fail('driftBins', 'Time-binning drift correction: no time bin produced a valid clustering.');
                end

                % Flatten all bins into one array
                spikeTimesFlat = []; waveformsFlat = []; labelsFlat = []; binIDsFlat = [];
                for i = 1:numel(waveformBins)
                    waveformsFlat = [waveformsFlat; waveformBins{i}]; %#ok<AGROW>
                    labelsFlat = [labelsFlat; labelBins{i}(:)]; %#ok<AGROW>
                    spikeTimesFlat = [spikeTimesFlat; timeBins{i}(:)]; %#ok<AGROW>
                    binIDsFlat = [binIDsFlat; i * ones(size(labelBins{i}(:)))]; %#ok<AGROW>
                end

                % Grid search over thresholds to merge clusters
                if params.enableGridSearchCheck
                    stageFcn('Merging clusters across time bins (grid search)...');
                else
                    stageFcn('Merging clusters across time bins...');
                end
                clusterLabels = MUAPipeline.optimizeClusterMerging(spikeTimesFlat, waveformsFlat, labelsFlat, binIDsFlat, params);
                % Enforce global minSpikesPerCluster after merging
                uniqueLabels = unique(clusterLabels);
                for i = 1:numel(uniqueLabels)
                    k = uniqueLabels(i);
                    if k == 0, continue; end  % skip unclustered
                    if sum(clusterLabels == k) < params.minSpikesPerCluster
                        clusterLabels(clusterLabels == k) = 0;  % reassign to noise
                    end
                end
                % Replace spike times, indices and waveforms with the kept bins
                % so they stay in sync with clusterLabels
                spikeTimes = spikeTimesFlat;
                alignedWaves = waveformsFlat;
                locs = round((spikeTimes - t(1)) * fs) + 1;  % aligned to segment trace
                locs = min(max(locs, 1), numel(t));

            % DRIFT CORRECTION: dynamic clustering
            elseif params.enableDriftCorrection && strcmpi(params.driftMethod, 'Dynamic Clustering')

                tSpan = max(spikeTimes) - min(spikeTimes);
                if tSpan <= 0, tSpan = 1; end
                tnorm = (spikeTimes(:) - min(spikeTimes)) / tSpan;
                dynFeatures = [features, tnorm];
                switch lower(params.clusterMethod)
                    case 'k-means', [clusterLabels, valid] = MUAPipeline.tryKMeans(dynFeatures, params.minSpikesPerCluster);
                    case 'gmm',    [clusterLabels, valid] = MUAPipeline.tryGMM(dynFeatures, params.minSpikesPerCluster);
                    case 'dbscan', [clusterLabels, valid] = MUAPipeline.tryDBSCAN(dynFeatures, params.minSpikesPerCluster, params.dbscanEpsilon);
                end
                if ~valid
                    MUAPipeline.fail('clustering', ['Dynamic clustering failed: no clustering had enough spikes in every ' ...
                        'cluster. Lower the minimum spikes per cluster or try another method.']);
                end
                clusterLabels = MUAPipeline.mergeWithinClusters(alignedWaves, clusterLabels, 0.8, 0.2);  % relative distance: similar size only
            % NO drift correction
            else
                switch lower(params.clusterMethod)
                    case 'k-means', [clusterLabels, valid] = MUAPipeline.tryKMeans(features, params.minSpikesPerCluster);
                    case 'gmm',    [clusterLabels, valid] = MUAPipeline.tryGMM(features, params.minSpikesPerCluster);
                    case 'dbscan', [clusterLabels, valid] = MUAPipeline.tryDBSCAN(features, params.minSpikesPerCluster, params.dbscanEpsilon);
                end
                if ~valid
                    MUAPipeline.fail('clustering', ['Clustering failed: no clustering had enough spikes in every cluster. ' ...
                        'Lower the minimum spikes per cluster or try another method.']);
                end
            end

            clusterLabels(~isfinite(clusterLabels)) = 0;
            clusterLabels = round(clusterLabels);

            %% Auto-merge over-split clusters (same shape and size)
            labelsBeforeMerge = clusterLabels;
            mergeLog = struct('keep', {}, 'absorbed', {}, 'r', {}, 'lag', {}, ...
                'ampRatio', {}, 'nKeep', {}, 'nAbsorbed', {});
            if params.autoMerge
                stageFcn('Merging similar clusters...');
                [clusterLabels, mergeLog] = ClusterTools.autoMerge(clusterLabels, alignedWaves, ...
                    MUAPipeline.mergeOptions(params, fs));
                if ~isempty(mergeLog)
                    fprintf('[AutoMerge] %s\n', ClusterTools.describeLog(mergeLog));
                end
            end

            stageFcn('Spike sorting complete. Computing quality metrics...');

            %% Save results and quality metrics
            results.spikeTimes = spikeTimes;
            [results, qc] = MUAPipeline.qualityMetrics(results, clusterLabels, alignedWaves, locs, t, fs, params);

            info = struct('locs', locs(:), 'threshLines', threshLines, 'qc', qc, ...
                'waves', alignedWaves, 'labelsBeforeMerge', labelsBeforeMerge, ...
                'mergeLog', mergeLog);
        end

        %% mergeOptions - ClusterTools.autoMerge options from sorting params
        % Shapes may be misaligned by up to 0.2 ms.
        function opts = mergeOptions(params, fs)
            params = MUAPipeline.completeParams(params);
            opts = struct('threshold', params.mergeThreshold, ...
                'minAmpRatio', params.mergeMinAmpRatio, 'maxLag', max(1, round(0.2e-3 * fs)));
        end

        %% qualityMetrics - Per-cluster waveforms, SNR and ISI checks
        % -------------------------------------------------------------
        % labels: cluster ID per spike; waves: aligned waveform per spike;
        % locs: sample index of each spike in t. Sets results.clusterIdx,
        % .waveforms, .isiViolationRate, .snr, .noiseSNR and
        % .rejectedClusters (replacing old values) and returns the display
        % QC struct array (one element per unique(labels)).
        % -------------------------------------------------------------
        function [results, qc] = qualityMetrics(results, labels, waves, locs, t, fs, params)
            params = MUAPipeline.completeParams(params);
            stale = intersect(fieldnames(results), {'snr', 'noiseSNR', 'rejectedClusters'});
            if ~isempty(stale), results = rmfield(results, stale); end
            clusterLabels = labels;
            alignedWaves = waves;
            results.clusterIdx = clusterLabels;
            results.waveforms = {};

            clusterIDs = unique(clusterLabels);

            % Per-cluster SNR and ISI quality checks
            results.isiViolationRate = containers.Map('KeyType', 'double', 'ValueType', 'double');
            refracMs = params.refractoryMs;  % e.g. 1.5
            isiThresh = 2.0;  % max % spikes with ISIs < refractory allowed
            SNRThresh = 2.0;  % min SNR allowed
            preSpikeBaseline = 0.5; % pre-spike baseline (e.g., first 0.5 ms)
            qc = struct('id', {}, 'n', {}, 'snr', {}, 'isiPct', {}, 'isiMs', {}, ...
                'rejected', {}, 'reason', {});
            for i = 1:numel(clusterIDs)
                k = clusterIDs(i);
                si = locs(clusterLabels == k);
                clusterWaves = alignedWaves(clusterLabels == k, :);

                % Default rejection flag
                isRejected = false;
                rejectionReason = '';

                % --- SNR Calculation ---
                meanWave = mean(clusterWaves, 1);
                ampP2P = max(meanWave) - min(meanWave);

                % Estimate noise from pre-spike baseline (e.g., first 0.5 ms)
                % (at least 2 samples so std is defined at low fs)
                baselineEnd = min(size(clusterWaves, 2), max(2, round(preSpikeBaseline / 1000 * fs)));
                baselineRegion = clusterWaves(:, 1:baselineEnd);
                noiseSD = std(baselineRegion(:));

                snr = ampP2P / (2 * noiseSD);
                if k == 0
                    results.noiseSNR = snr;
                else
                    results.snr(k) = snr;
                end

                % Report to console
                fprintf('[SNR] Cluster %d: %.2f (P2P=%.3g, noise=%.3g)\n', ...
                    k, snr, ampP2P, noiseSD);
                % Optional rejection
                if snr < SNRThresh && k ~= 0
                    isRejected = true;
                    rejectionReason = 'Low SNR';
                end

                % --- ISI analysis ---
                isi = diff(t(si));
                isiViolations = sum(isi < (refracMs / 1000));  % convert ms to seconds
                violationRate = 100 * isiViolations / max(1, length(isi));
                results.isiViolationRate(k) = violationRate;

                % Optional rejection
                if violationRate > isiThresh && k ~= 0
                    isRejected = true;
                    if isempty(rejectionReason)
                        rejectionReason = 'ISI Violation';
                    else
                        rejectionReason = [rejectionReason ' + ISI Violation']; %#ok<AGROW>
                    end
                else
                    fprintf('[ISI] Cluster %d: %.2f%% ISIs < %.1f ms\n', k, violationRate, refracMs);
                end

                results.waveforms{i} = clusterWaves;

                if isRejected
                    fprintf('[REJECTED] Cluster %d: %s\n', k, rejectionReason);
                end
                if k > 0
                    results.rejectedClusters(k) = isRejected;
                end

                % Display-only copy of the QC outcome (table, titles, markers)
                qc(i).id = k;
                qc(i).n = size(clusterWaves, 1);
                qc(i).snr = snr;
                qc(i).isiPct = violationRate;
                qc(i).isiMs = isi(:) * 1000;
                qc(i).rejected = isRejected;
                qc(i).reason = rejectionReason;
            end
        end

        %% Cluster merging for drift correction
        % Across time bins, a cluster joins the previous bin's cluster with
        % the best shape correlation >= 0.85 and relative distance <= 0.5
        % (the amplitude may drift); within the result, clusters merge when
        % correlation > 0.85 and relative distance < 0.2 (similar size:
        % two units of similar shape but different size stay apart), or
        % the grid-searched thresholds (0.8-0.95, 0.1-0.3) with the best
        % mean silhouette. Distances are relative (relativeDistance), so
        % results do not depend on V vs uV.
        function bestLabels = optimizeClusterMerging(spikeTimes, alignedWaves, clusterLabels, binIDs, params)
            fixedLabels = MUAPipeline.mergeClustersAcrossBins(spikeTimes, alignedWaves, clusterLabels, binIDs, 0.85, 0.5);
            if params.enableGridSearchCheck
                corrVals = 0.8:0.05:0.95;
                distVals = 0.1:0.05:0.3;   % relative distance (relativeDistance)
                bestScore = -Inf;
                bestLabels = zeros(size(clusterLabels));
                bestCorr = NaN;
                bestDist = NaN;

                fprintf('Running grid search over correlation × distance thresholds...\n');

                for c = 1:numel(corrVals)
                    for d = 1:numel(distVals)
                        try
                            labels = MUAPipeline.mergeSimilarClusters(alignedWaves, fixedLabels, corrVals(c), distVals(d));
                            u = unique(labels);
                            numClusters = numel(u(u > 0));  % exclude 0

                            if numClusters < 2, continue;  end
                            sil = silhouette(alignedWaves, labels);
                            avgSil = mean(sil(~isnan(sil)));

                            if avgSil > bestScore
                                bestScore = avgSil;
                                bestLabels = labels;
                                bestCorr = corrVals(c);
                                bestDist = distVals(d);
                            end
                        catch
                            continue;
                        end
                        u = unique(labels);
                        fprintf('[GridSearch] Corr %.2f Dist %.2f → %d nonzero clusters\n', ...
                            corrVals(c), distVals(d), numel(u(u > 0)));
                    end
                end
                fprintf('Best thresholds → Corr: %.2f, Dist: %.2f | Mean silhouette: %.3f\n', bestCorr, bestDist, bestScore);
            else
                bestLabels = MUAPipeline.mergeSimilarClusters(alignedWaves, fixedLabels, 0.85, 0.2);
            end
        end

        %% relativeDistance - Distance between two mean waveforms, relative to their size
        % norm(a - b) / max(norm(a), norm(b)): 0 = identical, 1 = as different
        % as the larger waveform is large. The same in V or uV, so merge
        % thresholds do not depend on the units of the recording.
        function d = relativeDistance(a, b)
            scale = max(norm(a), norm(b));
            if scale == 0, d = 0; else, d = norm(a - b) / scale; end
        end

        %% mergeClustersAcrossBins - Match clusters across time bins by centroid
        % Inputs: spikeTimes [nSpikes x 1]; waveforms [nSpikes x nSamples];
        % labels [nSpikes x 1] initial cluster labels (0 = noise stays 0);
        % binIDs [nSpikes x 1] time bin of each spike; corrThresh / distThresh
        % thresholds for centroid correlation / relative distance
        % (relativeDistance). Output: global labels.
        function finalLabels = mergeClustersAcrossBins(spikeTimes, waveforms, labels, binIDs, corrThresh, distThresh) %#ok<INUSL>
            uniqueBins = unique(binIDs);
            labelOffset = 0;
            finalLabels = zeros(size(labels));

            % Store cluster centroids (and their global labels) from previous bin
            prevCentroids = [];
            prevIDs = [];

            for b = 1:length(uniqueBins)
                bin = uniqueBins(b);
                idx = (binIDs == bin);

                waveBin = waveforms(idx, :);
                labelBin = labels(idx);
                uniqueClusts = unique(labelBin(labelBin > 0));  % label 0 = noise, stays 0

                % Compute centroids for each cluster in this bin
                centroids = zeros(length(uniqueClusts), size(waveBin, 2));
                for c = 1:length(uniqueClusts)
                    clusterIdx = labelBin == uniqueClusts(c);
                    centroids(c, :) = mean(waveBin(clusterIdx, :), 1);
                end

                % Match clusters to previous bin centroids
                newLabels = zeros(size(labelBin));
                curIDs = zeros(length(uniqueClusts), 1);

                for c = 1:length(uniqueClusts)
                    thisCentroid = centroids(c, :);
                    bestMatch = 0;
                    bestScore = -Inf;

                    for p = 1:size(prevCentroids,1)
                        corrVal = MUAPipeline.pearsonR(thisCentroid, prevCentroids(p,:));
                        distVal = MUAPipeline.relativeDistance(thisCentroid, prevCentroids(p,:));

                        if corrVal >= corrThresh && distVal <= distThresh
                            score = corrVal - 0.01 * distVal;
                            if score > bestScore
                                bestScore = score;
                                bestMatch = p;
                            end
                        end
                    end

                    if bestMatch > 0
                        % Inherit the global label of the matched previous cluster
                        curIDs(c) = prevIDs(bestMatch);
                    else
                        labelOffset = labelOffset + 1;
                        curIDs(c) = labelOffset;
                    end
                    newLabels(labelBin == uniqueClusts(c)) = curIDs(c);
                end

                finalLabels(idx) = newLabels;
                if ~isempty(uniqueClusts)  % an all-noise bin keeps the previous reference
                    prevCentroids = centroids;
                    prevIDs = curIDs;
                end
            end
        end

        %% mergeWithinClusters - Merge cluster pairs with similar centroids
        function mergedLabels = mergeWithinClusters(waveforms, labels, corrThresh, distThresh)
            mergedLabels = labels;
            uniqueClusts = unique(labels(labels > 0));  % exclude noise
            centroids = [];

            for k = uniqueClusts(:)'
                centroids(k,:) = mean(waveforms(labels == k,:), 1); %#ok<AGROW>
            end

            % Compare all pairs
            for i = 1:length(uniqueClusts)
                for j = i+1:length(uniqueClusts)
                    c1 = centroids(uniqueClusts(i),:);
                    c2 = centroids(uniqueClusts(j),:);
                    r = MUAPipeline.pearsonR(c1, c2);
                    d = MUAPipeline.relativeDistance(c1, c2);
                    if r > corrThresh && d < distThresh
                        mergedLabels(mergedLabels == uniqueClusts(j)) = uniqueClusts(i);
                    end
                end
            end

            % Reassign cluster labels to be sequential (keep 0 = noise as 0)
            pos = mergedLabels > 0;
            [~, ~, seqLabels] = unique(mergedLabels(pos), 'sorted');
            mergedLabels(pos) = seqLabels;
        end

        %% mergeSimilarClusters - Map similar clusters onto one label
        function mergedLabels = mergeSimilarClusters(waveforms, labels, corrThresh, distThresh)
            mergedLabels = labels;
            uClust = unique(labels(labels > 0));  % ignore 0/noise
            K = numel(uClust);
            centroids = zeros(K, size(waveforms,2));

            % Compute centroid of each cluster
            for i = 1:K
                centroids(i,:) = mean(waveforms(labels == uClust(i), :), 1);
            end

            % Pairwise comparison
            map = containers.Map('KeyType', 'double', 'ValueType', 'double');
            for i = 1:K
                map(uClust(i)) = uClust(i);  % initialize
            end

            for i = 1:K
                for j = i+1:K
                    r = MUAPipeline.pearsonR(centroids(i,:), centroids(j,:));
                    d = MUAPipeline.relativeDistance(centroids(i,:), centroids(j,:));
                    if r > corrThresh && d < distThresh
                        % Merge cluster j into i
                        map(uClust(j)) = map(uClust(i));
                    end
                end
            end

            % Apply mapping
            for k = 1:length(labels)
                if labels(k) > 0 && isKey(map, labels(k))
                    mergedLabels(k) = map(labels(k));
                end
            end

            % Reassign cluster labels to be sequential (keep 0 = noise as 0)
            pos = mergedLabels > 0;
            [~, ~, seqLabels] = unique(mergedLabels(pos), 'sorted');
            mergedLabels(pos) = seqLabels;
        end

        %% tryKMeans - K-means for 2-10 clusters, best mean silhouette
        function [idx, valid] = tryKMeans(features, minSpikes)
            valid = false;
            maxK = 10;
            bestScore = -Inf;
            idx = [];

            for k = 2:maxK
                tempIdx = kmeans(features, k, 'Replicates', 5, 'MaxIter', 500);
                counts = histcounts(tempIdx, 1:(k+1));

                if all(counts >= minSpikes)
                    silScore = mean(silhouette(features, tempIdx));
                    if silScore > bestScore
                        bestScore = silScore;
                        idx = tempIdx;
                        valid = true;
                    end
                end
            end
        end

        %% tryGMM - Gaussian mixture for 2-10 clusters, best mean silhouette
        function [idx, valid] = tryGMM(features, minSpikes)
            valid = false;
            maxK = 10;
            bestScore = -Inf;
            idx = [];

            for k = 2:maxK
                try
                    gmOptions = statset('MaxIter', 500);
                    GM = fitgmdist(features, k, 'Options', gmOptions, ...
                        'RegularizationValue', 1e-5, 'Replicates', 3);
                    tempIdx = cluster(GM, features);
                catch
                    continue;
                end

                counts = histcounts(tempIdx, 1:(k+1));
                if all(counts >= minSpikes)
                    silScore = mean(silhouette(features, tempIdx));
                    if silScore > bestScore
                        bestScore = silScore;
                        idx = tempIdx;
                        valid = true;
                    end
                end
            end
        end

        %% tryDBSCAN - Density clustering; unclustered spikes become 0 (noise)
        function [idx, valid] = tryDBSCAN(features, minSpikes, epsilon)
            if isnan(epsilon) || epsilon <= 0
                % Auto-tune epsilon using k-distance heuristic
                N = size(features, 1);
                if N < 2
                    idx = zeros(N, 1);
                    valid = false;
                    return;
                end
                k = min(10, N - 1); % e.g., 10th nearest neighbor
                % knnsearch avoids the N x N distance matrix; column 1 is self
                [~, D] = knnsearch(features, features, 'K', k + 1);
                kDistances = D(:, k + 1);
                epsilon = prctile(kDistances, 95);  % choose 95th percentile
            end

            idx = dbscan(features, epsilon, minSpikes);

            if all(idx == -1)
                valid = false;
                return;
            end

            idx(idx == -1) = 0; % unclustered
            valid = true;
        end
    end

    methods(Static, Access = private)

        %% fail - Throw a pipeline error with a user-facing message
        function fail(stage, msg)
            error(['NeuroAnalyzer:MUAPipeline:' stage], '%s', msg);
        end

        %% pearsonR - Pearson correlation of two vectors (base MATLAB)
        function r = pearsonR(a, b)
            R = corrcoef(a(:), b(:));
            r = R(1, 2);
        end
    end
end
