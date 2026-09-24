%% DemoDataTest.m
% =========================================================================
% UNIT TESTS FOR DemoData: THE TOOLBOX RECOVERS THE SIMULATED GROUND TRUTH
% =========================================================================
% Each demo dataset is analysed with the toolbox's own functions and the
% result compared with what was simulated (response delay and amplitude,
% ERP latency and depth, calcium events, vessel diameter, RBC speed).
% =========================================================================

function tests = DemoDataTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
end

function testLdfExportLoadsWithDefaultChannels(tests)
    d = DemoData.ldfExport();
    AppData = struct('RawStim', [], 'RawLDF', [], 'SamplingRate', 1000, 'FilePath', '', 'Metadata', struct());
    out = DataLoader.load(AppData, 'FromStruct', d);   % default channels 6 (stim) and 8 (LDF)
    verifyEqual(tests, numel(out.RawLDF), 300 * 1000);
    verifyEqual(tests, out.SamplingRate, 1000);
    verifyGreaterThan(tests, max(out.RawStim), 4);
end

function testLdfTrialsResponse(tests)
    s = DemoData.ldfTrials();
    y = movmean(mean(s.segmentedLDF, 1), 11);   % trial average, 1 s smoothing
    [lat, ~] = SignalFeatures.peakLatency(s.segmentedTime, y, 0, 'max');
    amp = SignalFeatures.peakAmplitude(s.segmentedTime, y, 0, 'max');
    verifyEqual(tests, lat, s.truth.responsePeakDelay, 'AbsTol', 0.5);
    verifyEqual(tests, amp, s.truth.responseAmplitude, 'RelTol', 0.25);
end

function testLfpErpLatencyAndSinkChannel(tests)
    s = DemoData.lfpFile();
    fs = s.lfp_fs; pre = round(0.05 * fs); post = round(0.2 * fs);
    idx = round(s.truth.onsets * fs) + 1;
    erp = zeros(size(s.lfp_data, 1), pre + post + 1);
    for k = 1:numel(idx)
        erp = erp + s.lfp_data(:, idx(k) - pre : idx(k) + post);
    end
    erp = erp / numel(idx);
    t = (-pre:post) / fs;
    [~, iMin] = min(erp(:, t > 0 & t < 0.1), [], 2);
    tPos = t(t > 0 & t < 0.1);
    verifyEqual(tests, tPos(iMin(s.truth.sinkChannel)), s.truth.n1LatencyS, 'AbsTol', 0.003);
    [~, deepest] = min(min(erp, [], 2));
    verifyEqual(tests, deepest, s.truth.sinkChannel);
end

function testMuaHasSpikesAboveNoise(tests)
    s = DemoData.muaFile();
    verifyEqual(tests, size(s.mua_data, 1), 3);
    x = s.mua_data(2, :);   % channel 4, home of units 1 and 2
    noise = median(abs(x)) / 0.6745;
    nCross = sum(diff(x < -4 * noise) == 1);
    nTrue = numel(s.truth.units(1).spikeTimes) + numel(s.truth.units(2).spikeTimes);
    verifyGreaterThan(tests, nCross, 0.6 * nTrue);
    verifyLessThan(tests, nCross, 1.5 * nTrue);
end

function testImagingGroundTruth(tests)
    s = DemoData.imagingStack();
    dff = deltaFOverF(s.stack, s.roiMask, s.timeVec, 'first', 20);
    [~, iPk] = max(dff);
    verifyEqual(tests, s.timeVec(iPk), s.truth.calciumEvents(end), 'AbsTol', 0.6);
    cx = s.truth.vesselCenterX;
    d = vesselDiameterFromLine(s.stack, [cx - 25, 70], [cx + 25, 70], s.timeVec, 'fwhm');
    verifyEqual(tests, mean(d, 'omitnan'), mean(s.truth.diameter), 'AbsTol', 3);
    ky = kymograph(s.stack(:, :, 1:20), [cx 1], [cx 96]);   % one RBC pass
    verifyEqual(tests, propagationSpeedFromKymograph(ky, 'fit'), s.truth.rbcSpeedPxPerFrame, 'AbsTol', 0.3);
end

function testWriteAll(tests)
    folder = fullfile(tempdir, ['NeuroAnalyzerDemoTest_' char(java.util.UUID.randomUUID)]);
    cleanup = onCleanup(@() rmdir(folder, 's'));
    files = DemoData.writeAll(folder);
    names = setdiff(fieldnames(files), {'folder'});
    for k = 1:numel(names)
        verifyTrue(tests, exist(files.(names{k}), 'file') == 2, names{k});
    end
    s = load(files.ldfCropped);
    verifyTrue(tests, all(isfield(s, {'stim', 'LDF', 't', 'Fs'})));
end

function testFileCacheAndDemoTank(tests)
    p = DemoData.file('ldfTrials');
    verifyTrue(tests, exist(p, 'file') == 2);
    tankDir = DemoData.file('tdtTank');
    verifyTrue(tests, DemoData.isDemoTank(tankDir));
    tank = DemoData.loadTank(tankDir);
    verifyTrue(tests, isfield(tank.streams, 'xRAW') && isfield(tank.streams, 'Whis'));
end
