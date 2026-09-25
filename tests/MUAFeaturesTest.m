%% MUAFeaturesTest.m
% =========================================================================
% UNIT TESTS FOR MUA CLUSTER CLEAN-UP, RASTERS / PSTHs AND CORRELOGRAMS
% =========================================================================
% ClusterTools on synthetic spike waveforms: two copies of one unit are
% merged, distinct units (different size or different shape) are not;
% manual merge / split keep the label bookkeeping right and never touch
% noise (0). SpikeTrains on synthetic spike trains: the PSTH recovers a
% known rate step, the autocorrelogram shows the refractory gap and the
% cross-correlogram a known lag. MUAPipeline on the demo MUA file
% (channel 4): after sorting + auto-merge there are 2-3 clusters (K-means
% alone over-splits into 4), the largest unit is unit 1 and its PSTH peaks
% 5-55 ms after the stimulus, as simulated.
% =========================================================================

function tests = MUAFeaturesTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
end

%% Shared fixture: three unit shapes (uV) on a 3-ms snippet at 24 kHz
% A: sharp, ~90 uV; B: same family but ~50 uV; C: ~95 uV but wide (other shape).
function [A, B, C] = unitShapes()
    fs = 24000; tw = (-36:36) / fs;
    A = -90 * exp(-tw.^2 / (2 * 0.07e-3^2)) + 35 * exp(-(tw - 0.35e-3).^2 / (2 * 0.25e-3^2));
    B = -50 * exp(-tw.^2 / (2 * 0.10e-3^2)) + 30 * exp(-(tw - 0.40e-3).^2 / (2 * 0.20e-3^2));
    C = -95 * exp(-tw.^2 / (2 * 0.25e-3^2)) + 15 * exp(-(tw + 0.6e-3).^2 / (2 * 0.2e-3^2));
end

%% Noisy spikes of the given shapes; labels(i) = ids(k) for shape k; noise rows get 0
function [W, labels] = noisySpikes(shapes, ids, nEach, nNoise, seed)
    rs = RandStream('mt19937ar', 'Seed', seed);
    nS = numel(shapes{1});
    W = zeros(0, nS); labels = zeros(0, 1);
    for k = 1:numel(shapes)
        W = [W; shapes{k} + 10 * randn(rs, nEach, nS)]; %#ok<AGROW>
        labels = [labels; ids(k) * ones(nEach, 1)]; %#ok<AGROW>
    end
    W = [W; 10 * randn(rs, nNoise, nS)];
    labels = [labels; zeros(nNoise, 1)];
end

%% Poisson spike train with a dead time, rate(t) given on a grid (s)
function st = poissonTrain(rs, rateFcn, T, deadTime)
    dt = 1e-4;
    t = (0:dt:T - dt)';
    st = t(rand(rs, numel(t), 1) < rateFcn(t) * dt);
    st = st + dt * rand(rs, size(st));   % off the grid: no lag falls exactly on a bin edge
    if deadTime > 0 && numel(st) > 1
        keep = true(size(st)); last = st(1);
        for i = 2:numel(st)
            if st(i) - last < deadTime, keep(i) = false; else, last = st(i); end
        end
        st = st(keep);
    end
end

%% ClusterTools -----------------------------------------------------------

function testSimilarity_lagAndAmplitude(tests)
    [A, B] = unitShapes();
    [r, lag, a] = ClusterTools.similarity(A, circshift(A, 3), 5);
    verifyEqual(tests, r, 1, 'AbsTol', 1e-6);
    verifyEqual(tests, lag, 3);
    verifyEqual(tests, a, 1, 'AbsTol', 1e-6);
    [r, ~, a] = ClusterTools.similarity(A, 0.5 * A);
    verifyEqual(tests, r, 1, 'AbsTol', 1e-9);
    verifyEqual(tests, a, 0.5, 'AbsTol', 1e-9);
    % Units 1 and 2 have similar shapes; their sizes tell them apart
    [r, ~, a] = ClusterTools.similarity(A, B, 5);
    verifyGreaterThan(tests, r, 0.9);
    verifyLessThan(tests, a, 0.8);
end

