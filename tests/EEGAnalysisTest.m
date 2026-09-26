%% EEGAnalysisTest.m
% =========================================================================
% UNIT TESTS FOR THE HEADLESS EEG ANALYSIS (core/EEGAnalysis.m)
% =========================================================================
% Exact numbers on a small hand-built EEG (baseline, mean, SEM, difference,
% mean and peak measures, edge peaks), then the known answers of the
% synthetic study of core/demo/demoEEG: P300 Target > Novel > Standard at
% Pz, N1 negative at Cz near 100 ms, one table row per participant and
% condition, and cutting the continuous rodent recording into trials
% around its light flashes (visual evoked potential over V1). Plain
% errors for unknown channels and conditions, bad windows and data that
% are not cut into trials yet.
% =========================================================================

function tests = EEGAnalysisTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'io'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.tmp = fullfile(tempdir, ['NeuroAnalyzerEEGAnalysisTest_' char(java.util.UUID.randomUUID)]);
    mkdir(tests.TestData.tmp);
    tests.TestData.demo = demoEEG(fullfile(tests.TestData.tmp, 'demo'), 'Participants', 3);
end

function teardownOnce(tests)
    if exist(tests.TestData.tmp, 'dir') == 7, rmdir(tests.TestData.tmp, 's'); end
end

%% --------------------------------------------------- Hand-built, exact numbers

function testConditionERPsExact(tests)
    eeg = tinyEEG();
    erp = EEGAnalysis.conditionERPs(eeg);
    verifyEqual(tests, erp.conditions, {'A', 'B'});
    verifyEqual(tests, erp.n, [2 2]);
    verifyEqual(tests, erp.labels, {'Fz', 'Cz'});
    verifyEqual(tests, erp.fs, 10);
    verifyEmpty(tests, erp.baseline);
    shape = [0 0 3 6 3];
    verifyEqual(tests, erp.mean(:, :, 1), 2 + [1; 2] * shape, 'AbsTol', 1e-12, 'A: trials 1 and 3');
    verifyEqual(tests, erp.mean(:, :, 2), 3 + [1; 2] * shape, 'AbsTol', 1e-12, 'B: trials 2 and 4');
    verifyEqual(tests, erp.sem, ones(2, 5, 2), 'AbsTol', 1e-12, 'std sqrt(2) over 2 trials');

    erp = EEGAnalysis.conditionERPs(eeg, 'Baseline', [-0.2 0]);
    verifyEqual(tests, erp.baseline, [-0.2 0]);
    after = [1; 2] * [-1 -1 2 5 2];
    verifyEqual(tests, erp.mean(:, :, 1), after, 'AbsTol', 1e-12, 'baseline mean removed per trial');
    verifyEqual(tests, erp.mean(:, :, 2), after, 'AbsTol', 1e-12);
    verifyEqual(tests, erp.sem, zeros(2, 5, 2), 'AbsTol', 1e-12, 'offsets gone with the baseline');

    erp = EEGAnalysis.conditionERPs(eeg, 'Conditions', {'B'});
    verifyEqual(tests, erp.conditions, {'B'});
    verifyEqual(tests, size(erp.mean), [2 5]);

    one = EEGSource.make(ones(2, 5, 3), 10, 'Times', (-2:2) / 10, 'Labels', {'Fz', 'Cz'}, ...
        'Conditions', {'A', 'B', 'B'}, 'IsEpoched', true, 'Unit', 'uV');
    erp = EEGAnalysis.conditionERPs(one);
    sem1 = erp.sem(:, :, 1);
    verifyTrue(tests, all(isnan(sem1(:))), 'no SEM from a single trial');
end

function testDifferenceExact(tests)
    erp = EEGAnalysis.conditionERPs(tinyEEG());
    d = EEGAnalysis.difference(erp, 'A', 'B');
    verifyEqual(tests, d.label, 'A minus B');
    verifyEqual(tests, d.mean, -ones(2, 5), 'AbsTol', 1e-12);
    verifyEqual(tests, d.times, erp.times);
    verifyEqual(tests, d.labels, {'Fz', 'Cz'});
    d = EEGAnalysis.difference(erp, 'B', 'A');
    verifyEqual(tests, d.label, 'B minus A');
    verifyEqual(tests, d.mean, ones(2, 5), 'AbsTol', 1e-12);
end

