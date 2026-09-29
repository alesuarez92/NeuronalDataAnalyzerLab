%% DataLoaderTest.m
% =========================================================================
% UNIT TESTS FOR DataLoader.load WITH 'FromStruct' (NO FILE DIALOG)
% =========================================================================
% Uses DataLoader.load(AppData, 'FromStruct', d) to test parsing without
% uigetfile. Tests: valid struct fills RawStim/RawLDF/Fs; invalid struct
% leaves RawStim empty; default channels 6/8 when not specified.
% =========================================================================

function tests = DataLoaderTest
    tests = functiontests(localfunctions);
end

%% setupOnce - Add toolbox root, apps, and core to path
function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
end

%% testLoadFromStruct_valid - Minimal LDF struct with 3 channels; load ch 1 and 2
function testLoadFromStruct_valid(tests)
    N = 1000;
    d = struct();
    d.data = randn(1, N * 3);
    d.datastart = [1, 501, 1001];
    d.dataend   = [500, 1000, 1500];
    d.samplerate = [1000 1000 1000];
    AppData = struct('RawStim', [], 'RawLDF', [], 'SamplingRate', 1000, ...
        'FilePath', '', 'Metadata', struct());
    out = DataLoader.load(AppData, 'FromStruct', d, 'StimChannel', 1, 'LDFChannel', 2);
    verifyEqual(tests, length(out.RawStim), 500);
    verifyEqual(tests, length(out.RawLDF), 500);
    verifyEqual(tests, out.SamplingRate, 1000);
end

%% testLoadFromStruct_invalidStruct - Missing datastart/dataend; load fails, RawStim empty
function testLoadFromStruct_invalidStruct(tests)
    AppData = struct('RawStim', [], 'RawLDF', [], 'FilePath', 'x');
    d = struct('data', 1:10);  % missing datastart, dataend
    out = DataLoader.load(AppData, 'FromStruct', d);
    verifyEmpty(tests, out.RawStim);
    % Invalid struct: load fails so RawStim/RawLDF remain unset or empty
end

%% testLoadFromStruct_defaultChannels - Default StimChannel 6, LDFChannel 8; 8 channels
function testLoadFromStruct_defaultChannels(tests)
    N = 200;
    d = struct();
    d.data = 1:(N*8);
    d.datastart = 1 + (0:7)*N;
    d.dataend   = (1:8)*N;
    d.samplerate = repmat(1000, 1, 8);
    AppData = struct('RawStim', [], 'RawLDF', [], 'SamplingRate', 1000, 'FilePath', '', 'Metadata', struct());
    out = DataLoader.load(AppData, 'FromStruct', d);
    verifyEqual(tests, length(out.RawStim), N);
    verifyEqual(tests, length(out.RawLDF), N);
end
