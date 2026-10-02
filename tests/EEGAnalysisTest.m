%% EEGAnalysisTest.m
% =========================================================================
% UNIT TESTS FOR THE HEADLESS EEG ANALYSIS (core/EEGAnalysis.m)
% =========================================================================
% Exact numbers on a small hand-built EEG (baseline, mean, SEM, difference,
% mean and peak measures, edge peaks), then the known answers of the
% synthetic study of core/demo/demoEEG: P300 Target > Novel > Standard at
% Pz, N1 negative at Cz near 100 ms, one table row per participant and
% condition, and cutting the continuous rodent recording into trials
% around its light flashes (visual evoked potential over V1). Cleaning
% raw recordings: filter designs and taps as MNE-Python, drift and line
% noise removed, exact re-references, bad channels (suggested, left out
% of the reference, rejection, ERPs and measures), event names and gaps,
% exact trial rejection, and the raw demo (T7 suggested, exactly the blink
% trials rejected, N1 at Cz against FCz and the average). Time-frequency
% per condition: the same ERSP / ITPC as TimeFrequency.ersp on the
% continuous recording where the wavelet fits, exact known answers (an
% amplitude halved: -6.02 dB and -75% band power; phase-locked trials: ITPC
% 1), blank edges, the grand average, and the demo's alpha decrease after
% Target. Plain errors for unknown channels and conditions, bad windows and
% data that are not cut into trials yet.
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

function testGrandAverageExact(tests)
    a = EEGAnalysis.conditionERPs(tinyEEG());
    x = 10 * ones(2, 5, 3);
    b = EEGAnalysis.conditionERPs(EEGSource.make(x, 10, 'Times', (-2:2) / 10, 'Labels', {'Fz', 'Cz'}, ...
        'Conditions', {'B', 'C', 'B'}, 'IsEpoched', true, 'Unit', 'uV'));
    ga = EEGAnalysis.grandAverage({a, b});
    verifyEqual(tests, ga.conditions, {'B'}, 'only the conditions every participant has');
    verifyEqual(tests, ga.n, 2, 'participants');
    verifyEqual(tests, ga.trials, 4, 'trials in total (2 + 2)');
    shape = [0 0 3 6 3];
    B1 = 3 + [1; 2] * shape;
    verifyEqual(tests, ga.mean, (B1 + 10) / 2, 'AbsTol', 1e-12, 'each participant counts once');
    verifyEqual(tests, ga.sem, abs(B1 - 10) / 2, 'AbsTol', 1e-12, 'SD over 2 participants / sqrt(2)');
    verifyEqual(tests, ga.notes, {'Left out of the grand average: A and C (not recorded in every participant).'});

    one = EEGAnalysis.grandAverage({a});
    verifyEqual(tests, one.mean, a.mean);
    verifyEqual(tests, one.trials, a.n);
    verifyEmpty(tests, one.notes);

    c = a; c.labels = {'Fz', 'Pz'};
    verifyError(tests, @() EEGAnalysis.grandAverage({a, c}), 'NeuroAnalyzer:eeg:mismatch');
    c = a; c.times = c.times + 0.1;
    verifyError(tests, @() EEGAnalysis.grandAverage({a, c}), 'NeuroAnalyzer:eeg:mismatch');
    c = a; c.conditions = {'X', 'Y'};
    verifyError(tests, @() EEGAnalysis.grandAverage({a, c}), 'NeuroAnalyzer:eeg:unknownCondition');
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
        'Cut into 30 trials from -0.1 to 0.4 s around the events flash (Neuronal Data Analyzer Lab).');
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

%% --------------------------------------------------- Cleaning raw recordings

