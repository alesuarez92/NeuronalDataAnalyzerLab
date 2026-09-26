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
%   guessed map and the BrainVision copy of the study. Checks the results
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
    tests.verifyEqual(char(app.CutBtn.Enable), 'off', 'nothing to cut');
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
