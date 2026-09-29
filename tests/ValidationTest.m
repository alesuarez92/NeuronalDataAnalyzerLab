%% ValidationTest.m
% =========================================================================
% UNIT TESTS FOR Validation CLASS
% =========================================================================
% Run with: runtests('tests/ValidationTest') or runtests('tests')
% Tests: isValidLDFStruct (valid struct, missing field, non-struct),
%        cropRange (valid, start>=end, NaN, out of bounds).
% =========================================================================

function tests = ValidationTest
    tests = functiontests(localfunctions);
end

%% setupOnce - Add toolbox root, apps, and core to path
function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
end

%% testIsValidLDFStruct_valid - Struct with data, datastart, dataend returns true
function testIsValidLDFStruct_valid(tests)
    d = struct('data', 1:100, 'datastart', [1 10 20], 'dataend', [10 20 100]);
    verifyTrue(tests, Validation.isValidLDFStruct(d));
end

%% testIsValidLDFStruct_missingField - Missing dataend returns false
function testIsValidLDFStruct_missingField(tests)
    d = struct('data', 1:10, 'datastart', 1);
    verifyFalse(tests, Validation.isValidLDFStruct(d));
end

%% testIsValidLDFStruct_notStruct - Non-struct ([], array) returns false
function testIsValidLDFStruct_notStruct(tests)
    verifyFalse(tests, Validation.isValidLDFStruct([]));
    verifyFalse(tests, Validation.isValidLDFStruct(1:10));
end

%% testCropRange_valid - Valid range (1, 5) within [0, 10] returns ok, empty msg
function testCropRange_valid(tests)
    [ok, msg] = Validation.cropRange(1, 5, 10);
    verifyTrue(tests, ok);
    verifyEmpty(tests, msg);
end

%% testCropRange_startGeEnd - start >= end returns false and message
function testCropRange_startGeEnd(tests)
    [ok, msg] = Validation.cropRange(5, 2, 10);
    verifyFalse(tests, ok);
    verifyNotEmpty(tests, msg);
end

%% testCropRange_nan - NaN start or end returns false
function testCropRange_nan(tests)
    [ok, msg] = Validation.cropRange(NaN, 5, 10);
    verifyFalse(tests, ok);
    verifyNotEmpty(tests, msg);
end

%% testCropRange_outOfBounds - start < 0 or end > duration returns false
function testCropRange_outOfBounds(tests)
    [ok, msg] = Validation.cropRange(-1, 5, 10);
    verifyFalse(tests, ok);
    [ok2, ~] = Validation.cropRange(1, 15, 10);
    verifyFalse(tests, ok2);
end
