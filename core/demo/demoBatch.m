%% demoBatch.m
% =========================================================================
% DEMO BATCH - SEVERAL SYNTHETIC FILES PER PIPELINE WITH KNOWN ANSWERS
% =========================================================================
% Input files for Batch processing (Batch.run / BatchApp.loadDemo): each
% file of a set has slightly different, known truths, so a batch summary
% can be checked row by row.
%
%   demo = demoBatch(pipeline)            writes to tempdir/NeuroAnalyzerDemo/batch/<pipeline>
%   demo = demoBatch(pipeline, folder)    writes to folder (created if needed)
%   demo = demoBatch(pipeline, folder, n) n files ('mua': always 2)
%
% Output struct demo: pipeline, folder, files (1 x n cellstr, sorted by
% name), truth (1 x n struct array, one per file, fields below) and params
% (Batch settings that suit the demo, complete: Batch.defaults + changes).
%
% Deterministic: RandStream('mt19937ar', 'Seed', 20260930 + pipeline
% offset); the same call always writes the same files.
%
% Pipelines (file k = 1..n):
%   'ldf'       cropped LDF (stim, LDF, t, Fs as saved by Extract LDF),
%               n = 4: 200 s at 1000 Hz, 7 stimuli (5 V, 5 s) at 10, 40,
%               ..., 190 s; LDF = baseline (115 + 5k PU) + slow drift +
%               vasomotion (0.13 Hz, 2 PU) + cardiac ripple (6 Hz, 1.5 PU) +
%               noise (SD 2 PU) + a gamma-shaped response per stimulus
%               (DemoData's shape) of amplitude 15 + 5k PU (20, 25, 30,
%               35) peaking 2.5 + 0.5k s after onset (3, 3.5, 4, 4.5).
%               truth: amplitude, peakDelay, baseline, onsets (s), nOnsets
%               (7), nTrials (6 with pre 5 s / post 20 s).
%   'erp'       LFP file (lfp_data, lfp_channels, lfp_fs, t_lfp, stim_data,
%               stim_fs, t_stim as saved by Extract Ephys), n = 3: 8
%               channels 100 um apart, 20 s at 1000 Hz, 10 stimuli (20 ms,
%               amplitude 1) every 2 s from 1 s. Evoked potential: N1 at
%               9 + 3k ms (12, 15, 18) of -(80 + 20k) uV and P2 25 ms later
%               (+50 uV), with a Gaussian depth profile (SD 150 um) centred
%               on channel 2 + k (3, 4, 5) = the CSD sink; plus a shared
%               1/f-like background (cancels in the CSD) and local noise.
%               truth: n1LatencyMs, n1AmplitudeUv (at the sink channel),
%               sinkChannel, onsets, nOnsets.
%   'mua'       MUA file (as saved by Extract Ephys), n = 2: file 1 is the
%               DemoData MUA recording (channels 3-5, 30 s at 24414 Hz,
%               units of ~90 and ~50 uV on channel 4); file 2 the same
%               recording recorded with twice the gain (mua_data x 2,
%               an exact scaling, so sorting finds the same spikes).
%               truth: gain, DemoData's truth (units, onsets).
%   'roi'       imaging .mat (stack, timeVec, roiMask), n = 3: 64 x 64 x
%               100 frames at 10 Hz. A cell (disk, radius 5 px, centre
%               (20, 20), the roiMask) whose fluorescence is F0 (1 + dF/F):
%               calcium transients at 3 and 6.5 s of peak dF/F 0.5k (0.5,
%               1.0, 1.5); a dark vertical vessel at x = 44 whose diameter
%               is 8 + 2k +/- 2 px (10, 12, 14 on average) at 0.2 Hz.
%               truth: peakDFF, peakDFFTime, meanDiameter, diameter (1 x N),
%               line [25 50 63 50] (across the vessel, used in params).
%   'features'  segmented LDF trials (segmentedLDF, segmentedTime, Fs as
%               saved by LDF Processing), n = 4: 8 trials from -5 to 20 s at
%               10 Hz, baseline 120 PU, response amplitude 15 + 5k PU and
%               peak delay 2.5 + 0.5k s (as 'ldf'), trial-to-trial
%               amplitude jitter (SD 1 PU) and noise (SD 0.5 PU).
%               truth: amplitude (realized mean over trials), peakDelay,
%               baseline, nTrials.
% =========================================================================

function demo = demoBatch(pipeline, folder, n)
    pipeline = lower(char(pipeline));
    if nargin < 2 || isempty(folder)
        folder = fullfile(tempdir, 'NeuroAnalyzerDemo', 'batch', pipeline);
    end
    defaultN = struct('ldf', 4, 'erp', 3, 'mua', 2, 'roi', 3, 'features', 4);
    if ~isfield(defaultN, pipeline)
        error('NeuroAnalyzer:demoBatch:pipeline', 'Unknown pipeline ''%s'' (ldf, erp, mua, roi, features).', pipeline);
    end
    if nargin < 3 || isempty(n), n = defaultN.(pipeline); end
    if exist(folder, 'dir') ~= 7, mkdir(folder); end
    offsets = struct('ldf', 1, 'erp', 2, 'mua', 3, 'roi', 4, 'features', 5);
    rs = RandStream('mt19937ar', 'Seed', 20260930 + offsets.(pipeline));

    switch pipeline
        case 'ldf',      [files, truth, params] = makeLDF(folder, n, rs);
        case 'erp',      [files, truth, params] = makeERP(folder, n, rs);
        case 'mua',      [files, truth, params] = makeMUA(folder);
        case 'roi',      [files, truth, params] = makeROI(folder, n, rs);
        otherwise,       [files, truth, params] = makeFeatures(folder, n, rs);
    end
    demo = struct('pipeline', pipeline, 'folder', folder, 'files', {files}, ...
        'truth', truth, 'params', params);
