%% EEGAnalysisWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: EEG ANALYSIS WINDOW ON THE DEMO EEG
% =========================================================================
% Drives EEGAnalysisApp through its public methods (no dialogs):
%   demo (8 participants) -> ERPs at Pz -> difference wave and butterfly
%   -> P300 mean amplitude 300-400 ms -> repeated-measures statistics ->
%   N1 peak at Cz -> an edge peak flagged -> export .csv / .mat -> session
%   save / reopen; then the continuous rodent recording cut into trials
%   around its flashes (VEP over V1), a plain .mat file read with the
%   guessed map and the BrainVision copy of the study; a session saved
%   before the cleaning and trial steps existed; then the raw demo
%   (3 continuous BrainVision recordings) cleaned (T7 bad, 0.1-30 Hz,
%   average reference), cut around its markers with a 100 uV rejection
%   that leaves out exactly the blink trials -> P300 -> session. Checks
%   the results against the demo's known answers (core/demo/demoEEG.m)
%   and saves a frame after every step to
%   test-artifacts/screens/walkthrough/EEGAnalysisApp_<NN>_<step>.png.
% Skipped when no display is available.
% =========================================================================

function tests = EEGAnalysisWalkthroughTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'io'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.outDir = fullfile(root, 'test-artifacts', 'screens', 'walkthrough');
    if ~exist(tests.TestData.outDir, 'dir'), mkdir(tests.TestData.outDir); end
    tests.TestData.tmp = tempname;
    mkdir(tests.TestData.tmp);
end

function teardownOnce(tests)
    try, rmdir(tests.TestData.tmp, 's'); catch, end
end

function setup(tests)
    try
        f = uifigure('Visible', 'off'); delete(f); canDraw = true;
    catch
        canDraw = false;
    end
    tests.assumeTrue(canDraw, 'uifigure not available (no display)');
end

