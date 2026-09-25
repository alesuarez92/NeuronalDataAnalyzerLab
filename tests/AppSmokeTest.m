%% AppSmokeTest.m
% =========================================================================
% SMOKE TESTS: EVERY WINDOW OPENS WITHOUT ERRORS
% =========================================================================
% Constructs each app (launcher, sub-apps and parameter dialogs), lets it
% render, saves a screenshot to test-artifacts/screens/<App>.png (uploaded
% by CI so the layout can be reviewed), then closes it. Skipped when no
% display is available.
% =========================================================================

function tests = AppSmokeTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    tests.TestData.outDir = fullfile(root, 'test-artifacts', 'screens');
    if ~exist(tests.TestData.outDir, 'dir'), mkdir(tests.TestData.outDir); end
    % Launcher prompts for project folders when none are set
    tests.TestData.hadImport = ispref('NeuroAnalyzer', 'ImportDir');
    if ~tests.TestData.hadImport
        ProjectManager.setBothDirs(tempdir);
    end
end

function teardownOnce(tests)
    if ~tests.TestData.hadImport && ispref('NeuroAnalyzer', 'ImportDir')
        rmpref('NeuroAnalyzer', 'ImportDir');
        if ispref('NeuroAnalyzer', 'ExportDir'), rmpref('NeuroAnalyzer', 'ExportDir'); end
    end
end

function setup(tests)
    % Skip (not fail) when uifigures cannot be created, e.g. no display
    try
        f = uifigure('Visible', 'off');
        delete(f);
        canDraw = true;
    catch
        canDraw = false;
    end
    tests.assumeTrue(canDraw, 'uifigure not available (no display)');
end

%% openAndCapture - Build app, screenshot its UIFig, close it
function openAndCapture(tests, name, ctor)
    app = ctor();
    fig = app.UIFig;
    tests.verifyTrue(isvalid(fig), sprintf('%s: UIFig not valid', name));
    drawnow;
    pause(0.5);
    try
        exportapp(fig, fullfile(tests.TestData.outDir, [name '.png']));
    catch ME
        % Legacy figure() windows are captured with exportgraphics/print
        try
            exportgraphics(fig, fullfile(tests.TestData.outDir, [name '.png']));
        catch
            warning('AppSmokeTest:capture', '%s: screenshot failed (%s)', name, ME.message);
        end
    end
    delete(fig);
end

function testMain(tests),                   openAndCapture(tests, 'Main', @() Main()); end
function testHelp(tests),                   openAndCapture(tests, 'HelpApp', @() HelpApp()); end
function testExtractLDF(tests),             openAndCapture(tests, 'ExtractLDFApp', @() ExtractLDFApp()); end
function testProcessingLDF(tests),          openAndCapture(tests, 'ProcessingLDFApp', @() ProcessingLDFApp()); end
function testLDFGrandAverage(tests),        openAndCapture(tests, 'LDFGrandAverageApp', @() LDFGrandAverageApp()); end
function testExtractEphys(tests),           openAndCapture(tests, 'ExtractEphysApp', @() ExtractEphysApp()); end
function testLFPAnalysis(tests),            openAndCapture(tests, 'LFPAnalysisApp', @() LFPAnalysisApp()); end
function testMUAAnalysis(tests),            openAndCapture(tests, 'MUAAnalysisApp', @() MUAAnalysisApp()); end
function testROIAnalysis(tests),            openAndCapture(tests, 'ROIAnalysisApp', @() ROIAnalysisApp()); end
function testSignalCharacterization(tests), openAndCapture(tests, 'SignalCharacterizationApp', @() SignalCharacterizationApp()); end
function testBatch(tests),                  openAndCapture(tests, 'BatchApp', @() BatchApp()); end
function testVirtualLab(tests),             openAndCapture(tests, 'VirtualLabApp', @() VirtualLabApp()); end
function testLDFParams(tests),              openAndCapture(tests, 'LDFProcessingParamsApp', @() LDFProcessingParamsApp(@(p) [], 1000)); end
function testLFPParams(tests),              openAndCapture(tests, 'LFPProcessingParamsApp', @() LFPProcessingParamsApp()); end
function testMUAParams(tests),              openAndCapture(tests, 'MUAProcessingParamsApp', @() MUAProcessingParamsApp()); end
function testERPConfig(tests),              openAndCapture(tests, 'ERPConfigApp', @() ERPConfigApp(1000)); end
