%% demoFormats.m
% =========================================================================
% DEMO FORMATS - THE DEMO TANK AS INTAN, OPEN EPHYS AND NWB RECORDINGS
% =========================================================================
% files = demoFormats()                    cached copy in <DemoData.folder>/formats
% files = demoFormats(folder)              (re)write the files into folder
% files = demoFormats(folder, Name, Value) options below
%
% Writes the first 6 s of 4 channels (3-6, around the evoked sink at
% channel 4 and the units at channels 4-5) of DemoData.tdtTank in three
% acquisition formats, so the readers in core/io can be round-trip tested
% and Extract Ephys can demonstrate every source:
%   files.intan      demo_intan.rhd: RHD file format v3.0, 20 kHz
%                    (resampled), stimulus on DIGITAL-IN-01 and as a 1 V
%                    pulse on ANALOG-IN-1
%   files.openephys  demo_openephys/ session folder (GUI 0.6 layout),
%                    30 kHz (resampled), CH1-CH4 + ADC1 (1 V pulses), TTL
%                    line 1 events, first sample number 512000
%   files.nwb        demo.nwb: raw at the tank rate (24414.0625 Hz) as
%                    int16 x 0.195 uV in /acquisition, the tank's whisker
%                    stimulus (1017.25 Hz) in /stimulus/presentation and
%                    the stimuli as /intervals/trials (written by writeNWB)
%   files.truth      onsets (s), stimDuration (0.02 s), duration (6 s),
%                    channels (tank channels 3:6), sinkIndex (2 = tank
%                    channel 4), and per format: fs, nSamples, lsb (volts
%                    per bit) and data (channels x samples, volts, before
%                    quantization; only when freshly written, not in the cache)
%   files.folder
%
% Options (Name, Value):
%   'Formats'  subset of {'intan', 'openephys', 'nwb'} (default: all)
%   'Tank'     a TDTbin2mat-like struct to convert instead of the demo tank
%              (streams.xRAW, streams.Whis, truth.onsets)
%   'Force'    true regenerates the cache (demoFormats() only)
% Deterministic: no random numbers beyond DemoData's fixed seed.
% Requires core/io on the path (writeIntanRHD, writeOpenEphysBinary,
% writeNWB). Toolboxes: none.
% =========================================================================

