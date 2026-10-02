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
%     alpha 10 Hz, 4 uV, largest over O1 / Oz / O2, random phase per trial;
%           after Target its amplitude halves from 350 to 650 ms (100 ms
%           ramps before and after): power -75% (-6 dB) there, an
%           event-related desynchronization (ERD) for time-frequency
%   plus 1/f and white noise and an average reference. Each participant
%   scales the amplitudes (about +-10%) and shifts N1 and P300 (about
%   +-10 ms). The history says: band-pass 0.1-30 Hz, average reference,
%   ICA components 1 and 3 removed, trials cut and baseline removed, 5
%   trials rejected, T7 interpolated.
% Rodent (continuous): 4 skull screws with bregma coordinates (mm), 1000
%   Hz, 60 s, a light flash every 2 s from 1 s (30 events 'flash'), a
%   visual evoked potential over V1 (-40 uV at 50 ms, +25 uV at 100 ms;
%   30% of that over M1), 1/f and white noise, cerebellar reference.
% Raw (continuous scalp recordings of the same oddball design, before any
%   cleaning): 3 participants as BrainVision Recorder files (float32, 500
%   Hz, about 100 s each), the same 32 channels recorded against FCz
%   (online reference, not in the data; azimuth 0, elevation 67.5 deg on
%   the sphere), markers 'S  1' / 'S  2' / 'S  3' = Standard (40) / Target
%   (15) / Novel (15), 1.2-1.5 s apart, from 2 s. The same P1 / N1 / P300 /
%   alpha (and its decrease after Target) as the scalp case (P300 at Pz:
%   Target > Novel > Standard), plus:
%     electrode offsets (+-400 uV) and linear drift (+-1 uV/s): a high-pass
%       filter removes them
%     50 Hz line noise, 5-15 uV per channel: a notch or a low-pass removes it
%     T7 noisy (150 uV white noise): suggested as bad; unless it is marked
%       bad, every trial exceeds 100 uV peak-to-peak
%     blinks (150 uV at Fp1 / Fp2, 50 ms SD) in 8 trials per participant
%       (truth.raw.participants(p).blinkTrials) and 6 more between trials:
%       100 uV peak-to-peak rejects exactly the 8 blink trials (after a
%       0.1-30 Hz band-pass and the average reference without T7)
%     N1 at Cz: small against FCz (n1CzFCz, about -2 uV), about -4 to -5 uV
%       against the average of the good channels (n1CzAverage)
%   Writes only for the brainvision format.
%
% Every case is written as:
%   eeglab     EEGLAB .set with an EEG variable, numbers inside
%   eeglabfdt  EEGLAB .set with the fields at the top level + .fdt file
%   fieldtrip  FieldTrip raw data (.mat): trialinfo codes 1-3 and the list
%              conditionNames; elec in mm (scalp: x = right, y = nose,
%              z = up, coordsys 'ras'; rodent: x = medial-lateral,
%              y = anterior-posterior, coordsys 'bregma'); cfg.previous
%              history; rodent events in the variable event
%   brainvision  BrainVision .vhdr + .vmrk + .eeg. Scalp: an Analyzer
%              export (float32 segments, markers Standard / Target / Novel
%              at time 0, positions on the sphere). Rodent: a Recorder
%              file (INT_16, 0.1 uV resolution, 'S  1' flash markers,
%              reference channel Cb, the amplifier table in [Comment])
%   edf        rodent only: EDF+C (writeEDF), channels 'EEG M1-L' ... in uV
%              (16 bits), 'flash' annotations, 1 s records
%   bdf        rodent only: BioSemi BDF (24 bits) with a Status channel,
%              trigger code 1 for 10 ms at each flash
%   mff        rodent only: an EGI .mff folder (writeMFF), blocks of 1000
%              samples, 'flash' events, positions (cm = mm / 10)
%   xdf        rodent only: a LabRecorder-style .xdf (writeXDF): an EEG
%              stream (float32, microvolts, time stamps from 1000 s) and a
%              Markers stream with 'flash' at each onset
%   bids       rodent only: an EEG-BIDS dataset (writeEEGBIDS) in bids/:
%              sub-rat01/ses-1/eeg/*_task-flash_eeg.edf with channels,
%              events (flash), electrodes (bregma, mm) and eeg.json
%   matrix     plain .mat. Scalp: eeg (trials x channels x samples, in
%              volts), srate, chanNames, times (s), condition. Rodent:
%              data (channels x samples, uV), fs, labels, flashTimes (s)
%
% files.folder, files.scalp(p).<format>, files.rodent.<format> ('' for a
% format not written), files.raw(p).brainvision,
% files.truth.scalp / .rodent: design, positions, per-participant
% conditions, rejected trials, and data (channels x samples x trials,
% single, uV; only when freshly written, not in the cache).
%
% Options (Name, Value):
%   'Participants'  number of scalp participants (default 8)
%   'Kinds'         subset of {'scalp', 'rodent', 'raw'} (default all)
%   'Formats'       subset of {'eeglab', 'eeglabfdt', 'fieldtrip', 'brainvision',
%                   'matrix', 'edf', 'bdf', 'mff', 'xdf', 'bids'} to write
%                   (default all; edf, bdf, mff, xdf and bids are written for
%                   the rodent only)
%   'Force'         true regenerates the cache (demoEEG() only)
% Deterministic: RandStream('mt19937ar', 'Seed', 20260926 + participant;
% rodent 20260926 + 100; raw 20260926 + 200 + participant). Requires core/io on the path (EEGSource,
% writeEEGLAB, writeFieldTrip, writeBrainVision, writeEDF, writeMFF,
% writeXDF, writeEEGBIDS).
% Toolboxes: none.
% =========================================================================

function files = demoEEG(folder, varargin)
    allFormats = {'eeglab', 'eeglabfdt', 'fieldtrip', 'brainvision', 'matrix', 'edf', 'bdf', 'mff', 'xdf', 'bids'};
    o = struct('Participants', 8, 'Kinds', {{'scalp', 'rodent', 'raw'}}, 'Formats', {allFormats}, 'Force', false);
    for k = 1:2:numel(varargin)
        o.(varargin{k}) = varargin{k + 1};
    end
    cacheVersion = 4;                    % 4: alpha decrease after Target
    cached = nargin < 1 || isempty(folder);
    if cached
        folder = fullfile(DemoData.folder(), 'eeg');
        manifest = fullfile(folder, 'demo_eeg.mat');
        if ~o.Force && exist(manifest, 'file') == 2
            s = load(manifest);
            if isfield(s, 'version') && s.version == cacheVersion && allExist(s.files, o.Kinds, o.Formats) ...
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
        [files.scalp, truth.scalp] = writeScalp(fullfile(folder, 'scalp'), o.Participants, o.Formats);
    end
    if any(strcmp(o.Kinds, 'rodent'))
        [files.rodent, truth.rodent] = writeRodent(fullfile(folder, 'rodent'), o.Formats);
    end
    if any(strcmp(o.Kinds, 'raw'))
        [files.raw, truth.raw] = writeRaw(fullfile(folder, 'raw'), 3, o.Formats);
    end
    files.truth = truth;

    if cached
        if isfield(files.truth, 'scalp')
            files.truth.scalp.participants = rmfield(files.truth.scalp.participants, 'data');
        end
        if isfield(files.truth, 'rodent')
            files.truth.rodent = rmfield(files.truth.rodent, 'data');
        end
        if isfield(files.truth, 'raw') && isfield(files.truth.raw, 'participants')
            files.truth.raw.participants = rmfield(files.truth.raw.participants, 'data');
        end
        version = cacheVersion; %#ok<NASGU>
        save(fullfile(folder, 'demo_eeg.mat'), 'files', 'version', '-v7');
    end
end

%% writeScalp - The oddball study, every participant in every format
function [out, truth] = writeScalp(folder, nPart, formats)
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
    erd = alphaEnvelope(times);                                 % alpha after a Target

    truth = struct('labels', {labels}, 'azel', azel, 'headRadius', R, 'posEEGLAB', posEEGLAB, ...
        'posRAS', posRAS, 'fs', fs, 'times', times, 'conditionNames', {names}, 'trialsPerCondition', nPer, ...
        'rejectedPerParticipant', nRej, ...
        'p1', struct('channel', 'Oz', 'latency', 0.06, 'amplitude', 2), ...
        'n1', struct('channel', 'Cz', 'latency', 0.1, 'amplitude', -5), ...
        'p300', struct('channel', 'Pz', 'latency', 0.35, 'amplitude', p300), ...
        'alpha', alphaTruth(), ...
        'participants', struct('condition', {}, 'rejected', {}, 'ampScale', {}, 'latShift', {}, 'data', {}));
    out = struct('eeglab', {}, 'eeglabfdt', {}, 'fieldtrip', {}, 'brainvision', {}, 'matrix', {});
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
            a = 4 * wA * sin(2 * pi * 10 * times + 2 * pi * rand(rs));
            if condAll(k) == 2, a = a .* erd; end
            X(:, :, k) = erp + a;
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
        out(p).eeglabfdt = [base '_fdt.set'];
        out(p).fieldtrip = [base '_fieldtrip.mat'];
        out(p).brainvision = [base '_brainvision.vhdr'];
        out(p).matrix = [base '_matrix.mat'];
        if any(strcmp(formats, 'eeglab')), writeEEGLAB(out(p).eeglab, eeg, 'History', hist); end
        if any(strcmp(formats, 'eeglabfdt'))
            writeEEGLAB(out(p).eeglabfdt, eeg, 'History', hist, 'DataFile', true, 'Layout', 'fields');
        end

        % FieldTrip: the same steps as a cfg.previous chain
        if any(strcmp(formats, 'fieldtrip'))
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
            writeFieldTrip(out(p).fieldtrip, eegFT, 'Cfg', c, 'ConditionNames', names, ...
                'Coordsys', 'ras', 'Unit', 'mm');
        end

        % BrainVision: an Analyzer export of the segments (positions x right, y nose, z up)
        if any(strcmp(formats, 'brainvision'))
            writeBrainVision(out(p).brainvision, eeg, 'Positions', posRAS);
        end

        % Plain matrix: trials x channels x samples, in volts
        if any(strcmp(formats, 'matrix'))
            M = struct('eeg', permute(double(data), [3 1 2]) * 1e-6, 'srate', fs, 'chanNames', {labels}, ...
                'times', times, 'condition', {cond});
            save(out(p).matrix, '-struct', 'M', '-v7');
        end
        for f = setdiff(fieldnames(out)', formats)
            out(p).(f{1}) = '';                                  % not written
        end
    end
end

%% writeRodent - Continuous skull-screw recording with light flashes
function [out, truth] = writeRodent(folder, formats)
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
        'fieldtrip', fullfile(folder, 'rat01_fieldtrip.mat'), 'brainvision', fullfile(folder, 'rat01_brainvision.vhdr'), ...
        'matrix', fullfile(folder, 'rat01_matrix.mat'), 'edf', fullfile(folder, 'rat01_edf.edf'), ...
        'bdf', fullfile(folder, 'rat01_biosemi.bdf'), 'mff', fullfile(folder, 'rat01_egi.mff'), ...
        'xdf', fullfile(folder, 'rat01_lsl.xdf'), 'bids', '');
    has = @(f) any(strcmp(formats, f));
    if has('eeglab'), writeEEGLAB(out.eeglab, eeg, 'History', hist, 'CoordSys', 'bregma, mm'); end
    if has('eeglabfdt')
        writeEEGLAB(out.eeglabfdt, eeg, 'History', hist, 'CoordSys', 'bregma, mm', 'DataFile', true, 'Layout', 'fields');
    end

    if has('fieldtrip')
        eegFT = eeg;
        for k = 1:4
            eegFT.chanlocs(k).x = ml(k); eegFT.chanlocs(k).y = ap(k); eegFT.chanlocs(k).z = 0;
        end
        c = struct('bpfilter', 'yes', 'bpfreq', [1 100], 'version', struct('name', 'ft_preprocessing'));
        writeFieldTrip(out.fieldtrip, eegFT, 'Cfg', c, 'Coordsys', 'bregma', 'Unit', 'mm');
    end

    % BrainVision Recorder: 16-bit integers of 0.1 uV, flashes as 'S  1', the amplifier table
    if has('brainvision')
        eegBV = eeg;
        [eegBV.events.type] = deal('S  1');
        amp = {'A m p l i f i e r  S e t u p', '============================', 'Number of channels: 4', ...
            sprintf('Sampling Rate [Hz]: %d', fs), '', 'Channels', '--------', ...
            '#     Name      Phys. Chn.    Resolution / Unit   Low Cutoff [s]   High Cutoff [Hz]   Notch [Hz]'};
        for k = 1:4
            amp{end + 1} = sprintf('%-5d %-9s %-13d 0.1 %sV             10               250                Off', ...
                k, labels{k}, k, char(181)); %#ok<AGROW>
        end
        amp = [amp, {'', 'S o f t w a r e  F i l t e r s', '==============================', 'Disabled'}];
        writeBrainVision(out.brainvision, eegBV, 'BinaryFormat', 'INT_16', 'Resolution', 0.1, ...
            'Reference', 'Cb', 'Comment', amp);
    end

    if has('matrix')
        M = struct('data', double(data), 'fs', fs, 'labels', {labels}, 'flashTimes', onsets);
        save(out.matrix, '-struct', 'M', '-v7');
    end

    % EDF+C: 'EEG <name>' labels, flashes as annotations
    sig = struct('label', strcat('EEG', {' '}, labels), 'units', 'uV', 'fs', fs, ...
        'data', num2cell(double(data), 2)');
    if has('edf')
        writeEDF(out.edf, sig, 'Format', 'EDF+C', 'Annotations', ...
            struct('onset', num2cell(onsets), 'duration', 0, 'text', 'flash'));
    end
    % BDF: 24 bits, trigger code 1 on the Status channel for 10 ms at each flash
    if has('bdf')
        status = zeros(1, N);
        for k = 1:numel(onsets), status(round(onsets(k) * fs) + (1:10)) = 1; end
        sigB = [struct('label', labels, 'units', 'uV', 'fs', fs, 'data', num2cell(double(data), 2)'), ...
            struct('label', 'Status', 'units', '', 'fs', fs, 'data', status)];
        writeEDF(out.bdf, sigB, 'Format', 'BDF');
    end
    % EGI .mff folder
    if has('mff')
        eegM = eeg;
        eegM.chanlocs = struct('label', labels, 'x', num2cell(ml / 10), 'y', num2cell(ap / 10), 'z', 0, ...
            'theta', NaN, 'radius', NaN);
        if exist(out.mff, 'dir') == 7, rmdir(out.mff, 's'); end
        writeMFF(out.mff, eegM);
    end
    % XDF: an EEG stream and a Markers stream on the LSL clock (from 1000 s)
    if has('xdf')
        S = struct('name', {'RodentAmp', 'Flash'}, 'type', {'EEG', 'Markers'}, 'fs', {fs, 0}, ...
            'format', {'float32', 'string'}, 'labels', {labels, {'Marker'}}, ...
            'units', {repmat({'microvolts'}, 1, 4), {''}}, 'timeStamps', {1000 + t, 1000 + onsets}, ...
            'data', {double(data), repmat({'flash'}, 1, numel(onsets))});
        writeXDF(out.xdf, S);
    end
    % EEG-BIDS: positions as ML (x, right) and AP (y, anterior) in mm from bregma
    if has('bids')
        eegB = eeg;
        eegB.chanlocs = struct('label', labels, 'x', num2cell(ml), 'y', num2cell(ap), 'z', 0, ...
            'theta', NaN, 'radius', NaN);
        out.bids = writeEEGBIDS(fullfile(folder, 'bids'), eegB, 'Subject', 'rat01', 'Session', '1', ...
            'Task', 'flash', 'CoordSystem', 'Other', 'CoordUnits', 'mm', 'Description', ...
            'Neuronal Data Analyzer Lab rodent EEG demo (synthetic)');
    end
    for f = setdiff(fieldnames(out)', formats)
        out.(f{1}) = '';                                         % not written
    end
end

%% writeRaw - Raw BrainVision Recorder files of the oddball study (FCz reference, artefacts)
function [out, truth] = writeRaw(folder, nPart, formats)
    out = struct('brainvision', {});
    truth = struct();
    if ~any(strcmp(formats, 'brainvision')), return; end
    if ~(exist(folder, 'dir') == 7), mkdir(folder); end
    labels = {'Fp1', 'Fp2', 'F7', 'F3', 'Fz', 'F4', 'F8', 'FC5', 'FC1', 'FC2', 'FC6', 'T7', ...
        'C3', 'Cz', 'C4', 'T8', 'TP9', 'CP5', 'CP1', 'CP2', 'CP6', 'TP10', 'P7', 'P3', 'Pz', ...
        'P4', 'P8', 'PO9', 'O1', 'Oz', 'O2', 'PO10'};
    azel = [18 0; -18 0; 54 0; 40 42; 0 45; -40 42; -54 0; 69 21; 45 67; -45 67; -69 21; ...
        90 0; 90 45; 0 90; -90 45; -90 0; 108 -18; 111 21; 135 67; -135 67; -111 21; -108 -18; ...
        126 0; 140 42; 180 45; -140 42; -126 0; 144 -18; 162 0; 180 0; -162 0; -144 -18];
    azel = [azel; 0 67.5];                                       % row 33: FCz, the online reference
    R = 85;
    az = azel(:, 1) * pi / 180;
    el = azel(:, 2) * pi / 180;
    u = [cos(el) .* cos(az), cos(el) .* sin(az), sin(el)];      % x nose, y left, z up
    posRAS = R * [-u(:, 2), u(:, 1), u(:, 3)];
    nCh = numel(labels);
    fs = 500;
    names = {'Standard', 'Target', 'Novel'};
    markers = {'S  1', 'S  2', 'S  3'};
    nPer = [40 15 15];
    p300 = [2 10 6];
    nBlinkTrials = 8;
    nBlinkBetween = 6;
    ch = @(name) find(strcmp([labels, {'FCz'}], name), 1);
    w = @(v, sig) exp(-(acos(max(-1, min(1, u * v'))) / sig) .^ 2);
    wP1 = w(u(ch('Oz'), :), 0.6); wN1 = w(u(ch('Cz'), :), 0.6); wP3 = w(u(ch('Pz'), :), 0.8);
    wA = w(u(ch('Oz'), :), 0.7);
    eyes = [cos(-0.3), 0, sin(-0.3)];                            % below the forehead, between the eyes
    wBlink = w(eyes, 0.5);
    wBlink = wBlink / max(wBlink([ch('Fp1'), ch('Fp2')]));       % 1 at Fp1 / Fp2
    good = ~strcmp(labels, 'T7');
    tk = (-100:400) / fs;                                        % -0.2 to 0.8 s around each event
    g = @(mu, sd) exp(-0.5 * ((tk - mu) / sd) .^ 2);

    truth = struct('labels', {labels}, 'reference', 'FCz', 'referenceAzEl', azel(end, :), 'fs', fs, ...
        'conditionNames', {names}, 'markers', {markers}, 'trialsPerCondition', nPer, 'badChannel', 'T7', ...
        'alpha', alphaTruth(), ...
        'lineFrequency', 50, 'blinkAmplitude', 150, 'participants', struct('condition', {}, 'onsets', {}, ...
        'blinkTrials', {}, 'blinkBetween', {}, 'ampScale', {}, 'latShift', {}, 'n1CzFCz', {}, ...
        'n1CzAverage', {}, 'dc', {}, 'lineAmplitude', {}, 'data', {}));
    locs = struct('label', labels, 'x', num2cell(R * u(1:nCh, 1)'), 'y', num2cell(R * u(1:nCh, 2)'), ...
        'z', num2cell(R * u(1:nCh, 3)'), 'theta', NaN, 'radius', NaN);
    for p = 1:nPart
        rs = RandStream('mt19937ar', 'Seed', 20260926 + 200 + p);
        amp = 1 + 0.1 * randn(rs);
        lat = max(-0.02, min(0.02, 0.01 * randn(rs)));
        c0 = [ones(1, nPer(1)), 2 * ones(1, nPer(2)), 3 * ones(1, nPer(3))];
        cond = c0(randperm(rs, numel(c0)));
        n = numel(cond);
        isi = 1.2 + 0.3 * rand(rs, 1, n - 1);
        onsets = 2 + [0, cumsum(isi)];
        T = ceil(onsets(end) + 2);
        nS = T * fs;
        t = (0:nS - 1) / fs;
        % True potentials at the 32 channels and FCz (against infinity)
        erd = ones(1, nS);                                       % alpha halved after each Target
        for k = find(cond == 2)
            erd = erd .* alphaEnvelope(t - onsets(k));
        end
        V = 3 * pinkNoise(rs, nS, nCh + 1)' + randn(rs, nCh + 1, nS) ...
            + 4 * wA * (erd .* sin(2 * pi * 10 * t + 2 * pi * rand(rs)));
        blinkTrials = sort(randperm(rs, n, nBlinkTrials));
        roomy = find(isi >= 1.4);
        roomy = roomy(~ismember(roomy, blinkTrials) & ~ismember(roomy + 1, blinkTrials));
        between = sort(roomy(randperm(rs, numel(roomy), nBlinkBetween)));
        for k = 1:n
            erp = amp * (2 * wP1 * g(0.06, 0.012) - 5 * wN1 * g(0.1 + lat, 0.015) ...
                + p300(cond(k)) * wP3 * g(0.35 + lat, 0.06));
            i = round(onsets(k) * fs) + 1 + (-100:400);
            V(:, i) = V(:, i) + erp;
        end
        blinkAt = [onsets(blinkTrials) + 0.1 + 0.5 * rand(rs, 1, nBlinkTrials), ...
            (onsets(between) + 0.8 + onsets(between + 1) - 0.2) / 2];
        for b = blinkAt
            V = V + 150 * wBlink * exp(-0.5 * ((t - b) / 0.05) .^ 2);
        end
        % Recorded: against FCz, plus electrode offsets, drift, line noise and a noisy T7
        dc = -400 + 800 * rand(rs, nCh, 1);
        slope = -1 + 2 * rand(rs, nCh, 1);                       % uV per s
        lineAmp = 5 + 10 * rand(rs, nCh, 1);
        X = V(1:nCh, :) - V(end, :) + dc + slope * t + lineAmp * sin(2 * pi * 50 * t);
        X(ch('T7'), :) = X(ch('T7'), :) + 150 * randn(rs, 1, nS);
        data = single(X);
        n1 = -5 * amp * wN1;
        truth.participants(p) = struct('condition', {names(cond)}, 'onsets', onsets, 'blinkTrials', blinkTrials, ...
            'blinkBetween', between, 'ampScale', amp, 'latShift', lat, 'n1CzFCz', n1(ch('Cz')) - n1(end), ...
            'n1CzAverage', n1(ch('Cz')) - mean(n1([good, false])), 'dc', dc', 'lineAmplitude', lineAmp', ...
            'data', data);

        ev = struct('type', markers(cond), 'latency', num2cell(onsets), 'duration', 0);
        eeg = EEGSource.make(data, fs, 'Times', t, 'Labels', labels, 'Chanlocs', locs, 'Events', ev, ...
            'Reference', 'FCz', 'Unit', 'uV', 'IsEpoched', false);
        out(p).brainvision = fullfile(folder, sprintf('sub-%02d_task-oddball.vhdr', p));
        amp32 = {'A m p l i f i e r  S e t u p', '============================', ...
            sprintf('Number of channels: %d', nCh), sprintf('Sampling Rate [Hz]: %d', fs), ...
            'Reference channel: FCz (not recorded)', '', 'S o f t w a r e  F i l t e r s', ...
            '==============================', 'Disabled'};
        writeBrainVision(out(p).brainvision, eeg, 'Positions', posRAS(1:nCh, :), 'Reference', 'FCz', ...
            'Comment', amp32);
    end
end

%% alphaEnvelope - Alpha amplitude at times tau (s) after a Target event
% 1, falling to 0.5 from 250 to 350 ms, 0.5 until 650 ms, back to 1 at 750
% ms (raised-cosine ramps); 1 before and after.
function e = alphaEnvelope(tau)
    e = ones(size(tau));
    r = tau > 0.25 & tau < 0.35;
    e(r) = 1 - 0.25 * (1 - cos(pi * (tau(r) - 0.25) / 0.1));
    e(tau >= 0.35 & tau <= 0.65) = 0.5;
    r = tau > 0.65 & tau < 0.75;
    e(r) = 0.5 + 0.25 * (1 - cos(pi * (tau(r) - 0.65) / 0.1));
end

%% alphaTruth - The simulated alpha and its decrease after Target (known answers)
function a = alphaTruth()
    a = struct('channels', {{'O1', 'Oz', 'O2'}}, 'frequency', 10, 'amplitude', 4, ...
        'decrease', struct('condition', 'Target', 'from', 0.35, 'to', 0.65, 'ramp', 0.1, ...
        'amplitudeFactor', 0.5, 'powerChangePct', -75, 'powerChangeDb', 10 * log10(0.25)));
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

%% allExist - Cached files present for every requested kind and format
function tf = allExist(files, kinds, formats)
    tf = true;
    for k = 1:numel(kinds)
        if ~isfield(files, kinds{k}), tf = false; return; end
        f = files.(kinds{k});
        for i = 1:numel(f)
            for fmt = formats
                if ~isfield(f(i), fmt{1}), continue; end            % rodent-only formats
                x = f(i).(fmt{1});
                if ~(exist(x, 'file') == 2 || exist(x, 'dir') == 7), tf = false; return; end
            end
        end
    end
end
