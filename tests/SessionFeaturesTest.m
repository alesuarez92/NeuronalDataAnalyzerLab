%% SessionFeaturesTest.m
% =========================================================================
% SESSION FILES: MD5, SAVE / LOAD, INPUT CHECKS AND RESTORE PER WINDOW
% =========================================================================
% Core (no display needed):
%   - Session.md5 of fixtures written by the test against values computed
%     independently (Python hashlib / md5sum), with the default engine
%     (Java) and the pure-MATLAB fallback; folder MD5; empty input
%   - Session.save / Session.load round trip, extension, invalid files
%   - Session.verifyInputs: ok / changed / missing / moved / generated
%   - Session.limitSize and Session.describe
% Windows (skipped without a display): for each of the 7 analysis windows,
% load the demo, run the analysis through the public methods used in
% DemoWalkthroughTest, save a session, open it in a NEW window and check
% that the results match; a session opened in the wrong window is refused.
% =========================================================================

function tests = SessionFeaturesTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    tests.TestData.dir = tempname;
    mkdir(tests.TestData.dir);
end

function teardownOnce(tests)
    try, rmdir(tests.TestData.dir, 's'); catch, end
end

%% ---------------------------------------------------------------- core

function testMD5KnownValues(tests)
    d = tests.TestData.dir;
    [pAbc, p100k] = writeFixtures(d);
    % Expected values from Python: hashlib.md5(b'abc') and
    % hashlib.md5(bytes((i*7+3) % 251 for i in range(100000)))
    tests.verifyEqual(Session.md5(pAbc), '900150983cd24fb0d6963f7d28e17f72');
    tests.verifyEqual(Session.md5(p100k), 'e82210e5ca4fe2021408617cb7b4c5e7');
    tests.verifyEqual(Session.md5(pAbc, 'matlab'), '900150983cd24fb0d6963f7d28e17f72');
    tests.verifyEqual(Session.md5(p100k, 'matlab'), 'e82210e5ca4fe2021408617cb7b4c5e7');
    tests.verifyEqual(Session.md5Bytes(uint8([]), 'matlab'), 'd41d8cd98f00b204e9800998ecf8427e');
    tests.verifyEqual(Session.md5Bytes(uint8('abc')), '900150983cd24fb0d6963f7d28e17f72');
    tests.verifyError(@() Session.md5(fullfile(d, 'no_such_file.bin')), 'NeuroAnalyzer:Session:md5');
end

function testMD5Folder(tests)
    d = fullfile(tests.TestData.dir, 'md5folder');
    mkdir(fullfile(d, 'sub'));
    [pAbc, p100k] = writeFixtures(tests.TestData.dir);
    copyfile(pAbc, fullfile(d, 'a.bin'));
    copyfile(p100k, fullfile(d, 'sub', 'b.bin'));
    % md5sum of the text "<md5 a.bin>  a.bin\n<md5 b.bin>  sub/b.bin\n"
    tests.verifyEqual(Session.md5(d), 'de275527a06abf8dae4f375ce64b3d57');
    info = Session.fileInfo(d, 'tank');
    tests.verifyTrue(info.isFolder);
    tests.verifyEqual(info.bytes, 100003);
    tests.verifyEqual(info.md5, 'de275527a06abf8dae4f375ce64b3d57');
end

function testSaveLoadRoundTrip(tests)
    d = tests.TestData.dir;
    [pAbc, p100k] = writeFixtures(d);
    s = Session.new('ExtractLDFApp');
    s.inputs = [Session.fileInfo(pAbc, 'first'), Session.fileInfo(p100k, 'second')];
    s.settings = struct('range', [20 280], 'view', 'Cropped segment', 'nested', struct('a', 1, 'b', {{'x', 'y'}}));
    s.results = struct('curve', linspace(0, 1, 50), 'n', 7);
    s.summary = {'line one', 'line two'};
    s.notes = sprintf('Rat 12\nbaseline day');
    out = Session.save(fullfile(d, 'roundtrip'), s);
    tests.verifyTrue(endsWith(out, '.nasession.mat'));
    tests.verifyEqual(exist(out, 'file'), 2);
    s2 = Session.load(out);
    for f = {'app', 'toolboxVersion', 'matlabVersion', 'os', 'created', 'settings', 'results', 'summary', 'notes'}
        tests.verifyEqual(s2.(f{1}), s.(f{1}), f{1});
    end
    tests.verifyEqual(s2.inputs, s.inputs);
    tests.verifyEqual(s2.toolboxVersion, UITheme.version);
    tests.verifyMatches(s2.created, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}');
    % Extension handling
    tests.verifyEqual(Session.withExtension('a/b.mat'), 'a/b.nasession.mat');
    tests.verifyEqual(Session.withExtension('a/b.nasession.mat'), 'a/b.nasession.mat');
    % Not a session
    x = 1; %#ok<NASGU>
    bad = fullfile(d, 'not_a_session.mat');
    save(bad, 'x');
    tests.verifyError(@() Session.load(bad), 'NeuroAnalyzer:Session:invalid');
    tests.verifyError(@() Session.load(fullfile(d, 'missing.nasession.mat')), 'NeuroAnalyzer:Session:notFound');
