%% DemoWalkthroughTest.m
% =========================================================================
% WALKTHROUGHS: DRIVE EACH WINDOW THROUGH ITS STEPS ON DEMO DATA
% =========================================================================
% Opens each window, loads its demo data and runs the workflow step by
% step through the windows' public methods (no dialogs), saving a frame
% after every step to test-artifacts/screens/walkthrough/<App>_NN_<step>.png.
% The frames feed the Help walkthroughs and the project website, and the
% test fails if any step errors. Skipped when no display is available.
% =========================================================================

function tests = DemoWalkthroughTest
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
        warning('DemoWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end

function testExtractLDF(tests)
    app = ExtractLDFApp(); c = onCleanup(@() delete(app.UIFig));
    shot(tests, app, 'ExtractLDFApp_01_start');
    app.loadDemo();
    shot(tests, app, 'ExtractLDFApp_02_demo_loaded');
    app.processData();
    shot(tests, app, 'ExtractLDFApp_03_cropped');
end

function testProcessingLDF(tests)
    app = ProcessingLDFApp(); c = onCleanup(@() delete(app.UIFig));
    app.loadDemo();
    shot(tests, app, 'ProcessingLDFApp_01_demo_loaded');
    % Downsample 10x to 100 Hz, 4th-order Butterworth low-pass at 1 Hz
    p = struct('downsample', 10, 'filterType', 2, 'designType', 1, 'filterOrder', 4, ...
        'cutoffLow', NaN, 'cutoffHigh', 1);
    tests.verifyTrue(logical(app.applyProcessingParams(p)));
    shot(tests, app, 'ProcessingLDFApp_02_filtered', 'Signals');
    shot(tests, app, 'ProcessingLDFApp_03_filter_response', 'Filter response');
    app.segmentByOnsetsConfig();
    shot(tests, app, 'ProcessingLDFApp_04_trials', 'Trials');
    % Checks tab: the clean demo gives no warnings
    chk = app.ChecksTable.Data;
    txt = strjoin(chk(:, 3), ' | ');
    tests.verifyFalse(any(strcmp(chk(:, 1), 'Warning')), txt);
    tests.verifyTrue(hasCheck(chk, 'OK', 'Baseline drift', '8 trials'), txt);
    tests.verifyTrue(hasCheck(chk, 'OK', 'Filter', 'low-pass at 1 Hz'), txt);
    tests.verifyTrue(hasCheck(chk, 'OK', 'Time resolution', 'after downsampling by 10'), txt);
    tests.verifyTrue(hasCheck(chk, 'Check', 'Trials', '1 of 9 stimuli were left out'), txt);
    st = app.sessionState();
    tests.verifyEqual({st.checks.topic}, {app.CheckRows.topic}, 'the checks go into sessions');
    shot(tests, app, 'ProcessingLDFApp_05_checks', 'Checks');

    % The faults demo: drift, a movement artefact in trial 3, a dropout to 0 between trials
    tests.verifyTrue(logical(app.openFile(DemoData.file('ldfFaults'))));
    tests.verifyEmpty(app.ChecksTable.Data, 'a new file clears the checks');
    app.setSegmentParams(2.5, 5, 20, 10);
    app.segmentByOnsetsConfig();
    chk = app.ChecksTable.Data;
    txt = strjoin(chk(:, 3), ' | ');
    tests.verifyTrue(hasCheck(chk, 'Check', 'Baseline drift', '%/min'), txt);
    tests.verifyTrue(hasCheck(chk, 'Warning', 'Movement artefacts', 'trial 3'), txt);
    tests.verifyTrue(hasCheck(chk, 'Warning', 'Signal range', 'at 0'), txt);
    tests.verifyTrue(contains(app.StatusLabel.Text, '2 warnings'), app.StatusLabel.Text);
    k = find(strcmp(chk(:, 2), 'Movement artefacts'), 1);
    UIKit.checkSelected(app.ChecksTable, struct('Indices', [k 3]), app.ChecksText);
    shot(tests, app, 'ProcessingLDFApp_06_checks_faults', 'Checks');
end

%% hasCheck - A row of a Checks table with this result, topic and finding text
function tf = hasCheck(chk, result, topic, finding)
    tf = any(strcmp(chk(:, 1), result) & strcmp(chk(:, 2), topic) & contains(chk(:, 3), finding));
end

function testLDFGrandAverage(tests)
    app = LDFGrandAverageApp(); c = onCleanup(@() delete(app.UIFig));
    app.loadDemo();
    shot(tests, app, 'LDFGrandAverageApp_01_demo_loaded');
    app.plotGrandAverage();
    shot(tests, app, 'LDFGrandAverageApp_02_grand_average');
end

function testExtractEphys(tests)
    app = ExtractEphysApp(); c = onCleanup(@() delete(app.UIFig));
    app.loadDemo();
    shot(tests, app, 'ExtractEphysApp_01_demo_loaded');
    app.processLFPData(struct());
    shot(tests, app, 'ExtractEphysApp_02_lfp');
    app.processMUAData(struct());
    shot(tests, app, 'ExtractEphysApp_03_mua');
end

function testLFPAnalysis(tests)
    app = LFPAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    app.loadDemo();
    shot(tests, app, 'LFPAnalysisApp_01_demo_loaded', 'Stimulus');
    app.runERP(struct('preTime', 0.05, 'postTime', 0.2, 'threshold', 0.5, 'minISI', 0.5));
    % Checks after the ERP: epochs and the stimulus artefact (no CSD rows yet)
    chk = app.ChecksTable.Data;
    txt = strjoin(chk(:, 3), ' | ');
    tests.verifyTrue(hasCheck(chk, 'OK', 'Epochs', '15 of 15 stimuli averaged'), txt);
    tests.verifyTrue(hasCheck(chk, 'OK', 'Stimulus artefact', 'No stimulus artefact'), txt);
    tests.verifyFalse(any(strcmp(chk(:, 2), 'CSD sink')), txt);
    shot(tests, app, 'LFPAnalysisApp_02_erp_overlay', 'ERP overlay');
    shot(tests, app, 'LFPAnalysisApp_03_erp_per_channel', 'ERP per channel');
    app.computeCSD(100, 1:8);
    shot(tests, app, 'LFPAnalysisApp_04_csd', 'CSD');
    % Checks tab after the CSD: the clean demo gives no warnings and nothing to check
    chk = app.ChecksTable.Data;
    txt = strjoin(chk(:, 3), ' | ');
    tests.verifyFalse(any(strcmp(chk(:, 1), 'Warning')), txt);
    tests.verifyFalse(any(strcmp(chk(:, 1), 'Check')), txt);
    tests.verifyTrue(hasCheck(chk, 'OK', 'Electrode spacing', 'from the file'), txt);
    tests.verifyTrue(hasCheck(chk, 'OK', 'CSD sink', 'contact 4 of 8 (channel 4), inside the probe'), txt);
    st = app.sessionState();
    tests.verifyEqual({st.checks.topic}, {app.CheckRows.topic}, 'the checks go into sessions');
    shot(tests, app, 'LFPAnalysisApp_05_checks', 'Checks');

    % The faults demo: a stimulus artefact on every contact, the sink at the
    % deepest contact, no electrode spacing in the file
    tests.verifyTrue(logical(app.openFile(DemoData.file('lfpFaults'))));
    tests.verifyEmpty(app.ChecksTable.Data, 'a new file clears the checks');
    app.setChannels(1:8);
    app.runERP(struct('preTime', 0.05, 'postTime', 0.2, 'threshold', 0.5, 'minISI', 0.5));
    tests.verifyTrue(contains(app.StatusLabel.Text, '1 warning in the Checks tab'), app.StatusLabel.Text);
    tests.verifyTrue(logical(app.computeCSD()));    % as the Compute CSD button: the Spacing box as it is
    chk = app.ChecksTable.Data;
    txt = strjoin(chk(:, 3), ' | ');
    tests.verifyTrue(hasCheck(chk, 'Warning', 'Stimulus artefact', 'the same on all 8 channels'), txt);
    tests.verifyTrue(hasCheck(chk, 'Check', 'Electrode spacing', 'the default 100'), txt);
    tests.verifyTrue(hasCheck(chk, 'Warning', 'CSD sink', 'at the edge of the probe'), txt);
    tests.verifyTrue(contains(app.StatusLabel.Text, '2 warnings in the Checks tab'), app.StatusLabel.Text);
    k = find(strcmp(chk(:, 2), 'Stimulus artefact'), 1);
    UIKit.checkSelected(app.ChecksTable, struct('Indices', [k 3]), app.ChecksText);
    shot(tests, app, 'LFPAnalysisApp_06_checks_faults', 'Checks');
end

function testMUAAnalysis(tests)
    app = MUAAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    shot(tests, app, 'MUAAnalysisApp_01_demo_loaded', 'Signal & spikes');
    tests.verifyTrue(logical(app.runSorting([])));
    shot(tests, app, 'MUAAnalysisApp_02_spikes', 'Signal & spikes');
    shot(tests, app, 'MUAAnalysisApp_03_waveforms', 'Waveforms');
    shot(tests, app, 'MUAAnalysisApp_04_clusters', 'Clusters (feature space)');
    shot(tests, app, 'MUAAnalysisApp_05_spike_rate', 'Spike rate');
    shot(tests, app, 'MUAAnalysisApp_06_quality', 'Quality');
    % Checks tab: the clean demo (channel 4) gives no warnings
    chk = app.ChecksTable.Data;
    txt = strjoin(chk(:, 3), ' | ');
    tests.verifyFalse(any(strcmp(chk(:, 1), 'Warning')), txt);
    tests.verifyTrue(hasCheck(chk, 'OK', 'Refractory period', 'check above 1%'), txt);
    tests.verifyTrue(hasCheck(chk, 'OK', 'Amplitude drift', 'check above 20%'), txt);
    tests.verifyTrue(any(strcmp(chk(:, 2), 'Signal-to-noise')), txt);
    st = app.sessionState();
    tests.verifyEqual({st.checks.topic}, {app.CheckRows.topic}, 'the checks go into sessions');
    shot(tests, app, 'MUAAnalysisApp_07_checks', 'Checks');

    % The faults demo: low SNR on ch 3, a unit without a refractory period on ch 4, a shrinking unit on ch 5
    tests.verifyTrue(logical(app.openFile(DemoData.file('muaFaults'), false)));
    tests.verifyEmpty(app.ChecksTable.Data, 'a new file clears the checks');
    for ch = 3:5
        app.ChannelMenu.Value = find(app.MUAData.channels == ch, 1);
        tests.verifyTrue(logical(app.runSorting([])));          % the demo settings (MAD, k = 4, negative)
        chk = app.ChecksTable.Data;
        txt = sprintf('ch %d: %s', ch, strjoin(chk(:, 3), ' | '));
        switch ch
            case 3
                tests.verifyTrue(hasCheck(chk, 'Warning', 'Signal-to-noise', 'No unit reaches SNR 3.5'), txt);
            case 4
                tests.verifyTrue(hasCheck(chk, 'Check', 'Refractory period', 'shorter than the refractory period') || ...
                    hasCheck(chk, 'Warning', 'Refractory period', 'shorter than the refractory period'), txt);
            case 5
                tests.verifyTrue(hasCheck(chk, 'Warning', 'Amplitude drift', 'from the first to the last spike'), txt);
                tests.verifyTrue(contains(app.StatusLabel.Text, 'in the Checks tab'), app.StatusLabel.Text);
        end
    end
    k = find(strcmp(chk(:, 2), 'Amplitude drift'), 1);
    if ~isempty(k), UIKit.checkSelected(app.ChecksTable, struct('Indices', [k 3]), app.ChecksText); end
    shot(tests, app, 'MUAAnalysisApp_08_checks_faults', 'Checks');
end

function testROIAnalysis(tests)
    app = ROIAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    shot(tests, app, 'ROIAnalysisApp_01_demo_loaded');
    tests.verifyTrue(logical(app.runAnalysis('dff')));
    shot(tests, app, 'ROIAnalysisApp_02_dff');
    % Checks tab: the clean demo moves < 1 px, does not bleach or clip
    chk = app.ChecksTable.Data;
    txt = strjoin(chk(:, 3), ' | ');
    tests.verifyFalse(any(strcmp(chk(:, 1), 'Warning')), txt);
    tests.verifyTrue(hasCheck(chk, 'OK', 'Motion', 'motion correction off'), txt);
    tests.verifyTrue(hasCheck(chk, 'OK', 'Bleaching', 'check above 10%'), txt);
    tests.verifyTrue(hasCheck(chk, 'OK', 'Saturation', 'No ROI pixel is clipped'), txt);
    st = app.sessionState();
    tests.verifyEqual({st.checks.topic}, {app.CheckRows.topic}, 'the checks go into sessions');
    tests.verifyTrue(logical(app.runAnalysis('Vessel')));
    shot(tests, app, 'ROIAnalysisApp_03_vessel_diameter');
    tests.verifyTrue(any(strcmp(app.ChecksTable.Data(:, 2), 'Motion')), 'line methods check motion too');
    tests.verifyTrue(logical(app.runAnalysis('Kymo')));
    shot(tests, app, 'ROIAnalysisApp_04_kymograph');
    shot(tests, app, 'ROIAnalysisApp_05_checks', 'Checks');

    % The faults demo: the field slides 14 px, the dye fades, Cell 2 clips at 4095
    tests.verifyTrue(logical(app.openFile(DemoData.file('imagingFaults'))));
    tests.verifyEmpty(app.ChecksTable.Data, 'a new stack clears the checks');
    tests.verifyEqual(numel(app.ROIs), 3, 'the three cell ROIs come from the file');
    tests.verifyTrue(logical(app.runAnalysis('dff')));
    chk = app.ChecksTable.Data;
    txt = strjoin(chk(:, 3), ' | ');
    tests.verifyTrue(hasCheck(chk, 'Warning', 'Motion', 'motion correction is off'), txt);
    tests.verifyTrue(hasCheck(chk, 'Warning', 'Bleaching', 'darker at the end'), txt);
    tests.verifyTrue(hasCheck(chk, 'Warning', 'Saturation', 'Cell 2'), txt);
    tests.verifyTrue(contains(app.W.Status.Text, 'in the Checks tab'), app.W.Status.Text);
    k = find(strcmp(chk(:, 2), 'Motion'), 1);
    UIKit.checkSelected(app.ChecksTable, struct('Indices', [k 3]), app.ChecksText);
    shot(tests, app, 'ROIAnalysisApp_06_checks_faults', 'Checks');
    % Motion correction on: Motion is OK, bleaching and clipping stay
    tests.verifyTrue(logical(app.runMotionCorrection()));
    tests.verifyTrue(logical(app.runAnalysis('dff')));
    chk = app.ChecksTable.Data;
    txt = strjoin(chk(:, 3), ' | ');
    tests.verifyTrue(hasCheck(chk, 'OK', 'Motion', 'Motion corrected'), txt);
    tests.verifyTrue(hasCheck(chk, 'Warning', 'Bleaching', 'darker at the end'), txt);
    shot(tests, app, 'ROIAnalysisApp_07_checks_motion_corrected', 'Checks');
end

function testSignalCharacterization(tests)
    app = SignalCharacterizationApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadDemo()));
    shot(tests, app, 'SignalCharacterizationApp_01_demo_loaded');
    tests.verifyTrue(logical(app.extract()));
    shot(tests, app, 'SignalCharacterizationApp_02_features');
end

function testHelpTryDemo(tests)
    h = HelpApp('LDF Average'); c = onCleanup(@() delete(h.UIFig));
    shot(tests, h, 'HelpApp_01_topic_with_demo_button');
    win = h.tryDemo('LDF Average');
    c2 = onCleanup(@() delete(win.UIFig));
    tests.verifyTrue(isvalid(win.UIFig));
end
