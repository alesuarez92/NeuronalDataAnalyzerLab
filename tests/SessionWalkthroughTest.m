%% SessionWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: SESSION BUTTONS, REOPENED SESSIONS AND PDF REPORTS
% =========================================================================
% For each analysis window: load the demo and run the analysis through
% the public methods, scroll the step column to the last card and save a
% frame showing the Save session / Open session / Report (PDF) buttons;
% save the session, open it in a new window and save a frame of the
% reopened window; write the one-page PDF report and check that it exists
% and is larger than 10 kB. Frames go to
% test-artifacts/screens/walkthrough/<App>_s<NN>_<step>.png and reports
% to test-artifacts/screens/reports/<App>_report.pdf. LFP Analysis also
% opens the Methods text dialog (core/MethodsWriter.m) and saves a frame
% of it (LFPAnalysisApp_s03_methods_text.png). Skipped when no display is
% available.
% =========================================================================

function tests = SessionWalkthroughTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    tests.TestData.outDir = fullfile(root, 'test-artifacts', 'screens', 'walkthrough');
    if ~exist(tests.TestData.outDir, 'dir'), mkdir(tests.TestData.outDir); end
    tests.TestData.reportDir = fullfile(root, 'test-artifacts', 'screens', 'reports');
    if ~exist(tests.TestData.reportDir, 'dir'), mkdir(tests.TestData.reportDir); end
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
        warning('SessionWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end

%% sessionSteps - Buttons frame, save, reopen frame, report checks
% btns: the session buttons to show (default app.SessionBtns).
function sessionSteps(tests, app, tag, ctor, btns)
    if nargin < 5, btns = app.SessionBtns; end
    tests.verifyEqual(char(btns.Save.Enable), 'on', [tag ': Save session disabled']);
    tests.verifyEqual(char(btns.Report.Enable), 'on', [tag ': Report disabled']);
    tests.verifyEqual(char(btns.Methods.Enable), 'on', [tag ': Methods text disabled']);
    tests.verifyEqual(btns.Save.Text, ['Save session' char(8230)]);
    tests.verifyEqual(btns.Methods.Text, ['Methods text' char(8230)]);
    scrollToButtons(btns);
    shot(tests, app, sprintf('%s_s01_session_buttons', tag));

    p = fullfile(tests.TestData.tmp, [tag Session.Extension]);
    tests.verifyTrue(logical(app.saveSessionTo(p, sprintf('%s walkthrough: demo data', tag))));

    pdf = fullfile(tests.TestData.reportDir, [tag '_report.pdf']);
    if exist(pdf, 'file'), delete(pdf); end
    tests.verifyTrue(logical(app.makeReport(pdf)), [tag ': report not written']);
    d = dir(pdf);
    tests.verifyNotEmpty(d, [tag ': no PDF']);
    if ~isempty(d)
        tests.verifyGreaterThan(d.bytes, 10 * 1024, [tag ': PDF smaller than 10 kB']);
    end

    b = ctor(); c = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)), [tag ': session not reopened']);
    shot(tests, b, sprintf('%s_s02_session_reopened', tag));
end

%% scrollToButtons - Scroll the step column so the session buttons are visible
function scrollToButtons(btns)
    try
        h = btns.Grid;
        while ~isempty(h) && ~(isa(h, 'matlab.ui.container.GridLayout') && strcmp(char(h.Scrollable), 'on'))
            h = h.Parent;
        end
        if ~isempty(h), scroll(h, 'bottom'); end
    catch
    end
end

function testExtractLDF(tests)
    app = ExtractLDFApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyEqual(char(app.SessionBtns.Save.Enable), 'off');
    tests.verifyEqual(char(app.SessionBtns.Open.Enable), 'on');
    tests.verifyEqual(char(app.SessionBtns.Methods.Enable), 'off');
    app.loadDemo();
    app.processData();
    sessionSteps(tests, app, 'ExtractLDFApp', @ExtractLDFApp);
end

