%% FormatsWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: EXTRACT EPHYS ON INTAN, OPEN EPHYS AND NWB RECORDINGS
% =========================================================================
% Opens Extract Ephys, loads the demo recording written in each acquisition
% format by core/demo/demoFormats (Intan .rhd, Open Ephys binary folder,
% NWB file), processes the LFP and exports it as NWB, all through the
% window's public methods (no dialogs). A frame is saved after every step
% to test-artifacts/screens/walkthrough/ExtractEphysApp_xNN_<step>.png.
% The exported NWB file is reopened in the window to close the loop.
% Skipped when no display is available.
% =========================================================================

function tests = FormatsWalkthroughTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    addpath(fullfile(root, 'core', 'io'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.outDir = fullfile(root, 'test-artifacts', 'screens', 'walkthrough');
    if ~exist(tests.TestData.outDir, 'dir'), mkdir(tests.TestData.outDir); end
    tests.TestData.tmp = fullfile(tempdir, ['NeuroAnalyzerFormatsWalk_' char(java.util.UUID.randomUUID)]);
    mkdir(tests.TestData.tmp);
end

function teardownOnce(tests)
    if exist(tests.TestData.tmp, 'dir') == 7, rmdir(tests.TestData.tmp, 's'); end
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
        warning('FormatsWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end

%% runFormat - Load the demo in one format, process LFP, export NWB (frames n..n+2)
function nwbFile = runFormat(tests, app, fmt, n, expFs, expLFPfs, stimName)
    app.loadDemo(fmt);
    tests.verifyEqual(app.SourceFormat, fmt);
    tests.verifyEqual(app.SourceMenu.Value, fmt);
    tests.verifyEqual(size(app.Data.streams.xRAW.data, 1), 4);
    tests.verifyEqual(app.Data.streams.xRAW.fs, expFs, 'AbsTol', 1e-6);
    tests.verifyEqual(app.WhisChannelMenu.Items{1}, stimName);
    tests.verifyEqual(double(app.RAWList.Value(:))', 1:4);
    shot(tests, app, sprintf('ExtractEphysApp_x%02d_%s_loaded', n, fmt));
    app.processLFPData(struct());
    tests.verifyNotEmpty(app.LastProcessedLFP);
    tests.verifyEqual(app.LastLFPfs, expLFPfs, 'AbsTol', 1e-6);
    shot(tests, app, sprintf('ExtractEphysApp_x%02d_%s_lfp', n + 1, fmt));
    nwbFile = fullfile(tests.TestData.tmp, sprintf('%s_LFP.nwb', fmt));
    tests.verifyTrue(logical(app.exportNWB(nwbFile)));
    tests.verifyTrue(exist(nwbFile, 'file') == 2);
    tests.verifyEqual(app.LastNWBExport, nwbFile);
    shot(tests, app, sprintf('ExtractEphysApp_x%02d_%s_nwb_exported', n + 2, fmt));
end

function testSourceDropdown(tests)
    app = ExtractEphysApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyEqual(app.SourceMenu.ItemsData, {'tdt', 'intan', 'openephys', 'nwb'});
    tests.verifyEqual(app.SourceMenu.Value, 'tdt');
    app.SourceMenu.Value = 'openephys';
    app.onSourceChanged();
    tests.verifyTrue(contains(app.LoadBtn.Tooltip, 'Open Ephys'));
    shot(tests, app, 'ExtractEphysApp_x01_source_openephys');
end

function testIntanRecording(tests)
    app = ExtractEphysApp(); c = onCleanup(@() delete(app.UIFig));
    nwbFile = runFormat(tests, app, 'intan', 2, 20000, 1000, 'DIGITAL-IN-01');
    % Reopen the exported LFP: NWB reader finds /processing/ecephys/LFP
    tests.verifyTrue(logical(app.openRecording(nwbFile, 'nwb')));
    tests.verifyEqual(app.Data.streams.xRAW.fs, 1000, 'AbsTol', 1e-9);
    tests.verifyEqual(app.Data.info.seriesPath, '/processing/ecephys/LFP/ElectricalSeries');
    tests.verifyEqual(app.Data.info.channelNames, {'tank ch3', 'tank ch4', 'tank ch5', 'tank ch6'});
    app.setChannels(1, 1:4);
    app.plotRAWData();
    shot(tests, app, 'ExtractEphysApp_x05_intan_nwb_reopened');
end

function testOpenEphysRecording(tests)
    app = ExtractEphysApp(); c = onCleanup(@() delete(app.UIFig));
    runFormat(tests, app, 'openephys', 6, 30000, 1000, 'TTL line 1');
    % Stimulus = ADC1 (analog copy of the TTL) works the same way
    app.setChannels(2, 1:4);
    app.plotRAWData();
    shot(tests, app, 'ExtractEphysApp_x09_openephys_adc_stimulus');
end

function testNWBRecording(tests)
    app = ExtractEphysApp(); c = onCleanup(@() delete(app.UIFig));
    runFormat(tests, app, 'nwb', 10, DemoData.FsRaw, DemoData.FsRaw / 24, 'whisker_stimulus');
    tests.verifyEqual(app.WhisChannelMenu.Items, {'whisker_stimulus', 'trials (intervals)'});
end

function testOpenRecordingAutoDetect(tests)
    % Files written fresh (not the cache) and opened with format detection
    files = demoFormats(fullfile(tests.TestData.tmp, 'demo'), 'Formats', {'intan', 'openephys'});
    app = ExtractEphysApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.openRecording(files.intan)));
    tests.verifyEqual(app.SourceFormat, 'intan');
    tests.verifyTrue(logical(app.openRecording(files.openephys)));
    tests.verifyEqual(app.SourceFormat, 'openephys');
    % A file that is not a recording: error in the status bar, previous recording kept
    bad = fullfile(tests.TestData.tmp, 'not_a_recording.rhd');
    fid = fopen(bad, 'w'); fwrite(fid, uint8(1:64)); fclose(fid);
    tests.verifyFalse(logical(app.openRecording(bad, 'intan')));
    tests.verifyEqual(app.SourceFormat, 'openephys');
    tests.verifyTrue(contains(app.StatusLabel.Text, 'magic number'));
    shot(tests, app, 'ExtractEphysApp_x13_load_error');
    % Close the alert so the window can be deleted cleanly
    drawnow;
end
