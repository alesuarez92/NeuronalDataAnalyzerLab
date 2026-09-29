%% demoLFPOscillations.m
% =========================================================================
% DEMO LFP WITH OSCILLATIONS - DemoData.lfpFile PLUS THETA AND EVOKED GAMMA
% =========================================================================
% s = demoLFPOscillations() returns the same struct as DemoData.lfpFile()
% (lfp_data, lfp_channels, lfp_fs, t_lfp, stim_data, stim_fs, t_stim,
% truth: 8 channels 100 um apart at 1017.25 Hz, 30 s, 20 ms stimuli every
% 2 s from 1 s, ERP with N1 at 15 ms / P2 at 40 ms and its sink at ch 4,
% 1/f background shared across channels) with two oscillations added:
%
%   Theta (ongoing)     6 Hz, constant amplitude 40 uV, identical on all
%                       8 channels (volume conducted, so it cancels in the
%                       CSD). Its instantaneous frequency wanders slowly
%                       (SD 0.5 Hz, correlation time ~0.5 s), so its phase
%                       is NOT locked to the stimuli (low ITPC), while its
%                       power in 4-8 Hz stays constant over time (A^2 =
%                       1.6e-9 V^2, plus a few % of 1/f background).
%   Gamma (evoked)      40 Hz burst from 50 to 250 ms after each stimulus
%                       onset on channels 3-5, amplitude 10 uV (flat top,
%                       25 ms raised-cosine ramps at each end), starting
%                       with the same phase at every stimulus (phase-locked:
%                       ITPC near 1, ERSP clearly above 0 dB there).
%
% Ground truth is added to s.truth.theta and s.truth.gamma (fields: freqHz,
% amplitudeV, channels, phaseLocked, plus freqJitterSdHz for theta and
% windowS, rampS for gamma). Deterministic: DemoData's seed for the base
% recording, RandStream('mt19937ar', 'Seed', DemoData.Seed + 101) for the
% theta frequency wander.
% =========================================================================

function s = demoLFPOscillations()
    s = DemoData.lfpFile();
    rs = RandStream('mt19937ar', 'Seed', DemoData.Seed + 101);
    fs = s.lfp_fs;
    t = s.t_lfp;
    nCh = size(s.lfp_data, 1);
    onsets = s.truth.onsets;

    % --- Theta: constant amplitude, slowly wandering frequency, all channels ---
    theta = struct('freqHz', 6, 'amplitudeV', 40e-6, 'channels', 1:nCh, ...
        'phaseLocked', false, 'freqJitterSdHz', 0.5);
    a = exp(-1 / (0.5 * fs));                          % AR(1): ~0.5 s correlation time
    jitter = filter(1 - a, [1 -a], randn(rs, 1, numel(t)));
    jitter = theta.freqJitterSdHz * (jitter - mean(jitter)) / std(jitter);
    phase = 2 * pi * cumsum(theta.freqHz + jitter) / fs + 2 * pi * rand(rs);
    thetaWave = theta.amplitudeV * cos(phase);

    % --- Gamma: phase-locked 40 Hz burst 50-250 ms after each onset, ch 3-5 ---
    gamma = struct('freqHz', 40, 'amplitudeV', 10e-6, 'channels', 3:5, ...
        'phaseLocked', true, 'windowS', [0.05 0.25], 'rampS', 0.025);
    burst = zeros(1, numel(t));
    for k = 1:numel(onsets)
        x = t - onsets(k);
        on = x >= gamma.windowS(1) & x <= gamma.windowS(2);
        xo = x(on);
        env = ones(size(xo));
        up = xo < gamma.windowS(1) + gamma.rampS;
        env(up) = 0.5 * (1 - cos(pi * (xo(up) - gamma.windowS(1)) / gamma.rampS));
        down = xo > gamma.windowS(2) - gamma.rampS;
        env(down) = 0.5 * (1 - cos(pi * (gamma.windowS(2) - xo(down)) / gamma.rampS));
        burst(on) = burst(on) + gamma.amplitudeV * env .* sin(2 * pi * gamma.freqHz * (xo - gamma.windowS(1)));
    end

    s.lfp_data = s.lfp_data + thetaWave;
    s.lfp_data(gamma.channels, :) = s.lfp_data(gamma.channels, :) + burst;
    s.truth.theta = theta;
    s.truth.gamma = gamma;
end
