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
% for the Help pages and the website. The test fails if any step errors
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
end

function testSingleFileFigureExport(tests)
    app = SignalCharacterizationApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    tests.verifyTrue(logical(app.extract()));
    tests.verifyTrue(logical(app.exportFigure(fullfile(tests.TestData.exportDir, 'series'), 'png300', 'series')));
    verifyFile(tests, app.LastExportPath);
    tests.verifyTrue(logical(app.exportFigure(fullfile(tests.TestData.exportDir, 'series'), 'eps', 'series')));
    verifyFile(tests, app.LastExportPath);
    shot(tests, app, 'SignalCharacterizationApp_x10_single_file_export', 'Single file');
end