end

%% makeLDF - Cropped LDF recordings with different response amplitude / delay
function [files, truth, params] = makeLDF(folder, n, rs)
    Fs = 1000; T = 200;
    t = (0:T*Fs) / Fs;
    onsets = 10:30:190; dur = 5;
    files = cell(1, n);
    truth = struct('amplitude', {}, 'peakDelay', {}, 'baseline', {}, 'onsets', {}, ...
        'nOnsets', {}, 'nTrials', {});
    for k = 1:n
        amp = 15 + 5 * k; tp = 2.5 + 0.5 * k; base = 115 + 5 * k;
        stim = zeros(size(t));
        for j = 1:numel(onsets)
            stim(t >= onsets(j) & t < onsets(j) + dur) = 5;
        end
        stim = stim + 0.01 * randn(rs, size(t));
        phase = 2 * pi * rand(rs);
        ldf = base + 5 * sin(2 * pi * t / 400) + 2 * sin(2 * pi * 0.13 * t + phase) ...
            + 1.5 * sin(2 * pi * 6 * t) + 2 * randn(rs, size(t));
        for j = 1:numel(onsets)
            ldf = ldf + amp * gammaShape(t - onsets(j), tp);
        end
        s = struct('stim', stim, 'LDF', ldf, 't', t, 'Fs', Fs);
        s.truth = struct('amplitude', amp, 'peakDelay', tp, 'baseline', base, 'onsets', onsets, ...
            'nOnsets', numel(onsets), 'nTrials', sum(onsets - 5 >= 0 & onsets + 20 <= T));
        files{k} = fullfile(folder, sprintf('ldf_animal%02d.mat', k));
        save(files{k}, '-struct', 's');
        truth(k) = s.truth;
    end
    params = Batch.completeParams('ldf', struct('downsample', 10, 'filterType', 'Low-pass', ...
        'cutoffHigh', 1, 'filterOrder', 4, 'threshold', 2.5, 'preSec', 5, 'postSec', 20, 'minISI', 1));
end

%% makeERP - LFP recordings with different N1 latency and sink channel
function [files, truth, params] = makeERP(folder, n, rs)
    fs = 1000; T = 20; nCh = 8; spacing = 100;
    nL = T * fs;
    tL = (0:nL - 1) / fs;
    onsets = 1:2:19;
    stim = zeros(1, nL);
    for j = 1:numel(onsets)
        stim(tL >= onsets(j) & tL < onsets(j) + 0.02) = 1;
    end
    depth = (0:nCh - 1) * spacing;
    files = cell(1, n);
    truth = struct('n1LatencyMs', {}, 'n1AmplitudeUv', {}, 'sinkChannel', {}, 'onsets', {}, 'nOnsets', {});
    for k = 1:n
        n1 = (9 + 3 * k) / 1000; a1 = -(80 + 20 * k) * 1e-6;
        sinkCh = 2 + mod(k - 1, 5) + 1;
        profile = exp(-(depth - (sinkCh - 1) * spacing).^2 / (2 * 150^2));
        erp = @(x) a1 * exp(-(x - n1).^2 / (2 * 0.005^2)) + 50e-6 * exp(-(x - n1 - 0.025).^2 / (2 * 0.012^2));
        evoked = zeros(1, nL);
        for j = 1:numel(onsets)
            x = tL - onsets(j);
            on = x >= 0 & x < 0.3;
            evoked(on) = evoked(on) + erp(x(on));
        end
        shared = filter(1, [1 -0.98], randn(rs, 1, nL)) * 3e-6;
        lfp = zeros(nCh, nL);
        for c = 1:nCh
            local = filter(1, [1 -0.9], randn(rs, 1, nL)) * 0.3e-6;
            lfp(c, :) = profile(c) * evoked + shared + local + 1e-6 * randn(rs, 1, nL);
        end
        s = struct('lfp_data', lfp, 'lfp_channels', 1:nCh, 'lfp_fs', fs, 't_lfp', tL, ...
            'stim_data', stim, 'stim_fs', fs, 't_stim', tL);
        s.truth = struct('n1LatencyMs', 1000 * n1, 'n1AmplitudeUv', 1e6 * a1, 'sinkChannel', sinkCh, ...
            'onsets', onsets, 'nOnsets', numel(onsets));
        files{k} = fullfile(folder, sprintf('lfp_animal%02d.mat', k));
        save(files{k}, '-struct', 's');
        truth(k) = s.truth;
    end
    params = Batch.completeParams('erp', struct('preTime', 0.05, 'postTime', 0.2, 'threshold', 0.5, ...
        'minISI', 0.5, 'computeCSD', true, 'spacingUm', spacing));