function files = demoFormats(folder, varargin)
    o = struct('Formats', {{'intan', 'openephys', 'nwb'}}, 'Tank', [], 'Force', false);
    for k = 1:2:numel(varargin)
        o.(varargin{k}) = varargin{k+1};
    end
    cacheVersion = 2;
    cached = nargin < 1 || isempty(folder);
    prev = [];
    if cached
        folder = fullfile(DemoData.folder(), 'formats');
        manifest = fullfile(folder, 'demo_formats.mat');
        if ~o.Force && exist(manifest, 'file') == 2
            s = load(manifest);
            if isfield(s, 'version') && s.version == cacheVersion
                prev = s.files;
                prev.folder = folder;
                if allExist(prev, o.Formats)
                    files = prev;
                    return;
                end
                % Generate only the formats missing from the cache
                o.Formats = o.Formats(~cellfun(@(f) allExist(prev, {f}), o.Formats));
            end
        end
    end
    if ~(exist(folder, 'dir') == 7), mkdir(folder); end

    tank = o.Tank;
    if isempty(tank)
        tank = DemoData.loadTank(DemoData.file('tdtTank'));
    end
    T = 6;
    chans = 3:6;
    fsT = tank.streams.xRAW.fs;
    nT = round(T * fsT);
    raw = double(tank.streams.xRAW.data(chans, 1:nT));
    tT = (0:nT - 1) / fsT;
    onsets = tank.truth.onsets(tank.truth.onsets < T - 0.5);
    dur = 0.02;
    truth = struct('onsets', onsets, 'stimDuration', dur, 'duration', T, 'channels', chans, ...
        'sinkIndex', find(chans == 4));
    files = struct('folder', folder);
    if ~isempty(prev)
        % Keep the cached formats; the common truth fields are recomputed identically
        files = prev;
        for f = {'intan', 'openephys', 'nwb'}
            if isfield(prev.truth, f{1}), truth.(f{1}) = prev.truth.(f{1}); end
        end
    end
    names = arrayfun(@(c) sprintf('tank ch%d', c), chans, 'UniformOutput', false);

    % ---- Intan RHD2000 (20 kHz) ----
    if any(strcmp(o.Formats, 'intan'))
        fs = 20000;
        [x, t] = resampleTo(raw, tT, fs, T);
        pulse = pulses(t, onsets, dur);
        f = fullfile(folder, 'demo_intan.rhd');
        out = writeIntanRHD(f, x, fs, 'Version', [3 0], 'DigitalIn', pulse, 'ADC', double(pulse), ...
            'ChannelNames', names, 'Notes', {'NeuroAnalyzer demo: DemoData tank channels 3-6, first 6 s', ...
            'Stimulus: DIGITAL-IN-01 (TTL) and ANALOG-IN-1 (1 V)'});
        n = out.nSamples;
        files.intan = f;
        truth.intan = struct('fs', fs, 'nSamples', n, 'lsb', 0.195e-6, 'adcLsb', 50.354e-6, ...
            'data', x(:, 1:n), 'digital', pulse(1:n), 'channelNames', {names});
    end

    % ---- Open Ephys binary (30 kHz) ----
    if any(strcmp(o.Formats, 'openephys'))
        fs = 30000;
        [x, t] = resampleTo(raw, tT, fs, T);
        pulse = pulses(t, onsets, dur);
        d = fullfile(folder, 'demo_openephys');
        if exist(d, 'dir') == 7, rmdir(d, 's'); end
        on = find(diff([0 pulse]) == 1);
        off = find(diff([0 pulse]) == -1);
        writeOpenEphysBinary(d, x, fs, 'Version', '0.6.7', 'ADC', double(pulse), ...
            'TTL', struct('line', 1, 'on', on, 'off', off), 'FirstSample', 512000, ...
            'ChannelNames', {'CH1', 'CH2', 'CH3', 'CH4'});
        files.openephys = d;
        truth.openephys = struct('fs', fs, 'nSamples', size(x, 2), 'lsb', 0.195e-6, ...
            'adcLsb', 0.00015258789, 'data', x, 'firstSample', 512000, 'ttlLine', 1);
    end

    % ---- NWB (tank rate, int16 raw + stimulus TimeSeries + trials) ----
    if any(strcmp(o.Formats, 'nwb'))
        f = fullfile(folder, 'demo.nwb');
        fsS = tank.streams.Whis.fs;
        nS = round(T * fsS);
        stim = double(tank.streams.Whis.data(1, 1:nS));
        lsb = 0.195e-6;
        r = struct();
        r.raw = struct('data', int16(round(raw / lsb)), 'fs', fsT, 'channels', chans, ...
            'conversion', lsb, 'description', 'DemoData tank channels 3-6 (first 6 s)');
        r.stim = struct('data', stim, 'fs', fsS, 'name', 'whisker_stimulus', 'unit', 'a.u.', ...
            'description', 'Whisker stimulus: 20 ms pulses every 2 s from 1 s');
        r.trials = struct('start', onsets, 'stop', onsets + dur);
        r.electrodes = struct('names', {names}, 'location', 'barrel cortex (synthetic)');
        r.sessionDescription = 'NeuroAnalyzer demo recording (synthetic)';
        r.identifier = 'neuroanalyzer-demo-tank';
        r.sessionStartTime = '2026-09-24T12:00:00.000+00:00';
        r.source = 'DemoData.tdtTank (synthetic TDT-like block)';
        r.subject = struct('subject_id', 'demo', ...
            'description', 'Synthetic recording generated by NeuroAnalyzer DemoData (no animal)');
        writeNWB(f, r, 'Engine', 'minimal');
        files.nwb = f;
        truth.nwb = struct('fs', fsT, 'nSamples', nT, 'lsb', lsb, 'data', raw, ...
            'stimFs', fsS, 'stim', stim);
    end

    files.truth = truth;
    if cached
        slim = files;
        for fmt = {'intan', 'openephys', 'nwb'}
            if isfield(slim.truth, fmt{1}) && isfield(slim.truth.(fmt{1}), 'data')
                slim.truth.(fmt{1}) = rmfield(slim.truth.(fmt{1}), 'data');
            end
        end
        version = cacheVersion; %#ok<NASGU>
        files = slim; %#ok<NASGU>
        save(fullfile(folder, 'demo_formats.mat'), 'files', 'version');
        files = slim;
    end
end

%% resampleTo - Linear interpolation of channels x samples onto a new rate
function [x, t] = resampleTo(raw, tIn, fs, T)
    t = (0:round(T * fs) - 1) / fs;
    x = interp1(tIn(:), raw', t(:), 'linear', 'extrap')';
end

%% pulses - 0/1 row: high from each onset for dur seconds (as DemoData's stimulus)
function p = pulses(t, onsets, dur)
    p = false(size(t));
    for k = 1:numel(onsets)
        p(t >= onsets(k) & t < onsets(k) + dur) = true;
    end
end

%% allExist - Cached files present for every requested format
function tf = allExist(files, formats)
    tf = true;
    for k = 1:numel(formats)
        f = formats{k};
        if ~isfield(files, f) || ~(exist(files.(f), 'file') == 2 || exist(files.(f), 'dir') == 7)
            tf = false;
            return;
        end
    end
end