function testAutoMerge_mergesCopiesOfOneUnit(tests)
    [A, B] = unitShapes();
    % Unit A split by the clustering into clusters 1 and 3; unit B is cluster 2
    [W, labels] = noisySpikes({A, B, A}, [1 2 3], 150, 40, 1);
    [merged, mergeLog] = ClusterTools.autoMerge(labels, W);
    verifyEqual(tests, unique(merged(merged > 0))', [1 2]);
    verifyEqual(tests, merged(labels == 3), ones(150, 1));          % copy joined unit 1
    verifyEqual(tests, merged(labels == 2), 2 * ones(150, 1));      % unit B untouched
    verifyEqual(tests, merged(labels == 0), zeros(40, 1));          % noise untouched
    verifyNumElements(tests, mergeLog, 1);
    verifyEqual(tests, [mergeLog.keep mergeLog.absorbed], [1 3]);
    verifyGreaterThan(tests, mergeLog.r, 0.95);
    verifyGreaterThan(tests, mergeLog.ampRatio, 0.9);
    verifyEqual(tests, [mergeLog.nKeep mergeLog.nAbsorbed], [150 150]);
end

function testAutoMerge_keepsDistinctUnits(tests)
    [A, B, C] = unitShapes();
    [W, labels] = noisySpikes({A, B, C}, [1 2 3], 150, 40, 2);
    [merged, mergeLog] = ClusterTools.autoMerge(labels, W, struct('threshold', 0.95, 'minAmpRatio', 0.85));
    verifyEqual(tests, merged, labels);
    verifyEmpty(tests, mergeLog);
    % Why: A/B differ in size, A/C in shape (similar size)
    [R, ~, Amp, ids] = ClusterTools.similarityMatrix(labels, W);
    verifyEqual(tests, ids, [1 2 3]);
    verifyLessThan(tests, Amp(1, 2), 0.85);
    verifyGreaterThan(tests, Amp(1, 3), 0.85);
    verifyLessThan(tests, R(1, 3), 0.95);
end

function testMerge_bookkeeping(tests)
    labels = [0 1 1 2 3 3 3 0 2 1]';
    m = ClusterTools.merge(labels, [3 1]);
    verifyEqual(tests, m, [0 1 1 2 1 1 1 0 2 1]');
    % Noise in the list is ignored; the remaining units are merged
    m = ClusterTools.merge(labels, [0 2 3]);
    verifyEqual(tests, m, [0 1 1 2 2 2 2 0 2 1]');
    verifyError(tests, @() ClusterTools.merge(labels, [1 0]), 'NeuroAnalyzer:ClusterTools:merge');
    verifyError(tests, @() ClusterTools.merge(labels, [1 7]), 'NeuroAnalyzer:ClusterTools:merge');
    verifyEqual(tests, ClusterTools.renumber([0 3 3 7 1 0]), [0 2 2 3 1 0]);
end

function testSplit_separatesMixedUnits(tests)
    [A, B] = unitShapes();
    % Cluster 1 mixes units A (200 spikes) and B (100 spikes); cluster 3 exists
    [W, truth] = noisySpikes({A, B, B}, [1 2 3], 100, 30, 3);
    W = [W; A + 10 * randn(RandStream('mt19937ar', 'Seed', 4), 100, numel(A))];
    truth = [truth; ones(100, 1)];
    labels = truth; labels(truth == 2) = 1;
    [s, newIds] = ClusterTools.split(labels, W, 1, 2);
    verifyEqual(tests, newIds, [1 4]);                      % new ID = max label + 1
    verifyGreaterThan(tests, mean(s(truth == 1) == 1), 0.97);   % larger part (A) keeps ID 1
    verifyGreaterThan(tests, mean(s(truth == 2) == 4), 0.97);   % unit B split off
    verifyEqual(tests, s(truth == 3), 3 * ones(100, 1));    % other clusters untouched
    verifyEqual(tests, s(truth == 0), zeros(30, 1));        % noise untouched
    % Deterministic, and merge undoes the split
    verifyEqual(tests, ClusterTools.split(labels, W, 1, 2), s);
    verifyEqual(tests, ClusterTools.merge(s, newIds), labels);
    verifyError(tests, @() ClusterTools.split(labels, W, 0), 'NeuroAnalyzer:ClusterTools:split');
    verifyError(tests, @() ClusterTools.split(labels, W, 9), 'NeuroAnalyzer:ClusterTools:split');
end

%% SpikeTrains ------------------------------------------------------------

function testStimulusOnsets(tests)
    t = (0:10)' * 0.1;
    stim = [0 0 1 1 0 1 0 0 1 1 0]';
    verifyEqual(tests, SpikeTrains.stimulusOnsets(stim, t, 0.5, 0.25), [0.2; 0.5; 0.8], 'AbsTol', 1e-12);
    % Each crossing is compared with the last KEPT onset: 0.5 s is 0.3 s after
    % 0.2 s (dropped), 0.8 s is 0.6 s after it (kept)
    verifyEqual(tests, SpikeTrains.stimulusOnsets(stim, t, 0.5, 0.4), [0.2; 0.8], 'AbsTol', 1e-12);
    verifyEmpty(tests, SpikeTrains.stimulusOnsets(stim, t, 2, 0));
end

function testPSTH_recoversRateStep(tests)
    rs = RandStream('mt19937ar', 'Seed', 5);
    onsets = (1:2:399)';   % 200 trials
    % 10 spikes/s, 100 spikes/s from 5 to 45 ms after each onset (every 2 s from 1 s)
    rateFcn = @(t) 10 + 90 * (t >= 1 & mod(t - 1, 2) >= 0.005 & mod(t - 1, 2) < 0.045);
    st = poissonTrain(rs, rateFcn, 400, 0);
    [raster, psth] = SpikeTrains.rasterPSTH(st, onsets, [-0.1 0.3], 0.005, [0 400]);
    verifyEqual(tests, raster.nTrials, 200);
    verifyEqual(tests, psth.nTrials, 200);
    verifyEqual(tests, numel(psth.centers), 80);
    verifyEqual(tests, numel(raster.time), sum(psth.counts(:)));
    verifyTrue(tests, all(raster.time >= -0.1 & raster.time < 0.3));
    evoked = psth.centers > 0.005 & psth.centers < 0.045;
    base = psth.centers < 0;
    verifyEqual(tests, mean(psth.rate(evoked)), 100, 'RelTol', 0.15);
    verifyEqual(tests, mean(psth.rate(base)), 10, 'AbsTol', 3);
    [~, iPk] = max(psth.rate);
    verifyTrue(tests, psth.centers(iPk) > 0.005 && psth.centers(iPk) < 0.045);
    % SEM = SD across trials / sqrt(nTrials)
    k = find(evoked, 1);
    verifyEqual(tests, psth.sem(k), std(psth.counts(:, k) / 0.005) / sqrt(200), 'AbsTol', 1e-9);
end

function testPSTH_spanDropsIncompleteTrials(tests)
    [raster, psth] = SpikeTrains.rasterPSTH([0.5 1.05 9.95], [0.05 1 9.9], [-0.1 0.3], 0.01, [0 10]);
    verifyEqual(tests, raster.onsets, 1);   % 0.05 - 0.1 < 0 and 9.9 + 0.3 > 10 are left out
    verifyEqual(tests, raster.time, 0.05, 'AbsTol', 1e-12);
    verifyEqual(tests, sum(psth.counts), 1);
end

function testCorrelogram_refractoryGap(tests)
    rs = RandStream('mt19937ar', 'Seed', 6);
    st = poissonTrain(rs, @(t) 40 * ones(size(t)), 200, 0.0025);   % dead time 2.5 ms
    [c, centers, edges] = SpikeTrains.correlogram(st, [], 0.05, 0.001);
    verifyEqual(tests, numel(c), 100);
    verifyEqual(tests, edges([1 51 end]), [-0.05 0 0.05], 'AbsTol', 1e-12);
    verifyEqual(tests, c(abs(centers) < 0.002), [0 0 0 0]);   % no spike pairs closer than 2 ms
    verifyEqual(tests, c, fliplr(c));                          % autocorrelogram is symmetric
    % Away from 0 the conditional rate is flat at the mean firing rate
    [~, ~, ~, rate] = SpikeTrains.correlogram(st, [], 0.05, 0.001);
    verifyEqual(tests, mean(rate(abs(centers) > 0.01)), numel(st) / 200, 'RelTol', 0.1);
    % Identical spike times are two spikes (kept); only self-pairs are dropped
    verifyEqual(tests, SpikeTrains.correlogram([1; 1; 2], [], 0.01, 0.001), [0 0 0 0 0 0 0 0 0 0 2 0 0 0 0 0 0 0 0 0]);
end

function testCorrelogram_knownLag(tests)
    rs = RandStream('mt19937ar', 'Seed', 7);
    t1 = poissonTrain(rs, @(t) 20 * ones(size(t)), 100, 0.002);
    t2 = t1 + 0.005 + 0.0008 * rand(rs, size(t1));   % unit 2 follows unit 1 by 5-5.8 ms
    [c, centers] = SpikeTrains.correlogram(t1, t2, 0.05, 0.001);
    [pk, iPk] = max(c);
    verifyEqual(tests, centers(iPk), 0.0055, 'AbsTol', 1e-9);
    verifyEqual(tests, pk, numel(t1));
    % Reversed order: the peak moves to -5.5 ms
    c2 = SpikeTrains.correlogram(t2, t1, 0.05, 0.001);
    verifyEqual(tests, c2, fliplr(c));
end

%% MUAPipeline on the demo MUA file -------------------------------------

function testDemo_autoMergeAndPSTH(tests)
    tests.assumeTrue(license('test', 'Statistics_Toolbox') && license('test', 'Signal_Toolbox') && ...
        exist('kmeans', 'file') == 2 && exist('findpeaks', 'file') == 2, ...
        'Spike sorting needs the Signal Processing and Statistics and Machine Learning Toolboxes');
    s = load(DemoData.file('mua'));
    x = s.mua_data(s.mua_channels == 4, :);
    params = struct('detectMethod', 'MAD', 'threshold', 4, 'polarity', 'negative');   % as loadDemo
    prevRng = rng; rng(0, 'twister'); restore = onCleanup(@() rng(prevRng));

    [res, info] = MUAPipeline.sort(x, s.t_mua, s.mua_fs, params);
    units = unique(res.clusterIdx(res.clusterIdx > 0));
    before = unique(info.labelsBeforeMerge(info.labelsBeforeMerge > 0));
    verifyGreaterThanOrEqual(tests, numel(units), 2);
    verifyLessThanOrEqual(tests, numel(units), 3);
    verifyGreaterThanOrEqual(tests, numel(before), numel(units));
    verifyNumElements(tests, info.mergeLog, numel(before) - numel(units));
    % Results keep the app's SpikeResults layout
    verifyEqual(tests, numel(res.waveforms), numel(unique(res.clusterIdx)));
    verifyEqual(tests, numel(res.spikeTimes), numel(res.clusterIdx));
    verifyEqual(tests, size(info.waves, 1), numel(res.clusterIdx));

    % Largest unit (peak-to-peak) = unit 1 (~90 uV)
    M = ClusterTools.meanWaveforms(res.clusterIdx, info.waves, units');
    [~, iBig] = max(max(M, [], 2) - min(M, [], 2));
    tBig = res.spikeTimes(res.clusterIdx == units(iBig));
    truth1 = s.truth.units(1).spikeTimes(:);
    matched = arrayfun(@(ts) any(abs(truth1 - ts) < 0.5e-3), tBig);
    verifyGreaterThan(tests, mean(matched), 0.7);   % (a mixed cluster may have been merged in)

    % Onsets detected from the stimulus channel match the simulated ones
    onsets = SpikeTrains.stimulusOnsets(s.stim_data, s.t_stim, 0.5, 1);
    verifyEqual(tests, onsets(:)', s.truth.onsets, 'AbsTol', 1.5e-3);   % stimulus sampled at ~1 kHz
    [~, psth] = SpikeTrains.rasterPSTH(tBig, onsets, [-0.1 0.3], 0.01, s.t_mua([1 end]));
    [~, iPk] = max(psth.rate);
    verifyGreaterThanOrEqual(tests, psth.centers(iPk), 0.005);
    verifyLessThanOrEqual(tests, psth.centers(iPk), 0.055);
    verifyGreaterThan(tests, max(psth.rate), 3 * mean(psth.rate(psth.centers < 0)));
end

%% testQualityResultsStored - Rejected units and ISI violation rates are stored in the results
% (they were shown on screen but results.rejectedClusters stayed false and
% results.isiViolationRate empty)
function testQualityResultsStored(tests)
    fs = 30000;
    rs = RandStream('mt19937ar', 'Seed', 11);
    nw = 36;                                   % 1.2 ms waveforms
    shape = -100 * exp(-((1:nw) - 24).^2 / 8);   % flat first 0.5 ms (noise estimate)
    % Cluster 1: clean unit (spikes >= 5 ms apart); cluster 2: same shape but
    % every other spike 0.5 ms after the previous one (refractory violations)
    s1 = (1:40) * 0.01;
    s2 = sort([(1:20) * 0.02 + 0.5, (1:20) * 0.02 + 0.5 + 0.0005]);
    t = (0:round(1.5 * fs)) / fs;
    locs = round([s1, s2] * fs)' + 1;
    labels = [ones(40, 1); 2 * ones(40, 1)];
    waves = repmat(shape, 80, 1) + 5 * randn(rs, 80, nw);
    p = MUAPipeline.completeParams(struct('refractoryMs', 1.5));
    [results, qc] = MUAPipeline.qualityMetrics(struct(), labels, waves, locs, t, fs, p);
    verifyEqual(tests, [qc.rejected], [false true]);
    verifyEqual(tests, results.rejectedClusters, [false true]);
    verifyEqual(tests, results.isiViolationRate(1), 0);
    verifyGreaterThan(tests, results.isiViolationRate(2), 2);
    verifyEqual(tests, results.isiViolationRate(2), qc(2).isiPct);
end

%% Drift correction ---------------------------------------------------------

%% testRelativeDistanceIsUnitFree - Merge distances do not depend on V vs uV
function testRelativeDistanceIsUnitFree(tests)
    [A, B] = unitShapes();
    verifyEqual(tests, MUAPipeline.relativeDistance(A, A), 0);
    verifyEqual(tests, MUAPipeline.relativeDistance(A, 0.5 * A), 0.5, 'AbsTol', 1e-12);
    verifyEqual(tests, MUAPipeline.relativeDistance(1e-6 * A, 1e-6 * B), ...
        MUAPipeline.relativeDistance(A, B), 'AbsTol', 1e-12);
    verifyEqual(tests, MUAPipeline.relativeDistance(0 * A, 0 * A), 0);
end

%% testMergeAcrossBins_sameInVoltsAndMicrovolts - One unit in two time bins
% keeps one label whatever the units of the recording (before: a fixed
% distance of 0.5 merged everything in V and nothing in uV)
function testMergeAcrossBins_sameInVoltsAndMicrovolts(tests)
    [A, B] = unitShapes();
    [W, labels] = noisySpikes({A, B, A, B}, [1 2 2 1], 60, 0, 3);   % bin 2 swaps the local labels
    bins = [ones(120, 1); 2 * ones(120, 1)];
    for scale = [1 1e-6]
        g = MUAPipeline.mergeClustersAcrossBins([], scale * W, labels, bins, 0.85, 0.5);
        verifyEqual(tests, numel(unique(g)), 2, sprintf('scale %g', scale));
        verifyEqual(tests, g(121:180), repmat(g(1), 60, 1), sprintf('scale %g: unit A', scale));
        verifyEqual(tests, g(181:240), repmat(g(61), 60, 1), sprintf('scale %g: unit B', scale));
    end
end

%% testDriftBinningKeepsEverySpike - Spikes of small time bins become noise, not lost
function testDriftBinningKeepsEverySpike(tests)
    tests.assumeTrue(license('test', 'Statistics_Toolbox') && license('test', 'Signal_Toolbox') && ...
        exist('kmeans', 'file') == 2 && exist('findpeaks', 'file') == 2, ...
        'Spike sorting needs the Signal Processing and Statistics and Machine Learning Toolboxes');
    s = load(DemoData.file('mua'));
    x = s.mua_data(s.mua_channels == 4, :);
    base = struct('detectMethod', 'MAD', 'threshold', 4, 'polarity', 'negative');
    prevRng = rng; restore = onCleanup(@() rng(prevRng));
    rng(0, 'twister');
    plain = MUAPipeline.sort(x, s.t_mua, s.mua_fs, base);
    drift = base;
    % 14 s bins over 30 s: the last bin (28-30 s, ~40 of 601 spikes) is below
    % 300 / 3 = 100 spikes per bin, so it is not clustered; its spikes must stay
    % (as noise). (Sorting needs at least 2 x minSpikesPerCluster spikes.)
    drift.enableDriftCorrection = true; drift.driftMethod = 'Time Binning'; drift.driftBinWidth = 14;
    drift.minSpikesPerCluster = 300;
    rng(0, 'twister');
    res = MUAPipeline.sort(x, s.t_mua, s.mua_fs, drift);
    verifyEqual(tests, numel(res.spikeTimes), numel(plain.spikeTimes));
    verifyEqual(tests, sort(res.spikeTimes(:)), sort(plain.spikeTimes(:)), 'AbsTol', 1e-12);
    verifyEqual(tests, res.clusterIdx(res.spikeTimes > 28), zeros(nnz(res.spikeTimes > 28), 1));
end

%% testMergeSimilarClusters_keepsDifferentSizes - Similar shape, different size: not merged
function testMergeSimilarClusters_keepsDifferentSizes(tests)
    [A, B] = unitShapes();
    [W, labels] = noisySpikes({A, B, A}, [1 2 3], 80, 0, 5);
    for scale = [1 1e-6]
        merged = MUAPipeline.mergeSimilarClusters(scale * W, labels, 0.85, 0.2);
        verifyEqual(tests, merged(labels == 3), merged(find(labels == 1, 1)) * ones(80, 1), sprintf('scale %g', scale));
        verifyNotEqual(tests, merged(find(labels == 2, 1)), merged(find(labels == 1, 1)), sprintf('scale %g', scale));
    end
end