function testFilterDesignMatchesMNE(tests)
    % Lengths, edges and taps as MNE-Python 1.13 create_filter(..., fir_design='firwin')
    d = EEGAnalysis.filterDesign(500, 'HighPass', 0.1, 'LowPass', 30);
    verifyEqual(tests, d.kind, 'band-pass');
    verifyEqual(tests, d.length, 16501);
    verifyEqual(tests, [d.highTransition d.lowTransition], [0.1 7.5], 'AbsTol', 1e-12);
    verifyEqual(tests, [d.highCutoff d.lowCutoff], [0.05 33.75], 'AbsTol', 1e-12);
    lp = EEGAnalysis.filterDesign(500, 'LowPass', 40);
    verifyEqual(tests, lp.length, 165);
    verifyEqual(tests, lp.h([83 1 71]), [0.17982833336141163 0.0002123807816329227 0.012156937905843782], 'AbsTol', 1e-12);
    verifyEqual(tests, sum(lp.h), 1, 'AbsTol', 1e-12, 'low-pass: DC gain 1');
    hp = EEGAnalysis.filterDesign(500, 'HighPass', 1);
    verifyEqual(tests, hp.length, 1651);
    verifyEqual(tests, hp.h([826 1]), [0.997990231681618 2.7636500548030848e-05], 'AbsTol', 1e-12);
    verifyEqual(tests, sum(hp.h), 0, 'AbsTol', 1e-12, 'high-pass: DC gain 0');
    gain = @(d, f) abs(sum(d.h .* exp(-2i * pi * f * (0:d.length - 1) / 500)));
    verifyEqual(tests, gain(lp, 20), 1, 'AbsTol', 0.003);
    verifyEqual(tests, gain(lp, lp.lowCutoff), 0.5, 'AbsTol', 0.01, '-6 dB at the cutoff');
    verifyLessThan(tests, gain(lp, 60), 0.003);
    n = EEGAnalysis.notchDesign(500, [50 100]);
    verifyEqual(tests, n.length, 3301);
    verifyEqual(tests, n.notchWidth, [0.25 0.5], 'AbsTol', 1e-12);
    verifyLessThan(tests, [gain(n, 50) gain(n, 100)], [0.01 0.01]);
    verifyEqual(tests, [gain(n, 45) gain(n, 75)], [1 1], 'AbsTol', 0.003);
    verifySubstring(tests, EEGAnalysis.describeFilter(d), 'Band-pass filter 0.1-30 Hz');
    verifySubstring(tests, EEGAnalysis.describeFilter(n), 'Notch filter at 50 and 100 Hz');
    verifyError(tests, @() EEGAnalysis.filterDesign(500, 'HighPass', 40, 'LowPass', 30), 'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() EEGAnalysis.filterDesign(500, 'LowPass', 300), 'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() EEGAnalysis.notchDesign(500, 250), 'NeuroAnalyzer:eeg:badOption');
end

function testFilterRemovesDriftAndLineNoise(tests)
    fs = 250;
    t = (0:20 * fs - 1) / fs;
    sig = 10 * sin(2 * pi * 6 * t);
    x = [sig + 300 + 2 * t + 20 * sin(2 * pi * 50 * t); -sig];
    eeg = EEGSource.make(single(x), fs, 'Labels', {'A', 'B'}, 'Unit', 'uV', 'IsEpoched', false);
    [out, info] = EEGAnalysis.filter(eeg, 'HighPass', 1, 'Notch', 50);
    verifyEqual(tests, info.band.kind, 'high-pass');
    verifyEqual(tests, info.notch.notch, 50);
    mid = 7 * fs:13 * fs;                                        % away from the edges (the filter is 6.6 s long)
    verifyEqual(tests, double(out.data(1, mid)), sig(mid), 'AbsTol', 0.05, 'offset, drift and 50 Hz removed');
    verifyEqual(tests, double(out.data(2, mid)), -sig(mid), 'AbsTol', 0.05);
    verifyEqual(tests, numel(out.history), 2);
    verifySubstring(tests, out.history{1}, 'High-pass filter: passband edge 1 Hz');
    % Trials are filtered one by one; a filter longer than a trial is noted
    ep = EEGSource.make(single(randn(2, 100, 3)), fs, 'Labels', {'A', 'B'}, 'Unit', 'uV', 'IsEpoched', true);
    epf = EEGAnalysis.filter(ep, 'HighPass', 1);
    verifySize(tests, epf.data, [2 100 3]);
    verifyTrue(tests, any(contains(epf.notes, 'longer than each trial')));
end