%% shot - Save a frame of the app window, optionally after selecting a tab
function shot(tests, app, name, tabTitle)
    if nargin >= 4 && ~isempty(tabTitle)
        tab = findobj(app.UIFig, 'Type', 'uitab', 'Title', tabTitle);
        tests.verifyNotEmpty(tab, sprintf('%s: no tab "%s"', name, tabTitle));
        if ~isempty(tab), tab(1).Parent.SelectedTab = tab(1); end
    end
    drawnow; pause(0.5);
    try
        exportapp(app.UIFig, fullfile(tests.TestData.outDir, [name '.png']));
    catch ME
        warning('EEGAnalysisWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end

%% values - Participants x {Standard, Target, Novel} from the app's measures
function Y = values(app)
    conds = {'Standard', 'Target', 'Novel'};
    Y = nan(numel(app.Measures), 3);
    for p = 1:numel(app.Measures)
        r = app.Measures{p};
        [~, j] = ismember(conds, {r.condition});
        Y(p, :) = [r(j).value];
    end
end

function testEEGDemo(tests)
    app = EEGAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyEqual(HelpApp.demoWindow('EEG Analysis'), 'EEGAnalysisApp');
    tests.verifyEqual(char(app.ShowBtn.Enable), 'off');

    % 1. Demo: 8 participants, already cut into trials; the Overview lists what was done
    tests.verifyTrue(logical(app.loadDemo()));
    tests.verifyNumElements(app.EEGs, 8);
    tests.verifyEqual(app.Generator, 'demoEEG');
    tests.verifyEqual(size(app.EEGs{1}.data), [32 250 65]);
    tests.verifyEqual(app.ParticipantDrop.Items{1}, app.GrandLabel);
    tests.verifyNumElements(app.ParticipantDrop.Items, 9);
    tests.verifyEqual(app.CutBtn.Text, 'Apply rejection', 'nothing to cut, only trials to reject');
    tests.verifyEqual(char(app.EventsEdit.Enable), 'off');
    tests.verifyEqual(char(app.TrialFromEdit.Enable), 'off');
    tests.verifyEqual(char(app.ShowBtn.Enable), 'on');
    tests.verifyEqual(char(app.MeasureBtn.Enable), 'off');
    ov = strjoin(app.OverviewText.Value(:)', newline);
    tests.verifyTrue(contains(ov, 'Already done to the data'));
    tests.verifyTrue(contains(ov, 'Band-pass filtered 0.1 to 30 Hz'));
    tests.verifyTrue(contains(ov, 'Trials per condition'));
    shot(tests, app, 'EEGAnalysisApp_01_demo_loaded', 'Overview');

    % 2. ERPs at Pz with the baseline -200 to 0 ms (the demo sets the channel)
    tests.verifyEqual(app.ChannelsEdit.Value, 'Pz');
    tests.verifyTrue(logical(app.showERPs()));
    tests.verifyNumElements(app.ERPs, 8);
    tests.verifyEqual(sort(app.Grand.conditions), {'Novel', 'Standard', 'Target'});
    tests.verifyEqual(app.Grand.n, [8 8 8], 'every participant once');
    tests.verifyEqual(sum(app.Grand.trials), 8 * 65);
    tests.verifyEqual(app.ERPSettings.baseline, [-0.2 0], 'AbsTol', 1e-12);
    pz = strcmp(app.Grand.labels, 'Pz');
    [~, i] = max(app.Grand.mean(pz, :, strcmp(app.Grand.conditions, 'Target')));
    tests.verifyEqual(app.Grand.times(i), 0.35, 'AbsTol', 0.03, 'grand-average P300 near 350 ms');
    tests.verifyTrue(contains(app.ErpInfo.Text, '8 participants'));
    tests.verifyEqual(char(app.MeasureBtn.Enable), 'on');
    shot(tests, app, 'EEGAnalysisApp_02_erps');

    % 3. Difference wave Target minus Standard, and the butterfly of one participant
    app.setView('grand', 'Difference wave', 'Target', 'Standard');
    tests.verifyEqual(char(app.CondBDrop.Enable), 'on');
    tests.verifyTrue(contains(app.AxERP.Title.String, 'Target minus Standard'));
    shot(tests, app, 'EEGAnalysisApp_03_difference');
    app.setView(2, 'All channels (butterfly)', 'Target');
    tests.verifyEqual(char(app.CondBDrop.Enable), 'off');
    tests.verifyGreaterThanOrEqual(numel(findobj(app.AxERP, 'Type', 'line')), 1);
    shot(tests, app, 'EEGAnalysisApp_04_butterfly');
    app.setView('grand', 'Conditions');

    % 4. P300: mean amplitude 300-400 ms at Pz (the demo's settings)
    tests.verifyTrue(logical(app.measure()));
    Y = values(app);
    tests.verifySize(Y, [8 3]);
    tests.verifyTrue(all(Y(:, 2) > Y(:, 3)), 'Target > Novel in every participant');
    tests.verifyTrue(all(Y(:, 3) > Y(:, 1)), 'Novel > Standard in every participant');
    tests.verifyEqual(mean(Y), [1.5 7 4], 'AbsTol', 1.5, 'about 1.5, 7 and 4 uV (Help)');
    tests.verifySize(app.MeasuresTable.Data, [24 6]);
    tests.verifyNumElements(findall(app.AxERP, 'Type', 'line'), 3, 'one line per condition, no butterfly left over');
    tests.verifyEqual(app.MeasuresTable.Data(1:3, 2)', app.Grand.conditions, 'conditions in the order of the ERPs');
    tests.verifyEqual(app.MeasuresTable.Data(4:6, 2)', app.Grand.conditions);
    tests.verifyEqual(app.MeasureInfo.Text, 'Mean amplitude from 300 to 400 ms, at Pz.');
    tests.verifyEqual(char(app.StatsBtn.Enable), 'on');
    tests.verifyEqual(char(app.ExportBtn.Enable), 'on');
    shot(tests, app, 'EEGAnalysisApp_05_measured', 'Measures');

    % 5. Statistics: repeated-measures ANOVA, every pair different; Friedman
    tests.verifyTrue(logical(app.compareConditions()));
    r = app.StatsResult;
    tests.verifyEqual(r.design, 'rm');
    tests.verifyLessThan(r.main.p, 0.001);
    tests.verifySize(app.StatsTable.Data, [3 5]);
    tests.verifyTrue(all([r.comparisons.p] < 0.05), 'every pair differs');
    tests.verifyTrue(contains(app.StatsText.Value{1}, 'Repeated-measures ANOVA'));
    shot(tests, app, 'EEGAnalysisApp_06_statistics', 'Statistics');
    app.setStatsMethod('nonparametric');
    tests.verifyTrue(logical(app.compareConditions()));
    tests.verifyTrue(startsWith(app.StatsResult.main.test, 'Friedman'));
    tests.verifyLessThan(app.StatsResult.main.p, 0.01);
    app.setStatsMethod('parametric');

    % 6. N1: negative peak 50-150 ms at Cz; then a window that cuts the P300 slope
    app.setMeasure('peak', 'negative', [0.05 0.15], {'Cz'});
    tests.verifyEqual(char(app.PolarityDrop.Enable), 'on');
    tests.verifyTrue(logical(app.measure()));
    for p = 1:8
        rr = app.Measures{p};
        tests.verifyTrue(all([rr.value] < -2), sprintf('N1 negative, participant %d', p));
        tests.verifyEqual([rr.latency], repmat(0.1, 1, 3), 'AbsTol', 0.025, sprintf('N1 latency, participant %d', p));
        tests.verifyFalse(any([rr.atEdge]));
    end
    tests.verifyEmpty(app.StatsResult, 'a new measure clears the old test');
    app.setMeasure('peak', 'positive', [0.2 0.3], {'Pz'});
    tests.verifyTrue(logical(app.measure()));
    tests.verifyTrue(contains(app.MeasureInfo.Text, 'on the edge of the window'));
    tests.verifyTrue(any(strcmp(app.MeasuresTable.Data(:, 6), 'Peak on the window edge')));
    shot(tests, app, 'EEGAnalysisApp_07_edge_peak', 'Measures');

    % Back to the P300 for the export and the session
    app.setMeasure('mean', 'positive', [0.3 0.4], {'Pz'});
    tests.verifyTrue(logical(app.measure()));
    tests.verifyTrue(logical(app.compareConditions()));

    % 7. Export .csv (one row per participant and condition) and .mat
    csvPath = fullfile(tests.TestData.tmp, 'eeg_measures.csv');
    tests.verifyTrue(logical(app.exportResultsTo(csvPath)));
    lines = strsplit(strtrim(fileread(csvPath)), newline);
    tests.verifyNumElements(lines, 25);   % header + 8 participants x 3 conditions
    tests.verifyTrue(startsWith(lines{1}, '"Participant","Condition","Value_uV"'));
    matPath = fullfile(tests.TestData.tmp, 'eeg.mat');
    tests.verifyTrue(logical(app.exportResultsTo(matPath)));
    m = load(matPath);
    tests.verifySize(m.results.measures, [24 6]);
    tests.verifyEqual(m.results.stats.design, 'rm');

    % 8. Session: save, reopen in a new window, same values and test
    tests.verifyEqual(char(app.SessionBtns.Save.Enable), 'on');
    p = fullfile(tests.TestData.tmp, ['EEGAnalysisApp' Session.Extension]);
    tests.verifyTrue(logical(app.saveSessionTo(p, 'EEG walkthrough: demo P300')));
    s = Session.load(p);
    [txt, ~] = MethodsWriter.fromSession(s);
    tests.verifyTrue(contains(txt, 'the mean amplitude from 300 to 400 ms at Pz was measured'));
    b = EEGAnalysisApp(); cb = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)), 'session not reopened');
    tests.verifyEqual(values(b), values(app), 'AbsTol', 1e-9);
    tests.verifyEqual(b.StatsResult.summary, app.StatsResult.summary);
    tests.verifyEqual(b.MeasuresTable.Data, app.MeasuresTable.Data);
    shot(tests, b, 'EEGAnalysisApp_08_session_reopened');
end

function testRodentContinuousAndPlainMat(tests)
    DemoData.ensureDemoPath();
    f = demoEEG();
    app = EEGAnalysisApp(); c = onCleanup(@() delete(app.UIFig));

    % Continuous rodent recording: cut into trials around the 30 flashes
    tests.verifyTrue(logical(app.openFiles({f.rodent.eeglab})));
    tests.verifyEmpty(app.EEGs, 'continuous: not analysable before cutting');
    tests.verifyEqual(char(app.CutBtn.Enable), 'on');
    tests.verifyEqual(char(app.ShowBtn.Enable), 'off');
    tests.verifyFalse(logical(app.showERPs()), 'ERPs need trials');
    app.setTrialWindow([-0.1 0.4]);
    tests.verifyTrue(logical(app.cutIntoTrials()));
    tests.verifyEqual(size(app.EEGs{1}.data), [4 501 30]);
    tests.verifyEqual(app.BaselineFromEdit.Value, -100, 'baseline starts with the trial');
    tests.verifyTrue(contains(strjoin(app.OverviewText.Value(:)', newline), 'Cut into 30 trials'));
    app.setBaseline(true, [-0.1 0]);
    app.setChannels({'V1-L', 'V1-R'});
    tests.verifyTrue(logical(app.showERPs()));
    tests.verifyEmpty(app.Grand, 'one participant: no grand average');
    tests.verifyNumElements(app.ParticipantDrop.Items, 1);
    app.setMeasure('peak', 'negative', [0.03 0.07], {});
    tests.verifyTrue(logical(app.measure()));
    r = app.Measures{1};
    tests.verifyLessThan(r.value, -25, 'VEP negative peak over V1');
    tests.verifyEqual(r.latency, 0.05, 'AbsTol', 0.006);
    tests.verifyEqual(r.n, 30);
    yl = app.AxERP.YLim;
    tests.verifyTrue(yl(1) < r.value && yl(2) > 10, 'the y axis shows the whole VEP');
    tests.verifyEqual(char(app.StatsBtn.Enable), 'off', 'statistics need two participants');
    shot(tests, app, 'EEGAnalysisApp_09_rodent_vep');

    % Session of a continuous recording: the trials are cut again on reopening
    p = fullfile(tests.TestData.tmp, ['EEGAnalysisRodent' Session.Extension]);
    tests.verifyTrue(logical(app.saveSessionTo(p, 'rodent')));
    b = EEGAnalysisApp(); cb = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)));
    tests.verifyEqual(b.TrialWindow, [-0.1 0.4], 'AbsTol', 1e-12);
    tests.verifyEqual(b.Measures{1}.value, r.value, 'AbsTol', 1e-9);

    % A session saved before steps 2 and 3 existed (no cleaning / trials settings) still reopens
    s = Session.load(p);
    s.settings = rmfield(s.settings, {'cleaning', 'trials'});
    o = EEGAnalysisApp(); co = onCleanup(@() delete(o.UIFig));
    tests.verifyTrue(logical(o.restoreSession(s)), 'older session not restored');
    tests.verifyEqual(o.TrialWindow, [-0.1 0.4], 'AbsTol', 1e-12);
    tests.verifyEmpty(o.Cleaned);
    tests.verifyEmpty(o.Rejections);
    tests.verifyEqual(o.Measures{1}.value, r.value, 'AbsTol', 1e-9);
    delete(co);

    % A plain .mat file: the guessed map is used and kept
    tests.verifyTrue(logical(app.openFiles({f.scalp(1).matrix, f.scalp(2).matrix})));
    tests.verifyEqual(app.Maps{1}.data, 'eeg');
    tests.verifyEqual(app.Maps{1}.dims, {'trial', 'channel', 'time'});
    tests.verifyEqual(size(app.EEGs{2}.data), [32 250 65]);
    tests.verifyEmpty(app.ChannelsEdit.Value, 'the rodent channels are not in the scalp files');
    tests.verifyEmpty(app.MeasureChannelsEdit.Value);
    tests.verifyTrue(logical(app.showERPs()));
    tests.verifyNumElements(app.Grand.conditions, 3);
    shot(tests, app, 'EEGAnalysisApp_10_plain_mat', 'Overview');

    % BrainVision (Analyzer export): the same study, conditions from the markers at time 0
    tests.verifyTrue(logical(app.openFiles({f.scalp(1).brainvision, f.scalp(2).brainvision})));
    tests.verifyEqual(size(app.EEGs{1}.data), [32 250 65]);
    tests.verifyTrue(contains(strjoin(app.OverviewText.Value(:)', newline), 'BrainVision'));
    app.setChannels({'Pz'});
    tests.verifyTrue(logical(app.showERPs()));
    tests.verifyEqual(sort(app.Grand.conditions), {'Novel', 'Standard', 'Target'});
end

function testRawDemoCleaning(tests)
    DemoData.ensureDemoPath();
    f = demoEEG();
    truth = f.truth.raw.participants;      % the cached manifest keeps blinkTrials (not the data)
    app = EEGAnalysisApp(); c = onCleanup(@() delete(app.UIFig));

    % 1. Raw demo: 3 continuous recordings; the suggested settings are filled in, nothing is applied
    tests.verifyTrue(logical(app.loadRawDemo()));
    tests.verifyEqual(app.Generator, 'demoEEGraw');
    tests.verifyNumElements(app.Loaded, 3);
    tests.verifyFalse(app.Loaded{1}.isEpoched);
    tests.verifyEqual(app.Loaded{1}.fs, 500);
    tests.verifyEmpty(app.Cleaned, 'the settings are not applied yet');
    tests.verifyEmpty(app.EEGs);
    tests.verifyEqual(app.CleanParticipantDrop.Items, app.Names);
    tests.verifyEqual(app.CutBtn.Text, 'Cut into trials');
    tests.verifyEqual(char(app.EventsEdit.Enable), 'on');
    tests.verifyEqual(char(app.ReferenceChannelsEdit.Enable), 'off', 'only for Reference = Channels');
    tests.verifyEqual(char(app.ShowBtn.Enable), 'off');
    tests.verifyTrue(contains(app.StatusLabel.Text, 'Apply (step 2)'));

    % 2. Suggest: T7 (noisy) in every participant
    for p = 1:3
        tests.verifyEqual(app.suggestBadChannels(p), {'T7'}, sprintf('suggested bad channels, participant %d', p));
        tests.verifyEqual(app.BadChannels{p}, {'T7'});
    end
    tests.verifyEqual(app.CleanParticipantDrop.Value, app.Names{3});
    tests.verifyEqual(app.BadEdit.Value, 'T7');
    tests.verifyTrue(contains(app.StatusLabel.Text, 'robust z-scores'), 'the status says how T7 was found');

    % 3. Band-pass 0.1-30 Hz, no notch, average reference (without T7)
    app.setFilters(0.1, 30, 'off');
    app.setReference('average');
    tests.verifyTrue(logical(app.applyCleaning()));
    tests.verifyNumElements(app.Cleaned, 3);
    tests.verifyEmpty(app.EEGs, 'the recordings are cut again after cleaning');
    for p = 1:3
        e = app.Cleaned{p};
        tests.verifyEqual(e.labels(EEGAnalysis.badChannels(e)), {'T7'});
        tests.verifyTrue(startsWith(e.reference, 'average of the 31 good channels'));
    end
    tests.verifyNumElements(app.CleanSettings.filterText, 1);
    tests.verifyTrue(startsWith(app.CleanSettings.filterText{1}, 'Band-pass filter 0.1-30 Hz'));
    tests.verifyEmpty(app.CleanSettings.notchFreqs);
    ov = strjoin(app.OverviewText.Value(:)', newline);
    tests.verifyTrue(contains(ov, 'Bad channels: T7'));
    tests.verifyTrue(contains(ov, 'Band-pass filter 0.1-30 Hz'));
    tests.verifyTrue(contains(ov, 'Re-referenced to the average'));
    shot(tests, app, 'EEGAnalysisApp_11_raw_cleaned', 'Overview');

    % 4. Trials around S 1 / S 2 / S 3, rejected above 100 uV peak-to-peak: exactly the blink trials
    app.setEvents('S 1 = Standard, S 2 = Target, S 3 = Novel');
    app.setTrialWindow([-0.2 0.8]);
    app.setRejection(true, 100, 0);
    tests.verifyEqual(char(app.PeakToPeakEdit.Enable), 'on');
    tests.verifyTrue(logical(app.cutIntoTrials()));
    tests.verifyNumElements(app.Rejections, 3);
    for p = 1:3
        tests.verifyEqual(app.Rejections(p).total, 70, sprintf('trials before rejection, participant %d', p));
        tests.verifyEqual(double(app.Rejections(p).rejected), double(truth(p).blinkTrials(:)'), ...
            sprintf('rejected = blink trials, participant %d', p));
        tests.verifyEqual(size(app.EEGs{p}.data, 3), 62);
        tests.verifyEqual(sort(app.EEGs{p}.conditions), {'Novel', 'Standard', 'Target'});
    end
    tests.verifyEqual(size(app.EEGs{1}.data, 2), 501, '-200 to 800 ms at 500 Hz');
    tests.verifyEqual(app.TrialWindow, [-0.2 0.8], 'AbsTol', 1e-12);
    tests.verifyTrue(contains(app.CutInfo.Text, 'Cut from -200 to 800 ms: 70, 70, 70 trials.'));
    tests.verifyTrue(contains(app.CutInfo.Text, 'Rejected 24 of 210'));
    tests.verifyTrue(contains(app.CutInfo.Text, 'most often on Fp'));
    tests.verifyTrue(contains(app.CutInfo.Text, '62, 62, 62 kept.'));
    tests.verifyEqual(app.BaselineFromEdit.Value, -200);
    shot(tests, app, 'EEGAnalysisApp_12_raw_trials');

    % 5. ERPs; a chosen channel that is bad gives a plain message instead of a plot
    app.setChannels({'T7'});
    tests.verifyTrue(logical(app.showERPs()));
    tests.verifyTrue(contains(app.StatusLabel.Text, 'marked bad'), 'only T7 chosen, and it is bad');
    app.setChannels({'Pz'});
    tests.verifyTrue(logical(app.showERPs()));
    tests.verifyEqual(app.Grand.n, [3 3 3]);
    tests.verifyEqual(sort(app.Grand.conditions), {'Novel', 'Standard', 'Target'});
    tests.verifyTrue(all(isnan(app.ERPs{1}.mean(strcmp(app.ERPs{1}.labels, 'T7'), :, 1))), 'T7 left out');
    app.setView(2, 'All channels (butterfly)', 'Target');
    tests.verifyNumElements(findall(app.AxERP, 'Type', 'line'), 32, '31 good channels and Pz, no line for T7');
    app.setView('grand', 'Conditions');

    % 6. P300 at Pz, 300-400 ms: Target > Novel > Standard on the grand average
    app.setMeasure('mean', 'positive', [0.3 0.4], {'Pz'});
    tests.verifyTrue(logical(app.measure()));
    Y = values(app);
    tests.verifySize(Y, [3 3]);
    m = mean(Y, 1);
    tests.verifyGreaterThan(m(2), m(3), 'Target > Novel');
    tests.verifyGreaterThan(m(3), m(1), 'Novel > Standard');
    for p = 1:3
        tests.verifyEqual(sum([app.Measures{p}.n]), 62, sprintf('trials measured, participant %d', p));
    end
    shot(tests, app, 'EEGAnalysisApp_13_raw_p300', 'Measures');

    % 7. Session: the cleaning, trials and rejection are replayed
    p = fullfile(tests.TestData.tmp, ['EEGAnalysisRaw' Session.Extension]);
    tests.verifyTrue(logical(app.saveSessionTo(p, 'EEG walkthrough: raw demo')));
    s = Session.load(p);
    cl = s.settings.cleaning;
    tests.verifyTrue(cl.applied);
    tests.verifyEqual(cl.bad, {{'T7'}, {'T7'}, {'T7'}});
    tests.verifyEqual([cl.highPass cl.lowPass], [0.1 30]);
    tests.verifyEqual(cl.notch, 'off');
    tests.verifyEqual(cl.referenceMode, 'average');
    tests.verifyNumElements(cl.filterText, 1);
    tr = s.settings.trials;
    tests.verifyTrue(tr.cut);
    tests.verifyTrue(tr.reject);
    tests.verifyEqual(tr.peakToPeak, 100);
    tests.verifyEqual(tr.rename, {'S 1', 'Standard'; 'S 2', 'Target'; 'S 3', 'Novel'});
    tests.verifyEqual(tr.window, [-0.2 0.8], 'AbsTol', 1e-12);
    tests.verifyEqual(s.settings.trialWindow, [-0.2 0.8], 'AbsTol', 1e-12);
    tests.verifyTrue(startsWith(s.settings.reference, 'average of the 31 good channels'));
    tests.verifyEqual(s.settings.recordedReference, 'channel FCz');
    tests.verifyNumElements(s.results.rejection, 3);
    tests.verifyEqual([s.results.rejection.kept], [62 62 62]);
    % Methods text: recorded against FCz, then cleaned here (not as steps done before the window)
    txt = MethodsWriter.fromSession(s);
    tests.verifyTrue(contains(txt, 'referenced to the channel FCz.'));
    tests.verifyTrue(contains(txt, 'They were re-referenced offline to the average of the 31 good channels'));
    tests.verifyFalse(contains(txt, 'earlier processing steps'), 'steps of the window listed as earlier steps');
    tests.verifyFalse(contains(txt, 'cleaned before the analysis'));
    b = EEGAnalysisApp(); cb = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)), 'session not reopened');
    tests.verifyEqual(b.Generator, 'demoEEGraw');
    tests.verifyEqual({b.Rejections.rejected}, {app.Rejections.rejected});
    tests.verifyEqual([b.Rejections.kept], [app.Rejections.kept]);
    tests.verifyEqual(values(b), values(app), 'AbsTol', 1e-9);
    shot(tests, b, 'EEGAnalysisApp_14_raw_session_reopened');
    delete(cb);

    % 8. Without T7 marked bad, every trial exceeds 100 uV on T7: a plain error and no trials
    for p = 1:3, app.setBadChannels(app.Names{p}, {}); end
    app.setFilters(0.1, 0, 50);
    app.setReference('linked mastoids');
    tests.verifyTrue(logical(app.applyCleaning()));
    tests.verifyEqual(app.CleanSettings.notchFreqs, [50 100 150 200], 'harmonics below 249 Hz');
    tests.verifyTrue(contains(app.Cleaned{1}.reference, 'TP9 and TP10'));
    tests.verifyFalse(logical(app.cutIntoTrials()));
    tests.verifyEmpty(app.EEGs);
    tests.verifyTrue(startsWith(app.StatusLabel.Text, [char(10007) ' Not cut into trials']));
    tests.verifyTrue(contains(app.StatusLabel.Text, 'T7'));

    % 9. Cut without Apply: the bad channels of step 2 still count
    tests.verifyTrue(logical(app.loadRawDemo()));
    tests.verifyEqual(app.NotchDrop.Value, app.NotchItems{1}, 'the notch of step 8 is not kept');
    app.setRejection(false);
    tests.verifyTrue(logical(app.cutIntoTrials()));
    tests.verifyEmpty(app.Cleaned);
    for p = 1:3
        tests.verifyEqual(app.EEGs{p}.labels(EEGAnalysis.badChannels(app.EEGs{p})), {'T7'});
        tests.verifyEqual(size(app.EEGs{p}.data, 3), 70);
    end

    % 10. Other files start from the default settings of steps 2 and 3
    tests.verifyTrue(logical(app.loadDemo()));
    tests.verifyEqual([app.HighPassEdit.Value app.LowPassEdit.Value], [0 0], 'already cut into trials: no filter');
    tests.verifyEqual(app.NotchDrop.Value, app.NotchItems{1});
    tests.verifyEqual(app.ReferenceDrop.Value, app.ReferenceModes{1});
    tests.verifyEmpty(app.EventsEdit.Value);
    tests.verifyFalse(logical(app.RejectCb.Value));
    tests.verifyEqual(app.PeakToPeakEdit.Value, 100);
end