end

function testVerifyInputs(tests)
    d = fullfile(tests.TestData.dir, 'verify');
    mkdir(d);
    [pAbc, p100k] = writeFixtures(tests.TestData.dir);
    a = fullfile(d, 'a.bin'); b = fullfile(d, 'b.bin'); c = fullfile(d, 'c.bin');
    copyfile(pAbc, a); copyfile(p100k, b); copyfile(pAbc, c);
    s = Session.new('X');
    s.inputs = [Session.fileInfo(a, 'kept'), Session.fileInfo(b, 'edited'), ...
        Session.fileInfo(c, 'deleted'), Session.fileInfo('', 'demo')];
    st = Session.verifyInputs(s);
    tests.verifyEqual({st.status}, {'ok', 'ok', 'ok', 'generated'});
    fid = fopen(b, 'a'); fwrite(fid, uint8(1)); fclose(fid);
    delete(c);
    st = Session.verifyInputs(s);
    tests.verifyEqual({st.status}, {'ok', 'changed', 'missing', 'generated'});
    tests.verifyEmpty(st(3).resolvedPath);
    % Moved: the file sits next to the session file (same name, same MD5)
    elsewhere = fullfile(tests.TestData.dir, 'elsewhere');
    mkdir(elsewhere);
    copyfile(pAbc, fullfile(elsewhere, 'c.bin'));
    sessionPath = Session.save(fullfile(elsewhere, 'moved'), s);
    [s2, st, msg] = Session.resolveInputs(s, sessionPath, false);
    tests.verifyEqual(st(3).status, 'moved');
    tests.verifyEqual(s2.inputs(3).path, fullfile(elsewhere, 'c.bin'));
    tests.verifyEqual(numel(msg), 2);   % changed + moved
end

function testLimitSizeAndDescribe(tests)
    v = struct('big', zeros(2000), 'small', 1, 'c', {{ones(3), zeros(2000)}});
    w = Session.limitSize(v, 1e6);
    tests.verifyTrue(ischar(w.big));
    tests.verifyEqual(w.small, 1);
    tests.verifyEqual(w.c{1}, ones(3));
    tests.verifyTrue(ischar(w.c{2}));
    lines = Session.describe(struct('a', 2, 'b', 'text', 'c', struct('d', [1 2 3]), 'e', rand(40)), 'cfg');
    tests.verifyEqual(lines, {'cfg.a = 2', 'cfg.b = text', 'cfg.c.d = [1 2 3]', 'cfg.e = [40x40 double]'});
end

%% ------------------------------------------------------------- windows

function testExtractLDFSession(tests)
    assumeDisplay(tests);
    a = ExtractLDFApp(); c1 = onCleanup(@() delete(a.UIFig));
    a.loadDemo();
    a.processData();
    a.setRange(30, 200);   % fields changed after the crop: saved as well
    p = saveSession(tests, a, 'ExtractLDF');
    b = ExtractLDFApp(); c2 = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)));
    tests.verifyEqual(b.CropRange, a.CropRange);
    tests.verifyEqual(b.AppData.ProcessedLDF, a.AppData.ProcessedLDF);
    tests.verifyEqual(b.currentRange(), [30 200]);
    tests.verifyGreaterThan(b.AxLDF.XLim(2), 200, 'reopened plot must show the whole crop');
    % A session of another window is refused
    g = LDFGrandAverageApp(); c3 = onCleanup(@() delete(g.UIFig));
    tests.verifyFalse(logical(g.openSession(p)));
end