function testLDFGrandAverage(tests)
    app = LDFGrandAverageApp(); c = onCleanup(@() delete(app.UIFig));
    app.loadDemo();
    app.plotGrandAverage();
    sessionSteps(tests, app, 'LDFGrandAverageApp', @LDFGrandAverageApp);
end

function testExtractEphys(tests)
    app = ExtractEphysApp(); c = onCleanup(@() delete(app.UIFig));
    app.loadDemo();
    app.processLFPData(struct());
    sessionSteps(tests, app, 'ExtractEphysApp', @ExtractEphysApp);
end

function testProcessingLDF(tests)
    app = ProcessingLDFApp(); c = onCleanup(@() delete(app.UIFig));
    app.loadDemo();
    app.applyProcessingParams(struct('downsample', 10, 'filterType', 2, 'designType', 1, ...
        'filterOrder', 4, 'cutoffLow', NaN, 'cutoffHigh', 1));
    app.segmentByOnsetsConfig();
    sessionSteps(tests, app, 'ProcessingLDFApp', @ProcessingLDFApp);
end

function testLFPAnalysis(tests)
    app = LFPAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    app.loadDemo();
    app.runERP(struct('preTime', 0.05, 'postTime', 0.2, 'threshold', 0.5, 'minISI', 0.5));
    app.computeCSD(100, 1:8);
    sessionSteps(tests, app, 'LFPAnalysisApp', @LFPAnalysisApp);
    % Methods text… opens the draft methods text of this analysis
    fig = MethodsWriter.forApp(app);
    tests.verifyNotEmpty(fig, 'Methods text dialog not opened');
    if isempty(fig), return; end
    c2 = onCleanup(@() delete(fig));
    ta = findobj(fig, 'Type', 'uitextarea');
    txt = strjoin(cellstr(ta.Value), newline);
    tests.verifyTrue(contains(txt, 'from 50 ms before to 200 ms after each onset'), txt);
    tests.verifyTrue(contains(txt, 'negative second spatial derivative'), txt);
    tests.verifyTrue(contains(txt, sprintf('NeuroAnalyzer v%s', UITheme.version)), txt);
    shot(tests, struct('UIFig', fig), 'LFPAnalysisApp_s03_methods_text');
end

function testMUAAnalysis(tests)
    hasTb = license('test', 'Statistics_Toolbox') && license('test', 'Signal_Toolbox') && ...
        exist('kmeans', 'file') == 2 && exist('findpeaks', 'file') == 2;
    tests.assumeTrue(hasTb, 'Spike sorting needs the Signal Processing and Statistics toolboxes');
    prevRng = rng; rng(0, 'twister'); r = onCleanup(@() rng(prevRng));
    app = MUAAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    tests.verifyTrue(logical(app.runSorting([])));
    app.TabGroup.SelectedTab = findobj(app.TabGroup, 'Type', 'uitab', 'Title', 'Waveforms');
    sessionSteps(tests, app, 'MUAAnalysisApp', @MUAAnalysisApp);
end

function testROIAnalysis(tests)
    app = ROIAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    tests.verifyTrue(logical(app.runAnalysis('dff')));
    sessionSteps(tests, app, 'ROIAnalysisApp', @ROIAnalysisApp);
end

function testSignalCharacterization(tests)
    app = SignalCharacterizationApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    tests.verifyTrue(logical(app.extract()));
    app.ModeTabs.SelectedTab = app.SingleTab;
    sessionSteps(tests, app, 'SignalCharacterizationApp', @SignalCharacterizationApp);
    % The Groups tab has the same buttons
    tests.verifyTrue(logical(app.loadGroupDemo()));
    tests.verifyTrue(logical(app.runGroupStats('Peak amplitude', 'paired', 'parametric', {'Control', 'Stimulated'})));
    scrollToButtons(app.GroupSessionBtns);
    shot(tests, app, 'SignalCharacterizationApp_s03_group_session_buttons');
    pdf = fullfile(tests.TestData.reportDir, 'SignalCharacterizationApp_groups_report.pdf');
    tests.verifyTrue(logical(app.makeReport(pdf)));
    d = dir(pdf);
    tests.verifyGreaterThan(d.bytes, 10 * 1024);
end
