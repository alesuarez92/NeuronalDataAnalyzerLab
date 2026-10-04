%% EEGChecksTest.m
% =========================================================================
% UNIT TESTS: EEG QUALITY CHECKS (EEG ANALYSIS AND BATCH)
% =========================================================================
% core/EEGAnalysis.m checks and interpolatedChannels:
%   * one rule at a time on synthetic EEG structs: trials per condition
%     (Check below 20, Warning below 10), rejection balance (Check above 20
%     points with 3 trials, Warning above 40; a note when the trials were
%     rejected before loading), condition balance against the measure
%     (peak: Check above 2 times; mean: OK), bad channels (Check above 10%,
%     Warning above 20%), interpolated channels against the measured ones;
%     several participants in one row; odd input gives fewer rows, never
%     an error;
%   * the history parser on the lines EEGSource writes for EEGLAB
%     pop_interp and FieldTrip ft_channelrepair;
%   * the clean demo (core/demo/demoEEG, 8 participants) gives no
%     warnings; the faults demo (demoEEG faults: blinks in 9 of 15 Target
%     trials, 8 noisy or flat channels, Pz interpolated) fires each check;
%   * Batch 'eeg': the Checks column and the log line on the faults demo.
% Base MATLAB only, except the Batch test (table, skipped in GNU Octave):
% the rest also runs in GNU Octave (with a RandStream shim).
% =========================================================================

function tests = EEGChecksTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'io'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.tmp = tempname;
    mkdir(tests.TestData.tmp);
    tests.TestData.demo = demoEEG(fullfile(tests.TestData.tmp, 'demo'), 'Kinds', {'scalp', 'faults'}, ...
        'Formats', {'eeglab'});
end

function teardownOnce(tests)
    try, rmdir(tests.TestData.tmp, 's'); catch, end
end

%% row - The first row of a topic ([] when none)
function r = row(Q, topic)
    r = [];
    if isempty(Q), return; end
    k = find(strcmp({Q.topic}, topic), 1);
    if ~isempty(k), r = Q(k); end
end

%% expect - A row of this topic with this level whose finding has the text
function expect(tests, Q, topic, level, text)
    r = row(Q, topic);
    txt = strjoin(QualityChecks.lines(Q), newline);
    tests.verifyNotEmpty(r, sprintf('no %s row:\n%s', topic, txt));
    if isempty(r), return; end
    tests.verifyEqual(r.level, level, sprintf('%s: %s', topic, r.found));
    if nargin >= 5
        tests.verifyTrue(~isempty(strfind(r.found, text)), sprintf('%s: "%s" not in "%s"', topic, text, r.found)); %#ok<STREMP>
    end
end

%% fakeEEG - Trials per condition (Standard, Target, Novel), 32 channels (Pz 25, T7 12), history
function eeg = fakeEEG(counts, history, bad)
    if nargin < 2, history = {}; end
    if nargin < 3, bad = 0; end
    names = {'Standard', 'Target', 'Novel'};
    cond = {};
    for c = 1:numel(counts)
        cond = [cond, repmat(names(c), 1, counts(c))]; %#ok<AGROW>
    end
    labels = arrayfun(@(k) sprintf('E%d', k), 1:32, 'UniformOutput', false);
    labels([12 14 25]) = {'T7', 'Cz', 'Pz'};
    eeg = EEGSource.make(zeros(32, 10, numel(cond), 'single'), 250, 'Labels', labels, 'Conditions', cond, ...
        'IsEpoched', true, 'Unit', 'uV', 'History', history, 'Source', 'EEGLAB');
    eeg.bad(1:bad) = true;
end

%% rejection - A rejectTrials info: trials per condition before and after
function info = rejection(before, after)
    info = struct('conditions', {{'Standard', 'Target', 'Novel'}}, 'before', before, 'after', after);
end

