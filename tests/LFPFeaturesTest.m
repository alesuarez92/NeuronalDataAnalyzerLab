%% LFPFeaturesTest.m
% =========================================================================
% UNIT TESTS FOR LFP TIME-FREQUENCY (TimeFrequency) AND ERPAnalysis
% =========================================================================
% Synthetic signals with closed-form answers check the spectral methods
% (Morlet power peak and phase, unit-energy wavelets, Welch peak and
% Parseval, STFT tracking, band-power calibration). The oscillation demo
% (core/demo/demoLFPOscillations: theta 6 Hz everywhere, phase-locked
% 40 Hz burst 50-250 ms after each stimulus on ch 3-5) checks ERSP / ITPC
% and band power against its ground truth. ERPAnalysis is checked to give
% bit-identical results to the LFPAnalysisApp code it replaced (copied
% below as legacyERP / legacyCSD) and the known ERP / CSD of DemoData.
% =========================================================================

function tests = LFPFeaturesTest
    tests = functiontests(localfunctions);
end

%% setupOnce - Paths; build the demo recordings once
function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.lfp = DemoData.lfpFile();
    tests.TestData.osc = demoLFPOscillations();
end

%% ---------------------------------------------------------------- Morlet

function testMorletPeaksAtSinusoidFrequency(tests)
    fs = 1000; t = (0:10 * fs - 1) / fs;
    x = 2 * cos(2 * pi * 25 * t);
    freqs = 5:60;
    [coef, pow, phase] = TimeFrequency.morletTF(x, fs, freqs, 7);
    verifySize(tests, coef, [numel(freqs) numel(t)]);
    mid = 2 * fs:8 * fs;
    [~, i] = max(mean(pow(:, mid), 2));
    verifyEqual(tests, freqs(i), 25, 'AbsTol', 1);
    % Cosine phase convention: the phase follows 2*pi*f*t
    k = 5 * fs + 1;
    verifyEqual(tests, angle(exp(1i * (phase(freqs == 25, k) - 2 * pi * 25 * t(k)))), 0, 'AbsTol', 0.05);
    % Matrix input: one signal per row, linear in the signal
    c2 = TimeFrequency.morletTF([x; 3 * x], fs, [20 25], 7);
    verifySize(tests, c2, [2 numel(t) 2]);
    verifyEqual(tests, c2(:, :, 2), 3 * c2(:, :, 1), 'AbsTol', 1e-9);
end

function testMorletUnitEnergyFlatForWhiteNoise(tests)
    % Unit-energy wavelets: expected power of white noise = its variance at every frequency
    rs = RandStream('mt19937ar', 'Seed', 11);
    fs = 500; x = randn(rs, 1, 120 * fs);
    [~, pow] = TimeFrequency.morletTF(x, fs, [10 20 40 80], 7);
    mp = mean(pow(:, 2 * fs:end - 2 * fs), 2) / var(x);
    verifyEqual(tests, mp, ones(4, 1), 'RelTol', 0.15);
end

function testMorletRejectsBadFrequencies(tests)
    verifyError(tests, @() TimeFrequency.morletTF(randn(1, 100), 100, [0 10]), ...
        'NeuroAnalyzer:TimeFrequency:badFreqs');
    verifyError(tests, @() TimeFrequency.morletTF(randn(1, 100), 100, 60), ...
        'NeuroAnalyzer:TimeFrequency:badFreqs');
end

%% ------------------------------------------------------------ Welch / STFT

function testWelchPeakAndParseval(tests)
    rs = RandStream('mt19937ar', 'Seed', 12);
    fs = 1000; t = (0:60 * fs - 1) / fs;
    sigma = 0.5;
    x = 2 * sin(2 * pi * 50 * t) + sigma * randn(rs, size(t));
    [pxx, f] = TimeFrequency.welchPSD(x, fs);
    df = f(2) - f(1);
    [~, i] = max(pxx);
    verifyEqual(tests, f(i), 50, 'AbsTol', df);
    % Density scaling: total power = variance (Parseval)
    verifyEqual(tests, sum(pxx) * df, var(x), 'RelTol', 0.02);
    % White-noise floor: one-sided density 2*sigma^2/fs
    verifyEqual(tests, median(pxx(f > 100 & f < 400)), 2 * sigma^2 / fs, 'RelTol', 0.1);
