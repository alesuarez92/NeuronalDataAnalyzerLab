%% demoEEG.m
% =========================================================================
% DEMO EEG - SYNTHETIC SCALP AND RODENT EEG WITH KNOWN ANSWERS, IN EVERY
% SUPPORTED FORMAT
% =========================================================================
% files = demoEEG()                    cached copy in <DemoData.folder>/eeg
% files = demoEEG(folder)              (re)write the files into folder
% files = demoEEG(folder, Name, Value) options below
%
% Scalp (an oddball study, data already cleaned and cut into trials):
%   8 participants, 32 channels (actiCAP 32 names) with positions on an
%   idealised spherical head (radius 85 mm), 250 Hz, trials from -0.2 to
%   0.8 s, conditions Standard (40), Target (15) and Novel (15) in random
%   order, 5 trials already rejected per participant (65 left).
%   Known answers:
%     P1    +2 uV at 60 ms, largest at Oz
%     N1    -5 uV at 100 ms, largest at Cz
%     P300  at 350 ms, largest at Pz: Target 10 > Novel 6 > Standard 2 uV
%     alpha 10 Hz, 4 uV, largest over O1 / Oz / O2, random phase per trial
%   plus 1/f and white noise and an average reference. Each participant
%   scales the amplitudes (about +-10%) and shifts N1 and P300 (about
%   +-10 ms). The history says: band-pass 0.1-30 Hz, average reference,
%   ICA components 1 and 3 removed, trials cut and baseline removed, 5
%   trials rejected, T7 interpolated.
% Rodent (continuous): 4 skull screws with bregma coordinates (mm), 1000
%   Hz, 60 s, a light flash every 2 s from 1 s (30 events 'flash'), a
%   visual evoked potential over V1 (-40 uV at 50 ms, +25 uV at 100 ms;
%   30% of that over M1), 1/f and white noise, cerebellar reference.
%
% Every case is written as:
%   eeglab     EEGLAB .set with an EEG variable, numbers inside
%   eeglabfdt  EEGLAB .set with the fields at the top level + .fdt file
%   fieldtrip  FieldTrip raw data (.mat): trialinfo codes 1-3 and the list
%              conditionNames; elec in mm (scalp: x = right, y = nose,
%              z = up, coordsys 'ras'; rodent: x = medial-lateral,
%              y = anterior-posterior, coordsys 'bregma'); cfg.previous
%              history; rodent events in the variable event
%   matrix     plain .mat. Scalp: eeg (trials x channels x samples, in
%              volts), srate, chanNames, times (s), condition. Rodent:
%              data (channels x samples, uV), fs, labels, flashTimes (s)
%
% files.folder, files.scalp(p).<format>, files.rodent.<format>,
% files.truth.scalp / .rodent: design, positions, per-participant
% conditions, rejected trials, and data (channels x samples x trials,
% single, uV; only when freshly written, not in the cache).
%
% Options (Name, Value):
%   'Participants'  number of scalp participants (default 8)
%   'Kinds'         subset of {'scalp', 'rodent'} (default both)
%   'Force'         true regenerates the cache (demoEEG() only)
% Deterministic: RandStream('mt19937ar', 'Seed', 20260926 + participant;
% rodent 20260926 + 100). Requires core/io on the path (EEGSource,
% writeEEGLAB, writeFieldTrip). Toolboxes: none.
% =========================================================================

function files = demoEEG(folder, varargin)
    o = struct('Participants', 8, 'Kinds', {{'scalp', 'rodent'}}, 'Force', false);
    for k = 1:2:numel(varargin)
        o.(varargin{k}) = varargin{k + 1};
    end
    cacheVersion = 1;
    cached = nargin < 1 || isempty(folder);
    if cached
        folder = fullfile(DemoData.folder(), 'eeg');
        manifest = fullfile(folder, 'demo_eeg.mat');
        if ~o.Force && exist(manifest, 'file') == 2
            s = load(manifest);
            if isfield(s, 'version') && s.version == cacheVersion && allExist(s.files, o.Kinds) ...
                    && (~any(strcmp(o.Kinds, 'scalp')) || numel(s.files.scalp) == o.Participants)
                files = s.files;
                return;
            end
        end
    end
    if ~(exist(folder, 'dir') == 7), mkdir(folder); end

    files = struct('folder', folder);
    truth = struct();
    if any(strcmp(o.Kinds, 'scalp'))
        [files.scalp, truth.scalp] = writeScalp(fullfile(folder, 'scalp'), o.Participants);
    end
    if any(strcmp(o.Kinds, 'rodent'))
        [files.rodent, truth.rodent] = writeRodent(fullfile(folder, 'rodent'));
    end
    files.truth = truth;

    if cached
        if isfield(files.truth, 'scalp')
            files.truth.scalp.participants = rmfield(files.truth.scalp.participants, 'data');
        end
        if isfield(files.truth, 'rodent')
            files.truth.rodent = rmfield(files.truth.rodent, 'data');
        end
        version = cacheVersion; %#ok<NASGU>
        save(fullfile(folder, 'demo_eeg.mat'), 'files', 'version', '-v7');
    end
