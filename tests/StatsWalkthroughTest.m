%% StatsWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: SIGNAL CHARACTERIZATION "GROUPS & STATISTICS" ON DEMO DATA
% =========================================================================
% Drives the Groups & statistics tab through its public methods (no
% dialogs): load the group demo (3 conditions x 8 animals), run a paired
% test (Control vs Stimulated), a one-way ANOVA over the 3 groups, switch
% to a box plot, a rank-based test, and export publication figures. A
% frame is saved after every step to
% test-artifacts/screens/walkthrough/SignalCharacterizationApp_xNN_<step>.png
% for the Help pages and the website. testRepeatedMeasures runs the
% repeated-measures design on the same demo (all three conditions, animals
% matched by #): repeated-measures ANOVA with sphericity, then Friedman,
% a session round trip, and the error for unequal group sizes; frames
% SignalCharacterizationApp_rNN_<step>.png. The test fails if any step errors
% or the known demo effect is not found. Skipped when no display is
% available.
% =========================================================================

function tests = StatsWalkthroughTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'demo'));
    addpath(fullfile(root, 'core', 'imaging'));
    tests.TestData.outDir = fullfile(root, 'test-artifacts', 'screens', 'walkthrough');
    if ~exist(tests.TestData.outDir, 'dir'), mkdir(tests.TestData.outDir); end
    tests.TestData.exportDir = tempname;
    mkdir(tests.TestData.exportDir);
end

function teardownOnce(tests)
    if exist(tests.TestData.exportDir, 'dir'), rmdir(tests.TestData.exportDir, 's'); end
end

function setup(tests)
    try
        f = uifigure('Visible', 'off'); delete(f); canDraw = true;
    catch
        canDraw = false;
    end
    tests.assumeTrue(canDraw, 'uifigure not available (no display)');
end

