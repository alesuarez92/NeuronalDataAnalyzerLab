%% CSDWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: LFP ANALYSIS CSD STEP WITH EVERY CSD METHOD ON THE DEMO LFP
% =========================================================================
% Opens LFPAnalysisApp, loads the demo LFP (DemoData: 8 channels 100 um
% apart, sink at channel 4 at the N1, 15 ms), runs the ERP and computes
% the CSD with each method of step 4 (Standard, iCSD delta, iCSD step,
% iCSD spline with smoothing, kCSD with cross-validated R / lambda)
% through the window's public methods (setCSDMethod, computeCSD; no
% dialogs), saving a frame after every step to
% test-artifacts/screens/walkthrough/LFPAnalysisApp_cNN_<step>.png. It
% checks that Standard is exactly ERPAnalysis.csd, that every method puts
% the sink at channel 4 (+/- 1), that only the relevant parameters are
% shown, that the plot title names the method, and that the export and a
% saved session keep the method and its parameters.
% Skipped when no display is available.
% =========================================================================

function tests = CSDWalkthroughTest
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
        warning('CSDWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end

%% sinkChannel - Ordered channel with the most negative CSD at the N1 (15 ms)
function ch = sinkChannel(app)
    [~, iN1] = min(abs(app.LastTime - 0.015));
    [~, k] = min(app.LastCSD(:, iN1));
    ch = app.LastCSDOrder(k);
end

%% verifyShown - Parameter fields visible (true) / hidden (false) for the selected method
function verifyShown(tests, app, sigma, diameter, smooth, R, lambda)
    ctrls = {app.CSDSigmaEdit, app.CSDDiameterEdit, app.CSDSmoothEdit, app.CSDREdit, app.CSDLambdaEdit};
    want = [sigma, diameter, smooth, R, lambda];
    names = {'sigma', 'diameter', 'smoothing', 'R', 'lambda'};
    for k = 1:numel(ctrls)
        tests.verifyEqual(strcmp(ctrls{k}.Visible, 'on'), want(k), ...
            sprintf('%s field visible = %d expected for %s', names{k}, ~want(k), app.CSDMethodDrop.Value));
    end
end

function testCSDMethodsWalkthrough(tests)
    app = LFPAnalysisApp(); c = onCleanup(@() delete(app.UIFig));
    app.loadDemo();
    app.runERP(struct('preTime', 0.05, 'postTime', 0.2, 'threshold', 0.5, 'minISI', 0.5));
    tests.verifyEqual(app.LastNValid, 15);
    tests.verifyEqual(app.CSDMethodDrop.Value, 'standard');
    verifyShown(tests, app, false, false, false, false, false);
    shot(tests, app, 'LFPAnalysisApp_c01_erp_standard_method', 'ERP overlay');

    % Standard: unchanged (bit-identical to ERPAnalysis.csd)
    tests.verifyTrue(logical(app.computeCSD(100, 1:8)));
    tests.verifyEqual(app.LastCSD, ERPAnalysis.csd(app.LastERP, 100, 1:8));
    tests.verifyEqual(app.LastCSDMethod, 'standard');
    tests.verifyEqual(sinkChannel(app), 4);
    tests.verifySubstring(app.AxCSD.Title.String, 'Standard');
    shot(tests, app, 'LFPAnalysisApp_c02_csd_standard', 'CSD');
    hStd = app.LeftGrid.RowHeight{4};

    % iCSD delta: conductivity, diameter and smoothing appear; the card grows
    tests.verifyTrue(logical(app.setCSDMethod('iCSD delta', struct('sigma', 0.3, 'diameterUm', 500))));
    verifyShown(tests, app, true, true, true, false, false);
    tests.verifyGreaterThan(app.LeftGrid.RowHeight{4}, hStd);
    tests.verifyTrue(logical(app.computeCSD(100, 1:8)));
    tests.verifyEqual(app.LastCSDInfo.unit, 'A/m^3');
    tests.verifyLessThanOrEqual(abs(sinkChannel(app) - 4), 1);
    tests.verifySubstring(app.AxCSD.Title.String, 'iCSD delta');
    shot(tests, app, 'LFPAnalysisApp_c03_csd_icsd_delta', 'CSD');

    tests.verifyTrue(logical(app.setCSDMethod('step')));
    tests.verifyTrue(logical(app.computeCSD()));
    tests.verifyLessThanOrEqual(abs(sinkChannel(app) - 4), 1);
    tests.verifySubstring(app.AxCSD.Title.String, 'iCSD step');
    shot(tests, app, 'LFPAnalysisApp_c04_csd_icsd_step', 'CSD');

    tests.verifyTrue(logical(app.setCSDMethod('spline', struct('smoothUm', 50))));
    tests.verifyEqual(app.CSDSmoothEdit.Value, 50);
    tests.verifyTrue(logical(app.computeCSD()));
    tests.verifyLessThanOrEqual(abs(sinkChannel(app) - 4), 1);
    tests.verifyGreaterThan(numel(app.LastCSDInfo.zGridUm), 8);        % finer estimation grid
    tests.verifySubstring(app.AxCSD.Title.String, 'smoothing 50');
    shot(tests, app, 'LFPAnalysisApp_c05_csd_icsd_spline_smoothed', 'CSD');

    % kCSD: R and lambda (0 = cross-validated) instead of smoothing
    tests.verifyTrue(logical(app.setCSDMethod('kCSD', struct('RUm', 0, 'lambda', 0))));
    verifyShown(tests, app, true, true, false, true, true);
    tests.verifyTrue(logical(app.computeCSD()));
    I = app.LastCSDInfo;
    tests.verifyTrue(isfinite(I.lambda) && I.lambda > 0);
    tests.verifyTrue(ismember(I.R, I.RGridUm));
    tests.verifyLessThanOrEqual(abs(sinkChannel(app) - 4), 1);
    tests.verifySubstring(app.AxCSD.Title.String, 'kCSD');
    tests.verifySubstring(app.CSDInfoLabel.Text, 'last run');
    shot(tests, app, 'LFPAnalysisApp_c06_csd_kcsd', 'CSD');

    % Export keeps the method, unit and parameters
    p = [tempname '.mat']; cleanP = onCleanup(@() deleteIfExists(p));
    app.exportResults(p);
    s = load(p);
    tests.verifyEqual(s.csd_method, 'kcsd');
    tests.verifyEqual(s.csd_unit, 'A/m^3');
    tests.verifyEqual(s.csd_params.sigma, 0.3);
    tests.verifyEqual(s.csd_kcsd.R_um, I.R);
    tests.verifyEqual(size(s.csd_grid, 1), numel(s.csd_grid_depth_um));
    shot(tests, app, 'LFPAnalysisApp_c07_exported', 'CSD');

    % Unknown method: refused without a dialog, selection kept
    tests.verifyFalse(logical(app.setCSDMethod('laplacian')));
    tests.verifyEqual(app.CSDMethodDrop.Value, 'kcsd');

    % A session restores the method, its parameters and the CSD
    sp = [tempname '.nasession.mat']; cleanS = onCleanup(@() deleteIfExists(sp));
    tests.verifyTrue(logical(app.saveSessionTo(sp, 'CSD walkthrough')));
    b = LFPAnalysisApp(); c2 = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(sp)));
    tests.verifyEqual(b.LastCSDMethod, 'kcsd');
    tests.verifyEqual(b.CSDMethodDrop.Value, 'kcsd');
    tests.verifyEqual(b.LastCSD, app.LastCSD, 'AbsTol', 1e-9 * max(abs(app.LastCSD(:))));
    tests.verifyEqual(b.LastCSDInfo.R, I.R);
    verifyShown(tests, b, true, true, false, true, true);
    shot(tests, b, 'LFPAnalysisApp_c08_session_restored_kcsd', 'CSD');
end

function deleteIfExists(p)
    if exist(p, 'file'), delete(p); end
end
