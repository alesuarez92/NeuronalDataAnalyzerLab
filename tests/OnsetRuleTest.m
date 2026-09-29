%% OnsetRuleTest.m
% =========================================================================
% ONE STIMULUS-ONSET RULE FOR LDF, LFP / ERP AND MUA
% =========================================================================
% LDFPipeline.detectOnsets, ERPAnalysis.detectOnsets and
% SpikeTrains.stimulusOnsets keep a threshold crossing only if it comes
% more than the minimum interval after the last KEPT onset. A train of
% pulses then gives one onset per train. (ERP and MUA used to compare with
% the previous crossing, so in a pulse train every pulse after the first
% was dropped and a whole recording of trains gave a single onset.)
% =========================================================================

function tests = OnsetRuleTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests) %#ok<INUSD>
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
end

%% pulseTrains - 4 trains of 5 pulses (10 Hz, 20 ms) every 3 s, from 1 s, at fs
function [stim, t, trainStarts] = pulseTrains(fs)
    t = (0:round(14 * fs) - 1) / fs;
    stim = zeros(size(t));
    trainStarts = 1 + (0:3) * 3;
    for s = trainStarts
        for p = 0:4
            on = s + p * 0.1;
            stim(t >= on & t < on + 0.02) = 5;
        end
    end
end

function testPulseTrainsGiveOneOnsetPerTrain(tests)
    fs = 1000;
    [stim, t, starts] = pulseTrains(fs);
    ldf = (LDFPipeline.detectOnsets(stim, fs, 2.5, 0.5) - 1) / fs;
    erp = ERPAnalysis.detectOnsets(stim, fs, 2.5, 0.5);
    mua = SpikeTrains.stimulusOnsets(stim, t, 2.5, 0.5);
    verifyEqual(tests, ldf(:)', starts, 'AbsTol', 1 / fs);
    verifyEqual(tests, erp(:)', starts, 'AbsTol', 1 / fs);
    verifyEqual(tests, mua(:)', starts, 'AbsTol', 1 / fs);
end

function testShortIntervalKeepsEveryPulse(tests)
    % With a minimum interval shorter than the pulse spacing, every pulse counts
    fs = 1000;
    [stim, t] = pulseTrains(fs);
    verifyNumElements(tests, ERPAnalysis.detectOnsets(stim, fs, 2.5, 0.05), 20);
    verifyNumElements(tests, SpikeTrains.stimulusOnsets(stim, t, 2.5, 0.05), 20);
    verifyNumElements(tests, LDFPipeline.detectOnsets(stim, fs, 2.5, 0.05), 20);
end