function testTrialsPerCondition(tests)
    expect(tests, EEGAnalysis.checks({fakeEEG([40 25 25])}), 'Trials per condition', 'ok', 'Target 25');
    expect(tests, EEGAnalysis.checks({fakeEEG([40 15 13])}), 'Trials per condition', 'check', 'Novel 13');
    Q = EEGAnalysis.checks({fakeEEG([38 6 14])}, {'sub-01'});
    expect(tests, Q, 'Trials per condition', 'warning', 'Fewest trials in a condition: Target 6.');
    tests.verifyTrue(~isempty(strfind(Q(1).why, 'mostly noise')), Q(1).why); %#ok<STREMP>
    % Several participants: one row, the worst first, the participants named
    Q = EEGAnalysis.checks({fakeEEG([40 25 25]), fakeEEG([38 6 14]), fakeEEG([40 15 15])}, {'a', 'b', 'c'});
    expect(tests, Q, 'Trials per condition', 'warning', 'Target 6 (b), Target 15 (c) (below 10 in 1 of 3 participants)');
    tests.verifyEqual(sum(strcmp({Q.topic}, 'Trials per condition')), 1, 'one row per check');
    % Every trial of a condition rejected: 0 trials (from the rejection info)
    Q = EEGAnalysis.checks({fakeEEG([40 15])}, {}, struct('rejections', rejection([40 15 15], [40 15 0])));
    expect(tests, Q, 'Trials per condition', 'warning', 'Novel 0');
end

function testRejectionBalance(tests)
    e = fakeEEG([38 6 14]);
    Q = EEGAnalysis.checks({e}, {'sub-01'}, struct('rejections', rejection([40 15 15], [38 6 14])));
    expect(tests, Q, 'Rejection balance', 'warning', 'Rejection removed 60% of Target trials but 5% of Standard.');
    r = row(Q, 'Rejection balance');
    tests.verifyTrue(~isempty(strfind(r.action, 'ICA')), r.action); %#ok<STREMP>
    % 33 or 27 points apart with 5 or 4 trials: Check; 20 points: OK; 40 points but only 2 trials: OK
    expect(tests, EEGAnalysis.checks({e}, {}, struct('rejections', rejection([40 15 15], [38 10 15]))), ...
        'Rejection balance', 'check', '33% of Target trials but 0% of Novel');
    expect(tests, EEGAnalysis.checks({e}, {}, struct('rejections', rejection([40 15 15], [36 11 15]))), ...
        'Rejection balance', 'check', '27% of Target trials but 0% of Novel');
    expect(tests, EEGAnalysis.checks({e}, {}, struct('rejections', rejection([40 15 15], [36 12 15]))), ...
        'Rejection balance', 'ok', 'Standard 10%, Target 20% and Novel 0% (20 points apart); check above 20 points');
    expect(tests, EEGAnalysis.checks({e}, {}, struct('rejections', rejection([40 5 15], [40 3 15]))), ...
        'Rejection balance', 'ok', '(40 points apart, but only 2 Target trials)');
    expect(tests, EEGAnalysis.checks({e}, {}, struct('rejections', rejection([40 15 15], [40 15 15]))), ...
        'Rejection balance', 'ok', 'left out no trial');
    % Several participants (a struct array of infos): the worst named
    Q = EEGAnalysis.checks({e, e}, {'a', 'b'}, struct('rejections', [rejection([40 15 15], [38 10 15]), ...
        rejection([40 15 15], [38 6 14])]));
    expect(tests, Q, 'Rejection balance', 'warning', '60% of Target trials but 5% of Standard (b); 33% of Target');
    % Not rejected here: a note when the history says trials were rejected before, else no row
    Q = EEGAnalysis.checks({fakeEEG([38 13 14], {'Rejected 5 trials (pop_rejepoch).'})});
    expect(tests, Q, 'Rejection balance', 'note', 'rejected before loading');
    tests.verifyEmpty(row(EEGAnalysis.checks({e}), 'Rejection balance'));
end

function testConditionBalance(tests)
    e = fakeEEG([38 6 14]);
    expect(tests, EEGAnalysis.checks({e}, {}, struct('measure', 'mean')), 'Condition balance', 'ok', ...
        'Standard has 6.3 times as many trials as Target (38 vs 6): fine for the mean amplitude');
    Q = EEGAnalysis.checks({e}, {}, struct('measure', 'Peak amplitude'));
    expect(tests, Q, 'Condition balance', 'check', 'the peak amplitude is measured');
    r = row(Q, 'Condition balance');
    tests.verifyTrue(~isempty(strfind(r.action, 'mean amplitude')), r.action); %#ok<STREMP>
    expect(tests, EEGAnalysis.checks({e}), 'Condition balance', 'note', 'peak amplitudes would come out larger');
    expect(tests, EEGAnalysis.checks({fakeEEG([30 20 15])}, {}, struct('measure', 'peak')), 'Condition balance', ...
        'ok', 'at most 2.0 times');
    tests.verifyEmpty(row(EEGAnalysis.checks({fakeEEG(40)}), 'Condition balance'), 'one condition: nothing to balance');