function testMeasureExact(tests)
    erp = EEGAnalysis.conditionERPs(tinyEEG(), 'Baseline', [-0.2 0]);
    % after the baseline, Cz is 2 * [-1 -1 2 5 2] at -0.2 ... 0.2 s
    r = EEGAnalysis.measure(erp, 'Channels', {'cz'}, 'Window', [0.1 0.2]);
    verifyEqual(tests, {r.condition}, {'A', 'B'});
    verifyEqual(tests, [r.value], [7 7], 'AbsTol', 1e-12, 'mean of 10 and 4');
    verifyTrue(tests, all(isnan([r.latency])), 'no latency for a mean');
    verifyFalse(tests, any([r.atEdge]));
    verifyEqual(tests, [r.n], [2 2]);

    r = EEGAnalysis.measure(erp, 'Window', [0.1 0.2]);
    verifyEqual(tests, r(1).value, 1.5 * 3.5, 'AbsTol', 1e-12, 'averaged over both channels');

    r = EEGAnalysis.measure(erp, 'Channels', 'Cz', 'Window', [0 0.2], 'Measure', 'peak');
    verifyEqual(tests, r(1).value, 10, 'AbsTol', 1e-12);
    verifyEqual(tests, r(1).latency, 0.1, 'AbsTol', 1e-9);
    verifyFalse(tests, r(1).atEdge, 'a real peak inside the window');

    r = EEGAnalysis.measure(erp, 'Channels', 'Cz', 'Window', [0.1 0.2], 'Measure', 'peak');
    verifyEqual(tests, r(1).latency, 0.1, 'AbsTol', 1e-9);
    verifyTrue(tests, r(1).atEdge, 'largest value on the first sample of the window');

    r = EEGAnalysis.measure(erp, 'Channels', 'Cz', 'Window', [-0.2 0.2], 'Measure', 'peak', ...
        'Polarity', 'negative');
    verifyEqual(tests, r(1).value, -2, 'AbsTol', 1e-12);
    verifyEqual(tests, r(1).latency, -0.2, 'AbsTol', 1e-9);
    verifyTrue(tests, r(1).atEdge);

    r = EEGAnalysis.measure(erp, 'Channels', 'Cz', 'Window', [0.1 0.1], 'Measure', 'peak');
    verifyFalse(tests, r(1).atEdge, 'a one-sample window has no edge to worry about');
end

function testDescribeMeasure(tests)
    s = EEGAnalysis.describeMeasure(struct('Window', [0.3 0.4], 'Channels', {{'Pz'}}, 'Measure', 'mean'));
    verifyEqual(tests, s, 'Mean amplitude from 300 to 400 ms, at Pz.');
    s = EEGAnalysis.describeMeasure(struct('Window', [0.05 0.15], 'Channels', {{'Cz', 'FCz', 'C1'}}, ...
        'Measure', 'peak', 'Polarity', 'Negative'));
    verifyEqual(tests, s, ['Largest negative value (peak amplitude and its latency) from 50 to 150 ms, ' ...
        'averaged over Cz, FCz and C1.']);
    s = EEGAnalysis.describeMeasure(struct('Window', [0.3 0.4], 'Measure', 'mean'));
    verifyEqual(tests, s, 'Mean amplitude from 300 to 400 ms, averaged over all channels.');
end

function testChannelIndex(tests)
    labels = {'Fz', 'Cz', 'Pz'};
    verifyEqual(tests, EEGAnalysis.channelIndex(labels, {'pz', 'FZ'}), [3 1]);
    verifyEqual(tests, EEGAnalysis.channelIndex(labels, 'Cz'), 2);
    verifyError(tests, @() EEGAnalysis.channelIndex(labels, {'Cz', 'Oz', 'T7'}), ...
        'NeuroAnalyzer:eeg:unknownChannel');
    try
        EEGAnalysis.channelIndex(labels, {'Cz', 'Oz', 'T7'});
    catch e
        verifyEqual(tests, e.message, 'Unknown channels Oz and T7.', 'names only the unknown ones');
    end
end

%% ------------------------------------------------------------- Demo answers

function testDemoP300Order(tests)
    d = tests.TestData.demo;
    for p = 1:numel(d.scalp)
        eeg = readEEGLAB(d.scalp(p).eeglab);
        erp = EEGAnalysis.conditionERPs(eeg, 'Baseline', [-0.2 0]);
        verifyEqual(tests, sort(erp.conditions), {'Novel', 'Standard', 'Target'});
        verifyEqual(tests, sum(erp.n), 65, '70 trials minus 5 rejected');
        verifyEqual(tests, size(erp.mean), [32 250 3]);
        r = EEGAnalysis.measure(erp, 'Channels', {'Pz'}, 'Window', [0.3 0.4]);
        v = @(c) r(strcmp({r.condition}, c)).value;
        tag = sprintf('participant %d', p);
        verifyGreaterThan(tests, v('Target'), v('Novel'), ['P300: Target > Novel, ' tag]);
        verifyGreaterThan(tests, v('Novel'), v('Standard'), ['P300: Novel > Standard, ' tag]);
        dw = EEGAnalysis.difference(erp, 'Target', 'Standard');
        verifyEqual(tests, dw.label, 'Target minus Standard');
        pz = strcmp(dw.labels, 'Pz');
        [~, i] = max(dw.mean(pz, :));
        verifyEqual(tests, dw.times(i), 0.35 + d.truth.scalp.participants(p).latShift, 'AbsTol', 0.03, ...
            ['difference wave peaks at the P300, ' tag]);
    end
