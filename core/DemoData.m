%% DemoData.m
% =========================================================================
% DEMO DATA - SYNTHETIC RECORDINGS WITH KNOWN GROUND TRUTH
% =========================================================================
% Generates realistic fake data for every pipeline so the toolbox can be
% explored, demonstrated and tested without lab recordings. Everything is
% deterministic (fixed seed) and the ground truth is returned alongside, so
% results can be checked against what was simulated.
%
%   files = DemoData.writeAll(folder)   writes every demo file (see below)
%   d  = DemoData.ldfExport()     LabChart-style export (data/datastart/dataend)
%   s  = DemoData.ldfCropped()    stim, LDF, t, Fs   (as saved by Extract LDF)
%   s  = DemoData.ldfTrials()     segmentedLDF, segmentedTime, Fs (Process LDF)
%   tk = DemoData.tdtTank()       TDTbin2mat-like struct (streams.Whis / xRAW)
%   s  = DemoData.lfpFile()       lfp_data, t_lfp, lfp_fs, stim_* (Extract Ephys)
%   s  = DemoData.muaFile()       mua_data, t_mua, mua_fs, stim_* (Extract Ephys)
%   s  = DemoData.imagingStack()  stack, timeVec, roiMask (ROI analysis)
%
%   p  = DemoData.file(kind)      cached demo file path (generated on first use),
%                                 used by the windows' "Try demo data" buttons
%
% Ground truth is in the .truth field of each struct (and saved as 'truth').
% =========================================================================

