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
%   that leaves out exactly the blink trials -> P300 -> session; then the
%   electrode layout: the demo's positions from the files, the Electrode
%   layout dialog (drawing, table, By name, Cancel), every channel by name
%   on the 10-5 system, a positions file that calls T7 by its old name T3,
%   a channel placed by hand, Use this layout (confirmed) -> session, and
%   the rodent's skull layout in mm from bregma; then scalp maps (P300
%   window, N1 at 100 ms, one participant, a session, the rodent's flat
%   map, a file without positions); then the time-frequency of step 7
%   (ERSP of the alpha decrease after Target at Oz, ITPC at the N1 over
%   Cz, alpha band power, a session, the raw demo cut into longer
%   trials). Checks the results
%   against the demo's known answers (core/demo/demoEEG.m) and saves a
%   frame after every step to
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

%% shotDialog - Save a frame of a dialog window (e.g. the Electrode layout dialog)
function shotDialog(tests, fig, name)
    drawnow; pause(0.5);
    try
        exportapp(fig, fullfile(tests.TestData.outDir, [name '.png']));
    catch ME
        warning('EEGAnalysisWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end

%% press - Click a button: run its ButtonPushedFcn
function press(b)
    fcn = b.ButtonPushedFcn;
    fcn(b, []);
    drawnow;
end

%% choose - Pick an item of a dropdown: set it and run its ValueChangedFcn
function choose(dd, value)
    dd.Value = value;
    fcn = dd.ValueChangedFcn;
    fcn(dd, []);
    drawnow;
end

%% editCell - Type a value into a table cell: set it and run its CellEditCallback
function editCell(tbl, ij, value)
    prev = tbl.Data{ij(1), ij(2)};
    d = tbl.Data;
    d{ij(1), ij(2)} = value;
    tbl.Data = d;
    fcn = tbl.CellEditCallback;
    fcn(tbl, struct('Indices', ij, 'DisplayIndices', ij, 'PreviousData', prev, 'EditData', value, ...
        'NewData', value, 'Error', ''));
    drawnow;
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
    tests.verifyEqual(app.ChannelsEdit.Value, 'Pz', 'the rodent channels are not in the scalp files: a midline channel');
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

function testElectrodeLayout(tests)
    DemoData.ensureDemoPath();
    f = demoEEG();
    sc = f.truth.scalp;
    u = sc.posRAS ./ sqrt(sum(sc.posRAS .^ 2, 2));     % the demo's directions (x = right ear, y = nose, z = up)
    [tl, tp] = EEGLayout.template();
    notChecked = [' Not checked yet: open Electrode layout' char(8230) ' to look at it.'];
    app = EEGAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyEqual(char(app.LayoutBtn.Enable), 'off', 'nothing loaded yet');
    tests.verifyEmpty(app.openLayout(), 'no layout dialog without data');

    % 1. Demo: the 32 positions of the EEGLAB files, turned to x = right ear, y = nose; not confirmed
    tests.verifyTrue(logical(app.loadDemo()));
    L = app.Layout;
    tests.verifyEqual(L.kind, 'scalp');
    tests.verifyEqual(L.labels, sc.labels);
    tests.verifyEqual(L.source, repmat({'file'}, 1, 32), 'all 32 from the file');
    tests.verifyEqual(L.pos, u, 'AbsTol', 1e-9);
    tests.verifyEqual(L.summary, '32 of 32 channels placed: 32 from the file.');
    tests.verifyTrue(startsWith(L.frame, 'EEGLAB (x = nose, y = left ear, z = up), turned to x = right ear'));
    tests.verifyFalse(L.confirmed);
    tests.verifyEqual(app.LayoutSettings.source, 'auto');
    tests.verifyEmpty(app.LayoutSettings.positionsFile);
    tests.verifyEmpty(app.LayoutSettings.edits);
    tests.verifyEqual(app.LayoutInfo.Text, [L.summary notChecked]);
    tests.verifyEqual(char(app.LayoutBtn.Enable), 'on');
    ov = strjoin(app.OverviewText.Value(:)', newline);
    tests.verifyTrue(startsWith(ov, sprintf('Electrode layout (from the first participant, %s):', app.Names{1})));
    tests.verifyTrue(contains(ov, ['   ' L.summary]));
    tests.verifyTrue(contains(ov, 'Positions: EEGLAB (x = nose, y = left ear, z = up), turned to'));
    tests.verifyFalse(contains(ov, 'Electrode positions for'), 'the layout replaces the position sentence of each file');

    % 2. The dialog: the drawing (head, nose, ears and 32 electrodes), the table and the summary
    fig = app.openLayout();
    tests.verifyTrue(isvalid(fig));
    tests.verifySameHandle(app.LayoutFig, fig);
    tests.verifyEqual(char(fig.WindowStyle), 'normal', 'not modal');
    d = app.LayoutDlg;
    tests.verifyEqual(d.SourceDrop.Items, app.LayoutSources);
    tests.verifyEqual(d.SourceDrop.Value, 'From the files, others by name');
    tests.verifyEqual(d.Table.ColumnName(:)', {'Channel', 'Placed from', 'As', 'Status'});
    tests.verifyEqual(logical(d.Table.ColumnEditable), [false false true false], 'only As is editable');
    tests.verifySize(d.Table.Data, [32 4]);
    tests.verifyEqual(d.Table.Data(:, 1)', sc.labels);
    tests.verifyEqual(unique(d.Table.Data(:, 2))', {'file'});
    tests.verifyEqual(d.Table.Data(:, 3)', sc.labels, 'the 10-5 name of each channel');
    tests.verifyEqual(unique(d.Table.Data(:, 4))', {'placed'});
    tests.verifyEqual(d.Text.Value{1}, L.summary);
    tests.verifyNumElements(findall(d.Axes, 'Type', 'line'), 5, 'head, nose, two ears and one set of electrodes');
    el = findall(d.Axes, 'Type', 'line', '-regexp', 'Tag', '^EEGLayout:');
    tests.verifyEqual(sum(arrayfun(@(h) numel(h.XData), el)), 32, 'every electrode drawn');
    tests.verifyNumElements(findobj(d.Axes, 'Type', 'text'), 32, 'one name per electrode');
    shotDialog(tests, fig, 'EEGAnalysisApp_15_layout_dialog');

    % 3. By name (10-5 system) in the dialog: shown at once, not used before Use this layout; Cancel
    choose(d.SourceDrop, 'By name (10-5 system)');
    tests.verifyEqual(app.LayoutDlg.L.summary, '32 of 32 channels placed: 32 by name (10-5 system).');
    tests.verifyEqual(unique(d.Table.Data(:, 2))', {'name (10-5)'});
    tests.verifyEqual(app.Layout.summary, '32 of 32 channels placed: 32 from the file.', 'only a preview');
    shotDialog(tests, fig, 'EEGAnalysisApp_16_layout_by_name');
    press(d.CancelBtn);
    tests.verifyFalse(isvalid(fig), 'Cancel closes the dialog');
    tests.verifyEmpty(app.LayoutFig);
    tests.verifyEqual(app.LayoutSettings.source, 'auto', 'Cancel keeps the layout');
    tests.verifyFalse(app.Layout.confirmed);

    % 4. Every channel by name: the 32 actiCAP names are all 10-5 positions
    tests.verifyTrue(all(ismember(sc.labels, tl)), 'the demo names are 10-5 names');
    tests.verifyTrue(logical(app.setLayout('Source', 'template')));
    L = app.Layout;
    [~, i] = ismember(L.labels, tl);
    tests.verifyEqual(L.source, repmat({'template'}, 1, 32));
    tests.verifyEqual(L.as, L.labels);
    tests.verifyEqual(L.pos, tp(i, :), 'AbsTol', 1e-12);
    tests.verifyEqual(L.summary, '32 of 32 channels placed: 32 by name (10-5 system).');
    tests.verifyEmpty(L.check.renamed);
    tests.verifyFalse(L.confirmed);
    tests.verifyEqual(app.LayoutInfo.Text, [L.summary notChecked]);

    % 5. A positions file (ASA .elc, mm) that names T7 by its old 10-20 name T3
    lab = sc.labels;
    lab{strcmp(lab, 'T7')} = 'T3';
    pf = fullfile(tests.TestData.tmp, 'actiCAP_T3.elc');
    writeElectrodes(pf, lab, sc.posRAS, 'Unit', 'mm');
    tests.verifyTrue(logical(app.setLayout('PositionsFile', pf)));
    L = app.Layout;
    tests.verifyEqual(app.LayoutSettings.source, 'auto', 'a positions file replaces By name');
    tests.verifyEqual(app.LayoutSettings.positionsFile, pf);
    tests.verifyEqual(app.LayoutPositions.format, 'ASA .elc');
    tests.verifyEqual(L.source, repmat({'positions file'}, 1, 32));
    tests.verifyEqual(L.summary, '32 of 32 channels placed: 32 from the positions file.');
    tests.verifyEqual(L.check.renamed, {'T7', 'T3'}, 'channel T7 took the position named T3 (its old name)');
    t7 = find(strcmp(L.labels, 'T7'));
    tests.verifyEqual(L.status{t7}, 'renamed');
    tests.verifyEqual(L.pos, u, 'AbsTol', 1e-6, 'the same places as the positions in the recording files');
    tests.verifyTrue(contains(strjoin(EEGLayout.describe(L), newline), 'T7 placed at T3 of the positions file'));
    % a file that is not there: a plain message and the layout unchanged
    tests.verifyFalse(logical(app.setLayout('PositionsFile', fullfile(tests.TestData.tmp, 'none.elc'))));
    tests.verifyTrue(startsWith(app.StatusLabel.Text, [char(10007) ' Electrode layout not changed: File not found']));
    tests.verifyEqual(app.LayoutSettings.positionsFile, pf);

    % 6. T7 placed by hand on FT7 in the table (As), then a name that is not a 10-5 position (refused)
    fig = app.openLayout();
    d = app.LayoutDlg;
    tests.verifyEqual(d.SourceDrop.Value, 'From a positions file');
    tests.verifyEqual(d.Text.Value{1}, 'Positions file: actiCAP_T3.elc');
    tests.verifyEqual(d.Table.Data{t7, 4}, ['renamed (T7 ' char(8594) ' T3)']);
    editCell(d.Table, [t7 3], 'FT7');
    D = app.LayoutDlg.L;
    tests.verifyEqual(D.summary, '32 of 32 channels placed: 31 from the positions file, 1 placed by hand.');
    mid = L.pos(strcmp(L.labels, 'F7'), :) + L.pos(t7, :);
    tests.verifyLessThan(acosd(D.pos(t7, :) * mid' / norm(mid)), 3, 'FT7 on this head: half-way from F7 to T7');
    tests.verifyEqual(d.Table.Data(t7, 2:4), {'by hand', 'FT7', 'placed'});
    tests.verifyEqual(app.Layout.summary, '32 of 32 channels placed: 32 from the positions file.', 'not used yet');
    editCell(d.Table, [t7 3], 'XYZ');
    tests.verifyEqual(d.Table.Data{t7, 3}, 'FT7', 'the table shows the layout before the refused name');
    tests.verifyTrue(contains(d.Message.Text, '''XYZ'' is not a position of the 10-5 system'));
    shotDialog(tests, fig, 'EEGAnalysisApp_17_layout_edited');

    % 7. Use this layout: used, confirmed, the dialog closed
    press(d.UseBtn);
    tests.verifyFalse(isvalid(fig), 'Use this layout closes the dialog');
    L = app.Layout;
    tests.verifyTrue(L.confirmed);
    tests.verifyTrue(app.LayoutSettings.confirmed);
    tests.verifyEqual(L.summary, '32 of 32 channels placed: 31 from the positions file, 1 placed by hand.');
    tests.verifyEqual(L.source{t7}, 'edited');
    tests.verifyEmpty(L.check.renamed, 'T7 placed by hand is no longer renamed');
    E = app.LayoutSettings.edits;
    tests.verifyNumElements(E, 1);
    tests.verifyEqual({E.label, E.as}, {'T7', 'FT7'});
    tests.verifyTrue(isnan(E.ap) && isnan(E.ml));
    tests.verifyEqual(app.LayoutInfo.Text, [L.summary ' Confirmed.']);
    tests.verifyTrue(contains(app.StatusLabel.Text, 'Electrode layout confirmed'));
    tests.verifyTrue(contains(strjoin(app.OverviewText.Value(:)', newline), 'Positions: positions file (ASA .elc)'));
    shot(tests, app, 'EEGAnalysisApp_18_layout_confirmed', 'Overview');

    % 8. Session: settings.layout, the positions file among the inputs; reopened with the same layout
    p = fullfile(tests.TestData.tmp, ['EEGAnalysisLayout' Session.Extension]);
    tests.verifyTrue(logical(app.saveSessionTo(p, 'EEG walkthrough: electrode layout')));
    s = Session.load(p);
    ly = s.settings.layout;
    tests.verifyEqual(sort(fieldnames(ly))', sort({'source', 'positionsFile', 'edits', 'confirmed', 'kind', ...
        'counts', 'renamed', 'frame', 'format', 'summary'}));
    tests.verifyEqual(ly.source, 'auto');
    tests.verifyEqual(ly.positionsFile, pf);
    tests.verifyTrue(ly.confirmed);
    tests.verifyEqual(ly.kind, 'scalp');
    tests.verifyEqual(ly.counts, struct('file', 0, 'template', 0, 'positionsFile', 31, 'edited', 1, 'none', 0, ...
        'total', 32));
    tests.verifySize(ly.renamed, [0 2]);
    tests.verifyEqual(ly.frame, L.frame);
    tests.verifyEqual(ly.format, 'ASA .elc');
    tests.verifyEqual(ly.summary, L.summary);
    tests.verifyEqual({ly.edits.label, ly.edits.as}, {'T7', 'FT7'});
    isPos = strcmp({s.inputs.role}, app.PositionsRole);
    tests.verifyEqual(sum(isPos), 1, 'the positions file is one of the inputs');
    tests.verifyEqual(s.inputs(isPos).name, 'actiCAP_T3.elc');
    tests.verifyNotEmpty(s.inputs(isPos).md5);
    b = EEGAnalysisApp(); cb = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)), 'session not reopened');
    tests.verifyEqual(b.Layout.pos, L.pos, 'AbsTol', 1e-9);
    tests.verifyEqual(b.Layout.source, L.source);
    tests.verifyTrue(b.Layout.confirmed);
    tests.verifyEqual(b.LayoutSettings.positionsFile, pf);
    tests.verifyEqual(b.LayoutInfo.Text, app.LayoutInfo.Text);
    shot(tests, b, 'EEGAnalysisApp_19_layout_session_reopened');
    delete(cb);
    % a session saved before layouts existed: the layout made from the files, not confirmed
    s.settings = rmfield(s.settings, 'layout');
    s.inputs = s.inputs(~isPos);
    o = EEGAnalysisApp(); co = onCleanup(@() delete(o.UIFig));
    tests.verifyTrue(logical(o.restoreSession(s)), 'session without a layout not restored');
    tests.verifyEqual(o.Layout.summary, '32 of 32 channels placed: 32 from the file.');
    tests.verifyFalse(o.Layout.confirmed);
    tests.verifyEqual(o.LayoutSettings.source, 'auto');
    delete(co);

    % 9. Rodent: a skull layout in mm from bregma (AP, ML), the demo's screw positions
    rt = f.truth.rodent;
    tests.verifyTrue(logical(app.openFiles({f.rodent.eeglab})));
    L = app.Layout;
    tests.verifyEqual(L.kind, 'skull');
    tests.verifyEqual(L.labels, rt.labels);
    tests.verifyEqual(L.pos(:, 2)', rt.ap, 'AbsTol', 1e-9, 'AP (anterior +)');
    tests.verifyEqual(L.pos(:, 1)', rt.ml, 'AbsTol', 1e-9, 'ML (right +)');
    tests.verifyEqual(L.summary, '4 of 4 channels placed: 4 from the file.');
    tests.verifyFalse(L.confirmed, 'new files: a new layout, not confirmed');
    tests.verifyEmpty(app.LayoutSettings.positionsFile, 'new files forget the positions file');
    tests.verifyEqual(app.LayoutInfo.Text, [L.summary notChecked]);
    ov = strjoin(app.OverviewText.Value(:)', newline);
    tests.verifyTrue(startsWith(ov, 'Electrode layout:'));
    tests.verifyTrue(contains(ov, 'turned to mm from bregma'));
    fig = app.openLayout();
    d = app.LayoutDlg;
    tests.verifyEqual(d.Table.ColumnName(:)', {'Channel', 'AP (mm)', 'ML (mm)', 'Status'});
    tests.verifyEqual(logical(d.Table.ColumnEditable), [false true true false], 'AP and ML are editable');
    tests.verifyEqual(d.Table.Data(:, 1)', rt.labels);
    tests.verifyEqual(cell2mat(d.Table.Data(:, 2))', rt.ap, 'AbsTol', 1e-9);
    tests.verifyEqual(cell2mat(d.Table.Data(:, 3))', rt.ml, 'AbsTol', 1e-9);
    tests.verifyNumElements(findall(d.Axes, 'Type', 'line'), 5, 'skull outline, midline, bregma cross, electrodes');
    v1l = find(strcmp(L.labels, 'V1-L'));
    editCell(d.Table, [v1l 2], -4);
    tests.verifyEqual(app.LayoutDlg.L.pos(v1l, 1:2), [-2.5 -4], 'AbsTol', 1e-12, 'AP typed: ML kept');
    tests.verifyEqual(app.LayoutDlg.L.source{v1l}, 'edited');
    shotDialog(tests, fig, 'EEGAnalysisApp_20_layout_rodent');
    press(d.CancelBtn);
    tests.verifyEqual(app.Layout.pos(v1l, 1:2), [-2.5 -3.5], 'AbsTol', 1e-12, 'Cancel keeps the layout');
    % the same kind of placement by script: V1-L at AP -4, ML -3 mm, confirmed
    tests.verifyTrue(logical(app.setLayout('Edits', struct('label', 'V1-L', 'ap', -4, 'ml', -3), 'Confirm', true)));
    L = app.Layout;
    tests.verifyEqual(L.pos(v1l, :), [-3 -4 0], 'AbsTol', 1e-12);
    tests.verifyEqual(L.source, {'file', 'file', 'edited', 'file'});
    tests.verifyEqual(L.summary, '4 of 4 channels placed: 3 from the file, 1 placed by hand.');
    tests.verifyTrue(L.confirmed);
    % a 10-5 name cannot place a channel on a skull: a plain message, the layout unchanged
    tests.verifyFalse(logical(app.setLayout('Edits', struct('label', 'V1-L', 'as', 'Oz'))));
    tests.verifyTrue(contains(app.StatusLabel.Text, 'the layout is in mm from bregma'));
    tests.verifyEqual(app.Layout.pos(v1l, :), [-3 -4 0], 'AbsTol', 1e-12);
    tests.verifyTrue(app.Layout.confirmed);
end

function testScalpMaps(tests)
    DemoData.ensureDemoPath();
    f = demoEEG();
    app = EEGAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    tests.verifyEqual(char(app.MapsBtn.Enable), 'off', 'no ERPs yet');
    tests.verifyFalse(logical(app.showScalpMaps()), 'maps need the ERPs');
    tests.verifyTrue(logical(app.showERPs()));
    tests.verifyEqual(char(app.MapsBtn.Enable), 'on');
    xy = EEGLayout.project(app.Layout);
    at = @(name) xy(strcmp(app.Layout.labels, name), :);
    vAt = @(m, name) m.values(strcmp(m.labels, name));

    % 1. The P300 window of step 5 (300-400 ms): a map per condition and Target minus Standard,
    %    on the layout from the files, not confirmed yet (the window says so)
    app.setView('grand', 'Conditions', 'Target', 'Standard');
    press(app.MapsBtn);
    tests.verifyEqual(app.ViewDrop.Value, 'Scalp maps');
    tests.verifyEqual(char(app.CondBDrop.Enable), 'on', 'B of the A minus B map');
    tests.verifyEqual(char(app.MapPanel.Visible), 'on');
    tests.verifyEqual(app.PlotGrid.RowHeight, {0, '1x'});
    tests.verifyEqual(char(app.ErpPanel.Visible), 'off', 'no strip of the ERP plot above the maps');
    tests.verifyTrue(contains(app.StatusLabel.Text, 'not confirmed'));
    tests.verifyTrue(logical(app.setLayout('Confirm', true)));
    tests.verifyFalse(contains(app.StatusLabel.Text, 'not confirmed'));
    M = app.ScalpMaps;
    tests.verifyEqual({M.name}, [app.Grand.conditions, {'Target minus Standard'}]);
    tests.verifyEqual(app.MapSettings.window, [0.3 0.4], 'AbsTol', 1e-12);
    tests.verifyEqual(M(1).method, 'spherical spline');
    tests.verifyNumElements(M(1).labels, 32);
    t = M(strcmp({M.name}, 'Target'));
    nv = M(strcmp({M.name}, 'Novel'));
    st = M(strcmp({M.name}, 'Standard'));
    tests.verifyLessThan(norm(peakAt(t, 'max') - at('Pz')), 0.15, 'P300 largest near Pz');
    tests.verifyLessThan(norm(peakAt(M(end), 'max') - at('Pz')), 0.15, 'Target minus Standard largest near Pz');
    tests.verifyTrue(vAt(t, 'Pz') > vAt(nv, 'Pz') && vAt(nv, 'Pz') > vAt(st, 'Pz'), 'Target > Novel > Standard at Pz');
    axs = findobj(app.MapPanel, 'Type', 'axes');
    tests.verifyNumElements(axs, 5, 'four maps and the colour scale');
    lim = ScalpMap.limits(M);
    tests.verifyEqual(sum(arrayfun(@(a) isequal(a.CLim, lim), axs)), 4, 'one colour scale for every map');
    shot(tests, app, 'EEGAnalysisApp_m01_scalp_maps_p300');

    % 2. N1 at 100 ms (one sample): most negative near Cz; step 5 shows the window
    tests.verifyTrue(logical(app.showScalpMaps([0.1 0.1])));
    tests.verifyEqual([app.WindowFromEdit.Value app.WindowToEdit.Value], [100 100]);
    tests.verifyTrue(contains(app.StatusLabel.Text, 'voltage at 100 ms'));
    n1 = app.ScalpMaps(strcmp({app.ScalpMaps.name}, 'Standard'));
    tests.verifyLessThan(norm(peakAt(n1, 'min') - at('Cz')), 0.15, 'N1 most negative near Cz');
    tests.verifyLessThan(vAt(n1, 'Cz'), -2);
    shot(tests, app, 'EEGAnalysisApp_m02_scalp_maps_n1');

    % 3. One participant and other conditions in the bar: the maps follow
    app.setView(3, '', 'Novel', 'Standard');
    names = {app.ScalpMaps.name};
    tests.verifyEqual(sort(names(1:end - 1)), sort(app.Grand.conditions));
    tests.verifyEqual(names{end}, 'Novel minus Standard');
    tests.verifyEqual(app.MapSettings.participant, app.Names{3});
    tests.verifyEqual(app.MapSettings.window, [0.1 0.1], 'AbsTol', 1e-12);

    % 4. Measuring while the maps are shown: they follow the window measured
    app.setView('grand', '', 'Target', 'Standard');
    app.setMeasure('mean', 'positive', [0.3 0.4], {'Pz'});
    tests.verifyTrue(logical(app.measure()));
    tests.verifyEqual(app.ViewDrop.Value, 'Scalp maps');
    tests.verifyEqual(app.MapSettings.window, [0.3 0.4], 'AbsTol', 1e-12);

    % 5. Session: the maps come back with the same values; the methods text describes them
    p = fullfile(tests.TestData.tmp, ['EEGAnalysisMaps' Session.Extension]);
    tests.verifyTrue(logical(app.saveSessionTo(p, 'scalp maps')));
    s = Session.load(p);
    tests.verifyEqual(s.settings.scalpMaps.window, [0.3 0.4], 'AbsTol', 1e-12);
    tests.verifyTrue(contains(MethodsWriter.fromSession(s), ['Scalp maps of the mean voltage from 300 to 400 ms ' ...
        'were interpolated over the head with spherical splines']));
    b = EEGAnalysisApp(); cb = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)), 'session not reopened');
    tests.verifyEqual(b.ViewDrop.Value, 'Scalp maps');
    tests.verifyEqual({b.ScalpMaps.name}, {app.ScalpMaps.name});
    tests.verifyEqual(b.ScalpMaps(2).z, app.ScalpMaps(2).z, 'AbsTol', 1e-9);
    delete(cb);

    % 6. Back to the ERPs: the plot area shows the axes again
    app.setView('', 'Conditions');
    tests.verifyEqual(char(app.MapPanel.Visible), 'off');
    tests.verifyEqual(app.PlotGrid.RowHeight, {'1x', 0});
    tests.verifyEqual(char(app.ErpPanel.Visible), 'on');
    tests.verifyNumElements(findall(app.AxERP, 'Type', 'line'), 3, 'one line per condition');

    % 7. The rodent recording: a flat map between the four screws, the VEP trough over V1
    tests.verifyTrue(logical(app.openFiles({f.rodent.eeglab})));
    app.setTrialWindow([-0.1 0.4]);
    tests.verifyTrue(logical(app.cutIntoTrials()));
    app.setBaseline(true, [-0.1 0]);
    app.setChannels({'V1-L', 'V1-R'});
    tests.verifyTrue(logical(app.showERPs()));
    tests.verifyTrue(logical(app.showScalpMaps([0.05 0.05])));
    M = app.ScalpMaps;
    tests.verifyNumElements(M, 1, 'one condition: one map');
    tests.verifyEqual(M.method, 'thin-plate spline');
    tests.verifyLessThan(vAt(M, 'V1-L'), -25);
    tests.verifyLessThan(vAt(M, 'V1-L'), vAt(M, 'M1-L'));
    tests.verifyTrue(isnan(M.z(end, 1)), 'nothing drawn outside the screws');
    shot(tests, app, 'EEGAnalysisApp_m03_rodent_flat_map');

    % 8. No positions (a plain .mat file, layout from the file only): no maps, and why
    tests.verifyTrue(logical(app.openFiles({f.scalp(1).matrix})));
    tests.verifyTrue(logical(app.setLayout('Source', 'file')));
    tests.verifyEqual(app.Layout.kind, 'none');
    tests.verifyTrue(logical(app.showERPs()));
    tests.verifyFalse(logical(app.showScalpMaps()));
    tests.verifyEmpty(app.ScalpMaps);
    tests.verifyTrue(contains(app.StatusLabel.Text, 'No scalp maps'));
end

%% testTimeFrequency - Step 7: ERSP, ITPC and band power on the demo's known answers
function testTimeFrequency(tests)
    DemoData.ensureDemoPath();
    app = EEGAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyEqual(char(app.TFBtn.Enable), 'off', 'no trials yet');
    tests.verifyTrue(logical(app.loadDemo()));
    tests.verifyEqual(char(app.TFBtn.Enable), 'on', 'the demo is already cut into trials');
    tests.verifyEqual(app.TFBaseFromEdit.Value, -200, 'the baseline starts with the trials');

    % 1. ERSP at Oz, 4-40 Hz, 3 cycles (no ERPs needed): alpha falls after Target; no ERSP
    %    below 8 Hz, where no whole wavelet fits inside the 200 ms before the event
    app.setTimeFrequency([4 40], 3, [-0.2 0], {'Oz'}, 'Alpha');
    app.setView('grand', '', 'Target', 'Standard');
    tests.verifyTrue(logical(app.showTimeFrequency()));
    tests.verifyEqual(app.ViewDrop.Value, app.Views{5});
    tests.verifyEqual(char(app.ViewDrop.Enable), 'on', 'the views of step 7 work without ERPs');
    tests.verifyEqual(char(app.CondBDrop.Enable), 'on', 'B of the A minus B image');
    tests.verifyEqual(char(app.MapPanel.Visible), 'on');
    tests.verifyEqual(char(app.ErpPanel.Visible), 'off');
    tests.verifyNumElements(app.TFs, 8);
    g = app.GrandTF;
    tests.verifyEqual(g.channels, {'Oz'});
    tests.verifyEqual(g.n, [8 8 8]);
    tests.verifyEqual(g.freqs, 4:40);
    i10 = g.freqs == 10;
    w = g.times >= 0.4 & g.times <= 0.6;
    v = @(cnd) mean(g.ersp(i10, w, strcmp(g.conditions, cnd)));
    tests.verifyLessThan(v('Target'), -2.5, 'alpha power falls after Target (simulated -6 dB, with noise)');
    tests.verifyLessThan(abs(v('Standard')), 1.5);
    tests.verifyLessThan(abs(v('Novel')), 1.5);
    tests.verifyTrue(all(all(isnan(g.ersp(g.freqs < 8, :, :)))), 'no ERSP below 8 Hz');
    tests.verifyTrue(contains(app.TFInfo.Text, 'ERSP from 8 Hz up'));
    tests.verifyTrue(contains(app.StatusLabel.Text, 'Grey: no value'));
    axs = findobj(app.MapPanel, 'Type', 'axes');
    tests.verifyNumElements(axs, 5, 'three conditions, Target minus Standard and the colour scale');
    titles = arrayfun(@(a) char(a.Title.String), axs, 'UniformOutput', false);
    tests.verifyTrue(any(strcmp(titles, 'Target minus Standard')));
    shot(tests, app, 'EEGAnalysisApp_t01_ersp_alpha_decrease');

    % 2. ITPC at Cz: the N1 has the same phase in every trial (about 100 ms), later about chance
    app.setTimeFrequency([], [], [], {'Cz'});
    tests.verifyTrue(logical(app.showTimeFrequency()));
    app.setView('', 'Phase locking');
    tests.verifyEqual(app.ViewDrop.Value, 'Phase locking (ITPC)');
    tests.verifyEqual(char(app.CondBDrop.Enable), 'off', 'no A minus B for ITPC');
    g = app.GrandTF;
    tests.verifyEqual(g.channels, {'Cz'});
    j = find(abs(g.times - 0.1) < 0.003, 1);
    tests.verifyGreaterThan(min(g.itpc(i10, j, :)), 0.5, 'N1: phase locked in every condition');
    tests.verifyLessThan(max(mean(g.itpc(i10, w, :), 2)), 0.4, 'no phase locking at 400-600 ms');
    tests.verifyNumElements(findobj(app.MapPanel, 'Type', 'axes'), 4, 'one per condition and the colour scale');
    shot(tests, app, 'EEGAnalysisApp_t02_itpc_n1');

    % 3. Alpha band power at Oz: Target about -55% from 400 to 600 ms; Standard and Novel near 0
    app.setTimeFrequency([], [], [], {'Oz'}, 'Alpha');
    tests.verifyTrue(logical(app.showTimeFrequency()));
    app.setView('grand', 'Band power');
    tests.verifyEqual(char(app.ErpPanel.Visible), 'on');
    tests.verifyEqual(char(app.MapPanel.Visible), 'off');
    tests.verifyNumElements(findall(app.AxERP, 'Type', 'line'), 3, 'one line per condition');
    tests.verifyTrue(contains(app.AxERP.Title.String, 'Alpha power'));
    g = app.GrandTF;
    bp = @(cnd) mean(g.bandPct(1, w, strcmp(g.conditions, cnd)));
    tests.verifyLessThan(bp('Target'), -35, 'alpha band power falls after Target');
    tests.verifyLessThan(abs(bp('Standard')), 30);
    tests.verifyTrue(contains(app.TFInfo.Text, 'Alpha band power: its baseline is only'), ...
        'the 1 s trials leave little baseline at 8 Hz');
    shot(tests, app, 'EEGAnalysisApp_t03_alpha_band_power');

    % 4. One participant: SEM across trials; the band outside the frequencies is refused
    app.setView(2, 'Time');
    tests.verifyNumElements(findobj(app.MapPanel, 'Type', 'axes'), 5);
    app.setTimeFrequency([4 20], [], [], [], 'Gamma');
    tests.verifyFalse(logical(app.showTimeFrequency()));
    tests.verifyTrue(contains(app.StatusLabel.Text, 'goes beyond the frequencies'));
    app.setTimeFrequency([4 40], [], [], [], 'Alpha');

    % 5. Session: the settings, the results and the view come back; the methods text describes them
    app.setView('grand', 'Band power');
    p = fullfile(tests.TestData.tmp, ['EEGAnalysisTF' Session.Extension]);
    tests.verifyTrue(logical(app.saveSessionTo(p, 'time-frequency')));
    s = Session.load(p);
    tests.verifyTrue(logical(s.settings.tfShown));
    tests.verifyEqual(s.settings.timeFrequency.channels, {'Oz'});
    tests.verifyEqual(s.settings.tfPlot.view, 'Band power');
    tests.verifyEqual(s.results.timeFrequency.lowestWithBaseline, 8);
    txt = MethodsWriter.fromSession(s);
    tests.verifyTrue(contains(txt, 'complex Morlet wavelet transforms (3 cycles; 37 frequencies from 4 to 40 Hz'));
    tests.verifyTrue(contains(txt, 'ERSP; Makeig, 1993'));
    tests.verifyTrue(contains(txt, 'alpha band power'));
    b = EEGAnalysisApp(); cb = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)), 'session not reopened');
    tests.verifyEqual(b.ViewDrop.Value, 'Band power');
    x = b.GrandTF.bandPct; y = app.GrandTF.bandPct;
    tests.verifyEqual(isnan(x), isnan(y));
    tests.verifyEqual(x(~isnan(x)), y(~isnan(y)), 'AbsTol', 1e-9);
    delete(cb);

    % 6. Raw demo cut into longer trials (-600 to 1000 ms): a baseline at every frequency,
    %    alpha band power about -70% after Target
    tests.verifyTrue(logical(app.loadRawDemo()));
    tests.verifyEmpty(app.TFs, 'new files: no time-frequency');
    for k = 1:3, app.setBadChannels(k, {'T7'}); end
    app.setFilters(0.1, 30, 'off');
    app.setReference('average');
    tests.verifyTrue(logical(app.applyCleaning()));
    app.setEvents('S 1 = Standard, S 2 = Target, S 3 = Novel');
    app.setTrialWindow([-0.6 1]);
    app.setRejection(true, 100, 0);
    tests.verifyTrue(logical(app.cutIntoTrials()));
    tests.verifyEqual(app.TFBaseFromEdit.Value, -600, 'the baseline starts with the new trials');
    app.setTimeFrequency([4 40], 3, [-0.5 -0.1], {'Oz'}, 'Alpha');
    tests.verifyTrue(logical(app.showTimeFrequency()));
    g = app.GrandTF;
    tests.verifyTrue(all(g.baselineSamples > 0), 'every frequency has a baseline');
    bp = @(cnd) mean(g.bandPct(1, w2(g), strcmp(g.conditions, cnd)));
    tests.verifyLessThan(bp('Target'), -45);
    tests.verifyLessThan(abs(bp('Standard')), 30);
    app.setView('grand', 'Band power');
    shot(tests, app, 'EEGAnalysisApp_t04_raw_alpha_band_power');
    app.setView('grand', 'Time', 'Target', 'Standard');
    shot(tests, app, 'EEGAnalysisApp_t05_raw_ersp');
end

%% w2 - 400-600 ms of a time-frequency result
function m = w2(g)
    m = g.times >= 0.4 & g.times <= 0.6;
end

%% peakAt - Drawing coordinates of the largest ('max') or smallest ('min') value of a map
function p = peakAt(M, which)
    z = M.z;
    if strcmp(which, 'min'), z = -z; end
    z(isnan(z)) = -Inf;
    [~, i] = max(z(:));
    [r, k] = ind2sub(size(z), i);
    p = [M.x(k) M.y(r)];
end