end

function testStftTracksFrequencyChange(tests)
    fs = 500; t = (0:20 * fs - 1) / fs;
    x = sin(2 * pi * 10 * t) .* (t < 10) + sin(2 * pi * 30 * t) .* (t >= 10);
    [P, f, tt] = TimeFrequency.stft(x, fs, 0.5, 0.5, [1 100]);
    verifySize(tests, P, [numel(f) numel(tt)]);
    verifyGreaterThanOrEqual(tests, min(f), 1);
    verifyLessThanOrEqual(tests, max(f), 100);
    [~, k] = max(P, [], 1);
    verifyEqual(tests, median(f(k(tt < 9))), 10, 'AbsTol', 2);
    verifyEqual(tests, median(f(k(tt > 11))), 30, 'AbsTol', 2);
    % Each window holds a unit-amplitude sinusoid: power 0.5
    verifyEqual(tests, median(sum(P, 1)) * (f(2) - f(1)), 0.5, 'RelTol', 0.1);
end

%% ------------------------------------------------------------- Band power

function testBandPowerCalibration(tests)
    fs = 1000; t = (0:20 * fs - 1) / fs; A = 3;
    p = TimeFrequency.bandPower(A * sin(2 * pi * 6 * t), fs, [4 8; 30 80]);
    verifySize(tests, p, [2 numel(t)]);
    mid = 2 * fs:18 * fs;
    verifyEqual(tests, p(1, mid), A^2 * ones(1, numel(mid)), 'RelTol', 0.01);   % |analytic|^2 = A^2
    verifyLessThan(tests, max(p(2, mid)), 1e-3 * A^2);                           % nothing in 30-80 Hz
end

function testBandPowerThetaConstant(tests)
    s = tests.TestData.osc; fs = s.lfp_fs; th = s.truth.theta;
    % Channel 8: far from the ERP sink, no gamma - theta plus 1/f background
    p = TimeFrequency.bandPower(s.lfp_data(8, :), fs, [4 8]);
    nb = round(2 * fs); k = floor(numel(p) / nb);
    bins = mean(reshape(p(1:k * nb), nb, k), 1);
    bins = bins(2:end - 1);                                  % skip the recording edges
    verifyEqual(tests, mean(bins), th.amplitudeV^2, 'RelTol', 0.2);
    verifyLessThan(tests, std(bins) / mean(bins), 0.25);
    % ... and not modulated by the stimuli
    on = ERPAnalysis.detectOnsets(s.stim_data, s.stim_fs, 0.5, 0.5);
    r = TimeFrequency.eventBandPower(s.lfp_data(8, :), fs, on, [-0.5 1], [4 8; 30 80], [-0.4 -0.1]);
    verifySize(tests, r.mean, [2 numel(r.t)]);
    verifyLessThan(tests, abs(mean(r.mean(1, :))), 25);
end

function testEventBandPowerGammaBurst(tests)
    s = tests.TestData.osc; fs = s.lfp_fs; g = s.truth.gamma;
    on = ERPAnalysis.detectOnsets(s.stim_data, s.stim_fs, 0.5, 0.5);
    r = TimeFrequency.eventBandPower(s.lfp_data(4, :), fs, on, [-0.5 1], [30 80], [-0.4 -0.1]);
    inBurst = r.t >= g.windowS(1) + 0.05 & r.t <= g.windowS(2) - 0.05;
    late = r.t >= 0.5 & r.t <= 0.9;
    verifyGreaterThan(tests, mean(r.mean(1, inBurst)), 100);         % % change vs baseline
    verifyLessThan(tests, abs(mean(r.mean(1, late))), 40);
    verifyGreaterThanOrEqual(tests, r.nTrials, 13);
    verifyTrue(tests, all(r.sem(1, :) >= 0));