classdef DemoData
    properties(Constant)
        Seed = 20260924
        % TDT-like rates: raw at 24414.0625 Hz, LFP after 24x decimation
        FsRaw = 24414.0625
        FsStimTDT = 1017.2526
    end

    methods(Static)

        %% file - Path to one demo file, generated on first use and cached
        % kind: 'ldfExport' | 'ldfCropped' | 'ldfTrials' | 'tdtTank' | 'lfp' |
        %       'mua' | 'imaging'. Files live in DemoData.folder(). For
        % 'tdtTank' the returned path is the tank folder (demo_tank/).
        function p = file(kind)
            folder = DemoData.folder();
            if ~exist(folder, 'dir'), mkdir(folder); end
            names = struct('ldfExport', 'demo_ldf_export.mat', 'ldfCropped', 'demo_ldf_cropped.mat', ...
                'ldfTrials', 'demo_ldf_trials.mat', 'tdtTank', fullfile('demo_tank', 'demo_tank.mat'), ...
                'lfp', 'demo_lfp.mat', 'mua', 'demo_mua.mat', 'imaging', 'demo_imaging.mat');
            if ~isfield(names, kind)
                error('NeuroAnalyzer:DemoData:unknownKind', 'Unknown demo data kind ''%s''.', kind);
            end
            p = fullfile(folder, names.(kind));
            if ~exist(p, 'file')
                if ~exist(fileparts(p), 'dir'), mkdir(fileparts(p)); end
                switch kind
                    case 'ldfExport',  s = DemoData.ldfExport();
                    case 'ldfCropped', s = DemoData.ldfCropped();
                    case 'ldfTrials',  s = DemoData.ldfTrials();
                    case 'lfp',        s = DemoData.lfpFile();
                    case 'mua',        s = DemoData.muaFile();
                    case 'imaging',    s = DemoData.imagingStack();
                    case 'tdtTank',    tank = DemoData.tdtTank(); %#ok<NASGU>
                end
                if strcmp(kind, 'tdtTank')
                    save(p, 'tank', '-v7.3');
                else
                    save(p, '-struct', 's', '-v7.3');
                end
            end
            if strcmp(kind, 'tdtTank'), p = fileparts(p); end
        end

        %% folder - Where demo files are cached (tempdir/NeuroAnalyzerDemo)
        function f = folder()
            f = fullfile(tempdir, 'NeuroAnalyzerDemo');
        end

        %% isDemoTank - True if folder is a demo tank (contains demo_tank.mat)
        function tf = isDemoTank(folder)
            tf = exist(fullfile(folder, 'demo_tank.mat'), 'file') == 2;
        end

        %% loadTank - TDTbin2mat stand-in for a demo tank folder
        function tank = loadTank(folder)
            s = load(fullfile(folder, 'demo_tank.mat'), 'tank');
            tank = s.tank;
        end

        %% writeAll - Write all demo files into folder; returns file list
        function files = writeAll(folder)
            if nargin < 1 || isempty(folder)
                folder = fullfile(tempdir, 'NeuroAnalyzerDemo');
            end
            if ~exist(folder, 'dir'), mkdir(folder); end
            files = struct();

            d = DemoData.ldfExport(); %#ok<NASGU>
            files.ldfExport = fullfile(folder, 'demo_ldf_export.mat');
            save(files.ldfExport, '-struct', 'd');

            s = DemoData.ldfCropped();
            files.ldfCropped = fullfile(folder, 'demo_ldf_cropped.mat');
            save(files.ldfCropped, '-struct', 's');

            s = DemoData.ldfTrials();
            files.ldfTrials = fullfile(folder, 'demo_ldf_trials.mat');
            save(files.ldfTrials, '-struct', 's');

            tank = DemoData.tdtTank();
            files.tdtTank = fullfile(folder, 'demo_tank', 'demo_tank.mat');
            if ~exist(fileparts(files.tdtTank), 'dir'), mkdir(fileparts(files.tdtTank)); end
            save(files.tdtTank, 'tank', '-v7.3');

            s = DemoData.lfpFile();
            files.lfp = fullfile(folder, 'demo_lfp.mat');
            save(files.lfp, '-struct', 's');

            s = DemoData.muaFile();
            files.mua = fullfile(folder, 'demo_mua.mat');
            save(files.mua, '-struct', 's', '-v7.3');

            s = DemoData.imagingStack();
            files.imaging = fullfile(folder, 'demo_imaging.mat');
            save(files.imaging, '-struct', 's');

            files.folder = folder;
        end

        %% ldfExport - 8-channel export; ch 6 = stimulus TTL, ch 8 = LDF
        % 300 s at 1000 Hz. Stimulus: 5 s pulses every 30 s from t = 30 s.
        % LDF: baseline ~120 PU + slow drift + vasomotion (0.1 Hz) + cardiac
        % ripple (6 Hz) + noise, plus a gamma-shaped hyperemia (+30 PU,
        % peak 4 s after onset) per stimulus.
        function d = ldfExport()
            rs = DemoData.stream(1);
            Fs = 1000; T = 300;
            t = (0:T*Fs-1) / Fs;
            onsets = 30:30:270; dur = 5;
            stim = zeros(size(t));
            for k = 1:numel(onsets)
                stim(t >= onsets(k) & t < onsets(k) + dur) = 5;
            end
            ldf = DemoData.ldfTrace(t, onsets, rs);
            nCh = 8;
            chans = cell(1, nCh);
            for c = 1:nCh
                chans{c} = 0.02 * randn(rs, 1, numel(t));
            end
            chans{6} = stim + 0.01 * randn(rs, 1, numel(t));
            chans{8} = ldf;
            d.data = cell2mat(chans);
            n = numel(t);
            d.datastart = 1 + (0:nCh-1) * n;
            d.dataend = (1:nCh) * n;
            d.samplerate = repmat(Fs, 1, nCh);
            d.titles = char('Ch1', 'Ch2', 'Ch3', 'Ch4', 'Ch5', 'Stimulus', 'Ch7', 'LDF');
            d.unittext = char('V', 'PU');
            d.truth = struct('onsets', onsets, 'stimDuration', dur, ...
                'responsePeakDelay', 4, 'responseAmplitude', 30, 'baseline', 120);
        end

        %% ldfCropped - Stim/LDF/t/Fs as written by Exporter.saveCropped (20-280 s)
        function s = ldfCropped()
            d = DemoData.ldfExport();
            Fs = d.samplerate(8);
            stim = d.data(d.datastart(6):d.dataend(6));
            ldf  = d.data(d.datastart(8):d.dataend(8));
            i1 = 20 * Fs + 1; i2 = 280 * Fs + 1;
            s.stim = stim(i1:i2);
            s.LDF = ldf(i1:i2);
            s.t = (0:numel(s.LDF) - 1) / Fs;
            s.Fs = Fs;
            s.truth = d.truth;
            s.truth.onsets = d.truth.onsets - 20;   % relative to crop start
        end

        %% ldfTrials - Trials cut around each onset (-5 s .. +20 s), 10 Hz
        function s = ldfTrials()
            c = DemoData.ldfCropped();
            dsF = 100; Fs = c.Fs / dsF;
            pre = 5; post = 20;
            segT = -pre:1/Fs:post;
            % Only trials whose whole window lies inside the recording
            ons = c.truth.onsets(c.truth.onsets - pre >= 0 & c.truth.onsets + post <= c.t(end));
            seg = zeros(numel(ons), numel(segT));
            for k = 1:numel(ons)
                idx = round((ons(k) + segT) * c.Fs) + 1;
                seg(k, :) = c.LDF(idx);
            end
            c.truth.onsets = ons;
            s.segmentedLDF = seg;
            s.segmentedTime = segT;
            s.Fs = Fs;
            s.truth = c.truth;
        end

        %% tdtTank - TDTbin2mat-like struct: 8-channel raw + whisker stimulus
        % 30 s. Stimulus pulses (20 ms) every 2 s from t = 1 s. Electrodes
        % 100 um apart; each stimulus evokes an ERP (N1 at 15 ms, P2 at
        % 40 ms) whose depth profile peaks at channel 4 (current sink there)
        % and bursts from three units with distinct waveforms.
        function tank = tdtTank()
            [lfpLow, mua, stim, info] = DemoData.ephysComponents();
            nRaw = size(mua, 2);
            tLow = (0:size(lfpLow, 2) - 1) / DemoData.FsStimTDT;
            tRaw = (0:nRaw - 1) / DemoData.FsRaw;
            raw = zeros(size(mua), 'single');
            for c = 1:size(mua, 1)
                raw(c, :) = single(interp1(tLow, lfpLow(c, :), tRaw, 'linear', 0)) + mua(c, :);
            end
            tank.info = struct('blockname', 'demo_tank', 'duration', info.duration);
            tank.streams.xRAW = struct('data', raw, 'fs', DemoData.FsRaw, 'channel', 1:size(raw, 1));
            tank.streams.Whis = struct('data', single([stim; 0 * stim]), 'fs', DemoData.FsStimTDT, 'channel', [1 2]);
            tank.truth = info;
        end

        %% lfpFile - What Extract Ephys saves after LFP processing
        function s = lfpFile()
            [lfpLow, ~, stim, info] = DemoData.ephysComponents();
            s.lfp_data = lfpLow;
            s.lfp_channels = 1:size(lfpLow, 1);
            s.lfp_fs = DemoData.FsStimTDT;
            s.t_lfp = (0:size(lfpLow, 2) - 1) / s.lfp_fs;
            s.stim_data = stim;
            s.stim_fs = DemoData.FsStimTDT;
            s.t_stim = (0:numel(stim) - 1) / s.stim_fs;
            s.truth = info;
        end

        %% muaFile - What Extract Ephys saves after MUA processing (ch 3-5)
        function s = muaFile()
            [~, mua, stim, info] = DemoData.ephysComponents();
            ch = 3:5;
            s.mua_data = double(mua(ch, :));
            s.mua_channels = ch;
            s.mua_fs = DemoData.FsRaw;
            s.t_mua = (0:size(s.mua_data, 2) - 1) / s.mua_fs;
            s.stim_data = stim;
            s.stim_fs = DemoData.FsStimTDT;
            s.t_stim = (0:numel(stim) - 1) / s.stim_fs;
            s.filterParams = struct('filterType', 'Standard (300-3000 Hz)', ...
                'lowCutoff', 300, 'highCutoff', 3000, 'order', 4, ...
                'savedSignal', 'synthetic: spikes + noise (already bandpassed)');
            s.truth = info;
        end

        %% imagingStack - 96x96x150 frames at 10 Hz
        % A vertical vessel (dark band) whose diameter oscillates 12 +/- 3 px
        % at 0.2 Hz, a red blood cell (bright spot) moving down the vessel at
        % 2 px/frame, and a cell (disk, r = 6 px) with calcium transients
        % (dF/F = 1.0) at 3 s, 7 s and 11 s. roiMask marks the cell.
        function s = imagingStack()
            rs = DemoData.stream(3);
            H = 96; W = 96; N = 150; fps = 10;
            t = (0:N-1) / fps;
            [X, Y] = meshgrid(1:W, 1:H);
            cx = 60; cellX = 24; cellY = 30; cellR = 6;
            diam = 12 + 3 * sin(2 * pi * 0.2 * t);
            events = [3 7 11];
            dff = zeros(1, N);
            for e = events
                on = t >= e;
                dff(on) = dff(on) + 1.0 * exp(-(t(on) - e) / 0.8) .* (1 - exp(-(t(on) - e) / 0.1));
            end
            texture = 0.05 * DemoData.smooth2(randn(rs, H, W), 2);
            cellMask = (X - cellX).^2 + (Y - cellY).^2 <= cellR^2;
            stack = zeros(H, W, N, 'single');
            for k = 1:N
                bg = 0.6 + texture;
                vessel = 1 ./ (1 + exp((abs(X - cx) - diam(k) / 2) / 0.8));   % 1 inside
                frame = bg .* (1 - 0.7 * vessel);
                rbcY = mod(5 + 2 * (k - 1), H);
                frame = frame + 0.8 * exp(-((X - cx).^2 + (Y - rbcY).^2) / (2 * 2^2));
                frame(cellMask) = frame(cellMask) + 0.25 * (1 + dff(k));
                frame = frame + 0.02 * randn(rs, H, W);
                stack(:, :, k) = single(frame);
            end
            s.stack = stack;
            s.timeVec = t;
            s.roiMask = cellMask;
            s.truth = struct('fps', fps, 'vesselCenterX', cx, 'diameter', diam, ...
                'rbcSpeedPxPerFrame', 2, 'cellCenter', [cellX cellY], 'cellRadius', cellR, ...
                'dff', dff, 'calciumEvents', events);
        end
    end

    methods(Static, Access = private)

        %% stream - Independent reproducible random stream per generator
        function rs = stream(k)
            rs = RandStream('mt19937ar', 'Seed', DemoData.Seed + k);
        end

        %% ldfTrace - Baseline + drift + vasomotion + cardiac + noise + responses
        function ldf = ldfTrace(t, onsets, rs)
            ldf = 120 + 5 * sin(2 * pi * t / 400) + 3 * sin(2 * pi * 0.1 * t) ...
                + 1.5 * sin(2 * pi * 6 * t) + 2 * randn(rs, size(t));
            tp = 4; a = 3;
            for k = 1:numel(onsets)
                x = (t - onsets(k)) / tp;
                g = zeros(size(t));
                on = x > 0;
                g(on) = x(on).^a .* exp(a * (1 - x(on)));
                ldf = ldf + 30 * g;
            end
        end

        %% ephysComponents - LFP (at FsStimTDT), MUA (at FsRaw), stimulus, truth
        function [lfp, mua, stim, info] = ephysComponents()
            rs = DemoData.stream(2);
            T = 30; nCh = 8; spacing = 100;
            fsL = DemoData.FsStimTDT; fsR = DemoData.FsRaw;
            nL = round(T * fsL); nR = round(T * fsR);
            tL = (0:nL-1) / fsL; tR = (0:nR-1) / fsR;
            onsets = 1:2:29;
            stim = zeros(1, nL);
            for k = 1:numel(onsets)
                stim(tL >= onsets(k) & tL < onsets(k) + 0.02) = 1;
            end

            % --- LFP: evoked potential with a Gaussian depth profile ---
            depth = (0:nCh-1) * spacing;
            z0 = 3 * spacing; sz = 150;
            profile = exp(-(depth - z0).^2 / (2 * sz^2));
            erp = @(x) -120e-6 * exp(-(x - 0.015).^2 / (2 * 0.005^2)) ...
                       + 60e-6 * exp(-(x - 0.040).^2 / (2 * 0.012^2));
            evoked = zeros(1, nL);
            for k = 1:numel(onsets)
                x = tL - onsets(k);
                on = x >= 0 & x < 0.3;
                evoked(on) = evoked(on) + erp(x(on));
            end
            lfp = zeros(nCh, nL);
            for c = 1:nCh
                bg = filter(1, [1 -0.98], randn(rs, 1, nL)) * 3e-6;   % 1/f-like background
                lfp(c, :) = profile(c) * evoked + bg + 2e-6 * randn(rs, 1, nL);
            end

            % --- MUA: three units, higher rate for 50 ms after each stimulus ---
            wlen = round(1.2e-3 * fsR);
            tw = (0:wlen-1) / fsR;
            shapes = { -90e-6 * exp(-(tw - 2.5e-4).^2 / (2 * 0.7e-4^2)) + 35e-6 * exp(-(tw - 6e-4).^2 / (2 * 2.5e-4^2)), ...
                       -50e-6 * exp(-(tw - 2e-4).^2 / (2 * 1e-4^2)) + 30e-6 * exp(-(tw - 6e-4).^2 / (2 * 2e-4^2)), ...
                       -110e-6 * exp(-(tw - 3e-4).^2 / (2 * 0.8e-4^2)) + 20e-6 * exp(-(tw - 8e-4).^2 / (2 * 2e-4^2)) };
            baseRate = [6 10 3]; evokedRate = [80 40 120];
            homeCh = [4 4 5];
            mua = zeros(nCh, nR, 'single');
            for c = 1:nCh
                mua(c, :) = single(10e-6 * randn(rs, 1, nR));
            end
            spikeTimes = cell(1, 3);
            for u = 1:3
                rate = baseRate(u) * ones(1, nR);
                for k = 1:numel(onsets)
                    rate(tR >= onsets(k) + 0.005 & tR < onsets(k) + 0.055) = evokedRate(u);
                end
                st = find(rand(rs, 1, nR) < rate / fsR);
                st = st(st + wlen - 1 <= nR);
                keep = [true, diff(st) > round(2e-3 * fsR)];   % 2 ms refractory
                st = st(keep);
                spikeTimes{u} = (st - 1) / fsR;
                for c = 1:nCh
                    gain = exp(-abs(c - homeCh(u)) / 0.8);
                    if gain < 0.05, continue; end
                    w = single(gain * shapes{u});
                    for i = st
                        mua(c, i:i + wlen - 1) = mua(c, i:i + wlen - 1) + w;
                    end
                end
            end

            info = struct('duration', T, 'onsets', onsets, 'channelSpacingUm', spacing, ...
                'sinkChannel', 4, 'n1LatencyS', 0.015, 'p2LatencyS', 0.040, ...
                'units', struct('homeChannel', num2cell(homeCh), 'baseRateHz', num2cell(baseRate), ...
                    'evokedRateHz', num2cell(evokedRate), 'spikeTimes', spikeTimes));
        end

        %% smooth2 - Small separable Gaussian blur (toolbox-free)
        function y = smooth2(x, sigma)
            r = ceil(2 * sigma);
            g = exp(-((-r:r).^2) / (2 * sigma^2)); g = g / sum(g);
            y = conv2(g, g, x, 'same');
        end
    end
end
