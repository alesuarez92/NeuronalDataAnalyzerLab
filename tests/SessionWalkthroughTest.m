%% SessionWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: SESSION BUTTONS, REOPENED SESSIONS AND PDF REPORTS
% =========================================================================
% For each analysis window: load the demo and run the analysis through
% the public methods, scroll the step column to the last card and save a
% frame showing the Save session / Open session / Report (PDF) buttons;
% save the session, open it in a new window and save a frame of the
% reopened window; write the one-page PDF report and check that it exists
% and is larger than 10 kB. The saved session is also checked against the
% 1.0 format lock: formatVersion is Session.FormatVersion and the
% window's frozen settings / results fields (frozenFields) are all there;
% a renamed or removed field fails, an added one does not, and a window
% without an entry in frozenFields fails. Frames go to
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
    addpath(fullfile(root, 'core', 'io'));
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
    verifyFrozenFields(tests, tag, p);

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

%% verifyFrozenFields - Saved session has the format version and the frozen fields
% The format version is read from the file as written (Session.load
% upgrades it); the fields are checked on the session as Session.load
% returns it. A tag without an entry in frozenFields fails.
function verifyFrozenFields(tests, tag, p)
    tests.verifyTrue(exist(p, 'file') == 2, [tag ': session file not written']);
    if exist(p, 'file') ~= 2, return; end
    raw = load(p, 'session');
    tests.verifyEqual(raw.session.formatVersion, Session.FormatVersion, ...
        [tag ': formatVersion is not Session.FormatVersion']);
    s = Session.load(p);
    tests.verifyEqual(s.formatVersion, Session.FormatVersion, [tag ': formatVersion after Session.load']);
    f = frozenFields(tag);
    if ischar(f) && strcmp(f, 'skip'), return; end
    tests.verifyNotEmpty(f, sprintf('%s: no entry in frozenFields (add the window''s session fields)', tag));
    if isempty(f), return; end
    verifyFieldList(tests, tag, 'settings', f.settings, s.settings);
    verifyFieldList(tests, tag, 'results', f.results, s.results);
    for k = 1:size(f.nested, 1)
        part = f.nested{k, 1};
        name = f.nested{k, 2};
        has = isfield(s.(part), name) && isstruct(s.(part).(name));
        tests.verifyTrue(has, sprintf('%s: frozen %s field %s missing or not a struct', tag, part, name));
        if has
            verifyFieldList(tests, tag, [part '.' name], f.nested{k, 3}, s.(part).(name));
        end
    end
end

%% verifyFieldList - Every name in list is a field of v
function verifyFieldList(tests, tag, where, list, v)
    have = fieldnames(v);
    tests.verifyTrue(all(ismember(list, have)), sprintf('%s: frozen %s fields missing: %s', ...
        tag, where, strjoin(setdiff(list, have), ', ')));
end

