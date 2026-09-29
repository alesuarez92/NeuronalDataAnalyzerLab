%% SignalFeaturesTest.m
% =========================================================================
% UNIT TESTS FOR SignalFeatures
% =========================================================================
% Uses a Gaussian response (known closed-form features) on a raised
% baseline, starting after a pre-stimulus period, so every feature can be
% checked against its analytic value. Also checks negative-going responses,
% that FWHM ignores a later unrelated bump, and NaN on empty windows.
% =========================================================================

function tests = SignalFeaturesTest
    tests = functiontests(localfunctions);
end

%% setupOnce - Add toolbox root, apps, and core to path
function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
end

%% Shared fixture: baseline 5, Gaussian bump of amplitude 2 peaking at 1 s (sigma 0.2 s)
function [t, y, base, A, mu, s] = gaussResponse()
    t = -1:0.001:3;
    base = 5; A = 2; mu = 1; s = 0.2;
    y = base + A * exp(-(t - mu).^2 / (2 * s^2));
end

function testPeakLatency(tests)
    [t, y, ~, ~, mu] = gaussResponse();
    [lat, amp] = SignalFeatures.peakLatency(t, y, 0, 'max');
    verifyEqual(tests, lat, mu, 'AbsTol', 1e-3);
    verifyEqual(tests, amp, 7, 'AbsTol', 1e-6);
end

function testPeakAmplitude_relativeToPreStimBaseline(tests)
    [t, y, ~, A, mu] = gaussResponse();
    [amp, tPeak] = SignalFeatures.peakAmplitude(t, y, 0, 'max');
    verifyEqual(tests, amp, A, 'AbsTol', 1e-6);
    verifyEqual(tests, tPeak, mu, 'AbsTol', 1e-3);
end

function testOnsetDelay_halfMax(tests)
    [t, y, base, ~, mu, s] = gaussResponse();
    expected = mu - s * sqrt(2 * log(2));
    verifyEqual(tests, SignalFeatures.onsetDelay(t, y, 0, 0.5, 'max', base), expected, 'AbsTol', 2e-3);
    % Default baseline (pre-stimulus mean) gives the same answer
    verifyEqual(tests, SignalFeatures.onsetDelay(t, y, 0), expected, 'AbsTol', 2e-3);
end

function testFwhm_gaussian(tests)
    [t, y, base, ~, ~, s] = gaussResponse();
    expected = 2 * sqrt(2 * log(2)) * s;
    verifyEqual(tests, SignalFeatures.fwhm(t, y, 0, 'max', base), expected, 'AbsTol', 3e-3);
end

function testFwhm_ignoresLaterBump(tests)
    [t, y, base, A, ~, s] = gaussResponse();
    y2 = y + 0.9 * A * exp(-(t - 2.5).^2 / (2 * 0.05^2));
    expected = 2 * sqrt(2 * log(2)) * s;
    verifyEqual(tests, SignalFeatures.fwhm(t, y2, 0, 'max', base), expected, 'AbsTol', 3e-3);
end

function testRiseTime_10to90(tests)
    [t, y, base, ~, ~, s] = gaussResponse();
    expected = s * (sqrt(2 * log(10)) - sqrt(2 * log(1 / 0.9)));
    verifyEqual(tests, SignalFeatures.riseTime(t, y, 0, 'max', base), expected, 'AbsTol', 3e-3);
end

function testDecayTime_toHalf(tests)
    [t, y, base, ~, ~, s] = gaussResponse();
    expected = s * sqrt(2 * log(2));
    verifyEqual(tests, SignalFeatures.decayTime(t, y, 0, 'max', base), expected, 'AbsTol', 3e-3);
end

function testNegativeResponse(tests)
    [t, y, base, A, mu, s] = gaussResponse();
    yn = 2 * base - y;   % mirror around baseline: dip of amplitude A
    verifyEqual(tests, SignalFeatures.peakAmplitude(t, yn, 0, 'min'), -A, 'AbsTol', 1e-6);
    verifyEqual(tests, SignalFeatures.fwhm(t, yn, 0, 'min'), 2 * sqrt(2 * log(2)) * s, 'AbsTol', 3e-3);
    verifyEqual(tests, SignalFeatures.onsetDelay(t, yn, 0, 0.5, 'min'), mu - s * sqrt(2 * log(2)), 'AbsTol', 2e-3);
    verifyEqual(tests, SignalFeatures.decayTime(t, yn, 0, 'min'), s * sqrt(2 * log(2)), 'AbsTol', 3e-3);
end

function testAuc(tests)
    [t, y, base, A, ~, s] = gaussResponse();
    expected = A * s * sqrt(2 * pi);
    verifyEqual(tests, SignalFeatures.aucPositive(t, y, base), expected, 'AbsTol', 1e-3);
    verifyEqual(tests, SignalFeatures.aucNegative(t, y, base), 0, 'AbsTol', 1e-9);
    verifyEqual(tests, SignalFeatures.aucNegative(t, 2 * base - y, base), expected, 'AbsTol', 1e-3);
end

function testAuc_defaultBaselineShortSignal(tests)
    % Fewer than 10 samples used to give an empty baseline window (NaN)
    a = SignalFeatures.aucPositive(1:4, [0 1 2 3]);
    verifyTrue(tests, isfinite(a));
end

function testEmptyWindowReturnsNaN(tests)
    t = 0:0.01:1; y = sin(t);
    verifyTrue(tests, isnan(SignalFeatures.peakLatency(t, y, 5)));
    verifyTrue(tests, isnan(SignalFeatures.fwhm(t, y, 5)));
    verifyTrue(tests, isnan(SignalFeatures.riseTime(t, y, 5)));
    verifyTrue(tests, isnan(SignalFeatures.decayTime(t, y, 5)));
    verifyTrue(tests, isnan(SignalFeatures.onsetDelay(t, y, 5)));
    verifyTrue(tests, isnan(SignalFeatures.stimResponseIntegration(t, [], y, 5)));
end

function testFlatSignalReturnsNaN(tests)
    t = 0:0.01:1; y = ones(size(t));
    verifyTrue(tests, isnan(SignalFeatures.fwhm(t, y, 0)));
    verifyTrue(tests, isnan(SignalFeatures.riseTime(t, y, 0)));
    verifyTrue(tests, isnan(SignalFeatures.decayTime(t, y, 0)));
end

function testStimResponseIntegration(tests)
    t = 0:0.001:2; y = ones(size(t));
    verifyEqual(tests, SignalFeatures.stimResponseIntegration(t, [], y, 0.5), 1.5, 'AbsTol', 1e-9);
end
