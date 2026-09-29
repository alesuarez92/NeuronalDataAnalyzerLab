%% TimeFrequency.m
% =========================================================================
% TIME-FREQUENCY - SPECTRA, SPECTROGRAMS, WAVELETS, ERSP / ITPC, BAND POWER
% =========================================================================
% Headless, toolbox-free (base MATLAB: fft/ifft only) spectral analysis of
% LFP-like signals. Used by LFPAnalysisApp (step 6 Time-frequency); every
% method also works from scripts. Signals are vectors, or matrices with
% one signal per ROW; sampling rate fs in Hz; times in s, with sample k at
% (k-1)/fs as everywhere else in the toolbox.
%
%   [pxx, f] = TimeFrequency.welchPSD(x, fs, segSec, overlap, nfft)
%       Welch power spectral density: Hann-windowed segments (default
%       2 s, 50% overlap), each segment's mean removed, one-sided
%       periodograms averaged. Density scaling (units^2/Hz): the total
%       power sum(pxx) * (f(2) - f(1)) equals the signal variance.
%   [P, f, t] = TimeFrequency.stft(x, fs, winSec, overlap, fRange)
%       Short-time Fourier power (spectrogram) for a continuous overview:
%       Hann windows of winSec (default 0.5 s) with the given overlap
%       (default 0.9), same density scaling as welchPSD. P is freq x time;
%       t is each window's centre (s). fRange [fmin fmax] keeps those rows.
%   [coef, pow, phase] = TimeFrequency.morletTF(x, fs, freqs, nCycles)
%       Complex Morlet wavelet transform by FFT convolution. For each
%       frequency f the wavelet is exp(2*pi*i*f*t) * exp(-t^2 / (2*s^2))
%       with s = nCycles / (2*pi*f) (default 7 cycles), truncated at
%       +/-3*s and normalised to unit energy (sum |w|^2 = 1), so white
%       noise has the same expected power at every frequency. The row mean
%       is removed first. coef is freq x time (x rows for a matrix input);
%       pow = |coef|^2, phase = angle(coef) (cosine phase: a cosine peak
%       has phase 0).
%   [p, z] = TimeFrequency.bandPower(x, fs, bands)
%       Band power over time: the analytic signal z of the band-passed
%       signal (FFT filter: gain 1 inside [lo hi], raised-cosine edges of
%       width min(2, max(0.1, (hi - lo) / 4)) Hz just outside, negative
%       frequencies removed - the FFT form of band-pass + Hilbert), and
%       p = |z|^2 (instantaneous power; a sinusoid of amplitude A in the
%       band gives p = A^2). bands is nBands x 2 (Hz); p is nBands x time
%       (x rows). The signal is mirror-extended to limit edge effects.
%   r = TimeFrequency.eventBandPower(x, fs, onsets, window, bands, baselineWindow)
%       bandPower of the continuous signal cut into epochs around each
%       onset (window [tmin tmax] s; onset sample round(onset*fs)+1),
%       expressed per trial as % change from the trial-averaged power in
%       baselineWindow; r.mean and r.sem (standard error across trials)
%       are nBands x time. Per band, only epochs at least one filter
%       settling time (1 / edge width, s) from the recording ends are used
%       (r.nTrials per band); the others are NaN in r.power / r.pctChange.
%   [erspDb, itpc, t, info] = TimeFrequency.ersp(x, fs, onsets, window, ...
%                                                freqs, baselineWindow, nCycles)
%       Event-related spectral perturbation and inter-trial phase
%       coherence. Epochs (window [tmin tmax] s around each onset) are
%       Morlet-transformed from the continuous signal (mean removed), then
%         ERSP(f,t) = 10*log10( mean_k P_k(f,t) / B(f) )   dB,
%       B(f) = trial-averaged power in baselineWindow, and
%         ITPC(f,t) = | mean_k coef_k(f,t) / |coef_k(f,t)| |   (0..1).
%       At each frequency only the epochs whose wavelet support (window
%       +/- 3*s) lies inside the recording are used, so low frequencies
%       may use fewer trials (info.nTrialsPerFreq); nothing is padded.
%       info: nTrials (max over frequencies), nTrialsPerFreq, nOnsets,
%       onsets (epoch inside the recording), freqs, nCycles, meanPower,
%       baselinePower, window, baselineWindow.
%   bands = TimeFrequency.defaultBands()
%       Conventional LFP/EEG bands (delta 1-4, theta 4-8, alpha 8-13,
%       beta 13-30, gamma 30-80 Hz) as a struct array with name / range.
%       These limits are conventions and differ between species and labs.
%
% Method references:
%   Welch PD (1967). The use of fast Fourier transform for the estimation
%     of power spectra: a method based on time averaging over short,
%     modified periodograms. IEEE Trans Audio Electroacoust 15(2):70-73.
%   Tallon-Baudry C, Bertrand O, Delpuech C, Pernier J (1996). Stimulus
%     specificity of phase-locked and non-phase-locked 40 Hz visual
%     responses in human. J Neurosci 16(13):4240-4249. (Morlet wavelet
%     power and the phase-locking factor, i.e. ITPC.)
%   Makeig S (1993). Auditory event-related dynamics of the EEG spectrum
%     and effects of exposure to tones. Electroencephalogr Clin
%     Neurophysiol 86(4):283-293. (ERSP.)
%   Pfurtscheller G, Lopes da Silva FH (1999). Event-related EEG/MEG
%     synchronization and desynchronization: basic principles. Clin
%     Neurophysiol 110(11):1842-1857. (Band power as % change from a
%     pre-stimulus reference.)
% =========================================================================