end

function testDemoN1Peak(tests)
    d = tests.TestData.demo;
    for p = 1:numel(d.scalp)
        eeg = readEEGLAB(d.scalp(p).eeglab);
        erp = EEGAnalysis.conditionERPs(eeg, 'Baseline', [-0.2 0]);
        r = EEGAnalysis.measure(erp, 'Channels', 'Cz', 'Window', [0.05 0.15], 'Measure', 'peak', ...
            'Polarity', 'negative');
        tag = sprintf('participant %d', p);
        for c = 1:numel(r)
            verifyLessThan(tests, r(c).value, -2, ['N1 negative at Cz, ' tag]);
            verifyEqual(tests, r(c).latency, 0.1 + d.truth.scalp.participants(p).latShift, ...
                'AbsTol', 0.02, ['N1 latency, ' tag]);
            verifyFalse(tests, r(c).atEdge, ['N1 is a real peak, ' tag]);
        end
    end
end

function testMeasureTable(tests)
    d = tests.TestData.demo;
    n = numel(d.scalp);
    eegs = arrayfun(@(s) readEEGLAB(s.eeglab), d.scalp, 'UniformOutput', false);
    names = arrayfun(@(p) sprintf('sub-%02d', p), 1:n, 'UniformOutput', false);
    T = EEGAnalysis.measureTable(eegs, names, 'Baseline', [-0.2 0], 'Channels', {'Pz'}, ...
        'Window', [0.3 0.4]);
    verifyClass(tests, T, 'table');
    verifyEqual(tests, T.Properties.VariableNames, {'Participant', 'Condition', 'Value', 'Latency', ...
        'Trials', 'AtEdge'});
    verifyEqual(tests, height(T), 3 * n, 'one row per participant and condition');
    for p = 1:n
        rows = T(strcmp(T.Participant, names{p}), :);
        verifyEqual(tests, height(rows), 3);
        erp = EEGAnalysis.conditionERPs(eegs{p}, 'Baseline', [-0.2 0]);
        r = EEGAnalysis.measure(erp, 'Channels', {'Pz'}, 'Window', [0.3 0.4]);
        verifyEqual(tests, rows.Condition, {r.condition}', 'same order as the window');
        verifyEqual(tests, rows.Value, [r.value]', 'AbsTol', 1e-12, 'same numbers as measure');
        verifyEqual(tests, sum(rows.Trials), 65);
        v = @(c) rows.Value(strcmp(rows.Condition, c));
        verifyGreaterThan(tests, v('Target'), v('Standard'));
    end
    verifyTrue(tests, all(isnan(T.Latency)));
    T = EEGAnalysis.measureTable(eegs(1), names(1), 'Conditions', {'Target'}, 'Channels', 'Cz', ...
        'Window', [0.05 0.15], 'Measure', 'peak', 'Polarity', 'negative');
    verifyEqual(tests, height(T), 1);
    verifyEqual(tests, T.Condition, {'Target'});
    verifyLessThan(tests, T.Value, 0);
    verifyEqual(tests, T.Latency, 0.1, 'AbsTol', 0.03);
end

%% ------------------------------------------------------------- Epoching

function testEpochRodent(tests)
    d = tests.TestData.demo;
    raw = readEEGLAB(d.rodent.eeglab);
    ep = EEGAnalysis.epoch(raw, 'Window', [-0.1 0.4]);
    verifyTrue(tests, ep.isEpoched);
    verifyEqual(tests, size(ep.data), [4 501 30], '30 flashes, -0.1 to 0.4 s at 1000 Hz');
    verifyEqual(tests, ep.times([1 end]), [-0.1 0.4], 'AbsTol', 1e-9);
    verifyEqual(tests, ep.conditions, {'flash'});
    verifyEqual(tests, ep.labels, raw.labels);
    verifyEqual(tests, ep.fs, 1000);
    verifyEqual(tests, ep.reference, 'cerebellar screw');
    verifyEqual(tests, ep.history(1:end-1), raw.history, 'the earlier steps are kept');
    verifyEqual(tests, ep.history{end}, ...
        'Cut into 30 trials from -0.1 to 0.4 s around the events flash (NeuroAnalyzer).');
    verifyEqual(tests, ep.notes, raw.notes, 'nothing skipped, nothing to note');
    % trial 1 is the recording around the first flash (1 s = sample 1001)
    verifyEqual(tests, ep.data(:, :, 1), raw.data(:, 1001 + (-100:400)));

    erp = EEGAnalysis.conditionERPs(ep, 'Baseline', [-0.1 0]);
    r = EEGAnalysis.measure(erp, 'Channels', {'V1-L', 'V1-R'}, 'Window', [0.03 0.07], ...
        'Measure', 'peak', 'Polarity', 'negative');
    verifyLessThan(tests, r.value, -25, 'VEP negative peak over V1');
    verifyEqual(tests, r.latency, 0.05, 'AbsTol', 0.006, 'VEP latency');
    verifyEqual(tests, r.n, 30);

    ep = EEGAnalysis.epoch(raw, 'Window', [-2 0.4]);
    verifyEqual(tests, size(ep.data, 3), 29, 'the flash at 1 s has no 2 s before it');
    verifyEqual(tests, ep.notes{end}, ['1 event was too close to the start or end of the recording ' ...
        'for this window and left out.']);

    ep = EEGAnalysis.epoch(raw, 'Window', [-0.1 0.4], 'Events', {'flash'});
    verifyEqual(tests, size(ep.data, 3), 30);
end

%% ----------------------------------------------------------------- Errors

function testErrors(tests)
    eeg = tinyEEG();
    erp = EEGAnalysis.conditionERPs(eeg);
    raw = readEEGLAB(tests.TestData.demo.rodent.eeglab);

    verifyError(tests, @() EEGAnalysis.conditionERPs(raw), 'NeuroAnalyzer:eeg:notEpoched');
    verifyError(tests, @() EEGAnalysis.conditionERPs(eeg, 'Conditions', {'A', 'C'}), ...
        'NeuroAnalyzer:eeg:unknownCondition');
    verifyError(tests, @() EEGAnalysis.conditionERPs(eeg, 'Baseline', [1 2]), 'NeuroAnalyzer:eeg:badWindow');
    verifyError(tests, @() EEGAnalysis.conditionERPs(eeg, 'Baseline', [0 -0.1]), 'NeuroAnalyzer:eeg:badWindow');
    verifyError(tests, @() EEGAnalysis.difference(erp, 'A', 'C'), 'NeuroAnalyzer:eeg:unknownCondition');

    verifyError(tests, @() EEGAnalysis.measure(erp), 'NeuroAnalyzer:eeg:badWindow');
    verifyError(tests, @() EEGAnalysis.measure(erp, 'Window', [0.5 0.6]), 'NeuroAnalyzer:eeg:badWindow');
    verifyError(tests, @() EEGAnalysis.measure(erp, 'Window', [0 0.1], 'Channels', 'Oz'), ...
        'NeuroAnalyzer:eeg:unknownChannel');
    verifyError(tests, @() EEGAnalysis.measure(erp, 'Window', [0 0.1], 'Measure', 'area'), ...
        'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() EEGAnalysis.measure(erp, 'Window', [0 0.1], 'Measure', 'peak', ...
        'Polarity', 'up'), 'NeuroAnalyzer:eeg:badOption');

    verifyError(tests, @() EEGAnalysis.epoch(eeg), 'NeuroAnalyzer:eeg:badOption', 'already in trials');
    noEvents = EEGSource.make(zeros(2, 100), 100, 'IsEpoched', false, 'Unit', 'uV');
    verifyError(tests, @() EEGAnalysis.epoch(noEvents), 'NeuroAnalyzer:eeg:notEpoched');
    verifyError(tests, @() EEGAnalysis.epoch(raw, 'Window', [0.4 -0.1]), 'NeuroAnalyzer:eeg:badWindow');
    verifyError(tests, @() EEGAnalysis.epoch(raw, 'Window', [-70 0]), 'NeuroAnalyzer:eeg:badWindow');
    verifyError(tests, @() EEGAnalysis.epoch(raw, 'Events', {'tone'}), 'NeuroAnalyzer:eeg:unknownCondition');
end

%% ---------------------------------------------------------------- Helpers

%% tinyEEG - 2 channels x 5 samples x 4 trials with known averages
% Trial k, channel c: k + c * [0 0 3 6 3] at -0.2 ... 0.2 s; conditions
% A B A B. Baseline [-0.2 0] leaves c * [-1 -1 2 5 2] in every trial.
function eeg = tinyEEG()
    x = zeros(2, 5, 4);
    for k = 1:4
        x(:, :, k) = k + [1; 2] * [0 0 3 6 3];
    end
    eeg = EEGSource.make(x, 10, 'Times', (-2:2) / 10, 'Labels', {'Fz', 'Cz'}, ...
        'Conditions', {'A', 'B', 'A', 'B'}, 'IsEpoched', true, 'Unit', 'uV');
end