end

%% makeMUA - The DemoData MUA recording, as is and with twice the gain
function [files, truth, params] = makeMUA(folder)
    s = load(DemoData.file('mua'));
    gains = [1 2];
    files = cell(1, 2);
    truth = struct('gain', {}, 'demo', {});
    base = s;
    for k = 1:2
        s = base;
        s.mua_data = gains(k) * double(base.mua_data);
        s.truth = struct('gain', gains(k), 'demo', base.truth);
        files{k} = fullfile(folder, sprintf('mua_session%02d.mat', k));
        save(files{k}, '-struct', 's', '-v7');
        truth(k) = s.truth;
    end
    params = Batch.completeParams('mua', struct('channels', 4, 'detectMethod', 'MAD', ...
        'threshold', 4, 'polarity', 'negative', 'seed', 0));
end

%% makeROI - Stacks with different calcium transient size and vessel diameter
function [files, truth, params] = makeROI(folder, n, rs)
    H = 64; W = 64; N = 100; fps = 10;
    t = (0:N - 1) / fps;
    [X, Y] = meshgrid(1:W, 1:H);
    cellMask = (X - 20).^2 + (Y - 20).^2 <= 5^2;
    cx = 44; lineXY = [25 50 63 50];
    kernel = @(u) (u > 0) .* exp(-max(u, 0) / 0.8) .* (1 - exp(-max(u, 0) / 0.1));
    files = cell(1, n);
    truth = struct('peakDFF', {}, 'peakDFFTime', {}, 'meanDiameter', {}, 'diameter', {}, 'line', {});
    for k = 1:n
        dffAmp = 0.5 * k / 0.675;              % kernel peak is ~0.675
        dff = dffAmp * (kernel(t - 3) + kernel(t - 6.5));
        diam = 8 + 2 * k + 2 * sin(2 * pi * 0.2 * t);
        texture = 0.05 * smooth2(randn(rs, H, W), 2);
        stack = zeros(H, W, N);
        for f = 1:N
            vessel = 1 ./ (1 + exp((abs(X - cx) - diam(f) / 2) / 0.8));
            frame = (0.6 + texture) .* (1 - 0.7 * vessel);
            frame(cellMask) = 0.8 * (1 + dff(f));
            stack(:, :, f) = frame + 0.02 * randn(rs, H, W);
        end
        [pk, ip] = max(dff);
        s = struct('stack', single(stack), 'timeVec', t, 'roiMask', cellMask);
        s.truth = struct('peakDFF', pk, 'peakDFFTime', t(ip), 'meanDiameter', mean(diam), ...
            'diameter', diam, 'line', lineXY);
        files{k} = fullfile(folder, sprintf('imaging_fov%02d.mat', k));
        save(files{k}, '-struct', 's');
        truth(k) = s.truth;
    end
    params = Batch.completeParams('roi', struct('measure', 'All', 'baselineFrames', 20, ...
        'line', lineXY, 'robust', true));
end

%% makeFeatures - Segmented LDF trial files with different amplitude / delay
function [files, truth, params] = makeFeatures(folder, n, rs)
    Fs = 10; segT = -5:1/Fs:20; nTrials = 8; base = 120;
    files = cell(1, n);
    truth = struct('amplitude', {}, 'peakDelay', {}, 'baseline', {}, 'nTrials', {});
    for k = 1:n
        amp = 15 + 5 * k; tp = 2.5 + 0.5 * k;
        trialAmp = amp + 1 * randn(rs, nTrials, 1);
        seg = zeros(nTrials, numel(segT));
        for j = 1:nTrials
            seg(j, :) = base + trialAmp(j) * gammaShape(segT, tp) + 0.5 * randn(rs, 1, numel(segT));
        end
        s = struct('segmentedLDF', seg, 'segmentedTime', segT, 'Fs', Fs);
        s.truth = struct('amplitude', mean(trialAmp), 'peakDelay', tp, 'baseline', base, 'nTrials', nTrials);
        files{k} = fullfile(folder, sprintf('trials_animal%02d.mat', k));
        save(files{k}, '-struct', 's');
        truth(k) = s.truth;
    end
    params = Batch.completeParams('features', struct('t0', 0, 'autoBaseline', true, ...
        'direction', 'Auto', 'seriesMode', 'Mean of series'));
end

%% gammaShape - x^3 exp(3 (1 - x)), x = t / tp: 0 before 0, peak 1 at t = tp
function g = gammaShape(t, tp)
    x = t / tp;
    g = zeros(size(t));
    on = x > 0;
    g(on) = x(on).^3 .* exp(3 * (1 - x(on)));
end

%% smooth2 - Small separable Gaussian blur (toolbox-free)
function y = smooth2(x, sigma)
    r = ceil(2 * sigma);
    g = exp(-((-r:r).^2) / (2 * sigma^2)); g = g / sum(g);
    y = conv2(g, g, x, 'same');
end
