%% LDFFormatsWalkthroughTest.m
% =========================================================================
% WALKTHROUGH: EXTRACT LDF ON EVERY RECORDING FORMAT
% =========================================================================
% Drives ExtractLDFApp through its public methods (no dialogs) on the LDF
% demo written as a LabChart text export, an AcqKnowledge .acq, a
% PeriSoft-style table (semicolons, decimal commas), a Spike2 export, an
% EDF+ file and a table without a time column (core/demo/demoLDFFormats.m): the flow
% channel and stimulus guessed from the names, the plots titled with the
% channel names, comments / markers as the stimulus, block choice on a
% LabChart .mat with two blocks, crop and save (with the channel names),
% sessions saved and reopened (also a session saved before the channel
% choice existed), and the methods text naming the format. Saves a frame
% of each file to test-artifacts/screens/walkthrough/ExtractLDFApp_formats_<kind>.png.
% Skipped when no display is available.
% =========================================================================

function tests = LDFFormatsWalkthroughTest
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
    tests.TestData.files = demoLDFFormats(fullfile(tests.TestData.tmp, 'formats'));
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

function testEveryFormat(tests)
    f = tests.TestData.files;
    tr = f.truth;
    app = ExtractLDFApp(); c = onCleanup(@() delete(app.UIFig));
    kinds = {'labchartText', 'acq', 'table', 'spike2', 'edf'};
    flows = {'LDF', 'LDF100C', 'Perfusion', 'LDF', 'LDF'};
    stims = {'Stimulus', 'Trigger', 'Stimulus', 'Comments / markers', 'Stimulus'};
    tol = [1e-4 1e-4 1e-4 1e-4 5e-3];                   % EDF: 16-bit samples
    for k = 1:numel(kinds)
        tests.verifyTrue(logical(app.openFile(f.(kinds{k}))), kinds{k});
        tests.verifyEqual(app.AppData.FlowName, flows{k}, kinds{k});
        tests.verifyEqual(app.AppData.StimName, stims{k}, kinds{k});
        tests.verifyEqual(app.AppData.SamplingRate, tr.fs, 'AbsTol', 1e-9, kinds{k});
        tests.verifyEqual(app.AppData.RawLDF, tr.ldf, 'AbsTol', tol(k), kinds{k});
        tests.verifyEqual(countOnsets(app.AppData.RawStim), numel(tr.onsets), kinds{k});
        tests.verifyTrue(contains(app.AxLDF.Title.String, flows{k}), app.AxLDF.Title.String);
        tests.verifyTrue(contains(app.FileInfoLabel.Text, '100 Hz'), app.FileInfoLabel.Text);
        tests.verifyEqual(app.FlowDropDown.Value, app.Selection.flow);
        tests.verifyEqual(app.StimValues{app.StimDropDown.Value}, app.Selection.stim);
        tests.verifyEqual(char(app.BlockDropDown.Enable), 'off', 'one block');
        shot(tests, app, ['ExtractLDFApp_formats_' kinds{k}]);
    end
    % The same answer after crop: 20-280 s as in the demo
    app.openFile(f.acq);
    app.setRange(20, 280);
    app.processData();
    p = fullfile(tests.TestData.tmp, 'cropped_acq.mat');
    tests.verifyTrue(logical(app.saveCroppedTo(p)));
    s = load(p);
    frozen(tests, s, {'stim', 'LDF', 't', 'Fs', 'flowName', 'flowUnits', 'stimName'}, ...
        'Extract LDF cropped file');
    tests.verifyEqual(s.Fs, tr.fs, 'AbsTol', 1e-9);
    tests.verifyEqual(s.flowName, 'LDF100C');
    tests.verifyEqual(s.flowUnits, 'BPU');
    tests.verifyEqual(s.stimName, 'Trigger');
    tests.verifyEqual(s.LDF, tr.ldf(20 * tr.fs + 1:280 * tr.fs + 1), 'AbsTol', 1e-9);
    % The cropped file opens in LDF Processing
    pr = ProcessingLDFApp(); c2 = onCleanup(@() delete(pr.UIFig));
    tests.verifyTrue(logical(pr.openFile(p)));
end