end

%% ------------------------------------------------------------ ERSP / ITPC

function testErspGammaBurstAndItpc(tests)
    s = tests.TestData.osc; fs = s.lfp_fs; g = s.truth.gamma;
    on = ERPAnalysis.detectOnsets(s.stim_data, s.stim_fs, 0.5, 0.5);
    freqs = 4:2:80;
    [E, I, t, info] = TimeFrequency.ersp(s.lfp_data(4, :), fs, on, [-0.5 1], freqs, [-0.4 -0.1], 7);
    verifySize(tests, E, [numel(freqs) numel(t)]);
    verifySize(tests, I, [numel(freqs) numel(t)]);
    verifyGreaterThanOrEqual(tests, info.nTrials, 14);
    gF = abs(freqs - g.freqHz) <= 4;
    inBurst = t >= g.windowS(1) + 0.05 & t <= g.windowS(2) - 0.05;   % 100-200 ms: past the ramps and N1
    late = t >= 0.5 & t <= 0.9;
    pre = t >= -0.4 & t <= -0.1;
    verifyGreaterThan(tests, mean(mean(E(gF, inBurst))), 6);          % gamma burst: clearly above 0 dB
    verifyLessThan(tests, abs(mean(mean(E(:, late)))), 1.5);           % elsewhere ~0 dB
    verifyLessThan(tests, abs(mean(mean(E(gF, late)))), 3);
    verifyLessThan(tests, abs(mean(mean(E(gF, pre)))), 1);
    % ITPC: the burst is phase-locked to the stimulus; background and theta are not
    verifyGreaterThan(tests, mean(mean(I(gF, inBurst))), 0.8);
    verifyLessThan(tests, mean(mean(I(gF, late))), 0.5);
    verifyLessThan(tests, mean(I(freqs == s.truth.theta.freqHz, late)), 0.75);
    verifyTrue(tests, all(I(:) >= 0 & I(:) <= 1 + 1e-12));
    % No gamma on a channel outside 3-5
    E8 = TimeFrequency.ersp(s.lfp_data(8, :), fs, on, [-0.5 1], freqs, [-0.4 -0.1], 7);
    verifyLessThan(tests, mean(mean(E8(gF, inBurst))), 3);
end

function testErspEdgeTrialsAndErrors(tests)
    rs = RandStream('mt19937ar', 'Seed', 13);
    fs = 500; x = randn(rs, 1, 20 * fs);
    % Onset 1 s: fine at 40 Hz, but a 4 Hz wavelet (7 cycles, 3 SD = 0.84 s) reaches before t = 0
    [~, ~, ~, info] = TimeFrequency.ersp(x, fs, [1 10], [-0.5 1], [4 40], [-0.4 -0.1], 7);
    verifyEqual(tests, info.nTrialsPerFreq, [1 2]);
    verifyError(tests, @() TimeFrequency.ersp(x, fs, 10, [-0.5 1], 40, [1.2 1.5]), ...
        'NeuroAnalyzer:TimeFrequency:badBaseline');
    verifyError(tests, @() TimeFrequency.ersp(x, fs, 0.1, [-0.5 1], 40, [-0.4 -0.1]), ...
        'NeuroAnalyzer:TimeFrequency:noEpochs');
end

%% ------------------------------------------------------------ ERPAnalysis