classdef TimeFrequency
    methods(Static)

        %% welchPSD - Welch PSD: Hann segments, 50% overlap, averaged periodograms
        % segSec: segment length (s, default 2, capped at the signal length);
        % overlap: fraction 0..<1 (default 0.5); nfft: FFT length (default
        % next power of 2 >= segment). OUTPUT pxx: one-sided PSD
        % (units^2/Hz), freq x rows for a matrix input (column for a
        % vector); f: frequencies (Hz, column).
        function [pxx, f] = welchPSD(x, fs, segSec, overlap, nfft)
            if nargin < 3 || isempty(segSec), segSec = 2; end
            if nargin < 4 || isempty(overlap), overlap = 0.5; end
            X = TimeFrequency.asRows(x);
            n = size(X, 2);
            nWin = min(n, max(8, round(segSec * fs)));
            if nargin < 5 || isempty(nfft), nfft = 2^nextpow2(nWin); end
            step = max(1, round(nWin * (1 - overlap)));
            f = (0:floor(nfft / 2)).' * fs / nfft;
            pxx = zeros(numel(f), size(X, 1));
            for r = 1:size(X, 1)
                P = TimeFrequency.framePSD(X(r, :), fs, nWin, step, nfft, 1:numel(f));
                pxx(:, r) = mean(P, 2);
            end
        end

        %% stft - Short-time Fourier power (freq x time) with Hann windows
        % x: vector. winSec: window (s, default 0.5); overlap: 0..<1
        % (default 0.9); fRange: [fmin fmax] Hz to keep (default all).
        % OUTPUT P: PSD per window (units^2/Hz), f (Hz, column), t (s, row:
        % window centres).
        function [P, f, t] = stft(x, fs, winSec, overlap, fRange)
            if nargin < 3 || isempty(winSec), winSec = 0.5; end
            if nargin < 4 || isempty(overlap), overlap = 0.9; end
            if nargin < 5, fRange = []; end
            x = TimeFrequency.asRows(x);
            if size(x, 1) ~= 1
                error('NeuroAnalyzer:TimeFrequency:notVector', 'stft expects a single signal (vector).');
            end
            n = numel(x);
            nWin = max(8, round(winSec * fs));
            if nWin > n
                error('NeuroAnalyzer:TimeFrequency:tooShort', ...
                    'The signal (%d samples) is shorter than the window (%d samples).', n, nWin);
            end
            nfft = 2^nextpow2(nWin);
            step = max(1, round(nWin * (1 - overlap)));
            fAll = (0:floor(nfft / 2)).' * fs / nfft;
            keep = 1:numel(fAll);
            if ~isempty(fRange)
                keep = find(fAll >= fRange(1) & fAll <= fRange(2));
                if isempty(keep)
                    error('NeuroAnalyzer:TimeFrequency:emptyRange', 'No frequencies in the requested range.');
                end
            end
            f = fAll(keep);
            [P, starts] = TimeFrequency.framePSD(x, fs, nWin, step, nfft, keep);
            t = (starts - 1 + (nWin - 1) / 2) / fs;
        end

        %% morletTF - Complex Morlet wavelet transform (unit-energy wavelets, FFT convolution)
        % x: vector or matrix (one signal per row). freqs: Hz (each > 0 and
        % < fs/2). nCycles: scalar or one value per frequency (default 7).
        % OUTPUT coef: freq x time (vector input) or freq x time x rows.
        function [coef, pow, phase] = morletTF(x, fs, freqs, nCycles)
            if nargin < 4 || isempty(nCycles), nCycles = 7; end
            [freqs, nCycles] = TimeFrequency.checkFreqs(freqs, nCycles, fs);
            X = TimeFrequency.asRows(x);
            X = X - mean(X, 2);
            [nR, n] = size(X);
            nF = numel(freqs);
            halfMax = TimeFrequency.halfLength(fs, min(freqs ./ nCycles));
            nfft = 2^nextpow2(n + 2 * halfMax);
            Xf = fft(X, nfft, 2);
            coef = complex(zeros(nF, n, nR));
            for i = 1:nF
                [w, h] = TimeFrequency.wavelet(fs, freqs(i), nCycles(i));
                y = ifft(Xf .* fft(w, nfft), nfft, 2);       % linear convolution (no wrap)
                coef(i, :, :) = permute(y(:, h + (1:n)), [3 2 1]);   % 'same' part
            end
            pow = abs(coef).^2;
            phase = angle(coef);
        end

        %% bandPower - Instantaneous band power |analytic band-passed signal|^2
        % x: vector or matrix (rows). bands: [lo hi] or nBands x 2 (Hz).
        % OUTPUT p: nBands x time (vector input) or nBands x time x rows;
        % z: the complex analytic band signals, same size.
        function [p, z] = bandPower(x, fs, bands)
            if size(bands, 2) ~= 2 || any(bands(:, 1) >= bands(:, 2)) || any(bands(:) < 0)
                error('NeuroAnalyzer:TimeFrequency:badBand', 'Each band must be [low high] with 0 <= low < high (Hz).');
            end
            if any(bands(:, 1) >= fs / 2)
                error('NeuroAnalyzer:TimeFrequency:badBand', 'Band starts above the Nyquist frequency (%g Hz).', fs / 2);
            end
            X = TimeFrequency.asRows(x);
            [nR, n] = size(X);
            nB = size(bands, 1);
            % Mirror extension (about 4 filter time constants of the narrowest edge)
            wMin = min(TimeFrequency.edgeWidth(bands));
            m = min(n - 1, ceil(4 * fs / wMin));
            if m > 0
                Xe = [fliplr(X(:, 2:m + 1)), X, fliplr(X(:, n - m:n - 1))];
            else
                Xe = X;
            end
            nfft = 2^nextpow2(size(Xe, 2));
            Xf = fft(Xe, nfft, 2);
            fk = (0:nfft - 1) * fs / nfft;
            pos = fk > 0 & fk < fs / 2;                  % positive frequencies only
            z = complex(zeros(nB, n, nR));
            for b = 1:nB
                H = 2 * TimeFrequency.bandGain(fk, bands(b, :)) .* pos;
                y = ifft(Xf .* H, nfft, 2);
                z(b, :, :) = permute(y(:, m + (1:n)), [3 2 1]);
            end
            p = abs(z).^2;
        end

        %% eventBandPower - Band power epochs around onsets, % change from baseline
        % x: vector (continuous). onsets: s. window, baselineWindow: [t1 t2] s
        % relative to onset (baseline inside the window). bands: nBands x 2.
        % OUTPUT r: t (s), bands, power (nBands x time x trials, units^2),
        % pctChange (same size), mean / sem of pctChange (nBands x time),
        % meanPower (nBands x time), baselinePower (nBands x 1), nTrials,
        % onsets (those used: epoch fully inside the recording).
        function r = eventBandPower(x, fs, onsets, window, bands, baselineWindow)
            x = TimeFrequency.asRows(x);
            if size(x, 1) ~= 1
                error('NeuroAnalyzer:TimeFrequency:notVector', 'eventBandPower expects a single signal (vector).');
            end
            n = numel(x);
            [rel, t, c, used] = TimeFrequency.epochGrid(n, fs, onsets, window);
            baseMask = TimeFrequency.baselineMask(t, baselineWindow);
            p = TimeFrequency.bandPower(x, fs, bands);                 % nBands x n
            nB = size(bands, 1); nT = numel(rel); nTr = numel(c);
            % Per band, only epochs at least one filter settling time
            % (1 / edge width) away from the recording ends
            margin = ceil(fs ./ TimeFrequency.edgeWidth(bands));
            ep = nan(nB, nT, nTr); pct = ep;
            mu = nan(nB, nT); se = mu; mp = mu;
            base = nan(nB, 1); nTrials = zeros(nB, 1);
            for b = 1:nB
                ok = find(c + rel(1) - margin(b) >= 1 & c + rel(end) + margin(b) <= n);
                if isempty(ok), continue; end
                e = zeros(1, nT, numel(ok));
                for k = 1:numel(ok)
                    e(1, :, k) = p(b, c(ok(k)) + rel);
                end
                base(b) = mean(mean(e(1, baseMask, :), 3), 2);
                pc = 100 * (e / base(b) - 1);
                ep(b, :, ok) = e; pct(b, :, ok) = pc;
                mu(b, :) = mean(pc, 3);
                se(b, :) = std(pc, 0, 3) / sqrt(numel(ok));
                mp(b, :) = mean(e, 3);
                nTrials(b) = numel(ok);
            end
            if ~any(nTrials)
                error('NeuroAnalyzer:TimeFrequency:noEpochs', ...
                    'No epochs far enough from the recording edges for the band filters (need %.2g s).', max(margin) / fs);
            end
            r = struct('t', t, 'bands', bands, 'power', ep, 'pctChange', pct, ...
                'mean', mu, 'sem', se, 'meanPower', mp, 'baselinePower', base, ...
                'nTrials', nTrials, 'onsets', onsets(used));
        end

        %% ersp - Event-related spectral perturbation (dB vs baseline) and ITPC
        % x: vector (continuous). onsets: s. window: [tmin tmax] s around
        % each onset. freqs: Hz. baselineWindow: [t1 t2] s inside window.
        % nCycles: scalar or per frequency (default 7).
        % OUTPUT erspDb, itpc: freq x time; t (s, row); info (see header).
        function [erspDb, itpc, t, info] = ersp(x, fs, onsets, window, freqs, baselineWindow, nCycles)
            if nargin < 7 || isempty(nCycles), nCycles = 7; end
            [freqs, nCycles] = TimeFrequency.checkFreqs(freqs, nCycles, fs);
            x = TimeFrequency.asRows(x);
            if size(x, 1) ~= 1
                error('NeuroAnalyzer:TimeFrequency:notVector', 'ersp expects a single signal (vector).');
            end
            n = numel(x);
            x = x - mean(x);
            [rel, t, c, used] = TimeFrequency.epochGrid(n, fs, onsets, window);
            baseMask = TimeFrequency.baselineMask(t, baselineWindow);
            nT = numel(rel); nF = numel(freqs);

            % Epochs padded by half the longest wavelet on each side. At each
            % frequency only trials whose wavelet support stays inside the
            % recording are used (samples clamped at the ends are never read
            % for them), so no data is invented at the recording edges.
            halfMax = TimeFrequency.halfLength(fs, min(freqs ./ nCycles));
            relP = (rel(1) - halfMax):(rel(end) + halfMax);
            idx = min(max(c(:) + relP, 1), n);
            seg = reshape(x(idx), size(idx));
            nP = size(seg, 2);
            nfft = 2^nextpow2(nP + 2 * halfMax);
            Sf = fft(seg, nfft, 2);

            meanPow = nan(nF, nT);
            itpc = nan(nF, nT);
            nTrials = zeros(1, nF);
            for i = 1:nF
                [w, h] = TimeFrequency.wavelet(fs, freqs(i), nCycles(i));
                ok = c + rel(1) - h >= 1 & c + rel(end) + h <= n;
                if ~any(ok), continue; end
                y = ifft(Sf(ok, :) .* fft(w, nfft), nfft, 2);
                y = y(:, h + halfMax + (1:nT));                 % epoch samples of the 'same' part
                a = abs(y);
                meanPow(i, :) = mean(a.^2, 1);
                itpc(i, :) = abs(mean(y ./ max(a, realmin), 1));
                nTrials(i) = sum(ok);
            end
            if ~any(nTrials)
                error('NeuroAnalyzer:TimeFrequency:noEpochs', ['No epochs far enough from the ' ...
                    'recording edges for the lowest frequency (need %.2g s). Raise the lowest frequency.'], halfMax / fs);
            end
            basePow = mean(meanPow(:, baseMask), 2);
            erspDb = 10 * log10(meanPow ./ basePow);
            info = struct('nTrials', max(nTrials), 'nTrialsPerFreq', nTrials, 'nOnsets', numel(onsets), ...
                'onsets', onsets(used), 'freqs', freqs, 'nCycles', nCycles, 'meanPower', meanPow, ...
                'baselinePower', basePow, 'window', window, 'baselineWindow', baselineWindow);
        end

        %% defaultBands - Conventional band names and limits (Hz)
        function bands = defaultBands()
            bands = struct('name', {'Delta', 'Theta', 'Alpha', 'Beta', 'Gamma'}, ...
                'range', {[1 4], [4 8], [8 13], [13 30], [30 80]});
        end
    end

    methods(Static, Access = private)

        %% asRows - Vector -> 1 x n double row; matrix -> double, one signal per row
        function X = asRows(x)
            if isvector(x), x = x(:).'; end
            X = double(x);
            if isempty(X)
                error('NeuroAnalyzer:TimeFrequency:empty', 'The signal is empty.');
            end
        end

        %% checkFreqs - Row of frequencies in (0, fs/2) and matching cycles
        function [freqs, nCycles] = checkFreqs(freqs, nCycles, fs)
            freqs = double(freqs(:).');
            if isempty(freqs) || any(~isfinite(freqs)) || any(freqs <= 0) || any(freqs >= fs / 2)
                error('NeuroAnalyzer:TimeFrequency:badFreqs', ...
                    'Frequencies must be above 0 and below the Nyquist frequency (%g Hz).', fs / 2);
            end
            nCycles = double(nCycles(:).');
            if isscalar(nCycles), nCycles = repmat(nCycles, size(freqs)); end
            if numel(nCycles) ~= numel(freqs) || any(~(nCycles > 0))
                error('NeuroAnalyzer:TimeFrequency:badCycles', ...
                    'nCycles must be positive: one value, or one per frequency.');
            end
        end

        %% wavelet - Unit-energy complex Morlet wavelet at f Hz; h = half-length (samples)
        function [w, h] = wavelet(fs, f, nc)
            s = nc / (2 * pi * f);
            h = TimeFrequency.halfLength(fs, f / nc);
            tt = (-h:h) / fs;
            w = exp(2i * pi * f * tt) .* exp(-tt.^2 / (2 * s^2));
            w = w / sqrt(sum(abs(w).^2));
        end

        %% halfLength - Samples in 3 Gaussian SDs for a wavelet with f/nCycles = fc
        function h = halfLength(fs, fc)
            s = 1 / (2 * pi * fc);                   % s = nCycles / (2*pi*f)
            h = max(1, ceil(3 * s * fs));
        end

        %% framePSD - One-sided PSD of each Hann-windowed frame (freq(keep) x frames)
        function [P, starts] = framePSD(x, fs, nWin, step, nfft, keep)
            n = numel(x);
            starts = 1:step:(n - nWin + 1);
            w = 0.5 * (1 - cos(2 * pi * (0:nWin - 1) / nWin));   % periodic Hann
            U = sum(w.^2);
            nHalf = floor(nfft / 2) + 1;
            scale = 2 * ones(1, nHalf);
            scale(1) = 1;
            if mod(nfft, 2) == 0, scale(end) = 1; end         % DC and Nyquist appear once
            P = zeros(numel(keep), numel(starts));
            chunk = max(1, floor(4e6 / nWin));                  % bound memory for long recordings
            for b = 1:chunk:numel(starts)
                e = min(numel(starts), b + chunk - 1);
                idx = starts(b:e).' + (0:nWin - 1);
                seg = reshape(x(idx), size(idx));
                seg = (seg - mean(seg, 2)) .* w;
                S = fft(seg, nfft, 2);
                ps = abs(S(:, 1:nHalf)).^2 / (fs * U) .* scale;
                P(:, b:e) = ps(:, keep).';
            end
        end

        %% edgeWidth - Raised-cosine edge width (Hz) for each band
        function w = edgeWidth(bands)
            w = min(2, max(0.1, (bands(:, 2) - bands(:, 1)) / 4));
        end

        %% bandGain - 1 inside [lo hi], raised-cosine to 0 over w Hz outside
        function H = bandGain(fk, band)
            w = TimeFrequency.edgeWidth(band);
            lo = band(1); hi = band(2);
            H = double(fk >= lo & fk <= hi);
            lower = fk < lo & fk > lo - w;
            H(lower) = 0.5 * (1 + cos(pi * (lo - fk(lower)) / w));
            upper = fk > hi & fk < hi + w;
            H(upper) = 0.5 * (1 + cos(pi * (fk(upper) - hi) / w));
        end

        %% epochGrid - Epoch sample offsets, times and onset samples fully inside 1..n
        function [rel, t, c, used] = epochGrid(n, fs, onsets, window)
            if numel(window) ~= 2 || window(1) >= window(2)
                error('NeuroAnalyzer:TimeFrequency:badWindow', 'The epoch window must be [start end] with start < end (s).');
            end
            rel = round(window(1) * fs):round(window(2) * fs);
            t = rel / fs;
            c = round(onsets(:).' * fs) + 1;
            used = c + rel(1) >= 1 & c + rel(end) <= n;
            c = c(used);
            if isempty(c)
                error('NeuroAnalyzer:TimeFrequency:noEpochs', ...
                    'No complete epochs: every onset is too close to the recording edges (or none given).');
            end
        end

        %% baselineMask - Samples of t inside the baseline window
        function m = baselineMask(t, baselineWindow)
            if numel(baselineWindow) ~= 2 || baselineWindow(1) >= baselineWindow(2)
                error('NeuroAnalyzer:TimeFrequency:badBaseline', 'The baseline must be [start end] with start < end (s).');
            end
            m = t >= baselineWindow(1) & t <= baselineWindow(2);
            if ~any(m)
                error('NeuroAnalyzer:TimeFrequency:badBaseline', ...
                    'The baseline window [%g %g] s lies outside the epoch window [%g %g] s.', ...
                    baselineWindow(1), baselineWindow(2), t(1), t(end));
            end
        end
    end
end