%% frozenFields - Session fields of each window that must stay
% Session fields frozen for 1.0: renaming or removing one breaks old
% sessions and MethodsWriter; add new fields freely. A change goes
% through Session.upgrade (core/Session.m).
% Per tag: settings / results = top-level fields present after the demo
% flow of the test; nested = {part, field, {sub-fields}} rows for structs
% always built there. Only fields set unconditionally on that path are
% listed (fields that depend on optional steps or on toolboxes the test
% does not require are left out). Unknown tag: [] (the test fails). A
% window intentionally not locked returns 'skip' (none at present).
function f = frozenFields(tag)
    f = [];
    switch tag
        case 'ExtractLDFApp'
            f = struct('settings', {{'range', 'view', 'format', 'formatLabel', 'flowChannel', ...
                'flowName', 'flowUnits', 'stimulus', 'stimName', 'block', 'stimulusChannel', ...
                'ldfChannel', 'rate'}}, ...
                'results', {{'cropRange', 'fs', 'nSamples', 'ldfMean', 'ldfSD'}}, ...
                'nested', {cell(0, 3)});
        case 'LDFGrandAverageApp'
            f = struct('settings', {{'relativeToBaseline', 'grandAverageShown'}}, ...
                'results', {{'nTrials', 'fileCounts', 'window', 'nSamples'}}, ...
                'nested', {cell(0, 3)});
        case 'ExtractEphysApp'
            % results.lfp needs the Signal Processing Toolbox (not required here)
            f = struct('settings', {{'format', 'stimChannel', 'rawChannels', 'lfp', 'mua', 'spacingUm'}}, ...
                'results', {cell(1, 0)}, ...
                'nested', {cell(0, 3)});
        case 'ProcessingLDFApp'
            f = struct('settings', {{'processing', 'threshold', 'preS', 'postS', 'minISI', ...
                'segmented', 'tab'}}, ...
                'results', {{'nTrials', 'window', 'fs', 'mean', 'sd'}}, ...
                'nested', {cell(0, 3)});
        case 'LFPAnalysisApp'
            f = struct('settings', {{'channels', 'erp', 'csd', 'tf', 'tfRuns', 'tab'}}, ...
                'results', {{'erp', 'csd'}}, ...
                'nested', {{ ...
                    'settings', 'erp', {'params', 'channels'}; ...
                    'settings', 'csd', {'spacingUm', 'order', 'computed', 'usedOrder', 'usedSpacingUm', ...
                        'method', 'params', 'usedMethod', 'usedParams', 'spacingSource'}; ...
                    'settings', 'tf', {'channel', 'fRange', 'cycles', 'epoch', 'baseline', ...
                        'bandNames', 'bandRanges', 'bandPlot', 'focus'}; ...
                    'settings', 'tfRuns', {'spectrum', 'spectrogram', 'ersp', 'bandpower'}; ...
                    'results', 'erp', {'mean', 'sd', 't', 'nValid', 'onsetTimes', 'channels'}; ...
                    'results', 'csd', {'csd', 'order', 'spacingUm', 'method', 'params', 'info'}}});
        case 'MUAAnalysisApp'
            f = struct('settings', {{'channelIndex', 'channel', 'segmentation', 'sortParams', 'raster', ...
                'correlogram', 'rate', 'selectedClusters', 'tab'}}, ...
                'results', {{'spikeResults', 'sortContext', 'clusterQC', 'spikeLocs', 'threshLines', ...
                'spikeWaves', 'displayPCs', 'editHistory', 'clusterEdits'}}, ...
                'nested', {{ ...
                    'settings', 'segmentation', {'on', 'params', 'segments', 'segment'}; ...
                    'settings', 'raster', {'from', 'to', 'binMs'}; ...
                    'settings', 'correlogram', {'maxLagMs', 'binMs'}; ...
                    'settings', 'rate', {'binS', 'relative'}}});
        case 'ROIAnalysisApp'
            f = struct('settings', {{'generator', 'preprocess', 'method', 'dffBaselineFrames', ...
                'robustDiameter', 'display', 'detectThresholdField', 'detectThresholdUsed', 'roiNames', ...
                'roiSources', 'roiPositions', 'roiMasks', 'line'}}, ...
                'results', {{'method', 't', 'roiNames', 'intensity', 'movement', 'dff', 'speed', ...
                'kymograph', 'diameter', 'diameterStandard', 'diameterPerFrame', 'diameterReplaced'}}, ...
                'nested', {{ ...
                    'settings', 'preprocess', {'motionCorrection', 'bw256', 'smooth', 'normalize'}}});
        case 'SignalCharacterizationApp'
            f = struct('settings', {{'mode', 'single', 'groups'}}, ...
                'results', {{'features'}}, ...
                'nested', {{ ...
                    'settings', 'single', {'input', 'dataType', 't0', 'baseline', 'direction', 'features', ...
                        'series', 'extracted'}; ...
                    'settings', 'groups', {'files', 'order', 'groupName', 'feature', 'subjectMode', 't0', ...
                        'baseline', 'baselineAuto', 'direction', 'design', 'method', 'groupA', 'groupB', ...
                        'plotStyle', 'tested'}; ...
                    'results', 'features', {'data', 'colNames'}}});
    end
end

%% scrollToButtons - Scroll the step column so the session buttons are visible
% The window is drawn and given time to lay out first (scrolling before the
% browser has the column's height does nothing), then every scrollable
% container above the buttons scrolls to the Methods text button ('bottom'
% where that is refused). What happened is printed to the CI log.
function scrollToButtons(btns)
    drawnow; pause(1);
    h = btns.Grid.Parent;
    while ~isempty(h) && ~isa(h, 'matlab.ui.Root')
        if isprop(h, 'Scrollable') && strcmp(char(h.Scrollable), 'on')
            before = viewport(h);
            msg = '';
            try
                scroll(h, btns.Methods);
            catch ME
                msg = ME.message;
                try, scroll(h, 'bottom'); catch ME2, msg = [msg ' / ' ME2.message]; end
            end
            drawnow; pause(0.5);
            fprintf('scrollToButtons: %s viewport %s -> %s %s\n', class(h), mat2str(before), ...
                mat2str(viewport(h)), msg);
        end
        h = h.Parent;
    end
end

function v = viewport(h)
    v = [];
    if isprop(h, 'ScrollableViewportLocation'), v = h.ScrollableViewportLocation; end
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
    tests.verifyTrue(contains(txt, sprintf('Neuronal Data Analyzer Lab v%s', UITheme.version)), txt);
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