function testErpAnalysisMatchesPreviousApp(tests)
    s = tests.TestData.lfp;
    p = struct('preTime', 0.05, 'postTime', 0.2, 'threshold', 0.5, 'minISI', 0.5);
    ch = 1:size(s.lfp_data, 1);
    ref = legacyERP(s, ch, p);
    [onsetTimes, onsetIdx] = ERPAnalysis.detectOnsets(s.stim_data, s.stim_fs, p.threshold, p.minISI);
    [erpAvg, erpStd, t, nValid] = ERPAnalysis.average(s.lfp_data(ch, :), s.lfp_fs, onsetTimes, p.preTime, p.postTime);
    % Bit-identical to the code the app used before
    verifyEqual(tests, onsetTimes, ref.onsetTimes);
    verifyEqual(tests, erpAvg, ref.erpAvg);
    verifyEqual(tests, erpStd, ref.erpStd);
    verifyEqual(tests, t, ref.t);
    verifyEqual(tests, nValid, ref.nValid);
    csd = ERPAnalysis.csd(erpAvg, 100, ch);
    verifyEqual(tests, csd, legacyCSD(ref.erpAvg, 100, ch));
    verifyEqual(tests, ERPAnalysis.csd(erpAvg, 100, fliplr(ch)), legacyCSD(ref.erpAvg, 100, fliplr(ch)));
    % Ground truth: 15 onsets at the simulated times, N1 at 15 ms deepest at ch 4, CSD sink at ch 4
    verifyEqual(tests, numel(onsetTimes), numel(s.truth.onsets));
    verifyEqual(tests, onsetTimes, s.truth.onsets, 'AbsTol', 1.01 / s.stim_fs);
    verifyEqual(tests, onsetTimes, (onsetIdx - 1) / s.stim_fs);
    verifyEqual(tests, nValid, numel(s.truth.onsets));
    post = t > 0 & t < 0.1;
    tPost = t(post);
    [~, iMin] = min(erpAvg(:, post), [], 2);
    sink = s.truth.sinkChannel;
    verifyEqual(tests, tPost(iMin(sink)), s.truth.n1LatencyS, 'AbsTol', 0.003);
    [~, deepest] = min(min(erpAvg, [], 2));
    verifyEqual(tests, deepest, sink);
    [~, iN1] = min(abs(t - s.truth.n1LatencyS));
    [~, csdSink] = min(csd(:, iN1));                      % sinks are negative
    verifyEqual(tests, csdSink, sink);
end

function testDetectOnsetsEdgeCases(tests)
    fs = 1000; stim = zeros(1, 5000);
    stim(1001:1020) = 1; stim(1101:1120) = 1; stim(3001:3020) = 1;
    [tOn, idx] = ERPAnalysis.detectOnsets(stim, fs, 0.5, 0.5);
    verifyEqual(tests, idx, [1001 3001]);                 % 2nd pulse within min ISI: dropped
    verifyEqual(tests, tOn, [1000 3000] / fs);            % sample k at (k-1)/fs
    verifyEqual(tests, ERPAnalysis.detectOnsets(stim(:), fs, 0.5, 0.5), tOn);   % column stimulus
    verifyEmpty(tests, ERPAnalysis.detectOnsets(zeros(1, 100), fs, 0.5, 0.5));   % none: empty, no error
    verifyError(tests, @() ERPAnalysis.detectOnsets(ones(2, 10), fs, 0.5, 0.5), ...
        'NeuroAnalyzer:ERPAnalysis:stimNotVector');
end

function testAverageSkipsEdgeEpochs(tests)
    fs = 100; lfp = [1:1000; 2 * (1:1000)];
    [avg, sd, t, nValid, epochs, valid] = ERPAnalysis.average(lfp, fs, [0.05 2 5 9.95], 0.1, 0.2);
    verifyEqual(tests, nValid, 2);
    verifyEqual(tests, valid, [false true true false]);
    verifyEqual(tests, t, (-10:20) / fs);
    verifyEqual(tests, avg(1, :), mean([191:221; 491:521], 1), 'AbsTol', 1e-12);   % onsets at samples 201, 501
    verifyEqual(tests, sd(2, :), std(2 * [191:221; 491:521], 0, 1), 'AbsTol', 1e-12);
    verifyTrue(tests, all(isnan(epochs(:, :, 1)), 'all'));
end

function testCsdQuadraticProfile(tests)
    % V(z) = z^2 (z in m) has d2V/dz2 = 2 everywhere, so CSD = -2 (edge rows replicated)
    z = (0:4)' * 100e-6;
    erp = repmat(z.^2, 1, 3);
    verifyEqual(tests, ERPAnalysis.csd(erp, 100), -2 * ones(5, 3), 'RelTol', 1e-9);
    verifyError(tests, @() ERPAnalysis.csd(erp, 100, [1 2]), 'NeuroAnalyzer:ERPAnalysis:tooFewChannels');
    verifyError(tests, @() ERPAnalysis.csd(erp, 0), 'NeuroAnalyzer:ERPAnalysis:badSpacing');