function testProcessingLDFSession(tests)
    assumeDisplay(tests);
    a = ProcessingLDFApp(); c1 = onCleanup(@() delete(a.UIFig));
    a.loadDemo();
    p = struct('downsample', 10, 'filterType', 2, 'designType', 1, 'filterOrder', 4, ...
        'cutoffLow', NaN, 'cutoffHigh', 1);
    tests.verifyTrue(logical(a.applyProcessingParams(p)));
    a.segmentByOnsetsConfig();
    f = saveSession(tests, a, 'ProcessingLDF');
    b = ProcessingLDFApp(); c2 = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(f)));
    tests.verifyEqual(b.ProcessingParams, a.ProcessingParams);
    tests.verifyEqual(b.SegmentedLDF, a.SegmentedLDF, 'AbsTol', 1e-10);
    tests.verifyEqual(b.SegmentedTime, a.SegmentedTime);
end

function testLDFGrandAverageSession(tests)
    assumeDisplay(tests);
    a = LDFGrandAverageApp(); c1 = onCleanup(@() delete(a.UIFig));
    a.loadDemo();
    a.plotGrandAverage();
    p = saveSession(tests, a, 'LDFGrandAverage');
    b = LDFGrandAverageApp(); c2 = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)));
    tests.verifyEqual(b.SegmentedData, a.SegmentedData);
    tests.verifyEqual(b.RelativeCheck.Value, a.RelativeCheck.Value);
    tests.verifyEqual(b.GrandPlot.YData, a.GrandPlot.YData, 'AbsTol', 1e-12);
    s = Session.load(p);
    tests.verifyEqual(s.results.mean, a.GrandPlot.YData, 'AbsTol', 1e-12);
end

function testExtractEphysSession(tests)
    assumeDisplay(tests);
    a = ExtractEphysApp(); c1 = onCleanup(@() delete(a.UIFig));
    a.loadDemo();
    a.setChannels(1, 3:6);
    a.processLFPData(struct('lowCutoff', 200));
    a.setChannels(1, [4 5]);
    a.processMUAData(struct());
    a.setChannels(1, 1:8);
    p = saveSession(tests, a, 'ExtractEphys');
    s = Session.load(p);
    tests.verifyTrue(s.inputs(1).isFolder);   % TDT tank folder
    b = ExtractEphysApp(); c2 = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)));
    tests.verifyEqual(b.LastLFPChannels, a.LastLFPChannels);
    tests.verifyEqual(b.LastLFPfs, a.LastLFPfs);
    tests.verifyEqual(b.LastProcessedLFP, a.LastProcessedLFP);
    tests.verifyEqual(b.LastMUAChannels, a.LastMUAChannels);
    tests.verifyEqual(b.LastProcessedMUA, a.LastProcessedMUA);
    tests.verifyEqual(b.RAWList.Value, a.RAWList.Value);
end

function testLFPAnalysisSession(tests)
    assumeDisplay(tests);
    a = LFPAnalysisApp(); c1 = onCleanup(@() delete(a.UIFig));
    a.loadDemo();
    a.runERP(struct('preTime', 0.05, 'postTime', 0.2, 'threshold', 0.5, 'minISI', 0.5));
    a.computeCSD(100, 1:8);
    tests.verifyTrue(logical(a.runSpectrum(4)));
    p = saveSession(tests, a, 'LFPAnalysis');
    b = LFPAnalysisApp(); c2 = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)));
    tests.verifyEqual(b.ERPParams, a.ERPParams);
    tests.verifyEqual(b.SelectedChannels, a.SelectedChannels);
    tests.verifyEqual(b.LastERP, a.LastERP, 'AbsTol', 1e-12);
    tests.verifyEqual(b.LastCSD, a.LastCSD, 'AbsTol', 1e-9);
    tests.verifyEqual(b.LastCSDOrder, a.LastCSDOrder);
    tests.verifyEqual(b.LastSpectrum.pxx, a.LastSpectrum.pxx, 'RelTol', 1e-10);
end

function testMUAAnalysisSession(tests)
    assumeDisplay(tests);
    hasTb = license('test', 'Statistics_Toolbox') && license('test', 'Signal_Toolbox') && ...
        exist('kmeans', 'file') == 2 && exist('findpeaks', 'file') == 2;
    tests.assumeTrue(hasTb, 'Spike sorting needs the Signal Processing and Statistics toolboxes');
    prevRng = rng; rng(0, 'twister'); r = onCleanup(@() rng(prevRng));
    a = MUAAnalysisApp(); c1 = onCleanup(@() delete(a.UIFig));
    tests.verifyTrue(logical(a.loadDemo()));
    tests.verifyTrue(logical(a.runSorting([])));
    ids = unique(a.SpikeResults.clusterIdx);
    ids = ids(ids > 0);
    if numel(ids) >= 2
        a.mergeClusters(ids(1:2)');   % a manual edit: restored as saved, Undo included
    end
    p = saveSession(tests, a, 'MUAAnalysis');
    b = MUAAnalysisApp(); c2 = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)));
    tests.verifyEqual(b.SpikeResults.spikeTimes, a.SpikeResults.spikeTimes);
    tests.verifyEqual(b.SpikeResults.clusterIdx, a.SpikeResults.clusterIdx);
    tests.verifyEqual([b.ClusterQC.id], [a.ClusterQC.id]);
    tests.verifyEqual(b.SpikeSortParams, a.SpikeSortParams);
    tests.verifyEqual(b.ClusterEdits, a.ClusterEdits);
    tests.verifyEqual(numel(b.EditHistory), numel(a.EditHistory));
    tests.verifyTrue(b.resultsCurrent());
    if ~isempty(b.EditHistory)
        tests.verifyTrue(logical(b.undoClusterEdit()));
    end