%% shot - Save a frame of the app window, optionally after selecting tabs
% tabTitles: one tab title or a cell of titles selected in order (outer
% tab first, e.g. {'Groups & statistics', 'Plot'}).
function shot(tests, app, name, tabTitles)
    if nargin >= 4 && ~isempty(tabTitles)
        if ischar(tabTitles), tabTitles = {tabTitles}; end
        for i = 1:numel(tabTitles)
            tab = findobj(app.UIFig, 'Type', 'uitab', 'Title', tabTitles{i});
            tests.verifyNotEmpty(tab, sprintf('%s: no tab "%s"', name, tabTitles{i}));
            if ~isempty(tab), tab(1).Parent.SelectedTab = tab(1); end
        end
    end
    drawnow; pause(0.5);
    try
        exportapp(app.UIFig, fullfile(tests.TestData.outDir, [name '.png']));
    catch ME
        warning('StatsWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end

%% frozen - Every frozen name (1.0) is present: struct fields, table columns or a cellstr
function frozen(tests, have, names, what)
    if isstruct(have)
        have = fieldnames(have);
    elseif istable(have)
        have = have.Properties.VariableNames;
    end
    missing = names(~ismember(names, have));
    tests.verifyEmpty(missing, sprintf('%s: missing %s (frozen for 1.0)', what, strjoin(missing, ', ')));
end

%% verifyFile - File exists and is not empty
function verifyFile(tests, path)
    d = dir(path);
    tests.verifyNotEmpty(d, sprintf('%s was not written', path));
    if ~isempty(d), tests.verifyGreaterThan(d(1).bytes, 0, sprintf('%s is empty', path)); end
end

function testGroupsAndStatistics(tests)
    app = SignalCharacterizationApp(); c = onCleanup(@() delete(app.UIFig));
    G = 'Groups & statistics';
    shot(tests, app, 'SignalCharacterizationApp_x01_groups_start', G);

    % 1 Group demo: Control, Stimulated, Drug x 8 animals (same animals)
    tests.verifyTrue(logical(app.loadGroupDemo()));
    tests.verifyNumElements(app.GroupFiles, 24);
    shot(tests, app, 'SignalCharacterizationApp_x02_group_demo_files', {G, 'Files'});
    truth = app.GroupDemo.truth;

    % 2 Paired t-test, Stimulated - Control, on the peak amplitude
    tests.verifyTrue(logical(app.runGroupStats('Peak amplitude', 'paired', 'parametric', ...
        {'Control', 'Stimulated'})));
    r = app.GroupResult;
    tests.verifyEqual(r.main.test, 'Paired t-test');
    tests.verifyLessThan(r.main.p, 0.05);
    tests.verifyEqual(r.comparisons(1).diff, mean(truth.amplitude(:, 2) - truth.amplitude(:, 1)), 'AbsTol', 2);
    tests.verifyGreaterThan(r.main.effect, 1);
    tests.verifyTrue(r.checkAgrees);
    tests.verifyNotEmpty(app.StatsTable.Data);
    % Checks tab: 8 animals, normal differences, no warnings
    chk = app.ChecksTable.Data;
    txt = strjoin(chk(:, 3), ' | ');
    tests.verifyFalse(any(strcmp(chk(:, 1), 'Warning')), txt);
    tests.verifyTrue(hasCheck(chk, 'OK', 'Sample size', '8 subjects'), txt);
    tests.verifyTrue(hasCheck(chk, 'OK', 'Normality', 'Shapiro-Wilk'), txt);
    tests.verifyEqual({r.checkRows.topic}, {app.CheckRows.topic});
    shot(tests, app, 'SignalCharacterizationApp_x03_paired_plot', {G, 'Plot'});
    shot(tests, app, 'SignalCharacterizationApp_x04_paired_results', {G, 'Results'});

    % 3 One-way ANOVA over the three conditions, Tukey-Kramer pairs
    tests.verifyTrue(logical(app.runGroupStats('Peak amplitude', 'anova')));
    r = app.GroupResult;
    tests.verifyEqual(r.main.test, 'One-way ANOVA');
    tests.verifyEqual(r.main.df, [2 21]);
    tests.verifyLessThan(r.main.p, 0.05);
    tests.verifyNumElements(r.comparisons, 3);
    tests.verifySize(app.PostHocTable.Data, [3 5]);
    shot(tests, app, 'SignalCharacterizationApp_x05_anova_plot', {G, 'Plot'});
    shot(tests, app, 'SignalCharacterizationApp_x06_anova_results', {G, 'Results'});

    % 4 Box-plot style
    app.setGroupPlotStyle('box');
    shot(tests, app, 'SignalCharacterizationApp_x07_anova_boxplot', {G, 'Plot'});

    % 5 Rank-based paired test (Wilcoxon signed-rank), same direction
    tests.verifyTrue(logical(app.runGroupStats('Peak amplitude', 'paired', 'nonparametric', ...
        {'Control', 'Stimulated'})));
    r = app.GroupResult;
    tests.verifyEqual(r.main.test, 'Wilcoxon signed-rank test');
    tests.verifyLessThan(r.main.p, 0.05);
    tests.verifyGreaterThan(r.main.effect, 0);
    app.setGroupPlotStyle('mean');
    shot(tests, app, 'SignalCharacterizationApp_x08_wilcoxon_plot', {G, 'Plot'});

    % 6 Publication figures (vector + 300 dpi) and values + report
    out = tests.TestData.exportDir;
    for fmt = {'pdf', 'svg', 'png300'}
        tests.verifyTrue(logical(app.exportFigure(fullfile(out, 'group_stats'), fmt{1}, 'groups')), fmt{1});
        verifyFile(tests, app.LastExportPath);
    end
    shot(tests, app, 'SignalCharacterizationApp_x09_figure_exported', {G, 'Plot'});
    tests.verifyTrue(logical(app.exportGroupResults(fullfile(out, 'group_values.csv'))));
    verifyFile(tests, fullfile(out, 'group_values.csv'));
    verifyFile(tests, fullfile(out, 'group_values_report.txt'));
    % Frozen for 1.0: Group, Subject and the feature's column; the .mat result struct
    frozen(tests, readtable(fullfile(out, 'group_values.csv')), {'Group', 'Subject', ...
        matlab.lang.makeValidName(app.GroupResult.feature)}, 'Group values .csv');
    tests.verifyTrue(logical(app.exportGroupResults(fullfile(out, 'group_result.mat'))));
    m = load(fullfile(out, 'group_result.mat'));
    frozen(tests, m, {'result'}, 'Group result .mat');
    frozen(tests, m.result, {'design', 'method', 'groupNames', 'values', 'nExcluded', 'desc', 'main', ...
        'check', 'checkAgrees', 'comparisons', 'assumptions', 'summary', 'labels', 'feature', 'subjectMode', ...
        'designLabel', 'unit', 'settings', 'checkRows'}, 'Group result .mat result');
end

function testRepeatedMeasures(tests)
    app = SignalCharacterizationApp(); c = onCleanup(@() delete(app.UIFig));
    G = 'Groups & statistics';
    tests.verifyTrue(logical(app.loadGroupDemo()));
    truth = app.GroupDemo.truth;
    realizedDiff = mean(truth.amplitude(:, 2) - truth.amplitude(:, 1));

    % 1 Repeated-measures ANOVA over Control, Stimulated, Drug (same 8 animals)
    tests.verifyTrue(logical(app.runGroupStats('Peak amplitude', 'rm', 'parametric')));
    r = app.GroupResult;
    tests.verifyEqual(r.design, 'rm');
    tests.verifyEqual(app.DesignMenu.Value, 'Repeated measures (same animals, 3+ conditions)');
    tests.verifyEqual(r.main.test, 'Repeated-measures ANOVA');
    tests.verifyLessThan(r.main.p, 0.001);
    tests.verifyEqual(r.groupNames, {'Control', 'Stimulated', 'Drug'});
    tests.verifyEqual(cellfun(@numel, r.values), [8 8 8]);
    tests.verifyNumElements(r.comparisons, 3);
    tests.verifyEqual(r.comparisons(1).diff, realizedDiff, 'AbsTol', 2);
    tests.verifyLessThan(r.comparisons(1).p, 0.05);
    tests.verifyEqual(r.check.test, 'Friedman test');
    tests.verifySize(app.PostHocTable.Data, [3 5]);
    q = app.StatsTable.Data(:, 1);
    tests.verifyTrue(any(strcmp(q, 'Sphericity')), 'Results table has no sphericity row');
    tests.verifyTrue(any(strcmp(q, 'Greenhouse-Geisser')));
    tests.verifyTrue(any(strcmp(q, 'Huynh-Feldt')));
    rep = strjoin(reshape(cellstr(app.ReportText.Value), 1, []), ' ');
    tests.verifyTrue(contains(rep, 'Animals (matched by subject number)'));
    shot(tests, app, 'SignalCharacterizationApp_r01_rm_anova_plot', {G, 'Plot'});
    shot(tests, app, 'SignalCharacterizationApp_r02_rm_anova_results', {G, 'Results'});

    % 2 Box-plot style keeps the animal lines
    app.setGroupPlotStyle('box');
    shot(tests, app, 'SignalCharacterizationApp_r03_rm_boxplot', {G, 'Plot'});
    app.setGroupPlotStyle('mean');

    % 3 Friedman test (rank-based), repeated-measures ANOVA as the check
    tests.verifyTrue(logical(app.runGroupStats('Peak amplitude', 'rm', 'nonparametric')));
    r = app.GroupResult;
    tests.verifyEqual(r.main.test, 'Friedman test');
    tests.verifyLessThan(r.main.p, 0.05);
    tests.verifyEqual(r.check.test, 'Repeated-measures ANOVA');
    tests.verifyTrue(any(strcmp(app.StatsTable.Data(:, 1), 'Sphericity')));
    shot(tests, app, 'SignalCharacterizationApp_r04_friedman_plot', {G, 'Plot'});
    shot(tests, app, 'SignalCharacterizationApp_r05_friedman_results', {G, 'Results'});

    % 4 Session round trip keeps the repeated-measures design
    tests.verifyTrue(logical(app.runGroupStats('Peak amplitude', 'rm', 'parametric')));
    p = fullfile(tests.TestData.exportDir, ['rm_session' Session.Extension]);
    tests.verifyTrue(logical(app.saveSessionTo(p, 'Repeated measures')));
    b = SignalCharacterizationApp(); c2 = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)));
    tests.verifyEqual(b.DesignMenu.Value, app.DesignMenu.Value);
    tests.verifyEqual(b.GroupResult.design, 'rm');
    tests.verifyEqual(b.GroupResult.main.p, app.GroupResult.main.p, 'AbsTol', 1e-12);
    tests.verifyEqual(b.GroupResult.summary, app.GroupResult.summary);

    % 5 Unequal group sizes: clear error, no result change
    last = find(strcmp({app.GroupFiles.group}, 'Drug'), 1, 'last');
    tests.verifyTrue(logical(app.removeGroupFile(last)));
    tests.verifyFalse(logical(app.runGroupStats('Peak amplitude', 'rm')));
    tests.verifyTrue(contains(app.W.Status.Text, 'group sizes differ'));
    shot(tests, app, 'SignalCharacterizationApp_r06_rm_unequal_sizes', {G, 'Files'});

    % 6 Every trial counted as a subject: the Sample size warning
    tests.verifyTrue(logical(app.loadGroupDemo()));
    app.SubjectMenu.Value = 'Each series';
    tests.verifyTrue(logical(app.runGroupStats('Peak amplitude', 'paired', 'parametric', {'Control', 'Stimulated'})));
    chk = app.ChecksTable.Data;
    tests.verifyTrue(hasCheck(chk, 'Warning', 'Sample size', 'Every series is counted'), strjoin(chk(:, 3), ' | '));
    tests.verifyTrue(contains(app.W.Status.Text, 'in the Checks tab'), app.W.Status.Text);

    % 7 The faults study: 6 animals, animal 6 responds 3x, the same Drug rise in every animal
    tests.verifyTrue(logical(app.loadGroupDemo(true)));
    tests.verifyNumElements(app.GroupFiles, 18);
    tests.verifyEqual(app.DesignMenu.Value, 'Repeated measures (same animals, 3+ conditions)');
    tests.verifyTrue(logical(app.runGroupStats('Peak amplitude', 'rm', 'parametric')));
    chk = app.ChecksTable.Data;
    txt = strjoin(chk(:, 3), ' | ');
    tests.verifyTrue(hasCheck(chk, 'Check', 'Sample size', 'fewer than 8'), txt);
    tests.verifyTrue(hasCheck(chk, 'Check', 'Normality', 'Not normal') || ...
        hasCheck(chk, 'Warning', 'Normality', 'Not normal'), txt);
    tests.verifyTrue(hasCheck(chk, 'Check', 'Sphericity', 'Violated'), txt);
    k = find(strcmp(chk(:, 2), 'Sphericity'), 1);
    UIKit.checkSelected(app.ChecksTable, struct('Indices', [k 3]), app.ChecksText);
    shot(tests, app, 'SignalCharacterizationApp_r07_checks_faults', {G, 'Checks'});
    st = app.sessionState();
    tests.verifyEqual({st.checks.topic}, {app.CheckRows.topic}, 'the checks go into sessions');