function testStimulusChoiceAndNoTimeColumn(tests)
    f = tests.TestData.files;
    tr = f.truth;
    app = ExtractLDFApp(); c = onCleanup(@() delete(app.UIFig));
    % LabChart comments as the stimulus instead of the channel
    app.openFile(f.labchartText);
    tests.verifyTrue(logical(app.selectSignals(3, 'events', 1)));
    tests.verifyEqual(app.AppData.StimName, 'Comments / markers');
    tests.verifyEqual(app.AppData.Metadata.Onsets, tr.onsets, 'AbsTol', 1e-9);
    tests.verifyEqual(max(app.AppData.RawStim), 1);
    tests.verifyTrue(ismember('Comments "Stim" (9)', app.StimDropDown.Items) || ...
        ismember('Comments / markers (9)', app.StimDropDown.Items), strjoin(app.StimDropDown.Items, ' | '));
    % Another channel as the flow (the dropdown value follows)
    tests.verifyTrue(logical(app.selectSignals(2, 1, 1)));
    tests.verifyEqual(app.AppData.FlowName, 'Blood pressure');
    tests.verifyEqual(app.FlowDropDown.Value, 2);
    % A choice that cannot be used keeps what is shown
    tests.verifyFalse(logical(app.selectSignals(3, 1, 5)));
    tests.verifyEqual(app.AppData.FlowName, 'Blood pressure');
    % No time column: refused without the rate (no dialog), read with it
    before = app.AppData.RawLDF;
    tests.verifyFalse(logical(app.openFile(f.noTime)));
    tests.verifyEqual(app.AppData.RawLDF, before, 'previous data kept');
    tests.verifyTrue(logical(app.openFile(f.noTime, 100)));
    tests.verifyEqual(app.AppData.SamplingRate, 100);
    tests.verifyEqual(app.AppData.FlowName, 'LDF');
    tests.verifyEqual(app.AppData.StimName, 'Stim');
    % Session of a file without a time column: the rate is reused on open
    app.setRange(20, 280);
    app.processData();
    ps = fullfile(tests.TestData.tmp, ['notime' Session.Extension]);
    tests.verifyTrue(logical(app.saveSessionTo(ps)));
    b = ExtractLDFApp(); c2 = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(ps)));
    tests.verifyEqual(b.AppData.SamplingRate, 100);
    tests.verifyEqual(b.AppData.ProcessedLDF, app.AppData.ProcessedLDF);
    txt = MethodsWriter.fromSession(Session.load(ps));
    tests.verifyTrue(contains(txt, 'LDF on channel 1 ("LDF") and stimulus trigger on channel 2 ("Stim")'), txt);
end

function testBlocksAndSessions(tests)
    % A LabChart .mat with two blocks and named channels
    d = DemoData.ldfExport();
    n = d.dataend(1) - d.datastart(1) + 1;
    stim = d.data(d.datastart(6):d.dataend(6));
    ldf = d.data(d.datastart(8):d.dataend(8));
    h = n / 2;
    L.data = [stim(1:h) ldf(1:h) stim(h+1:end) ldf(h+1:end)];
    L.datastart = [1 2*h+1; h+1 3*h+1];
    L.dataend = [h 3*h; 2*h 4*h];
    L.samplerate = [1000 1000; 1000 1000];
    L.titles = char('Whisker stim', 'Laser Doppler');
    L.unittext = char('V', 'PU');
    L.unittextmap = [1 1; 2 2];
    L.blocktimes = [739525.4 739525.5];
    p = fullfile(tests.TestData.tmp, 'two_blocks.mat');
    save(p, '-struct', 'L');
    app = ExtractLDFApp(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyTrue(logical(app.openFile(p)));
    tests.verifyEqual(app.Selection, struct('flow', 2, 'stim', 1, 'block', 1));
    tests.verifyEqual(char(app.BlockDropDown.Enable), 'on');
    tests.verifyEqual(numel(app.BlockDropDown.Items), 2);
    tests.verifyEqual(app.AppData.FlowUnits, 'PU');
    tests.verifyTrue(logical(app.selectSignals(2, 1, 2)));
    tests.verifyEqual(app.AppData.RawLDF, double(ldf(h+1:end)));
    app.setRange(10, 100);
    app.processData();
    ps = fullfile(tests.TestData.tmp, ['blocks' Session.Extension]);
    tests.verifyTrue(logical(app.saveSessionTo(ps)));
    b = ExtractLDFApp(); c2 = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(ps)));
    tests.verifyEqual(b.Selection.block, 2);
    tests.verifyEqual(b.AppData.ProcessedLDF, app.AppData.ProcessedLDF);
    txt = MethodsWriter.fromSession(Session.load(ps));
    tests.verifyTrue(contains(txt, 'block 2 of the recording'), txt);
    tests.verifyTrue(contains(txt, 'with LabChart (ADInstruments)'), txt);

    % A session saved before the channel choice existed (stimulusChannel / ldfChannel only)
    a = ExtractLDFApp(); c3 = onCleanup(@() delete(a.UIFig));
    a.loadDemo();
    a.processData();
    s = Session.load(saveTo(tests, a, 'demo'));
    s.settings = struct('range', s.settings.range, 'view', s.settings.view, ...
        'stimulusChannel', 6, 'ldfChannel', 8);
    old = Session.save(fullfile(tests.TestData.tmp, 'old_session'), s);
    o = ExtractLDFApp(); c4 = onCleanup(@() delete(o.UIFig));
    tests.verifyTrue(logical(o.openSession(old)));
    tests.verifyEqual(o.Selection, struct('flow', 8, 'stim', 6, 'block', 1));
    tests.verifyEqual(o.AppData.ProcessedLDF, a.AppData.ProcessedLDF);
    txt = MethodsWriter.fromSession(Session.load(old));
    tests.verifyTrue(contains(txt, 'LabChart-format .mat file (LDF on channel 8 and stimulus trigger on channel 6'), txt);
end

%% ------------------------------------------------------------- helpers

function p = saveTo(tests, app, name)
    p = fullfile(tests.TestData.tmp, [name Session.Extension]);
    tests.verifyTrue(logical(app.saveSessionTo(p)));
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

function n = countOnsets(x)
    above = x(:) > 0.5 * max(x);
    n = sum(diff([false; above]) == 1);
end

function shot(tests, app, name)
    try
        drawnow;
        exportapp(app.UIFig, fullfile(tests.TestData.outDir, [name '.png']));
    catch ME
        warning('LDFFormatsWalkthroughTest:capture', '%s: %s', name, ME.message);
    end
end
