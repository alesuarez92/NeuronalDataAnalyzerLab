%% LFPWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: LFP ANALYSIS TIME-FREQUENCY STEP ON THE OSCILLATION DEMO
% =========================================================================
% Opens LFPAnalysisApp, loads the oscillation demo (core/demo/
% demoLFPOscillations: 6 Hz theta on every channel, a phase-locked 40 Hz
% burst 50-250 ms after each stimulus on channels 3-5) and runs step 6
% (Spectrum, Spectrogram, ERSP / ITPC, Band power) and the ERP through the
% window's public methods (no dialogs), saving a frame after every step to
% test-artifacts/screens/walkthrough/LFPAnalysisApp_xNN_<step>.png. The
% test fails if a step errors or misses the simulated gamma burst.
% Skipped when no display is available.
% =========================================================================

function tests = LFPWalkthroughTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
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
        warning('LFPWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end

function testLFPTimeFrequency(tests)
    app = LFPAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadOscillationDemo()));
    tests.verifyEqual(app.TFChannelDrop.Value, 4);
    shot(tests, app, 'LFPAnalysisApp_x01_oscillation_demo_loaded', 'Stimulus');

    tests.verifyTrue(logical(app.runSpectrum(4)));
    S = app.LastSpectrum;
    band = S.f >= 3 & S.f <= 10;
    fb = S.f(band); [~, k] = max(S.pxx(band));
    tests.verifyEqual(fb(k), 6, 'AbsTol', 1);            % theta peak
    shot(tests, app, 'LFPAnalysisApp_x02_spectrum', 'Spectrum');

    tests.verifyTrue(logical(app.runSpectrogram(4, [2 80])));
    tests.verifyEqual(numel(app.LastSpectrogram.onsetTimes), 15);
    shot(tests, app, 'LFPAnalysisApp_x03_spectrogram', 'Spectrogram');

    tests.verifyTrue(logical(app.runERSP(4, [4 80], [-0.4 -0.1])));
    E = app.LastERSP;
    gF = abs(E.freqs - 40) <= 4;
    inBurst = E.t >= 0.1 & E.t <= 0.2;
    tests.verifyGreaterThan(mean(mean(E.erspDb(gF, inBurst))), 6);
    tests.verifyGreaterThan(mean(mean(E.itpc(gF, inBurst))), 0.8);
    shot(tests, app, 'LFPAnalysisApp_x04_ersp_itpc', 'ERSP / ITPC');

    tests.verifyTrue(logical(app.runBandPower(4, {'Theta', 'Gamma'})));
    r = app.LastBandPower;
    tests.verifyEqual(r.names, {'Theta', 'Gamma'});
    tests.verifyGreaterThan(mean(r.mean(2, r.t >= 0.1 & r.t <= 0.2)), 100);
    shot(tests, app, 'LFPAnalysisApp_x05_band_power', 'Band power');

    % The ERP of the same data shows the phase-locked 40 Hz ripple after the N1/P2
    app.runERP(struct('preTime', 0.05, 'postTime', 0.3, 'threshold', 0.5, 'minISI', 0.5));
    tests.verifyEqual(app.LastNValid, 15);
    shot(tests, app, 'LFPAnalysisApp_x06_erp_with_gamma', 'ERP overlay');
end

function testLFPTimeFrequencyInputChecks(tests)
    app = LFPAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.loadOscillationDemo()));
    % Invalid requests fail with a message instead of an error; close the alerts
    tests.verifyFalse(logical(app.runBandPower(4, {'NoSuchBand'})));
    closeAlerts(app);
    tests.verifyFalse(logical(app.runSpectrogram(4, [2 5000])));   % above Nyquist
    closeAlerts(app);
    tests.verifyFalse(logical(app.runSpectrum(99)));                % no such channel
    closeAlerts(app);
    % Numeric bands work too and reuse the table names
    tests.verifyTrue(logical(app.runBandPower(3, [4 8; 30 80])));
    tests.verifyEqual(app.LastBandPower.names, {'Theta', 'Gamma'});
end

%% closeAlerts - Dismiss uialert dialogs left open by failed steps
function closeAlerts(app)
    drawnow;
    try
        delete(findall(app.UIFig, 'Type', 'uialert'));
    catch
    end
end