function testRereferenceExact(tests)
    x = single([1 2 3; 4 5 6; 7 8 9; 10 20 30]);
    eeg = EEGSource.make(x, 10, 'Labels', {'Cz', 'TP9', 'TP10', 'T7'}, 'Unit', 'uV', 'IsEpoched', false, ...
        'Reference', 'FCz', 'Bad', {'T7'});
    verifyEqual(tests, EEGAnalysis.badChannels(eeg), [false false false true]);
    a = EEGAnalysis.rereference(eeg, 'average');
    m = mean(double(x(1:3, :)), 1);
    verifyEqual(tests, double(a.data(1:3, :)), double(x(1:3, :)) - m, 'AbsTol', 1e-5);
    verifyEqual(tests, a.data(4, :), x(4, :), 'bad channel as recorded (as MNE-Python)');
    verifyEqual(tests, a.reference, 'average of the 3 good channels (T7 marked bad and left out)');
    verifySubstring(tests, a.history{end}, 'was: FCz');
    l = EEGAnalysis.rereference(eeg, {'tp9', 'TP10'});
    verifyEqual(tests, double(l.data(1, :)), double(x(1, :)) - mean(double(x(2:3, :)), 1), 'AbsTol', 1e-5);
    verifyEqual(tests, l.reference, 'mean of TP9 and TP10 (linked mastoids)');
    c = EEGAnalysis.rereference(eeg, 'Cz');
    verifyEqual(tests, double(c.data(1, :)), [0 0 0]);
    verifyEqual(tests, c.reference, 'channel Cz');
    verifyError(tests, @() EEGAnalysis.rereference(eeg, 'T7'), 'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() EEGAnalysis.rereference(eeg, 'M1'), 'NeuroAnalyzer:eeg:unknownChannel');
    % Older structs without eeg.bad: no channel is bad
    verifyEqual(tests, EEGAnalysis.badChannels(rmfield(eeg, 'bad')), false(1, 4));
end

function testMarkAndSuggestBadChannels(tests)
    rs = RandStream('mt19937ar', 'Seed', 7);
    x = 10 * randn(rs, 8, 2000);
    x(3, :) = 0.01 * randn(rs, 1, 2000);                         % flat
    x(6, :) = 200 * randn(rs, 1, 2000);                          % very noisy
    labels = arrayfun(@(k) sprintf('E%d', k), 1:8, 'UniformOutput', false);
    eeg = EEGSource.make(single(x), 100, 'Labels', labels, 'Unit', 'uV', 'IsEpoched', false);
    [names, info] = EEGAnalysis.suggestBadChannels(eeg);
    verifyEqual(tests, names, {'E3', 'E6'});
    verifySubstring(tests, info.rule, 'robust z-scores');
    b = EEGAnalysis.markBad(eeg, names);
    verifyEqual(tests, find(b.bad), [3 6]);
    verifySubstring(tests, b.history{end}, 'Marked bad: E3 and E6');
    verifyEqual(tests, EEGAnalysis.markBad(b, {}).bad, false(1, 8));
    verifyError(tests, @() EEGAnalysis.markBad(eeg, 'X9'), 'NeuroAnalyzer:eeg:unknownChannel');
end

function testEpochRenameAndGaps(tests)
    fs = 100;
    x = single(repmat(0:999, 2, 1));
    ev = struct('type', {'S  1', 'S  2', 'boundary', 'S  1', 'S 1', 'other'}, ...
        'latency', {1, 2, 4.5, 4.4, 7, 8}, 'duration', 0);
    eeg = EEGSource.make(x, fs, 'Labels', {'A', 'B'}, 'Events', ev, 'Unit', 'uV', 'IsEpoched', false, 'Bad', {'B'});
    ep = EEGAnalysis.epoch(eeg, 'Window', [-0.2 0.5], 'Rename', {'s 1', 'Standard'; 'S 2', 'Target'});
    verifyEqual(tests, ep.trials.condition, {'Standard', 'Target', 'Standard'}, 'the trial across the gap is left out');
    verifyTrue(tests, any(contains(ep.notes, 'across a gap')));
    verifyEqual(tests, ep.bad, [false true], 'bad channels carried over');
    verifySubstring(tests, ep.history{end}, 'S  1 (Standard)');
    all = EEGAnalysis.epoch(eeg, 'Window', [-0.2 0.5]);
    verifyFalse(tests, any(strcmp(all.trials.condition, 'boundary')));
end

function testRejectTrialsExact(tests)
    x = zeros(3, 11, 6);
    x(1, 5, 2) = 80;                                             % p2p 80
    x(2, 6, 3) = 120;                                            % p2p 120 -> rejected
    x(3, 6, 4) = 500;                                            % bad channel: ignored
    x(1, :, 5) = 70;                                             % offset only: p2p 0, absolute 70
    x(1, 1, 6) = -60; x(1, 11, 6) = 60;                          % p2p 120 at the edges
    x = x + 0.01 * (0:10);                                       % no trial is flat
    ep = EEGSource.make(single(x), 10, 'Times', (-5:5) / 10, 'Labels', {'A', 'B', 'C'}, 'Unit', 'uV', ...
        'IsEpoched', true, 'Conditions', {'X', 'X', 'Y', 'Y', 'X', 'Y'}, 'Bad', {'C'});
    [out, info] = EEGAnalysis.rejectTrials(ep, 'PeakToPeak', 100);
    verifyEqual(tests, info.rejected, [3 6]);
    verifyEqual(tests, [info.before; info.after], [3 3; 3 1]);
    verifyEqual(tests, info.channels, {'A', 'B'});
    verifyEqual(tests, size(out.data, 3), 4);
    verifyEqual(tests, out.trials.condition, {'X', 'X', 'Y', 'X'});
    verifySubstring(tests, info.sentence, 'Rejected 2 of 6 trials with a peak-to-peak amplitude above 100 uV');
    verifySubstring(tests, out.history{end}, 'X 0 of 3 and Y 2 of 3');
    i2 = EEGAnalysis.rejectTrials(ep, 'PeakToPeak', 100, 'Window', [-0.4 0.4]);
    verifyEqual(tests, size(i2.data, 3), 5, 'edges outside the window');
    [~, i3] = EEGAnalysis.rejectTrials(ep, 'Absolute', 65);
    verifyEqual(tests, i3.rejected, [2 3 5]);
    [~, i4] = EEGAnalysis.rejectTrials(ep, 'Absolute', 65, 'Baseline', [-0.5 0]);
    verifyEqual(tests, i4.rejected, [2 3 6], 'the offset of trial 5 is removed by the baseline');
    verifyError(tests, @() EEGAnalysis.rejectTrials(ep, 'PeakToPeak', 1e-3), 'NeuroAnalyzer:eeg:allRejected');
    verifyError(tests, @() EEGAnalysis.rejectTrials(ep), 'NeuroAnalyzer:eeg:badOption');
end

function testBadChannelsInERPsAndMeasures(tests)
    eeg = tinyEEG();
    eeg = EEGAnalysis.markBad(eeg, 'Fz');
    erp = EEGAnalysis.conditionERPs(eeg);
    verifyTrue(tests, all(isnan(erp.mean(1, :))));
    verifyFalse(tests, any(isnan(erp.mean(2, :))));
    good = EEGAnalysis.conditionERPs(tinyEEG());
    r = EEGAnalysis.measure(erp, 'Window', [0.2 0.3]);
    rc = EEGAnalysis.measure(good, 'Channels', 'Cz', 'Window', [0.2 0.3]);
    verifyEqual(tests, [r.value], [rc.value], 'AbsTol', 1e-12, 'the bad channel is left out of the average');
    rf = EEGAnalysis.measure(erp, 'Channels', 'Fz', 'Window', [0.2 0.3]);
    verifyTrue(tests, all(isnan([rf.value])));
    ga = EEGAnalysis.grandAverage({erp, good});
    verifyEqual(tests, ga.mean(1, :, :), good.mean(1, :, :), 'AbsTol', 1e-12, 'Fz from the other participant');
    verifyEqual(tests, ga.mean(2, :, :), good.mean(2, :, :), 'AbsTol', 1e-12);
    verifyEqual(tests, ga.bad, [false false]);
    verifyTrue(tests, any(contains(ga.notes, 'Fz in 1')));
end

function testRawDemoPipeline(tests)
    f = tests.TestData.demo;
    tr = f.truth.raw;
    verifyNumElements(tests, f.raw, 3);
    ren = {'S 1', 'Standard'; 'S 2', 'Target'; 'S 3', 'Novel'};
    erps = cell(1, 3);
    for p = 1:3
        eeg = EEGSource.open(f.raw(p).brainvision);
        verifyEqual(tests, eeg.reference, 'channel FCz');
        verifyEqual(tests, EEGAnalysis.suggestBadChannels(eeg), {'T7'}, sprintf('participant %d', p));
        e = EEGAnalysis.filter(eeg, 'HighPass', 0.1, 'LowPass', 30);
        % Without marking T7 bad, its noise fails every trial
        verifyError(tests, @() EEGAnalysis.rejectTrials(EEGAnalysis.epoch(EEGAnalysis.rereference(e, ...
            'average'), 'Rename', ren), 'PeakToPeak', 100), 'NeuroAnalyzer:eeg:allRejected');
        e = EEGAnalysis.rereference(EEGAnalysis.markBad(e, 'T7'), 'average');
        ep = EEGAnalysis.epoch(e, 'Window', [-0.2 0.8], 'Rename', ren);
        verifyEqual(tests, ep.trials.condition, tr.participants(p).condition);
        [ep, info] = EEGAnalysis.rejectTrials(ep, 'PeakToPeak', 100);
        verifyEqual(tests, info.rejected, tr.participants(p).blinkTrials, 'exactly the blink trials');
        erps{p} = EEGAnalysis.conditionERPs(ep, 'Baseline', [-0.2 0]);
        n1 = EEGAnalysis.measure(erps{p}, 'Channels', 'Cz', 'Window', [0.07 0.13], 'Measure', 'peak', 'Polarity', 'negative');
        verifyEqual(tests, mean([n1.value]), tr.participants(p).n1CzAverage, 'AbsTol', 1);
    end
    ga = EEGAnalysis.grandAverage(erps);
    r = EEGAnalysis.measure(ga, 'Channels', 'Pz', 'Window', [0.3 0.4]);
    v = containers.Map({r.condition}, {r.value});
    verifyGreaterThan(tests, v('Target'), v('Novel'));
    verifyGreaterThan(tests, v('Novel'), v('Standard'));
    verifyTrue(tests, all(ga.bad == strcmp(ga.labels, 'T7')));
    % Against FCz (no re-reference) the N1 at Cz is small
    e = EEGAnalysis.markBad(EEGAnalysis.filter(EEGSource.open(f.raw(1).brainvision), 'HighPass', 0.1, 'LowPass', 30), 'T7');
    erp = EEGAnalysis.conditionERPs(EEGAnalysis.epoch(e, 'Rename', ren), 'Baseline', [-0.2 0]);
    n1 = EEGAnalysis.measure(erp, 'Channels', 'Cz', 'Window', [0.07 0.13], 'Measure', 'peak', 'Polarity', 'negative');
    verifyEqual(tests, mean([n1.value]), tr.participants(1).n1CzFCz, 'AbsTol', 1);
    verifyGreaterThan(tests, abs(tr.participants(1).n1CzAverage), 2 * abs(tr.participants(1).n1CzFCz));
end

%% ------------------------------------------------------- Time-frequency

%% testTimeFrequencyMatchesContinuous - Trials long enough: the values of TimeFrequency.ersp
% ersp transforms the continuous recording; timeFrequency the trials cut from it (each
% trial's mean removed). Where the whole wavelet lies inside the trial they agree.
function testTimeFrequencyMatchesContinuous(tests)
    fs = 250;
    rs = RandStream('mt19937ar', 'Seed', 5);
    N = 60 * fs;
    x = randn(rs, 1, N) + 2 * sin(2 * pi * 10 * (0:N - 1) / fs);
    onsets = 3:2:55;
    for k = 1:numel(onsets)                          % a phase-locked 20 Hz burst after each onset
        i = round(onsets(k) * fs) + (1:round(0.3 * fs));
        x(i) = x(i) + 3 * sin(2 * pi * 20 * (0:numel(i) - 1) / fs);
    end
    w = [-1 1.5]; freqs = 8:2:30; nc = 7; base = [-0.5 -0.1];
    [E, I] = TimeFrequency.ersp(x, fs, onsets, w, freqs, base, nc);
    m = max(TimeFrequency.supportSamples(fs, freqs, nc));
    rel = round(w(1) * fs) - m:round(w(2) * fs) + m;
    data = zeros(1, numel(rel), numel(onsets));
    for k = 1:numel(onsets), data(1, :, k) = x(round(onsets(k) * fs) + 1 + rel); end
    eeg = EEGSource.make(data, fs, 'Times', rel / fs, 'Labels', {'A'}, ...
        'Conditions', repmat({'X'}, 1, numel(onsets)), 'IsEpoched', true);
    tf = EEGAnalysis.timeFrequency(eeg, 'Frequencies', freqs, 'Cycles', nc, 'Baseline', base, ...
        'Bands', [18 22], 'BandNames', {'Beta'});
    in = tf.times >= w(1) - 1e-9 & tf.times <= w(2) + 1e-9;
    verifyTrue(tests, all(all(tf.valid(:, in))));
    verifyEqual(tests, tf.ersp(:, in), E, 'AbsTol', 0.01, 'ERSP (dB) as from the continuous recording');
    verifyEqual(tests, tf.itpc(:, in), I, 'AbsTol', 0.01, 'ITPC as from the continuous recording');
    verifyEqual(tests, tf.bandNames, {'Beta'});
    b = mean(tf.bandPct(1, tf.times >= 0.1 & tf.times <= 0.2));
    verifyGreaterThan(tests, b, 50, 'the 20 Hz burst raises beta power');
end

%% testTimeFrequencyKnownAnswers - Amplitude halved: -6.02 dB, -75%; locked phase: ITPC 1; blank edges
function testTimeFrequencyKnownAnswers(tests)
    fs = 250; t = -0.5 + (0:374) / fs; nT = 20;
    rs = RandStream('mt19937ar', 'Seed', 6);
    env = ones(size(t)); env(t >= 0.2) = 0.5;
    data = zeros(3, numel(t), 2 * nT);
    cond = [repmat({'Locked'}, 1, nT), repmat({'Random'}, 1, nT)];
    for k = 1:2 * nT
        ph = 0;
        if k > nT, ph = 2 * pi * rand(rs); end
        data(1:2, :, k) = repmat(4 * sin(2 * pi * 10 * t + ph) .* env, 2, 1);
        data(3, :, k) = 100 * randn(rs, 1, numel(t));            % a bad channel
    end
    eeg = EEGSource.make(data, fs, 'Times', t, 'Labels', {'O1', 'Oz', 'T7'}, 'Conditions', cond, 'IsEpoched', true);
    eeg = EEGAnalysis.markBad(eeg, {'T7'});
    tf = EEGAnalysis.timeFrequency(eeg, 'Frequencies', 6:14, 'Cycles', 3, 'Baseline', [-0.4 -0.1]);
    verifyEqual(tests, tf.channels, {'O1', 'Oz'}, 'all good channels by default');
    verifyEqual(tests, tf.conditions, {'Locked', 'Random'});
    verifyEqual(tests, tf.n, [nT nT]);
    verifyEqual(tests, tf.cycles, 3 * ones(1, 9));
    verifyEqual(tests, tf.bandNames, {'Alpha'});
    i10 = tf.freqs == 10;
    j = abs(tf.times - 0.5) < 1e-9;
    verifyEqual(tests, squeeze(tf.ersp(i10, j, :))', [-6.02 -6.02], 'AbsTol', 0.05, 'amplitude halved: -6 dB');
    verifyEqual(tests, tf.itpc(i10, j, 1), 1, 'AbsTol', 1e-9, 'the same phase in every trial');
    verifyLessThan(tests, tf.itpc(i10, j, 2), 0.6, 'random phases');
    verifyEqual(tests, squeeze(tf.bandPct(1, j, :))', [-75 -75], 'AbsTol', 1, 'power -75% in the alpha band');
    verifyEqual(tests, tf.bandSem(1, j, 1), 0, 'AbsTol', 1e-6, 'identical trials');
    % Where the wavelet fits: samples h+1 .. n-h at each frequency; blank (NaN) elsewhere
    h = TimeFrequency.supportSamples(fs, tf.freqs, 3);
    for i = 1:numel(tf.freqs)
        verifyEqual(tests, find(tf.valid(i, :), 1), h(i) + 1);
        verifyEqual(tests, find(tf.valid(i, :), 1, 'last'), numel(t) - h(i));
    end
    verifyTrue(tests, all(isnan(tf.ersp(~repmat(tf.valid, 1, 1, 2)))));
    verifyTrue(tests, all(isnan(tf.itpc(~repmat(tf.valid, 1, 1, 2)))));
    verifyEqual(tests, tf.bandValid(1, :), all(tf.valid(tf.freqs >= 8 & tf.freqs <= 13, :), 1));
    verifyEqual(tests, tf.baselineSamples, sum(tf.valid(:, t >= -0.4 - 1e-9 & t <= -0.1 + 1e-9), 2)');
    % One channel, one condition, cycles per frequency
    tf = EEGAnalysis.timeFrequency(eeg, 'Channels', 'oz', 'Conditions', 'Random', 'Frequencies', [8 10 12], ...
        'Cycles', [3 4 5], 'Baseline', [-0.4 -0.1], 'Bands', [9 11], 'BandNames', {'Mu'});
    verifyEqual(tests, tf.channels, {'Oz'});
    verifyEqual(tests, tf.conditions, {'Random'});
    verifyEqual(tests, [size(tf.ersp, 1), size(tf.ersp, 2), size(tf.ersp, 3)], [3 numel(t) 1]);
    verifyEqual(tests, tf.cycles, [3 4 5]);
    verifyTrue(tests, contains(EEGAnalysis.describeTimeFrequency(tf), 'Morlet wavelets of 3 to 5 cycles, 8 to 12 Hz (3 frequencies), at Oz'));
    tf = EEGAnalysis.timeFrequency(eeg, 'Channels', {'Oz', 'T7'}, 'Frequencies', 10, 'Bands', [9 11]);
    verifyEqual(tests, tf.channels, {'Oz'}, 'the bad channel is left out');
    verifyEqual(tests, tf.left, {'T7'});
    verifyEqual(tests, tf.baseline, [-0.5 0], 'AbsTol', 1e-12, 'default: trial start to the event');
end

%% testTimeFrequencyShortTrials - What a 1 s trial leaves blank, said in words
function testTimeFrequencyShortTrials(tests)
    rs = RandStream('mt19937ar', 'Seed', 7);
    t = -0.2 + (0:249) / 250;
    eeg = EEGSource.make(randn(rs, 1, 250, 10), 250, 'Times', t, 'Labels', {'Oz'}, ...
        'Conditions', repmat({'S'}, 1, 10), 'IsEpoched', true);
    tf = EEGAnalysis.timeFrequency(eeg);
    verifyEqual(tests, tf.freqs, 4:40);
    verifyEqual(tests, tf.baseline, [-0.2 0], 'AbsTol', 1e-12);
    has = tf.baselineSamples > 0;
    verifyEqual(tests, tf.freqs(find(has, 1)), 8, 'a baseline sample from 8 Hz up (3 cycles)');
    verifyTrue(tests, all(all(isnan(tf.ersp(~has, :)))), 'no ERSP without a baseline');
    verifyTrue(tests, any(isfinite(tf.power(1, :))), '4 Hz still has power values in the middle');
    s = EEGAnalysis.describeTimeFrequency(tf);
    verifyTrue(tests, contains(s, 'ERSP from 8 Hz up'));
    verifyTrue(tests, contains(s, 'At 8 Hz the values run from -20 to 616 ms'));
    tf = EEGAnalysis.timeFrequency(eeg, 'Frequencies', 1:2, 'Bands', [1 2]);
    verifyFalse(tests, any(tf.valid(:)));
    verifyTrue(tests, contains(EEGAnalysis.describeTimeFrequency(tf), 'No value'));
end

%% testTimeFrequencyGrandAverage - Mean over participants, SEM across them, common conditions
function testTimeFrequencyGrandAverage(tests)
    rs = RandStream('mt19937ar', 'Seed', 8);
    t = -0.4 + (0:299) / 250;
    mk = @(conds) EEGSource.make(randn(rs, 2, 300, numel(conds)), 250, 'Times', t, 'Labels', {'Cz', 'Pz'}, ...
        'Conditions', conds, 'IsEpoched', true);
    a = EEGAnalysis.timeFrequency(mk(repmat({'A', 'B'}, 1, 6)), 'Frequencies', 8:12);
    b = EEGAnalysis.timeFrequency(mk([repmat({'A', 'B'}, 1, 4), {'C', 'C'}]), 'Frequencies', 8:12);
    ga = EEGAnalysis.grandTimeFrequency({a, b});
    verifyEqual(tests, ga.conditions, {'A', 'B'});
    verifyEqual(tests, ga.n, [2 2]);
    verifyEqual(tests, ga.trials, [10 10]);
    verifyEqualNaN(tests, ga.ersp, (a.ersp + b.ersp(:, :, 1:2)) / 2, 1e-12);
    verifyEqualNaN(tests, ga.itpc, (a.itpc + b.itpc(:, :, 1:2)) / 2, 1e-12);
    verifyEqualNaN(tests, ga.bandSem, abs(a.bandPct - b.bandPct(:, :, 1:2)) / 2, 1e-9);   % SEM of two: half their distance
    verifyTrue(tests, contains(ga.notes{1}, 'Left out of the grand average: C'));
    one = EEGAnalysis.grandTimeFrequency({a});
    verifyEqualNaN(tests, one.ersp, a.ersp, 0);
    verifyEqual(tests, one.trials, a.n);
    c = EEGAnalysis.timeFrequency(mk(repmat({'A', 'B'}, 1, 3)), 'Frequencies', 8:13);
    verifyError(tests, @() EEGAnalysis.grandTimeFrequency({a, c}), 'NeuroAnalyzer:eeg:mismatch');
end

%% testTimeFrequencyErrors - Plain messages
function testTimeFrequencyErrors(tests)
    eeg = tinyEEG();
    verifyError(tests, @() EEGAnalysis.timeFrequency(eeg, 'Frequencies', 6), 'NeuroAnalyzer:eeg:badOption', ...
        'at or above half the sampling rate (5 Hz)');
    verifyError(tests, @() EEGAnalysis.timeFrequency(eeg, 'Frequencies', [1 2], 'Cycles', 0), 'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() EEGAnalysis.timeFrequency(eeg, 'Frequencies', [1 2], 'Cycles', [3 4 5]), 'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() EEGAnalysis.timeFrequency(eeg, 'Frequencies', [1 2], 'Bands', [3 4]), 'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() EEGAnalysis.timeFrequency(eeg, 'Frequencies', [1 2], 'Bands', [2 1]), 'NeuroAnalyzer:eeg:badOption');
    verifyError(tests, @() EEGAnalysis.timeFrequency(eeg, 'Frequencies', [1 2], 'Bands', [1 2], 'Channels', 'Oz'), ...
        'NeuroAnalyzer:eeg:unknownChannel');
    verifyError(tests, @() EEGAnalysis.timeFrequency(eeg, 'Frequencies', [1 2], 'Bands', [1 2], 'Conditions', 'C'), ...
        'NeuroAnalyzer:eeg:unknownCondition');
    verifyError(tests, @() EEGAnalysis.timeFrequency(eeg, 'Frequencies', [1 2], 'Bands', [1 2], 'Baseline', [0.3 0.4]), ...
        'NeuroAnalyzer:eeg:badWindow');
    verifyError(tests, @() EEGAnalysis.timeFrequency(EEGAnalysis.markBad(eeg, {'Fz', 'Cz'}), 'Frequencies', [1 2], ...
        'Bands', [1 2]), 'NeuroAnalyzer:eeg:badOption', 'every channel bad');
    late = EEGSource.make(zeros(1, 5, 2), 10, 'Times', (0:4) / 10, 'Labels', {'Cz'}, 'Conditions', {'A', 'A'}, ...
        'IsEpoched', true);
    verifyError(tests, @() EEGAnalysis.timeFrequency(late, 'Frequencies', [1 2], 'Bands', [1 2]), ...
        'NeuroAnalyzer:eeg:badWindow', 'no time before the event: a baseline must be given');
    cont = EEGSource.make(zeros(1, 50), 10, 'Labels', {'Cz'}, 'IsEpoched', false);
    verifyError(tests, @() EEGAnalysis.timeFrequency(cont), 'NeuroAnalyzer:eeg:notEpoched');
    verifyError(tests, @() EEGAnalysis.grandTimeFrequency({}), 'NeuroAnalyzer:eeg:badOption');
end

%% testDemoAlphaDecrease - The demo's alpha halves after Target (O1 / Oz / O2, 350-650 ms)
function testDemoAlphaDecrease(tests)
    d = tests.TestData.demo;
    a = d.truth.scalp.alpha;
    verifyEqual(tests, a.decrease.condition, 'Target');
    verifyEqual(tests, a.decrease.powerChangePct, -75);
    tfs = cell(1, numel(d.scalp));
    for p = 1:numel(d.scalp)
        tfs{p} = EEGAnalysis.timeFrequency(readEEGLAB(d.scalp(p).eeglab), 'Channels', {'Oz'}, ...
            'Frequencies', 4:40, 'Cycles', 3, 'Baseline', [-0.2 0]);
    end
    ga = EEGAnalysis.grandTimeFrequency(tfs);
    w = ga.times >= 0.4 & ga.times <= 0.6;
    i10 = ga.freqs == 10;
    v = @(c) mean(ga.ersp(i10, w, strcmp(ga.conditions, c)));
    verifyLessThan(tests, v('Target'), -1.5, 'alpha power falls after Target (simulated -6 dB, with noise)');
    verifyLessThan(tests, abs(v('Standard')), 1.5, 'no change after Standard');
    verifyLessThan(tests, abs(v('Novel')), 1.5, 'no change after Novel');
    bp = @(c) mean(ga.bandPct(1, w, strcmp(ga.conditions, c)));
    verifyLessThan(tests, bp('Target'), -30, 'alpha band power falls after Target');
    verifyTrue(tests, all(all(isnan(ga.ersp(ga.freqs < 8, :, :)))), '1 s trials: no ERSP below 8 Hz');
    % Raw recordings cut into longer trials: a baseline well before the event
    ren = {'S 1', 'Standard'; 'S 2', 'Target'; 'S 3', 'Novel'};
    tfs = cell(1, numel(d.raw));
    for p = 1:numel(d.raw)
        e = EEGAnalysis.filter(EEGAnalysis.markBad(EEGSource.open(d.raw(p).brainvision), 'T7'), 'HighPass', 0.1, 'LowPass', 30);
        ep = EEGAnalysis.epoch(EEGAnalysis.rereference(e, 'average'), 'Window', [-0.6 1], 'Rename', ren);
        tfs{p} = EEGAnalysis.timeFrequency(EEGAnalysis.rejectTrials(ep, 'PeakToPeak', 100), 'Channels', {'Oz'}, ...
            'Frequencies', 4:40, 'Cycles', 3, 'Baseline', [-0.5 -0.1]);
    end
    ga = EEGAnalysis.grandTimeFrequency(tfs);
    verifyTrue(tests, all(ga.baselineSamples > 0), 'every frequency has a baseline');
    w = ga.times >= 0.4 & ga.times <= 0.6;
    bp = @(c) mean(ga.bandPct(1, w, strcmp(ga.conditions, c)));
    verifyLessThan(tests, bp('Target'), -45, 'alpha band power about -70% after Target');
    verifyLessThan(tests, abs(bp('Standard')), 30);
end

%% ---------------------------------------------------------------- Helpers

%% verifyEqualNaN - Same NaN positions and the same values elsewhere
function verifyEqualNaN(tests, x, y, tol)
    verifyEqual(tests, size(x), size(y));
    verifyEqual(tests, isnan(x), isnan(y), 'the same values are blank');
    verifyEqual(tests, x(~isnan(x)), y(~isnan(y)), 'AbsTol', tol);
end

%% tinyEEG - 2 channels x 5 samples x 4 trials with known averages
% Trial k, channel c: k + c * [0 0 3 6 3] at -0.2 ... 0.2 s; conditions
% A B A B. Baseline [-0.2 0] leaves c * [-1 -1 2 5 2] in every trial.
%% testWindowMean - One value per channel in a window (scalp maps)
function testWindowMean(tests)
    erp = EEGAnalysis.conditionERPs(tinyEEG());     % A: 2 + [1; 2] * [0 0 3 6 3], B: 3 + ...
    verifyEqual(tests, EEGAnalysis.windowMean(erp, [0 0.1], 'A'), [6.5; 11], 'AbsTol', 1e-12);
    verifyEqual(tests, EEGAnalysis.windowMean(erp, [0 0.1], 'A', 'B'), [-1; -1], 'AbsTol', 1e-12);
    verifyEqual(tests, EEGAnalysis.windowMean(erp, [0.1 0.1], 'B'), [9; 15], 'AbsTol', 1e-12, 'one sample');
    verifyEqual(tests, EEGAnalysis.windowMean(erp, [0.04 0.04], 'A'), [5; 8], 'AbsTol', 1e-12, ...
        'between two samples: the nearest one');
    verifyEqual(tests, EEGAnalysis.windowMean(erp, [0.02 0.06], 'A'), [5; 8], 'AbsTol', 1e-12, ...
        'no sample inside: the one nearest the middle');
    verifyError(tests, @() EEGAnalysis.windowMean(erp, [0.3 0.4], 'A'), 'NeuroAnalyzer:eeg:badWindow');
    verifyError(tests, @() EEGAnalysis.windowMean(erp, [0.1 0], 'A'), 'NeuroAnalyzer:eeg:badWindow');
    verifyError(tests, @() EEGAnalysis.windowMean(erp, [0 0.1], 'C'), 'NeuroAnalyzer:eeg:unknownCondition');
    verifyError(tests, @() EEGAnalysis.windowMean(erp, [0 0.1], 'A', 'C'), 'NeuroAnalyzer:eeg:unknownCondition');
    erp = EEGAnalysis.conditionERPs(EEGAnalysis.markBad(tinyEEG(), {'Cz'}));
    v = EEGAnalysis.windowMean(erp, [0 0.1], 'A');
    verifyEqual(tests, v(1), 6.5, 'AbsTol', 1e-12);
    verifyTrue(tests, isnan(v(2)), 'a bad channel has no value');
end

function eeg = tinyEEG()
    x = zeros(2, 5, 4);
    for k = 1:4
        x(:, :, k) = k + [1; 2] * [0 0 3 6 3];
    end
    eeg = EEGSource.make(x, 10, 'Times', (-2:2) / 10, 'Labels', {'Fz', 'Cz'}, ...
        'Conditions', {'A', 'B', 'A', 'B'}, 'IsEpoched', true, 'Unit', 'uV');
end