end

function testBadChannels(tests)
    expect(tests, EEGAnalysis.checks({fakeEEG([40 25 25])}), 'Bad channels', 'ok', 'No channel marked bad');
    expect(tests, EEGAnalysis.checks({fakeEEG([40 25 25], {}, 3)}), 'Bad channels', 'ok', ...
        'At most 3 of 32 channels marked bad (9%: E1, E2 and E3)');
    expect(tests, EEGAnalysis.checks({fakeEEG([40 25 25], {}, 5)}), 'Bad channels', 'check', '5 of 32 channels marked bad (16%)');
    Q = EEGAnalysis.checks({fakeEEG([40 25 25], {}, 8)});
    expect(tests, Q, 'Bad channels', 'warning', '8 of 32 channels marked bad (25%): E1, E2, E3, E4, E5, E6, E7 and E8.');
    Q = EEGAnalysis.checks({fakeEEG([40 25 25], {}, 5), fakeEEG([40 25 25], {}, 10)}, {'a', 'b'});
    expect(tests, Q, 'Bad channels', 'warning', 'Channels marked bad: b: 10 of 32 (31%: E1, E2, E3, E4, ...); a: 5 of 32 (16%');
end

function testHistoryParser(tests)
    labels = fakeEEG(1).labels;
    % EEGLAB pop_interp, as EEGSource writes it into the history
    h = EEGSource.eeglabHistory('EEG = pop_interp(EEG, [12], ''spherical'');', labels);
    [names, info] = EEGAnalysis.interpolatedChannels(struct('history', {h}, 'source', 'EEGLAB'));
    tests.verifyEqual(names, {'T7'}, h{1});
    tests.verifyFalse(info.unknown);
    tests.verifyEqual(info.where, 'in EEGLAB');
    h = EEGSource.eeglabHistory('EEG = pop_interp(EEG, [12 25], ''spherical'');', labels);
    tests.verifyEqual(EEGAnalysis.interpolatedChannels(struct('history', {h})), {'T7', 'Pz'}, h{1});
    h = EEGSource.eeglabHistory('EEG = pop_interp(EEG, {''Pz''}, ''invdist'');', labels);
    tests.verifyEqual(EEGAnalysis.interpolatedChannels(struct('history', {h})), {'Pz'}, h{1});
    % Not named: 'Interpolated bad channels'
    h = EEGSource.eeglabHistory('EEG = pop_interp(EEG, [], ''spherical'');', labels);
    [names, info] = EEGAnalysis.interpolatedChannels(struct('history', {h}));
    tests.verifyEmpty(names);
    tests.verifyTrue(info.unknown, h{1});
    tests.verifyEqual(info.where, 'before loading');
    % FieldTrip ft_channelrepair (cfg.badchannel), from the cfg.previous chain
    c = struct('badchannel', {{'T7', 'P8', 'O1'}}, 'method', 'spline', 'version', struct('name', 'ft_channelrepair'));
    h = EEGSource.fieldtripHistory(c, labels);
    [names, info] = EEGAnalysis.interpolatedChannels(struct('history', {h}, 'source', 'FieldTrip'));
    tests.verifyEqual(names, {'T7', 'P8', 'O1'}, h{1});
    tests.verifyEqual(info.where, 'in FieldTrip');
    % Other lines, no history, odd input
    tests.verifyEmpty(EEGAnalysis.interpolatedChannels(struct('history', {{'Re-referenced to the average (pop_reref).'}})));
    tests.verifyEmpty(EEGAnalysis.interpolatedChannels(struct('history', {{}})));
    tests.verifyEmpty(EEGAnalysis.interpolatedChannels(42));
end

