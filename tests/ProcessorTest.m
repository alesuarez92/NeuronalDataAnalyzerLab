%% ProcessorTest.m
% =========================================================================
% UNIT TESTS FOR Processor.crop
% =========================================================================
% Run with: runtests('tests/ProcessorTest'). Tests: basic crop (lengths, time
% vector), bounds clamping when endIdx > N, mismatched RawStim/RawLDF lengths.
% =========================================================================

function tests = ProcessorTest
    tests = functiontests(localfunctions);
end

%% setupOnce - Add toolbox root, apps, and core to path
function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
end

%% testCrop_basic - Crop [100,500] gives 401 samples, time 0 to 0.4 s at 1000 Hz
function testCrop_basic(tests)
    AppData = struct('RawStim', 1:1000, 'RawLDF', (1:1000)*2, 'SamplingRate', 1000, ...
        'ProcessedStim', [], 'ProcessedLDF', [], 'TimeVector', []);
    out = Processor.crop(AppData, 100, 500);
    verifyEqual(tests, length(out.ProcessedStim), 401);
    verifyEqual(tests, length(out.ProcessedLDF), 401);
    verifyEqual(tests, length(out.TimeVector), 401);
    verifyEqual(tests, out.TimeVector(1), 0);
    verifyEqual(tests, out.TimeVector(end), 400/1000);
end

%% testCrop_boundsClamped - endIdx 1000 clamped to N=100; output length 100
function testCrop_boundsClamped(tests)
    AppData = struct('RawStim', 1:100, 'RawLDF', 1:100, 'SamplingRate', 100, ...
        'ProcessedStim', [], 'ProcessedLDF', [], 'TimeVector', []);
    out = Processor.crop(AppData, 1, 1000);
    verifyEqual(tests, length(out.ProcessedStim), 100);
    verifyEqual(tests, length(out.ProcessedLDF), 100);
end

%% testCrop_mismatchedLengths - RawStim 100, RawLDF 80; crop to common range (41 samples)
function testCrop_mismatchedLengths(tests)
    AppData = struct('RawStim', 1:100, 'RawLDF', 1:80, 'SamplingRate', 100, ...
        'ProcessedStim', [], 'ProcessedLDF', [], 'TimeVector', []);
    warning('off', 'NeuroAnalyzer:Processor:lengthMismatch');
    out = Processor.crop(AppData, 10, 50);
    warning('on', 'NeuroAnalyzer:Processor:lengthMismatch');
    verifyEqual(tests, length(out.ProcessedStim), 41);
    verifyEqual(tests, length(out.ProcessedLDF), 41);
end
