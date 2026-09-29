%% EEGFormatsTest.m
% =========================================================================
% UNIT TESTS FOR THE EEG DATA MODEL AND IMPORTERS (EEGLAB, FIELDTRIP,
% BRAINVISION, .mat)
% =========================================================================
% The synthetic study written by core/demo/demoEEG (oddball scalp EEG and
% a continuous rodent recording) is read back from every format: each
% importer must return the same numbers (single, microvolts), trial
% conditions, events, channel names, positions and history sentences.
% Because a round trip only proves the readers agree with our own
% writers, each format also has hand-built files assembled here from the
% published layouts (EEGLAB EEG struct with a .fdt file, FieldTrip raw and
% timelock structures, BrainVision headers as Recorder and Analyzer write
% them), and clear-error checks (missing .fdt, truncated
% data, wrong sizes, unknown variables). The demo's known answers (N1,
% P300 order, alpha, VEP) are checked on the data as read.
% =========================================================================

function tests = EEGFormatsTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'io'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.tmp = fullfile(tempdir, ['NeuroAnalyzerEEGTest_' char(java.util.UUID.randomUUID)]);
    mkdir(tests.TestData.tmp);
    tests.TestData.demo = demoEEG(fullfile(tests.TestData.tmp, 'demo'), 'Participants', 2);
end

function teardownOnce(tests)
    if exist(tests.TestData.tmp, 'dir') == 7, rmdir(tests.TestData.tmp, 's'); end
end

%% ------------------------------------------------------------ Demo, EEGLAB