end

%% ------------------------------------------------------ Oscillation demo

function testOscillationDemoGroundTruth(tests)
    s = tests.TestData.osc; b = tests.TestData.lfp;
    th = s.truth.theta; g = s.truth.gamma;
    verifyEqual(tests, s.stim_data, b.stim_data);
    verifyEqual(tests, [th.freqHz g.freqHz], [6 40]);
    verifyEqual(tests, g.channels, 3:5);
    d = s.lfp_data - b.lfp_data;                          % the added oscillations
    verifyEqual(tests, max(abs(d(1, :))), th.amplitudeV, 'RelTol', 1e-3);   % ch 1: theta only
    verifyEqual(tests, d(8, :), d(1, :), 'AbsTol', 1e-12);                  % same theta everywhere
    burst = d(4, :) - d(1, :);                            % gamma only
    verifyEqual(tests, max(abs(burst)), g.amplitudeV, 'RelTol', 0.01);
    verifyEqual(tests, d(3, :), d(4, :), 'AbsTol', 1e-12);
    verifyEqual(tests, d(5, :), d(4, :), 'AbsTol', 1e-12);
    verifyLessThan(tests, max(abs(d(6, :) - d(1, :))), 1e-12);
    tRel = mod(s.t_lfp - s.truth.onsets(1), 2);           % time since the last stimulus
    outside = s.t_lfp < s.truth.onsets(1) | tRel < g.windowS(1) | tRel > g.windowS(2);
    verifyLessThan(tests, max(abs(burst(outside))), 0.01 * g.amplitudeV);
    [pxx, f] = TimeFrequency.welchPSD(d(1, :), s.lfp_fs, 4);
    [~, k] = max(pxx);
    verifyEqual(tests, f(k), th.freqHz, 'AbsTol', 1);
end

%% ------------------------------------------------ Previous app code (reference)

%% legacyERP - LFPAnalysisApp.computeERP before the move to ERPAnalysis (verbatim maths)
function r = legacyERP(s, chIdx, p)
    fs = s.lfp_fs;
    stim = s.stim_data;
    stim = stim - mean(stim);
    above = stim > p.threshold;
    onsets = find(diff([0 above]) == 1);
    isi = diff(onsets) / s.stim_fs;
    validIdx = [true, isi > p.minISI];
    onsets = onsets(validIdx);
    onsetTimes = (onsets - 1) / s.stim_fs;
    preSamples = round(p.preTime * fs);
    postSamples = round(p.postTime * fs);
    totalSamples = preSamples + postSamples + 1;
    erpMat = nan(length(chIdx), totalSamples, length(onsetTimes));
    nValid = 0;
    for t = 1:length(onsetTimes)
        centerIdx = round(onsetTimes(t) * fs) + 1;
        idxRange = centerIdx - preSamples : centerIdx + postSamples;
        if idxRange(1) < 1 || idxRange(end) > size(s.lfp_data, 2)
            continue;
        end
        erpMat(:, :, t) = s.lfp_data(chIdx, idxRange);
        nValid = nValid + 1;
    end
    r.onsetTimes = onsetTimes;
    r.erpAvg = mean(erpMat, 3, 'omitnan');
    r.erpStd = std(erpMat, 0, 3, 'omitnan');
    r.t = (-preSamples:postSamples) / fs;
    r.nValid = nValid;
end

%% legacyCSD - LFPAnalysisApp.computeCSD maths before the move to ERPAnalysis
function csd = legacyCSD(erpAll, spacingUm, reorder)
    spacing_um = spacingUm * 1e-6;
    erp = erpAll(reorder, :);
    dz  = spacing_um;
    csd = -diff(erp, 2, 1) / dz^2;
    csd = [csd(1,:); csd; csd(end,:)];
end