function testInterpolatedChannels(tests)
    e = fakeEEG([40 25 25], {'Interpolated channel Pz using spherical splines (pop_interp).'});
    Q = EEGAnalysis.checks({e}, {}, struct('channels', 'Pz'));
    expect(tests, Q, 'Interpolated channels', 'warning', 'Pz, the measured channel, was interpolated (in EEGLAB).');
    expect(tests, EEGAnalysis.checks({e}, {}, struct('channels', {{'Pz', 'Cz'}})), 'Interpolated channels', 'check', ...
        'Pz, among the measured channels (Pz and Cz), was interpolated (in EEGLAB).');
    % No measure channels: the ERP channels count; none at all: every channel is measured
    expect(tests, EEGAnalysis.checks({e}, {}, struct('erpChannels', {{'Pz'}})), 'Interpolated channels', 'warning');
    expect(tests, EEGAnalysis.checks({e}), 'Interpolated channels', 'check', 'among the measured channels (all channels)');
    % Interpolated elsewhere: OK, with the participants
    t7 = fakeEEG([40 25 25], {'Interpolated channel T7 using spherical splines (pop_interp).'});
    Q = EEGAnalysis.checks(repmat({t7}, 1, 8), arrayfun(@(k) sprintf('sub-%02d', k), 1:8, 'UniformOutput', false), ...
        struct('channels', 'Pz'));
    expect(tests, Q, 'Interpolated channels', 'ok', 'T7 was interpolated (in EEGLAB) in 8 participants; not among the measured channels (Pz).');
    Q = EEGAnalysis.checks({t7, e}, {'a', 'b'}, struct('channels', 'Pz'));
    expect(tests, Q, 'Interpolated channels', 'warning', 'was interpolated (in EEGLAB) in b.');
    % Not named in the history: Check; nothing interpolated: OK
    u = fakeEEG([40 25 25], {'Interpolated bad channels using spherical splines (pop_interp).'});
    expect(tests, EEGAnalysis.checks({u}, {}, struct('channels', 'Pz')), 'Interpolated channels', 'check', 'but not which');
    expect(tests, EEGAnalysis.checks({fakeEEG([40 25 25])}, {}, struct('channels', 'Pz')), 'Interpolated channels', ...
        'ok', 'No interpolated channel');
end

function testOddInput(tests)
    tests.verifyEmpty(EEGAnalysis.checks({}));
    tests.verifyEmpty(EEGAnalysis.checks(42));
    tests.verifyEmpty(EEGAnalysis.checks({struct('x', 1)}), 'no trials, no labels: no rows');
    e = fakeEEG([40 15 15]);
    Q = EEGAnalysis.checks(e);                                % a struct, no names, no options
    tests.verifyEqual({Q.topic}, {'Trials per condition', 'Condition balance', 'Bad channels', 'Interpolated channels'});
    Q = EEGAnalysis.checks({e, e}, {'only one name'}, struct('rejections', {{[]}}, 'measure', 7, 'channels', 3));
    expect(tests, Q, 'Trials per condition', 'check', 'Target 15 (only one name), Target 15 (participant 2)');
    Q = EEGAnalysis.checks({e}, {}, struct('rejections', struct('conditions', {{'Standard'}}, 'before', [1 2], 'after', 3)));
    expect(tests, Q, 'Trials per condition', 'check', 'Target 15');
    tests.verifyEmpty(row(Q, 'Rejection balance'), 'a rejection info that does not fit is ignored');
    % Checks never change the data
    tests.verifyTrue(isequaln(e, fakeEEG([40 15 15])));
end

function testCleanDemoNoWarnings(tests)
    f = tests.TestData.demo;
    eegs = cellfun(@(p) EEGSource.open(p), {f.scalp.eeglab}, 'UniformOutput', false);
    names = arrayfun(@(k) sprintf('sub-%02d', k), 1:numel(eegs), 'UniformOutput', false);
    Q = EEGAnalysis.checks(eegs, names, struct('measure', 'mean', 'channels', 'Pz'));
    txt = strjoin(QualityChecks.lines(Q), newline);
    tests.verifyEqual(QualityChecks.count(Q, 'warning'), 0, txt);
    expect(tests, Q, 'Trials per condition', 'check', 'below 20 in 8 of 8 participants');
    expect(tests, Q, 'Rejection balance', 'note', 'rejected before loading in 8 participants');
    expect(tests, Q, 'Condition balance', 'ok', 'fine for the mean amplitude');
    expect(tests, Q, 'Bad channels', 'ok', 'No channel marked bad');
    expect(tests, Q, 'Interpolated channels', 'ok', ...
        'T7 was interpolated (in EEGLAB) in 8 participants; not among the measured channels (Pz).');
    % The N1 peak at Cz: unequal trial counts become a Check, still no warnings
    Q = EEGAnalysis.checks(eegs, names, struct('measure', 'peak', 'channels', 'Cz'));
    tests.verifyEqual(QualityChecks.count(Q, 'warning'), 0, strjoin(QualityChecks.lines(Q), newline));
    expect(tests, Q, 'Condition balance', 'check', 'peak amplitude');