function testEEGLABInline(tests)
    d = tests.TestData.demo;
    tr = d.truth.scalp;
    P = tr.participants(1);
    eeg = readEEGLAB(d.scalp(1).eeglab);
    verifyEqual(tests, size(eeg.data), [32 250 65]);
    verifyEqual(tests, eeg.data, P.data, 'the numbers exactly as written (single, uV)');
    verifyEqual(tests, eeg.fs, 250);
    verifyEqual(tests, eeg.times, tr.times, 'AbsTol', 1e-9);
    verifyEqual(tests, eeg.labels, tr.labels);
    verifyTrue(tests, eeg.isEpoched);
    verifyEqual(tests, eeg.trials.condition, P.condition);
    verifyEqual(tests, sort(eeg.conditions), sort(tr.conditionNames));
    verifyEqual(tests, [[eeg.chanlocs.x]', [eeg.chanlocs.y]', [eeg.chanlocs.z]'], tr.posEEGLAB, 'AbsTol', 1e-9);
    verifyEqual(tests, eeg.coordSystem, 'EEGLAB (x = nose, y = left ear, z = up)');
    % EEGLAB polar positions: theta 0 = nose, negative to the left; radius 0.5 at the equator
    t7 = strcmp(eeg.labels, 'T7');
    verifyEqual(tests, [eeg.chanlocs(t7).theta, eeg.chanlocs(t7).radius], [-90 0.5], 'AbsTol', 1e-9);
    verifyEqual(tests, eeg.chanlocs(strcmp(eeg.labels, 'Cz')).radius, 0, 'AbsTol', 1e-9);
    verifyEqual(tests, eeg.reference, 'average of all channels');
    verifyEqual(tests, eeg.history, eeglabHistoryLines(P.rejected));
    verifyEmpty(tests, eeg.notes);
    verifyEqual(tests, eeg.source, 'EEGLAB');
end

function testEEGLABFdtAndTopLevelFields(tests)
    d = tests.TestData.demo;
    f = d.scalp(1).eeglabfdt;
    s = load(f, '-mat');
    verifyFalse(tests, isfield(s, 'EEG'), 'newer pop_saveset layout: fields at the top level');
    [~, b] = fileparts(f);
    verifyEqual(tests, s.data, [b '.fdt'], 'EEG.data names the .fdt file');
    eeg = readEEGLAB(f);
    ref = readEEGLAB(d.scalp(1).eeglab);
    verifyEqual(tests, eeg.data, ref.data);
    verifyEqual(tests, eeg.trials.condition, ref.trials.condition);
    verifyEqual(tests, eeg.history, ref.history);
    verifyEqual(tests, eeg.chanlocs, ref.chanlocs);
end

%% --------------------------------------------------------- Demo, FieldTrip

function testFieldTripRaw(tests)
    d = tests.TestData.demo;
    tr = d.truth.scalp;
    P = tr.participants(2);
    eeg = readFieldTrip(d.scalp(2).fieldtrip);
    verifyEqual(tests, eeg.data, P.data);
    verifyEqual(tests, eeg.fs, 250);
    verifyEqual(tests, eeg.times, tr.times, 'AbsTol', 1e-9);
    verifyEqual(tests, eeg.labels, tr.labels);
    verifyEqual(tests, eeg.trials.condition, P.condition, 'trialinfo codes named from conditionNames');
    verifyEqual(tests, [[eeg.chanlocs.x]', [eeg.chanlocs.y]', [eeg.chanlocs.z]'], tr.posRAS, 'AbsTol', 1e-9);
    verifyEqual(tests, eeg.coordSystem, 'FieldTrip (ras, mm)');
    verifyEqual(tests, eeg.reference, 'average of all channels');
    verifyEqual(tests, eeg.history, { ...
        'Band-pass filtered 0.1 to 30 Hz (ft_preprocessing).', ...
        'Re-referenced to the average of all channels (ft_preprocessing).', ...
        'Computed ICA with runica (ft_componentanalysis).', ...
        'Removed ICA components 1 and 3 (ft_rejectcomponent).', ...
        'Cut into 70 trials (ft_redefinetrial).', ...
        'Removed the baseline, the mean from -0.2 to 0 s (ft_preprocessing).', ...
        'Rejected the trials with 5 artifacts marked by the visual check (ft_rejectartifact).', ...
        'Interpolated channel T7 using the spline method (ft_channelrepair).'});
    verifyEmpty(tests, eeg.notes);
end

%% ------------------------------------------------------------ Demo, matrix

function testMatrixGuessAndRead(tests)
    d = tests.TestData.demo;
    P = d.truth.scalp.participants(1);
    g = EEGSource.guessMatrixMap(d.scalp(1).matrix);
    verifyFalse(tests, g.ambiguous);
    verifyEqual(tests, g.map.data, 'eeg');
    verifyEqual(tests, g.map.dims, {'trial', 'channel', 'time'});
    verifyEqual(tests, g.map.fs, 'srate');
    verifyEqual(tests, g.map.labels, 'chanNames');
    verifyEqual(tests, g.map.times, 'times');
    verifyEqual(tests, g.map.conditions, 'condition');
    verifyEqual(tests, numel(g.variables), 5);

    eeg = EEGSource.open(d.scalp(1).matrix);          % detect + guessed map
    verifyEqual(tests, eeg.format, 'matrix');
    verifyClass(tests, eeg.data, 'single');
    verifyEqual(tests, double(eeg.data), double(P.data), 'AbsTol', 1e-4, 'volts converted to uV');
    verifyEqual(tests, eeg.trials.condition, P.condition);
    verifyEqual(tests, numel(eeg.notes), 1);
    verifyNotEmpty(tests, strfind(eeg.notes{1}, 'volts'));
    verifyEqual(tests, eeg.coordSystem, '', 'a plain matrix has no positions');
    verifyEqual(tests, EEGSource.describeHistory(eeg), {'The file does not say how the data were processed before.'});

    % The same file read with a map written by hand
    map = struct('data', 'eeg', 'fs', 250, 'dims', {{'trial', 'channel', 'time'}}, 'labels', 'chanNames', ...
        'tStart', -0.2, 'conditions', 'condition', 'unit', 'V');
    eeg2 = readEEGMatrix(d.scalp(1).matrix, map);
    verifyEqual(tests, eeg2.data, eeg.data);
    verifyEqual(tests, eeg2.times, d.truth.scalp.times, 'AbsTol', 1e-9);
end

function testAllFormatsAgree(tests)
    d = tests.TestData.demo;
    for p = 1:2
        ref = readEEGLAB(d.scalp(p).eeglab);
        for fmt = {'eeglabfdt', 'fieldtrip', 'brainvision', 'matrix'}
            eeg = EEGSource.open(d.scalp(p).(fmt{1}));
            tag = sprintf('participant %d, %s', p, fmt{1});
            verifyEqual(tests, double(eeg.data), double(ref.data), 'AbsTol', 1e-4, tag);
            verifyEqual(tests, eeg.labels, ref.labels, tag);
            verifyEqual(tests, eeg.times, ref.times, 'AbsTol', 1e-9, tag);
            verifyEqual(tests, eeg.trials.condition, ref.trials.condition, tag);
            verifyEqual(tests, sort(eeg.conditions), sort(ref.conditions), tag);
        end
    end
end

function testDetect(tests)
    d = tests.TestData.demo;
    for k = {'scalp', 'rodent'}
        f = d.(k{1})(1);
        verifyEqual(tests, EEGSource.detect(f.eeglab), 'eeglab');
        verifyEqual(tests, EEGSource.detect(f.eeglabfdt), 'eeglab');
        verifyEqual(tests, EEGSource.detect(f.fieldtrip), 'fieldtrip');
        verifyEqual(tests, EEGSource.detect(f.matrix), 'matrix');
        verifyEqual(tests, EEGSource.detect(f.brainvision), 'brainvision');
        verifyError(tests, @() EEGSource.detect(strrep(f.brainvision, '.vhdr', '.vmrk')), 'NeuroAnalyzer:io:unknownFormat');
        verifyError(tests, @() EEGSource.detect(strrep(f.brainvision, '.vhdr', '.eeg')), 'NeuroAnalyzer:io:unknownFormat');
    end
    % An EEG variable inside a .mat file is EEGLAB too
    s = load(d.scalp(1).eeglab, '-mat');
    EEG = s.EEG; %#ok<NASGU>
    f = fullfile(tests.TestData.tmp, 'eeg_in_mat.mat');
    save(f, 'EEG');
    verifyEqual(tests, EEGSource.detect(f), 'eeglab');
    e1 = EEGSource.open(f);
    e2 = readEEGLAB(d.scalp(1).eeglab);
    verifyEqual(tests, e1.data, e2.data);
    fdt = strrep(d.scalp(1).eeglabfdt, '.set', '.fdt');
    verifyError(tests, @() EEGSource.detect(fdt), 'NeuroAnalyzer:io:unknownFormat');
    verifyError(tests, @() EEGSource.detect(fullfile(tests.TestData.tmp, 'none.set')), 'NeuroAnalyzer:io:fileNotFound');
    list = EEGSource.formats();
    verifyEqual(tests, {list.key}, {'eeglab', 'fieldtrip', 'brainvision', 'matrix'});
end

%% ------------------------------------------------------------ Demo, rodent

function testRodentContinuous(tests)
    d = tests.TestData.demo;
    tr = d.truth.rodent;
    for fmt = {'eeglab', 'eeglabfdt', 'fieldtrip', 'matrix'}
        eeg = EEGSource.open(d.rodent.(fmt{1}));
        tag = fmt{1};
        verifyFalse(tests, eeg.isEpoched, tag);
        verifyEqual(tests, eeg.fs, 1000, tag);
        verifyEqual(tests, size(eeg.data), [4 60000], tag);
        verifyEqual(tests, eeg.data, tr.data, tag);
        verifyEqual(tests, eeg.labels, tr.labels, tag);
        verifyEqual(tests, eeg.times(1), 0, tag);
        verifyEmpty(tests, eeg.trials.condition, tag);
        verifyEqual(tests, numel(eeg.events), 30, tag);
        verifyEqual(tests, [eeg.events.latency], tr.onsets, 'AbsTol', 1e-9, tag);
        if ~strcmp(tag, 'matrix')
            verifyEqual(tests, unique({eeg.events.type}), {'flash'}, tag);
        end
    end
    eeg = readEEGLAB(d.rodent.eeglab);
    verifyEqual(tests, [eeg.chanlocs.x], tr.ap, 'EEGLAB x = anterior');
    verifyEqual(tests, [eeg.chanlocs.y], -tr.ml, 'EEGLAB y = left');
    verifyEqual(tests, eeg.coordSystem, 'EEGLAB (x = nose, y = left ear, z = up); bregma, mm');
    verifyEqual(tests, eeg.reference, 'cerebellar screw');
    verifyEqual(tests, eeg.history, {'Band-pass filtered 1 to 100 Hz (pop_eegfiltnew).'});
    eeg = readFieldTrip(d.rodent.fieldtrip);
    verifyEqual(tests, [eeg.chanlocs.x], tr.ml);
    verifyEqual(tests, [eeg.chanlocs.y], tr.ap);
    verifyEqual(tests, eeg.coordSystem, 'FieldTrip (bregma, mm)');
    verifyEqual(tests, eeg.history, {'Band-pass filtered 1 to 100 Hz (ft_preprocessing).'});
    g = EEGSource.guessMatrixMap(d.rodent.matrix);
    verifyEqual(tests, g.map.dims, {'channel', 'time'});
    verifyEqual(tests, g.map.events, 'flashTimes');
    lines = EEGSource.describe(eeg);
    verifyEqual(tests, lines{1}, '4 channels at 1000 Hz, a continuous recording of 60.0 s.');
    verifyEqual(tests, lines{2}, '30 events marked (flash).');
end

%% ------------------------------------------------------ Demo known answers

function testDemoKnownAnswers(tests)
    d = tests.TestData.demo;
    tr = d.truth.scalp;
    for p = 1:2
        P = tr.participants(p);
        eeg = readEEGLAB(d.scalp(p).eeglab);
        verifyEqual(tests, numel(P.rejected), 5);
        counts = cellfun(@(c) sum(strcmp(eeg.trials.condition, c)), tr.conditionNames);
        verifyEqual(tests, sum(counts), 65, '70 trials minus 5 rejected');
        verifyTrue(tests, all(counts <= tr.trialsPerCondition), 'rejected trials only remove');
        t = eeg.times;
        pz = strcmp(eeg.labels, 'Pz');
        w = t >= 0.3 & t <= 0.4;
        m = cellfun(@(c) mean(mean(eeg.data(pz, w, strcmp(eeg.trials.condition, c)), 3)), tr.conditionNames);
        verifyGreaterThan(tests, m(2), m(3), 'P300: Target > Novel');
        verifyGreaterThan(tests, m(3), m(1), 'P300: Novel > Standard');
        verifyGreaterThan(tests, m(2) - m(1), 4, 'P300: Target clearly above Standard');
        cz = strcmp(eeg.labels, 'Cz');
        erp = mean(eeg.data(cz, :, :), 3);
        w = t >= 0.05 & t <= 0.15;
        [v, i] = min(erp(w));
        tw = t(w);
        verifyLessThan(tests, v, -2, 'N1 negative at Cz');
        verifyEqual(tests, tw(i), 0.1 + P.latShift, 'AbsTol', 0.02, 'N1 latency');
        oz = strcmp(eeg.labels, 'Oz');
        x = squeeze(double(eeg.data(oz, :, :)));
        pw = mean(abs(fft(x - mean(x, 1))) .^ 2, 2);
        f = (0:numel(t) - 1) * eeg.fs / numel(t);
        band = find(f >= 5 & f <= 20);
        [~, j] = max(pw(band));
        verifyEqual(tests, f(band(j)), 10, 'alpha peak at 10 Hz over Oz');
    end
    r = d.truth.rodent;
    eeg = readEEGLAB(d.rodent.eeglab);
    v1 = strcmp(eeg.labels, 'V1-L');
    idx = round(r.onsets * r.fs);
    seg = cell2mat(arrayfun(@(i) double(eeg.data(v1, i + (1:200))), idx', 'UniformOutput', false));
    vep = mean(seg, 1);
    [v, i] = min(vep(30:70));
    verifyLessThan(tests, v, -25, 'VEP negative peak over V1');
    verifyEqual(tests, (i + 29) / r.fs, 0.05, 'AbsTol', 0.006, 'VEP latency');
end

%% --------------------------------------------------- Hand-built EEGLAB files

function testEEGLABHandBuilt(tests)
    % EEGLAB dataset layout (pop_saveset, fields at the top level): the
    % numbers are float32 little-endian in a .fdt file, channels x
    % (samples x trials); event latencies count samples in that
    % concatenated time axis; numeric event types; no event.epoch field.
    tmp = fullfile(tests.TestData.tmp, 'handset');
    mkdir(tmp);
    vals = single(reshape(1:60, 3, 20)) * 10;
    fid = fopen(fullfile(tmp, 'hand.fdt'), 'w', 'ieee-le');
    fwrite(fid, vals, 'float32');
    fclose(fid);
    EEG = struct('setname', 'hand', 'nbchan', 3, 'trials', 4, 'pnts', 5, 'srate', 100, ...
        'xmin', -0.02, 'xmax', 0.02, 'times', [-20 -10 0 10 20], 'data', 'hand.fdt', ...
        'datfile', 'hand.fdt', 'ref', 'common', 'epoch', [], ...
        'history', sprintf(['EEG.etc.eeglabvers = ''2024.0''; %% this tracks which version of EEGLAB is being used\n' ...
        'EEG = pop_eegfiltnew(EEG, 1, 40);\nEEG = pop_reref( EEG, [2 3]);\n' ...
        'EEG = pop_select( EEG, ''nochannel'',{''EOG''});\nEEG = pop_rejepoch( EEG, [0 1 1 0 1], 0);\n' ...
        'EEG = my_custom_step(EEG, 3);\nsystem(''echo hello'');']));
    EEG.chanlocs = struct('labels', {'Fz', 'Cz', 'Pz'}, 'X', {60, 0, -60}, 'Y', {0, 0, 0}, 'Z', {60, 85, 60});
    EEG.event = struct('type', {11, 22, 11, 22, 'boundary'}, 'latency', {3, 8, 13, 18, 19});
    f = fullfile(tmp, 'hand.set');
    save(f, '-struct', 'EEG');
    eeg = readEEGLAB(f);
    verifyEqual(tests, size(eeg.data), [3 5 4]);
    for e = 1:4
        verifyEqual(tests, eeg.data(:, :, e), vals(:, (e - 1) * 5 + (1:5)), sprintf('trial %d', e));
    end
    verifyEqual(tests, eeg.times, [-0.02 -0.01 0 0.01 0.02], 'AbsTol', 1e-12);
    verifyEqual(tests, eeg.labels, {'Fz', 'Cz', 'Pz'});
    verifyEqual(tests, eeg.trials.condition, {'11', '22', '11', '22'}, 'type of the event at time 0');
    verifyEqual(tests, eeg.conditions, {'11', '22'});
    verifyEqual(tests, [eeg.chanlocs.z], [60 85 60]);
    verifyEqual(tests, eeg.reference, 'Cz and Pz', 'from pop_reref when EEG.ref says common');
    verifyEqual(tests, eeg.history, { ...
        'Band-pass filtered 1 to 40 Hz (pop_eegfiltnew).', ...
        'Re-referenced to Cz and Pz (pop_reref).', ...
        'Removed channel EOG (pop_select).', ...
        'Rejected 3 trials (pop_rejepoch).', ...
        'Other step (as written in the file): EEG = my_custom_step(EEG, 3);', ...
        'Other step (as written in the file): system(''echo hello'');'});

    % Conditions from EEG.epoch when the events do not say
    EEG2 = rmfield(EEG, 'event');
    EEG2.event = [];
    EEG2.epoch = struct('event', {1, 2, 3, 4}, 'eventtype', {{'cue', 'A'}, {'B'}, {'A'}, {'x'}}, ...
        'eventlatency', {{-10, 0}, {0}, {0}, {10}});
    EEG2.data = vals;                                   % inline this time
    EEG2.datfile = '';
    EEG = EEG2; %#ok<NASGU>
    f2 = fullfile(tmp, 'hand_epoch.set');
    save(f2, 'EEG');
    eeg = readEEGLAB(f2);
    verifyEqual(tests, eeg.trials.condition, {'A', 'B', 'A', 'No event at 0 s'});
    verifyEqual(tests, eeg.data(:, :, 2), vals(:, 6:10));
end

function testEEGLABErrors(tests)
    d = tests.TestData.demo;
    tmp = fullfile(tests.TestData.tmp, 'errs');
    mkdir(tmp);
    verifyError(tests, @() readEEGLAB(fullfile(tmp, 'missing.set')), 'NeuroAnalyzer:io:fileNotFound');
    % .set without its .fdt
    copyfile(d.scalp(1).eeglabfdt, fullfile(tmp, 'alone.set'));
    s = load(fullfile(tmp, 'alone.set'), '-mat');
    verifyError(tests, @() readEEGLAB(fullfile(tmp, 'alone.set')), 'NeuroAnalyzer:io:fileNotFound');
    try
        readEEGLAB(fullfile(tmp, 'alone.set'));
    catch err
        verifyNotEmpty(tests, strfind(err.message, s.data), 'the message names the missing .fdt');
    end
    % Truncated .fdt
    fdt = strrep(d.scalp(1).eeglabfdt, '.set', '.fdt');
    fid = fopen(fdt, 'r'); b = fread(fid, Inf, 'uint8=>uint8'); fclose(fid);
    fid = fopen(fullfile(tmp, s.data), 'w'); fwrite(fid, b(1:end - 400)); fclose(fid);
    verifyError(tests, @() readEEGLAB(fullfile(tmp, 'alone.set')), 'NeuroAnalyzer:io:truncated');
    % Not an EEGLAB dataset
    x = 1; %#ok<NASGU>
    save(fullfile(tmp, 'other.set'), 'x', '-mat');
    verifyError(tests, @() readEEGLAB(fullfile(tmp, 'other.set')), 'NeuroAnalyzer:eeg:notEEGLAB');
    % Wrong sizes: nbchan says 4, the numbers hold 3 channels
    EEG = struct('nbchan', 4, 'pnts', 5, 'trials', 1, 'srate', 100, 'xmin', 0, 'data', zeros(3, 5)); %#ok<NASGU>
    save(fullfile(tmp, 'size.set'), 'EEG', '-mat');
    verifyError(tests, @() readEEGLAB(fullfile(tmp, 'size.set')), 'NeuroAnalyzer:eeg:sizeMismatch');
end

%% ------------------------------------------------ Hand-built FieldTrip files

function testFieldTripHandBuilt(tests)
    tmp = fullfile(tests.TestData.tmp, 'handft');
    mkdir(tmp);
    % raw: label, trial {chan x time}, time {1 x time}, fsample, trialinfo
    data = struct('label', {{'a'; 'b'}}, 'fsample', 10, ...
        'trial', {{[10 20 30; 40 50 60], [11 21 31; 41 51 61]}}, ...
        'time', {{[-0.1 0 0.1], [-0.1 0 0.1]}}, 'trialinfo', [5; 7]);
    data.cfg = struct('hpfilter', 'yes', 'hpfreq', 0.5, 'lpfilter', 'yes', 'lpfreq', 40, ...
        'dftfilter', 'yes', 'dftfreq', [50 100 150], 'resamplefs', 10, ...
        'previous', struct('trl', [1 3 -1; 4 6 -1]));
    f = fullfile(tmp, 'raw.mat');
    save(f, 'data');
    eeg = readFieldTrip(f);
    verifyEqual(tests, eeg.data, single(cat(3, data.trial{:})));
    verifyEqual(tests, eeg.times, [-0.1 0 0.1]);
    verifyEqual(tests, eeg.labels, {'a', 'b'});
    verifyEqual(tests, eeg.trials.condition, {'Code 5', 'Code 7'});
    verifyEqual(tests, eeg.notes, {'The trials are labelled with the numbers found in trialinfo.'});
    verifyEqual(tests, eeg.history, {'Cut into 2 trials.', 'High-pass filtered above 0.5 Hz.', ...
        'Low-pass filtered below 40 Hz.', 'Removed line noise at 50, 100 and 150 Hz.', 'Resampled to 10 Hz.'});
    verifyEqual(tests, eeg.coordSystem, '');
    eeg = readFieldTrip(f, 'ConditionNames', {'', '', '', '', 'Five', '', 'Seven'});
    verifyEqual(tests, eeg.trials.condition, {'Five', 'Seven'});

    % timelock average (dimord chan_time)
    tl = struct('label', {{'a'; 'b'}}, 'avg', [1 2 3; 4 5 6] * 10, 'time', [-0.1 0 0.1], 'dimord', 'chan_time');
    save(fullfile(tmp, 'avg.mat'), 'tl');
    eeg = readFieldTrip(fullfile(tmp, 'avg.mat'));
    verifyEqual(tests, size(eeg.data), [2 3]);
    verifyEqual(tests, eeg.trials.condition, {'Average'});
    verifyEqual(tests, eeg.fs, 10, 'AbsTol', 1e-9, 'rate from the time axis');
    verifyEqual(tests, numel(eeg.notes), 1);

    % timelock with trials (dimord rpt_chan_time)
    x = reshape(1:12, 2, 2, 3) * 10;
    tt = struct('label', {{'a'; 'b'}}, 'trial', x, 'time', [0 0.1 0.2], 'dimord', 'rpt_chan_time', ...
        'trialinfo', [1; 2]);
    save(fullfile(tmp, 'tt.mat'), 'tt');
    eeg = readFieldTrip(fullfile(tmp, 'tt.mat'));
    verifyTrue(tests, eeg.isEpoched);
    verifyEqual(tests, eeg.data(:, :, 2), single(squeeze(x(2, :, :))));

    % Two FieldTrip variables: the first is used (with a note), or the one asked for
    erpA = tl; erpB = tl; erpB.avg = erpB.avg * 2; %#ok<NASGU>
    save(fullfile(tmp, 'two.mat'), 'erpA', 'erpB');
    eeg = readFieldTrip(fullfile(tmp, 'two.mat'));
    verifyEqual(tests, eeg.data, single(tl.avg));
    verifyNotEmpty(tests, strfind(eeg.notes{1}, 'erpA, erpB'));
    eeg = readFieldTrip(fullfile(tmp, 'two.mat'), 'Variable', 'erpB');
    verifyEqual(tests, eeg.data, single(tl.avg * 2));
    verifyError(tests, @() readFieldTrip(fullfile(tmp, 'two.mat'), 'Variable', 'nope'), 'NeuroAnalyzer:eeg:unknownVariable');

    % Errors
    data.trial{2} = [1 2; 3 4];
    data.time{2} = [0 0.1];
    save(fullfile(tmp, 'unequal.mat'), 'data');
    verifyError(tests, @() readFieldTrip(fullfile(tmp, 'unequal.mat')), 'NeuroAnalyzer:eeg:unequalTrials');
    verifyError(tests, @() readFieldTrip(tests.TestData.demo.scalp(1).matrix), 'NeuroAnalyzer:eeg:notFieldTrip');
end

%% ---------------------------------------------------- Matrix map and model

function testMatrixErrors(tests)
    tmp = fullfile(tests.TestData.tmp, 'mat');
    mkdir(tmp);
    f = tests.TestData.demo.scalp(1).matrix;
    base = struct('data', 'eeg', 'fs', 'srate', 'dims', {{'trial', 'channel', 'time'}});
    m = base; m.data = 'nope';
    verifyError(tests, @() readEEGMatrix(f, m), 'NeuroAnalyzer:eeg:unknownVariable');
    m = base; m.times = 'srate';
    verifyError(tests, @() readEEGMatrix(f, m), 'NeuroAnalyzer:eeg:sizeMismatch');
    m = base; m.labels = {'a', 'b'};
    verifyError(tests, @() readEEGMatrix(f, m), 'NeuroAnalyzer:eeg:sizeMismatch');
    m = base; m.dims = {'trial', 'channel', 'channel'};
    verifyError(tests, @() readEEGMatrix(f, m), 'NeuroAnalyzer:eeg:badOption');
    m = base; m.colour = 'red';
    verifyError(tests, @() readEEGMatrix(f, m), 'NeuroAnalyzer:eeg:badOption');
    % Unclear file: equal dimensions and no sampling rate -> ask for a map
    x = ones(10, 10, 10); %#ok<NASGU>
    save(fullfile(tmp, 'unclear.mat'), 'x');
    g = EEGSource.guessMatrixMap(fullfile(tmp, 'unclear.mat'));
    verifyTrue(tests, g.ambiguous);
    verifyError(tests, @() EEGSource.open(fullfile(tmp, 'unclear.mat')), 'NeuroAnalyzer:eeg:needsMap');
end

function testMakeValidateDescribe(tests)
    x = 1e-6 * ones(2, 3, 3);                          % volts
    eeg = EEGSource.make(x, 100, 'Times', [-0.01 0 0.01], 'Labels', {'Cz', 'Pz'}, ...
        'Conditions', {'A', 'B', 'A'});
    verifyEqual(tests, eeg.data, single(ones(2, 3, 3)), 'AbsTol', single(1e-6));
    verifyEqual(tests, eeg.conditions, {'A', 'B'});
    verifyTrue(tests, EEGSource.validate(eeg));
    lines = EEGSource.describe(eeg);
    verifyEqual(tests, lines{1}, '2 channels at 100 Hz, 3 trials from -0.01 to 0.01 s around the event.');
    verifyEqual(tests, lines{2}, 'Trials per condition: A (2) and B (1).');
    verifyEqual(tests, lines{3}, 'Reference: unknown.');
    verifyEqual(tests, lines{4}, 'The file has no electrode positions.');
    verifyNotEmpty(tests, strfind(lines{5}, 'volts'));
    eeg = EEGSource.make(ones(2, 3, 2) * 5, 100, 'Conditions', [1 2]);
    verifyEqual(tests, eeg.trials.condition, {'Code 1', 'Code 2'});
    verifyEqual(tests, eeg.labels, {'Ch 1', 'Ch 2'});
    verifyError(tests, @() EEGSource.make(ones(2, 3), 100, 'Labels', {'a'}), 'NeuroAnalyzer:eeg:invalid');
    verifyError(tests, @() EEGSource.make(ones(2, 3), -1), 'NeuroAnalyzer:eeg:invalid');
    verifyError(tests, @() EEGSource.make(ones(2, 3), 100, 'Unit', 'furlongs'), 'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() EEGSource.make(ones(2, 3), 100, 'Colour', 'red'), 'NeuroAnalyzer:eeg:badOption');
    bad = eeg;
    bad.times = [0 0.01];
    [ok, problems] = EEGSource.validate(bad);
    verifyFalse(tests, ok);
    verifyEqual(tests, problems, {'There are 2 time points for 3 samples.'});
end

function testHistoryIsReadNotRun(tests)
    verifyEqual(tests, EEGSource.parseValue('[1:3 7]'), [1 2 3 7]);
    verifyEqual(tests, EEGSource.parseValue('{  ''a''  ''b'' }'), {'a', 'b'});
    verifyEqual(tests, EEGSource.parseValue('''it''''s'''), 'it''s');
    verifyEqual(tests, EEGSource.parseValue('[]'), []);
    verifyEqual(tests, EEGSource.parseValue('delete(''x'')'), 'delete(''x'')', 'code stays text');
    marker = fullfile(tests.TestData.tmp, 'must_not_exist.txt');
    lines = EEGSource.eeglabHistory(sprintf('EEG = pop_resample(EEG, fclose(fopen(''%s'', ''w'')));', marker), {});
    verifyFalse(tests, exist(marker, 'file') == 2, 'nothing in the history is run');
    verifyEqual(tests, numel(lines), 1);
    [lines, info] = EEGSource.eeglabHistory({'EEG = pop_reref(EEG, {''TP9'' ''TP10''});', ...
        'EEG = pop_eegfiltnew(EEG, ''hicutoff'', 40);', 'EEG = pop_eegfiltnew(EEG, 49, 51, [], 1);'}, {});
    verifyEqual(tests, lines, {'Re-referenced to TP9 and TP10 (pop_reref).', ...
        'Low-pass filtered below 40 Hz (pop_eegfiltnew).', ...
        'Removed 49 to 51 Hz with a band-stop filter (pop_eegfiltnew).'});
    verifyEqual(tests, info.reference, 'TP9 and TP10');
end

%% ------------------------------------------------------------ BrainVision

function testBrainVisionDemo(tests)
    d = tests.TestData.demo;
    tr = d.truth.scalp;
    P = tr.participants(1);
    % Scalp: an Analyzer export of the segments
    eeg = readBrainVision(d.scalp(1).brainvision);
    verifyEqual(tests, eeg.data, P.data, 'float32 numbers exactly as written');
    verifyEqual(tests, eeg.fs, 250);
    verifyEqual(tests, eeg.times, tr.times, 'AbsTol', 1e-9, 'time 0 from the Time 0 marker');
    verifyEqual(tests, eeg.labels, tr.labels);
    verifyTrue(tests, eeg.isEpoched);
    verifyEqual(tests, eeg.trials.condition, P.condition, 'condition = marker at time 0');
    verifyEqual(tests, [[eeg.chanlocs.x]', [eeg.chanlocs.y]', [eeg.chanlocs.z]'], tr.posRAS, 'AbsTol', 1e-6);
    verifyEqual(tests, eeg.coordSystem, 'BrainVision (x = right ear, y = nose, z = up)');
    verifyEqual(tests, eeg.reference, 'unknown');
    verifyEqual(tests, eeg.history, {'Cut into 65 segments of -200 to 796 ms (BrainVision Analyzer segmentation).'});
    verifyEmpty(tests, eeg.notes);
    verifyEqual(tests, eeg.source, 'BrainVision');
    verifyEqual(tests, EEGSource.open(d.scalp(1).brainvision).data, eeg.data);

    % Rodent: a Recorder file, 16-bit integers of 0.1 uV
    r = d.truth.rodent;
    eeg = readBrainVision(d.rodent.brainvision);
    verifyFalse(tests, eeg.isEpoched);
    verifyEqual(tests, size(eeg.data), [4 60000]);
    verifyEqual(tests, double(eeg.data), double(r.data), 'AbsTol', 0.05 + 1e-4, 'rounded to 0.1 uV');
    verifyEqual(tests, eeg.labels, r.labels);
    verifyEqual(tests, numel(eeg.events), 30);
    verifyEqual(tests, [eeg.events.latency], r.onsets, 'AbsTol', 1e-9);
    verifyEqual(tests, unique({eeg.events.type}), {'S 1'}, '''S  1'' with the spaces collapsed');
    verifyEqual(tests, eeg.reference, 'channel Cb');
    verifyEqual(tests, eeg.coordSystem, '');
    verifyEqual(tests, eeg.notes, { ...
        'When recorded, the amplifier filtered from 0.0159 Hz (time constant 10 s), up to 250 Hz, no notch filter.', ...
        'No software filter was applied while recording.'});
    verifyEmpty(tests, eeg.history);
    % The VEP is there after cutting trials around the flashes
    ep = EEGAnalysis.epoch(eeg, 'Window', [-0.1 0.4]);
    erp = EEGAnalysis.conditionERPs(ep, 'Baseline', [-0.1 0]);
    m = EEGAnalysis.measure(erp, 'Channels', {'V1-L', 'V1-R'}, 'Window', [0.03 0.07], ...
        'Measure', 'peak', 'Polarity', 'negative');
    verifyLessThan(tests, m.value, -25);
    verifyEqual(tests, m.condition, 'S 1');
end

function testBrainVisionRecorderHandBuilt(tests)
    % A Recorder header as written by BrainVision Recorder 1.2x: Latin-1
    % micro sign, empty reference fields, INT_16 multiplexed, resolutions
    % per channel, a channel in mV, a comma in a name (\1), the data file
    % named with a Windows path, markers with 'S  1' / 'R  2', a comment, a
    % bad interval and a second New Segment (a paused recording). The data
    % file ends in the middle of a sample.
    tmp = fullfile(tests.TestData.tmp, 'bvrec');
    mkdir(tmp);
    mu = char(181);
    hdr = {'Brain Vision Data Exchange Header File Version 1.0', ...
        '; Data created by the Vision Recorder', '', '[Common Infos]', ...
        'Codepage=UTF-8', 'DataFile=C:\Vision\Raw Files\rec.eeg', 'MarkerFile=rec.vmrk', ...
        'DataFormat=BINARY', '; Data orientation: MULTIPLEXED=ch1,pt1, ch2,pt1 ...', ...
        'DataOrientation=MULTIPLEXED', 'NumberOfChannels=3', '; Sampling interval in microseconds', ...
        'SamplingInterval=2000', '', '[Binary Infos]', 'BinaryFormat=INT_16', '', '[Channel Infos]', ...
        '; Each entry: Ch<Channel number>=<Name>,<Reference channel name>,', ...
        ['Ch1=Fp1,,0.1,' mu 'V'], ['Ch2=A\1B,,0.5,' mu 'V'], 'Ch3=EOG,,0.001,mV', '', ...
        '[Comment]', '', 'A m p l i f i e r  S e t u p', '============================', ...
        '#     Name      Phys. Chn.    Resolution / Unit   Low Cutoff [s]   High Cutoff [Hz]   Notch [Hz]', ...
        ['1     Fp1         1                0.1 ' mu 'V             DC              1000              50'], ...
        ['2     A,B         2                0.5 ' mu 'V             DC              1000              50'], ...
        '3     EOG         3                0.001 mV           DC              1000              50', '', ...
        'S o f t w a r e  F i l t e r s', '==============================', ...
        '#     Low Cutoff [s]   High Cutoff [Hz]   Notch [Hz]', ...
        '1     0.1592              70                 Off', '2     0.1592              70                 Off', ...
        '3     0.1592              70                 Off'};
    writeLatin1(fullfile(tmp, 'rec.vhdr'), hdr);
    mrk = {'Brain Vision Data Exchange Marker File, Version 1.0', '', '[Common Infos]', 'DataFile=rec.eeg', '', ...
        '[Marker Infos]', '; Each entry: Mk<Marker number>=<Type>,<Description>,<Position in data points>,', ...
        'Mk1=New Segment,,1,1,0,20260926101500000000', 'Mk2=Stimulus,S  1,11,1,0', 'Mk3=Response,R  2,26,1,0', ...
        'Mk4=Comment,eyes closed,30,1,0', 'Mk5=Bad Interval,,31,5,0', 'Mk6=New Segment,,41,1,0', ...
        'Mk7=Stimulus,S  1,51,1,0'};
    writeLatin1(fullfile(tmp, 'rec.vmrk'), mrk);
    raw = int16(reshape(1:180, 3, 60));
    fid = fopen(fullfile(tmp, 'rec.eeg'), 'w', 'ieee-le');
    fwrite(fid, [raw(:); 7], 'int16');                   % one number too many
    fclose(fid);

    eeg = EEGSource.open(fullfile(tmp, 'rec.vhdr'));
    verifyEqual(tests, eeg.fs, 500);
    verifyEqual(tests, size(eeg.data), [3 60]);
    verifyEqual(tests, eeg.labels, {'Fp1', 'A,B', 'EOG'});
    verifyEqual(tests, double(eeg.data(1, 1:3)), [1 4 7] * 0.1, 'AbsTol', 1e-5, 'resolution 0.1 uV');
    verifyEqual(tests, double(eeg.data(2, 1:3)), [2 5 8] * 0.5, 'AbsTol', 1e-5, 'resolution 0.5 uV');
    verifyEqual(tests, double(eeg.data(3, 1:3)), [3 6 9], 'AbsTol', 1e-4, '0.001 mV = 1 uV');
    verifyEqual(tests, {eeg.events.type}, {'S 1', 'R 2', 'S 1'}, 'stimuli and responses; no comment, no bad interval');
    verifyEqual(tests, [eeg.events.latency], [10 25 50] / 500, 'AbsTol', 1e-12);
    verifyEqual(tests, eeg.reference, 'unknown');
    verifyEqual(tests, eeg.coordSystem, '');
    verifyEqual(tests, eeg.history, {'Filtered while recording (Recorder software filter): from 1 Hz (time constant 0.1592 s), up to 70 Hz, no notch filter.'});
    notes = strjoin(eeg.notes, ' | ');
    verifyTrue(tests, contains(notes, 'ended in the middle of a sample'), notes);
    verifyTrue(tests, contains(notes, 'converted to'), notes);
    verifyTrue(tests, contains(notes, 'paused or restarted 1 time(s)'), notes);
    verifyTrue(tests, contains(notes, '1 bad interval(s)'), notes);
    verifyTrue(tests, contains(notes, '1 comment marker(s)'), notes);
    verifyTrue(tests, contains(notes, 'from DC (no high-pass), up to 1000 Hz, notch at 50 Hz'), notes);

    % Errors: missing data file, not a header, frequency data
    delete(fullfile(tmp, 'rec.eeg'));
    verifyError(tests, @() readBrainVision(fullfile(tmp, 'rec.vhdr')), 'NeuroAnalyzer:io:fileNotFound');
    writeLatin1(fullfile(tmp, 'bad.vhdr'), {'Some other file', '[Common Infos]', 'NumberOfChannels=1'});
    verifyError(tests, @() readBrainVision(fullfile(tmp, 'bad.vhdr')), 'NeuroAnalyzer:eeg:notBrainVision');
    fq = strrep(hdr, 'DataFormat=BINARY', 'DataType=FREQUENCYDOMAIN');
    writeLatin1(fullfile(tmp, 'fq.vhdr'), fq);
    verifyError(tests, @() readBrainVision(fullfile(tmp, 'fq.vhdr')), 'NeuroAnalyzer:eeg:unsupported');
    verifyError(tests, @() readBrainVision(fullfile(tmp, 'none.vhdr')), 'NeuroAnalyzer:io:fileNotFound');
end

function testBrainVisionAnalyzerHandBuilt(tests)
    % Analyzer exports: (1) big-endian float32 segments cut at fixed times,
    % no Time 0 marker, averaged, positions on a unit sphere; (2) ASCII,
    % vectorized, decimal comma, a header line and channel names in the
    % first column (SkipLines / SkipColumns).
    tmp = fullfile(tests.TestData.tmp, 'bvana');
    mkdir(tmp);
    hdr = {'BrainVision Data Exchange Header File Version 2.0', '', '[Common Infos]', 'Codepage=UTF-8', ...
        'DataFile=avg.dat', 'MarkerFile=avg.vmrk', 'DataFormat=BINARY', 'DataOrientation=MULTIPLEXED', ...
        'DataType=TIMEDOMAIN', 'NumberOfChannels=2', 'SamplingInterval=4000', 'SegmentationType=FIXTIME', ...
        'SegmentDataPoints=4', 'Averaged=YES', 'AveragedSegments=40', '', '[Binary Infos]', ...
        'BinaryFormat=IEEE_FLOAT_32', 'UseBigEndianOrder=YES', '', '[Channel Infos]', ...
        'Ch1=Cz,Ref,1,µV', 'Ch2=Oz,Ref,1,µV', '', '[Coordinates]', 'Ch1=1,0,0', 'Ch2=1,90,-90'};
    writeUtf8(fullfile(tmp, 'avg.vhdr'), hdr);
    writeUtf8(fullfile(tmp, 'avg.vmrk'), {'BrainVision Data Exchange Marker File Version 2.0', '', ...
        '[Marker Infos]', 'Mk1=New Segment,,1,1,0', 'Mk2=New Segment,,5,1,0'});
    vals = single(reshape(1:16, 2, 8)) / 4;
    fid = fopen(fullfile(tmp, 'avg.dat'), 'w', 'ieee-be');
    fwrite(fid, vals, 'float32');
    fclose(fid);
    eeg = readBrainVision(fullfile(tmp, 'avg.vhdr'));
    verifyEqual(tests, size(eeg.data), [2 4 2]);
    verifyEqual(tests, eeg.data(:, :, 2), vals(:, 5:8), 'big-endian float32, second segment');
    verifyEqual(tests, eeg.times, (0:3) / 250, 'AbsTol', 1e-12, 'no Time 0: segments start at 0 s');
    verifyEqual(tests, eeg.trials.condition, {'All trials', 'All trials'});
    verifyEqual(tests, eeg.reference, 'channel Ref');
    verifyEqual(tests, [eeg.chanlocs.z], [1 0], 'AbsTol', 1e-12);
    verifyEqual(tests, [eeg.chanlocs.y], [0 -1], 'AbsTol', 1e-12);
    verifyEqual(tests, eeg.coordSystem, 'BrainVision (x = right ear, y = nose, z = up); on a unit sphere');
    notes = strjoin(eeg.notes, ' | ');
    verifyTrue(tests, contains(notes, 'no Time 0 marker'), notes);
    verifyTrue(tests, contains(notes, 'averages of 40 segments'), notes);

    % ASCII export
    hdr = {'Brain Vision Data Exchange Header File Version 1.0', '[Common Infos]', 'DataFile=txt.dat', ...
        'DataFormat=ASCII', 'DataOrientation=VECTORIZED', 'NumberOfChannels=2', 'SamplingInterval=1000', '', ...
        '[ASCII Infos]', 'DecimalSymbol=,', 'SkipLines=1', 'SkipColumns=1', '', '[Channel Infos]', ...
        'Ch1=C3,,1,uV', 'Ch2=C4,,1,uV'};
    writeLatin1(fullfile(tmp, 'txt.vhdr'), hdr);
    writeLatin1(fullfile(tmp, 'txt.dat'), {'Channel  values', 'C3 1,5 -2,25 3', 'C4 4 5,5 -6,75'});
    eeg = readBrainVision(fullfile(tmp, 'txt.vhdr'));
    verifyEqual(tests, double(eeg.data), [1.5 -2.25 3; 4 5.5 -6.75], 'AbsTol', 1e-6);
    verifyEqual(tests, eeg.fs, 1000);
    verifyFalse(tests, eeg.isEpoched);
    verifyTrue(tests, contains(strjoin(eeg.notes, ' '), 'no marker file'));
end

function testBrainVisionWriterRoundTrip(tests)
    % Our writer against our reader for the options the demo does not use
    tmp = fullfile(tests.TestData.tmp, 'bvrt');
    mkdir(tmp);
    x = single(round(randn(RandStream('mt19937ar', 'Seed', 5), 3, 100) * 100) / 10);
    P = [0 1 0; -cosd(72) sind(72) 0; 0 0 1];           % Fpz, Fp1, Cz (x right, y nose, z up)
    eeg = EEGSource.make(x, 200, 'Labels', {'Fpz', 'Fp1', 'Cz'}, 'Unit', 'uV', 'IsEpoched', false, ...
        'Events', struct('type', {'go, left', 'stop'}, 'latency', {0.1, 0.3}, 'duration', {0, 0.05}));
    out = writeBrainVision(fullfile(tmp, 'rt.vhdr'), eeg, 'BinaryFormat', 'INT_32', 'Resolution', 0.1, ...
        'Orientation', 'VECTORIZED', 'Positions', P, 'Version', 2, 'Reference', 'TP9');
    txt = fileread(out.vhdr);
    verifyTrue(tests, contains(txt, 'Ch2=1,-90,-72'), 'Fp1 as BrainVision writes it');
    verifyTrue(tests, contains(txt, 'Ch3=1,0,0'));
    r = readBrainVision(out.vhdr);
    verifyEqual(tests, double(r.data), double(x), 'AbsTol', 1e-4);
    verifyEqual(tests, {r.events.type}, {'go, left', 'stop'}, 'a comma in a description (\1)');
    verifyEqual(tests, [r.events.duration], [0 0.05], 'AbsTol', 1e-12);
    verifyEqual(tests, [[r.chanlocs.x]', [r.chanlocs.y]', [r.chanlocs.z]'], P ./ vecnorm(P, 2, 2), 'AbsTol', 1e-3);
    verifyEqual(tests, r.reference, 'channel TP9');
    verifyError(tests, @() writeBrainVision(fullfile(tmp, 'big.vhdr'), ...
        EEGSource.make(single([1e5 0]), 100, 'Unit', 'uV', 'IsEpoched', false), 'BinaryFormat', 'INT_16'), ...
        'NeuroAnalyzer:eeg:badOption');
end

%% --------------------------------------------------------------- helpers

function writeLatin1(p, lines)
    fid = fopen(p, 'w');
    fwrite(fid, uint8(double([strjoin(lines, sprintf('\r\n')) sprintf('\r\n')])), 'uint8');
    fclose(fid);
end

function writeUtf8(p, lines)
    fid = fopen(p, 'w');
    fwrite(fid, unicode2native([strjoin(lines, sprintf('\r\n')) sprintf('\r\n')], 'UTF-8'), 'uint8');
    fclose(fid);
end

function lines = eeglabHistoryLines(rej)
    lines = { ...
        'Band-pass filtered 0.1 to 30 Hz (pop_eegfiltnew).', ...
        'Re-referenced to the average of all channels (pop_reref).', ...
        'Computed ICA with runica (pop_runica).', ...
        'Removed ICA components 1 and 3 (pop_subcomp).', ...
        'Cut into trials from -0.2 to 0.8 s around the events Standard, Target and Novel (pop_epoch).', ...
        'Removed the baseline, the mean from -200 to 0 ms (pop_rmbase).', ...
        sprintf('Rejected %d trials (pop_rejepoch).', numel(rej)), ...
        'Interpolated channel T7 using spherical splines (pop_interp).'};
end