end

%% hasCheck - A Checks table row with this result and topic whose finding has the text
function tf = hasCheck(chk, result, topic, finding)
    tf = any(strcmp(chk(:, 1), result) & strcmp(chk(:, 2), topic) & contains(chk(:, 3), finding));
end

function testSingleFileFigureExport(tests)
    app = SignalCharacterizationApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    tests.verifyTrue(logical(app.extract()));
    % Frozen for 1.0: the columns of the features export (.csv header, colNames of the .mat)
    frozen(tests, app.ResultsTable.ColumnName, {'Trial_Channel', 'PeakLatency_s', 'OnsetDelay_s', 'FWHM_s', ...
        'AUCpos', 'AUCneg', 'RiseTime_s', 'DecayTime_s', 'PeakAmp', 'Integral'}, 'Features export columns');
    tests.verifyTrue(logical(app.exportFigure(fullfile(tests.TestData.exportDir, 'series'), 'png300', 'series')));
    verifyFile(tests, app.LastExportPath);
    tests.verifyTrue(logical(app.exportFigure(fullfile(tests.TestData.exportDir, 'series'), 'eps', 'series')));
    verifyFile(tests, app.LastExportPath);
    shot(tests, app, 'SignalCharacterizationApp_x10_single_file_export', 'Single file');
end