end

function testROIAnalysisSession(tests)
    assumeDisplay(tests);
    a = ROIAnalysisApp(); c1 = onCleanup(@() delete(a.UIFig));
    tests.verifyTrue(logical(a.loadDemo()));
    m = false(size(a.ROIMask)); m(60:70, 20:30) = true;
    a.addROI(m, 'Background');
    tests.verifyTrue(logical(a.runAnalysis('dff')));
    p = saveSession(tests, a, 'ROIAnalysis');
    b = ROIAnalysisApp(); c2 = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)));
    tests.verifyEqual({b.ROIs.Name}, {a.ROIs.Name});
    tests.verifyEqual(b.LastMethod, a.LastMethod);
    tests.verifyEqual(b.DFF, a.DFF, 'AbsTol', 1e-12);
    tests.verifyEqual([b.LineStart; b.LineEnd], [a.LineStart; a.LineEnd]);
end

function testSignalCharacterizationSession(tests)
    assumeDisplay(tests);
    a = SignalCharacterizationApp(); c1 = onCleanup(@() delete(a.UIFig));
    tests.verifyTrue(logical(a.loadDemo()));
    tests.verifyTrue(logical(a.extract()));
    tests.verifyTrue(logical(a.loadGroupDemo()));
    tests.verifyTrue(logical(a.runGroupStats('Peak amplitude', 'paired', 'parametric', {'Control', 'Stimulated'})));
    p = saveSession(tests, a, 'SignalCharacterization');
    b = SignalCharacterizationApp(); c2 = onCleanup(@() delete(b.UIFig));
    tests.verifyTrue(logical(b.openSession(p)));
    tests.verifyEqual(b.ResultsTable.Data, a.ResultsTable.Data);
    tests.verifyEqual({b.GroupFiles.path}, {a.GroupFiles.path});
    tests.verifyEqual({b.GroupFiles.group}, {a.GroupFiles.group});
    tests.verifyEqual(b.GroupResult.main.p, a.GroupResult.main.p, 'AbsTol', 1e-12);
    tests.verifyEqual(b.GroupResult.summary, a.GroupResult.summary);
    tests.verifyEqual(b.ModeTabs.SelectedTab.Title, a.ModeTabs.SelectedTab.Title);
end

%% ------------------------------------------------------------- helpers

%% writeFixtures - 'abc' and 100000 bytes (i*7+3) mod 251, i = 0..99999
function [pAbc, p100k] = writeFixtures(d)
    pAbc = fullfile(d, 'fx_abc.bin');
    p100k = fullfile(d, 'fx_100k.bin');
    fid = fopen(pAbc, 'w'); fwrite(fid, uint8('abc')); fclose(fid);
    fid = fopen(p100k, 'w'); fwrite(fid, uint8(mod((0:99999) * 7 + 3, 251))); fclose(fid);
end

%% saveSession - Save the window's session with notes; check the file
function p = saveSession(tests, app, name)
    p = fullfile(tests.TestData.dir, [name Session.Extension]);
    tests.verifyTrue(logical(app.saveSessionTo(p, sprintf('Test session for %s', name))));
    tests.verifyEqual(exist(p, 'file'), 2);
    s = Session.load(p);
    tests.verifyEqual(s.app, class(app));
    tests.verifyEqual(s.notes, sprintf('Test session for %s', name));
    st = Session.verifyInputs(s);
    tests.verifyTrue(all(ismember({st.status}, {'ok', 'generated'})), [name ': inputs not ok']);
end

function assumeDisplay(tests)
    try
        f = uifigure('Visible', 'off'); delete(f); canDraw = true;
    catch
        canDraw = false;
    end
    tests.assumeTrue(canDraw, 'uifigure not available (no display)');
end