end

function testFaultsDemo(tests)
    f = tests.TestData.demo;
    tr = f.truth.faults;
    e = EEGSource.open(f.faults.eeglab);
    tests.verifyEqual(size(e.data), [32 250 70]);
    tests.verifyTrue(any(strcmp(e.history, 'Interpolated channel Pz using spherical splines (pop_interp).')), ...
        strjoin(e.history, ' | '));
    % The 8 noisy or flat channels are suggested, nothing else; without them every trial is rejected
    tests.verifyEqual(EEGAnalysis.suggestBadChannels(e), tr.badChannels);
    tests.verifyNumElements(tr.badChannels, 8);
    tests.verifyError(@() EEGAnalysis.rejectTrials(e, 'PeakToPeak', 100), 'NeuroAnalyzer:eeg:allRejected');
    e = EEGAnalysis.markBad(e, tr.badChannels);
    [ep, info] = EEGAnalysis.rejectTrials(e, 'PeakToPeak', 100);
    tests.verifyEqual(double(info.rejected), double(tr.blinkTrials), 'exactly the blink trials');
    [~, j] = ismember(tr.conditionNames, info.conditions);
    tests.verifyEqual(info.after(j), tr.keptPerCondition);
    % Each check fires
    Q = EEGAnalysis.checks({ep}, {'sub-01_faults'}, struct('rejections', info, 'measure', 'mean', 'channels', 'Pz'));
    expect(tests, Q, 'Trials per condition', 'warning', 'Target 6');
    expect(tests, Q, 'Rejection balance', 'warning', '60% of Target trials but 5% of Standard');
    expect(tests, Q, 'Condition balance', 'ok', '6.3 times');
    expect(tests, Q, 'Bad channels', 'warning', '8 of 32 channels marked bad (25%): F8, FC6, T7, T8, TP9, TP10, PO9 and PO10.');
    expect(tests, Q, 'Interpolated channels', 'warning', 'Pz, the measured channel, was interpolated (in EEGLAB).');
    tests.verifyEqual(QualityChecks.count(Q, 'warning'), 4);
    tests.verifyEqual(QualityChecks.brief(Q), '4 warnings: Trials per condition: Fewest trials in a condition: Target 6.');
    Q = EEGAnalysis.checks({ep}, {}, struct('rejections', info, 'measure', 'peak', 'channels', 'Pz'));
    expect(tests, Q, 'Condition balance', 'check', 'peak amplitude');
end

function testFaultsDemoFile(tests)
    % DemoData 'eegFaults': a copy of the faults participant (an EEGLAB EEG variable in a .mat)
    e = EEGSource.open(DemoData.file('eegFaults'));
    tests.verifyEqual(e.format, 'eeglab');
    tests.verifyEqual(size(e.data), [32 250 70]);
    [names, info] = EEGAnalysis.interpolatedChannels(e);
    tests.verifyEqual(names, {'Pz'});
    tests.verifyEqual(info.where, 'in EEGLAB');
end

function testBatchChecksColumn(tests)
    tests.assumeTrue(exist('OCTAVE_VERSION', 'builtin') == 0, 'Batch.run writes a table (MATLAB)');
    f = tests.TestData.demo;
    p = Batch.completeParams('eeg', struct('suggestBad', true, 'peakToPeak', 100, 'channels', 'Pz', ...
        'windowMs', [300 400], 'baselineMs', [-200 0]));
    R = Batch.run('eeg', {f.faults.eeglab}, p, fullfile(tests.TestData.tmp, 'batch'), 'Name', 'faults');
    S = R.summary;
    tests.verifyEqual(R.nOK, 1, 'the checks do not change the Status');
    tests.verifyEqual(height(S), 3);
    tests.verifyTrue(ismember('Checks', S.Properties.VariableNames));
    tests.verifyEqual(unique(S.Checks), {'4 warnings: Trials per condition: Fewest trials in a condition: Target 6.'});
    tests.verifyEqual(sum(S.Rejected), 12);
    log = fileread(R.paths.log);
    tests.verifyTrue(~isempty(strfind(log, 'checks: 4 warnings: Trials per condition')), log); %#ok<STREMP>
end