end

%% writeScalp - The oddball study, every participant in every format
function [out, truth] = writeScalp(folder, nPart)
    if ~(exist(folder, 'dir') == 7), mkdir(folder); end
    labels = {'Fp1', 'Fp2', 'F7', 'F3', 'Fz', 'F4', 'F8', 'FC5', 'FC1', 'FC2', 'FC6', 'T7', ...
        'C3', 'Cz', 'C4', 'T8', 'TP9', 'CP5', 'CP1', 'CP2', 'CP6', 'TP10', 'P7', 'P3', 'Pz', ...
        'P4', 'P8', 'PO9', 'O1', 'Oz', 'O2', 'PO10'};
    % Azimuth (deg, 0 = nose, +90 = left ear) and elevation (deg, 90 = vertex)
    % on an idealised sphere: Fpz / T7 / Oz on the equator, Cz at the top.
    azel = [18 0; -18 0; 54 0; 40 42; 0 45; -40 42; -54 0; 69 21; 45 67; -45 67; -69 21; ...
        90 0; 90 45; 0 90; -90 45; -90 0; 108 -18; 111 21; 135 67; -135 67; -111 21; -108 -18; ...
        126 0; 140 42; 180 45; -140 42; -126 0; 144 -18; 162 0; 180 0; -162 0; -144 -18];
    R = 85;
    az = azel(:, 1) * pi / 180;
    el = azel(:, 2) * pi / 180;
    u = [cos(el) .* cos(az), cos(el) .* sin(az), sin(el)];     % EEGLAB axes: x nose, y left, z up
    posEEGLAB = R * u;
    posRAS = R * [-u(:, 2), u(:, 1), u(:, 3)];                  % x right, y nose, z up
    nCh = numel(labels);
    fs = 250;
    times = -0.2 + (0:249) / fs;
    nS = numel(times);
    names = {'Standard', 'Target', 'Novel'};
    nPer = [40 15 15];
    p300 = [2 10 6];
    nRej = 5;
    ch = @(name) find(strcmp(labels, name), 1);
    w = @(name, sig) exp(-(acos(max(-1, min(1, u * u(ch(name), :)'))) / sig) .^ 2);
    g = @(mu, sd) exp(-0.5 * ((times - mu) / sd) .^ 2);
    wP1 = w('Oz', 0.6); wN1 = w('Cz', 0.6); wP3 = w('Pz', 0.8); wA = w('Oz', 0.7);

    truth = struct('labels', {labels}, 'azel', azel, 'headRadius', R, 'posEEGLAB', posEEGLAB, ...
        'posRAS', posRAS, 'fs', fs, 'times', times, 'conditionNames', {names}, 'trialsPerCondition', nPer, ...
        'rejectedPerParticipant', nRej, ...
        'p1', struct('channel', 'Oz', 'latency', 0.06, 'amplitude', 2), ...
        'n1', struct('channel', 'Cz', 'latency', 0.1, 'amplitude', -5), ...
        'p300', struct('channel', 'Pz', 'latency', 0.35, 'amplitude', p300), ...
        'alpha', struct('channels', {{'O1', 'Oz', 'O2'}}, 'frequency', 10, 'amplitude', 4), ...
        'participants', struct('condition', {}, 'rejected', {}, 'ampScale', {}, 'latShift', {}, 'data', {}));
    out = struct('eeglab', {}, 'eeglabfdt', {}, 'fieldtrip', {}, 'matrix', {});
    locs = struct('label', labels, 'x', num2cell(posEEGLAB(:, 1)'), 'y', num2cell(posEEGLAB(:, 2)'), ...
        'z', num2cell(posEEGLAB(:, 3)'), 'theta', NaN, 'radius', NaN);

    for p = 1:nPart
        rs = RandStream('mt19937ar', 'Seed', 20260926 + p);
        amp = 1 + 0.1 * randn(rs);
        lat = max(-0.02, min(0.02, 0.01 * randn(rs)));
        c0 = [ones(1, nPer(1)), 2 * ones(1, nPer(2)), 3 * ones(1, nPer(3))];
        condAll = c0(randperm(rs, numel(c0)));
        n = numel(condAll);
        X = zeros(nCh, nS, n);
        for k = 1:n
            erp = amp * (2 * wP1 * g(0.06, 0.012) - 5 * wN1 * g(0.1 + lat, 0.015) ...
                + p300(condAll(k)) * wP3 * g(0.35 + lat, 0.06));
            X(:, :, k) = erp + 4 * wA * sin(2 * pi * 10 * times + 2 * pi * rand(rs));
        end
        X = X + 3 * permute(reshape(pinkNoise(rs, nS, nCh * n), nS, nCh, n), [2 1 3]) ...
            + randn(rs, nCh, nS, n);
        X = X - mean(X, 1);                                     % average reference
        rej = sort(randperm(rs, n, nRej));
        keep = setdiff(1:n, rej);
        data = single(X(:, :, keep));
        cond = names(condAll(keep));
        truth.participants(p) = struct('condition', {cond}, 'rejected', rej, 'ampScale', amp, ...
            'latShift', lat, 'data', data);

        eeg = EEGSource.make(data, fs, 'Times', times, 'Labels', labels, 'Chanlocs', locs, ...
            'CoordSystem', 'EEGLAB (x = nose, y = left ear, z = up)', 'Conditions', cond, ...
            'Reference', 'average of all channels', 'Unit', 'uV', 'IsEpoched', true);
        base = fullfile(folder, sprintf('sub-%02d', p));
        hist = strjoin({ ...
            sprintf('EEG = pop_loadset(''filename'', ''sub-%02d_raw.set'');', p), ...
            'EEG = pop_eegfiltnew(EEG, ''locutoff'', 0.1, ''hicutoff'', 30);', ...
            'EEG = pop_reref( EEG, []);', ...
            'EEG = pop_runica(EEG, ''icatype'', ''runica'', ''extended'', 1);', ...
            'EEG = pop_subcomp( EEG, [1  3], 0);', ...
            'EEG = pop_epoch( EEG, {  ''Standard''  ''Target''  ''Novel''  }, [-0.2         0.8], ''epochinfo'', ''yes'');', ...
            'EEG = pop_rmbase( EEG, [-200 0] ,[]);', ...
            sprintf('EEG = pop_rejepoch( EEG, [%s] ,0);', num2str(rej)), ...
            'EEG = pop_interp(EEG, [12], ''spherical'');'}, newline);
        out(p).eeglab = [base '_eeglab.set'];
        writeEEGLAB(out(p).eeglab, eeg, 'History', hist);
        out(p).eeglabfdt = [base '_fdt.set'];
        writeEEGLAB(out(p).eeglabfdt, eeg, 'History', hist, 'DataFile', true, 'Layout', 'fields');

        % FieldTrip: the same steps as a cfg.previous chain
        c = struct('bpfilter', 'yes', 'bpfreq', [0.1 30], 'reref', 'yes', 'refchannel', {{'all'}}, ...
            'version', struct('name', 'ft_preprocessing'));
        c = struct('method', 'runica', 'version', struct('name', 'ft_componentanalysis'), 'previous', c);
        c = struct('component', [1 3], 'version', struct('name', 'ft_rejectcomponent'), 'previous', c);
        trl = [(0:n - 1)' * 500 + 1, (0:n - 1)' * 500 + nS, repmat(-50, n, 1)];
        c = struct('trl', trl, 'version', struct('name', 'ft_redefinetrial'), 'previous', c);
        c = struct('demean', 'yes', 'baselinewindow', [-0.2 0], 'version', struct('name', 'ft_preprocessing'), 'previous', c);
        c = struct('artfctdef', struct('visual', struct('artifact', trl(rej, 1:2))), 'reject', 'complete', ...
            'version', struct('name', 'ft_rejectartifact'), 'previous', c);
        c = struct('badchannel', {{'T7'}}, 'method', 'spline', 'version', struct('name', 'ft_channelrepair'), 'previous', c);
        eegFT = eeg;
        for k = 1:nCh
            eegFT.chanlocs(k).x = posRAS(k, 1); eegFT.chanlocs(k).y = posRAS(k, 2); eegFT.chanlocs(k).z = posRAS(k, 3);
        end
        out(p).fieldtrip = [base '_fieldtrip.mat'];
        writeFieldTrip(out(p).fieldtrip, eegFT, 'Cfg', c, 'ConditionNames', names, ...
            'Coordsys', 'ras', 'Unit', 'mm');

        % Plain matrix: trials x channels x samples, in volts
        M = struct('eeg', permute(double(data), [3 1 2]) * 1e-6, 'srate', fs, 'chanNames', {labels}, ...
            'times', times, 'condition', {cond});
        out(p).matrix = [base '_matrix.mat'];
        save(out(p).matrix, '-struct', 'M', '-v7');
    end
end

%% writeRodent - Continuous skull-screw recording with light flashes
function [out, truth] = writeRodent(folder)
    if ~(exist(folder, 'dir') == 7), mkdir(folder); end
    labels = {'M1-L', 'M1-R', 'V1-L', 'V1-R'};
    ap = [1 1 -3.5 -3.5];                 % mm from bregma, anterior positive
    ml = [-1.5 1.5 -2.5 2.5];             % mm from the midline, right positive
    fs = 1000;
    T = 60;
    N = T * fs;
    t = (0:N - 1) / fs;
    onsets = 1:2:59;
    weight = [0.3 0.3 1 1]';
    tk = (0:399) / fs;
    kernel = -40 * exp(-0.5 * ((tk - 0.05) / 0.008) .^ 2) + 25 * exp(-0.5 * ((tk - 0.1) / 0.02) .^ 2);
    rs = RandStream('mt19937ar', 'Seed', 20260926 + 100);
    x = 15 * pinkNoise(rs, N, 4)' + 3 * randn(rs, 4, N);
    for k = 1:numel(onsets)
        i = round(onsets(k) * fs) + (1:numel(tk));
        x(:, i) = x(:, i) + weight * kernel;
    end
    data = single(x);
    truth = struct('labels', {labels}, 'ap', ap, 'ml', ml, 'fs', fs, 'duration', T, ...
        'onsets', onsets, 'vep', struct('channels', {{'V1-L', 'V1-R'}}, 'latency', [0.05 0.1], ...
        'amplitude', [-40 25]), 'reference', 'cerebellar screw', 'data', data);

    locs = struct('label', labels, 'x', num2cell(ap), 'y', num2cell(-ml), 'z', 0, 'theta', NaN, 'radius', NaN);
    ev = struct('type', 'flash', 'latency', num2cell(onsets), 'duration', 0);
    eeg = EEGSource.make(data, fs, 'Times', t, 'Labels', labels, 'Chanlocs', locs, ...
        'Events', ev, 'Reference', 'cerebellar screw', 'Unit', 'uV', 'IsEpoched', false);
    hist = strjoin({'EEG = pop_loadset(''filename'', ''rat01_raw.set'');', ...
        'EEG = pop_eegfiltnew(EEG, 1, 100);'}, newline);
    out = struct('eeglab', fullfile(folder, 'rat01_eeglab.set'), 'eeglabfdt', fullfile(folder, 'rat01_fdt.set'), ...
        'fieldtrip', fullfile(folder, 'rat01_fieldtrip.mat'), 'matrix', fullfile(folder, 'rat01_matrix.mat'));
    writeEEGLAB(out.eeglab, eeg, 'History', hist, 'CoordSys', 'bregma, mm');
    writeEEGLAB(out.eeglabfdt, eeg, 'History', hist, 'CoordSys', 'bregma, mm', 'DataFile', true, 'Layout', 'fields');

    eegFT = eeg;
    for k = 1:4
        eegFT.chanlocs(k).x = ml(k); eegFT.chanlocs(k).y = ap(k); eegFT.chanlocs(k).z = 0;
    end
    c = struct('bpfilter', 'yes', 'bpfreq', [1 100], 'version', struct('name', 'ft_preprocessing'));
    writeFieldTrip(out.fieldtrip, eegFT, 'Cfg', c, 'Coordsys', 'bregma', 'Unit', 'mm');

    M = struct('data', double(data), 'fs', fs, 'labels', {labels}, 'flashTimes', onsets);
    save(out.matrix, '-struct', 'M', '-v7');
end

%% pinkNoise - nS x m columns of 1/f noise with unit standard deviation
function n = pinkNoise(rs, nS, m)
    W = randn(rs, nS, m);
    f = (0:nS - 1)';
    f = min(f, nS - f);
    f(1) = 1;
    n = real(ifft(fft(W) ./ sqrt(f)));
    n = n / std(n(:));
end

%% allExist - Cached files present for every requested kind
function tf = allExist(files, kinds)
    tf = true;
    for k = 1:numel(kinds)
        if ~isfield(files, kinds{k}), tf = false; return; end
        f = files.(kinds{k});
        for i = 1:numel(f)
            for fmt = {'eeglab', 'eeglabfdt', 'fieldtrip', 'matrix'}
                if ~(exist(f(i).(fmt{1}), 'file') == 2), tf = false; return; end
            end
        end
    end
end
