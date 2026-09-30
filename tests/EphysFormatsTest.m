%% EphysFormatsTest.m
% =========================================================================
% ELECTROPHYSIOLOGY RECORDINGS FROM MORE ACQUISITION SYSTEMS
% =========================================================================
% core/io readers on files written by their synthetic writers in the
% layouts the vendors document (each writer was checked against the
% independent python-neo readers during development; the neo check is
% not part of this test): SpikeGLX imec (Neuropixels 1.0 and 2.0 gains,
% sync word) and nidq (MN / XA / digital word), Blackrock NSx 2.1 / 2.3 /
% 3.0 (scaling, analog inputs, several data blocks) with NEV digital
% events, Neuralynx .ncs folders (ADBitVolts, inverted input, natural
% channel order) with Events.nev TTLs, Axon ABF 2 (gap-free, episodic
% with sweep start times, float32), Open Ephys legacy .continuous folders
% (CH, ADC, TTL events, first timestamp), Intan RHS2000 (digital and
% analog inputs, stimulation current, DC amplifier data saved) and
% Plexon .plx (versions 107 and 102, AI channels, events, spike times,
% gaps). Values in volts, rates, channel names and the stimulus lines are
% checked. No display needed.
% =========================================================================

function tests = EphysFormatsTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'io'));
    tests.TestData.dir = tempname;
    mkdir(tests.TestData.dir);
end

function teardownOnce(tests)
    try, rmdir(tests.TestData.dir, 's'); catch, end
end

function f = tmp(tests, name)
    f = fullfile(tests.TestData.dir, name);
end

function x = ramp(nCh, n)
    x = zeros(nCh, n);
    for c = 1:nCh, x(c, :) = sin(2 * pi * (1:n) / (50 + 10 * c)) * c; end
end

function testSpikeGLX(tests)
    d = tmp(tests, 'run_g0'); mkdir(d);
    q = int16(round(100 * ramp(4, 400)));
    sy = zeros(1, 400, 'int16'); sy(101:150) = 64; sy(301:350) = 64;
    f = fullfile(d, 'run_g0_t0.imec0.ap.bin');
    writeSpikeGLX(f, [q; sy], 'imec1', 'Gain', 500);
    rec = readSpikeGLX(f);
    tests.verifyEqual(rec.info.format, 'spikeglx');
    tests.verifyEqual(rec.streams.xRAW.fs, 30000);
    tests.verifyEqual(double(rec.streams.xRAW.data), double(q) * 0.6 / 512 / 500, 'AbsTol', 1e-10);
    tests.verifyEqual(rec.info.channelNames, {'AP0', 'AP1', 'AP2', 'AP3'});
    tests.verifyEqual(rec.info.stimNames, {'SY bit 6'});
    tests.verifyEqual(find(diff([0 double(rec.streams.Whis.data)]) == 1), [101 301]);
    % Neuropixels 2.0: fixed gain 80, 8192 steps; open by the .meta
    f2 = fullfile(d, 'run_g0_t0.imec1.ap.bin');
    writeSpikeGLX(f2, [q; sy], 'imec2');
    rec = readSpikeGLX(strrep(f2, '.bin', '.meta'));
    tests.verifyEqual(double(rec.streams.xRAW.data), double(q) * 0.5 / 8192 / 80, 'AbsTol', 1e-10);
    tests.verifySubstring(rec.info.source, '2.0');
    % nidq: 2 MN channels (gain 200), 1 XA, 1 digital word
    xa = int16(round(16384 * double(mod(0:399, 200) < 20)));
    dw = zeros(1, 400, 'int16'); dw(51:60) = 5;
    fn = fullfile(d, 'run_g0_t0.nidq.bin');
    writeSpikeGLX(fn, [q(1:2, :); xa; dw], 'nidq', 'Counts', [2 0 1 1]);
    rec = readSpikeGLX(fn);
    tests.verifyEqual(rec.streams.xRAW.fs, 25000);
    tests.verifyEqual(double(rec.streams.xRAW.data), double(q(1:2, :)) * 5 / 32768 / 200, 'AbsTol', 1e-10);
    tests.verifyEqual(rec.info.stimNames, {'XA0', 'DW0 bit 0', 'DW0 bit 2'});
    tests.verifyEqual(double(rec.streams.Whis.data(1, 1)), 2.5, 'AbsTol', 1e-4);
    tests.verifyEqual(find(double(rec.streams.Whis.data(2, :))), 51:60);
    % Missing .meta
    delete(strrep(fn, '.bin', '.meta'));
    tests.verifyError(@() readSpikeGLX(fn), 'NeuroAnalyzer:io:spikeglx');
end

function testBlackrock(tests)
    x = 50e-6 * ramp(3, 3000);
    a = 0.5 * double(mod(0:2999, 1000) < 100);
    dig = struct('sample', {1001, 1101, 2001, 2101}, 'value', {1, 0, 3, 0});
    for spec = {'2.3', '3.0'}
        b = tmp(tests, ['br' strrep(spec{1}, '.', '')]);
        writeBlackrock(b, [x; a], 30000, 'ElectrodeIds', [1 2 3 129], 'Spec', spec{1}, 'Digital', dig, 'Blocks', [1 1501]);
        rec = readBlackrock([b '.ns6']);
        tests.verifyEqual(rec.streams.xRAW.fs, 30000);
        tests.verifyEqual(double(rec.streams.xRAW.data), x, 'AbsTol', 2e-7, spec{1});
        tests.verifyEqual(rec.info.channelNames, {'elec1', 'elec2', 'elec3'});
        tests.verifyEqual(rec.info.nBlocks, 2);
        tests.verifyEqual(rec.info.stimNames, {'ainp1', 'Digital in bit 0', 'Digital in bit 1'});
        s = double(rec.streams.Whis.data);
        tests.verifyEqual(s(1, :), a, 'AbsTol', 1e-3);
        tests.verifyEqual(find(diff([0 s(2, :)]) == 1), [1001 2001]);
        tests.verifyEqual(find(diff([0 s(3, :)]) == 1), 2001);
        % Opened by the .nev as well
        rec2 = readBlackrock([b '.nev']);
        tests.verifyEqual(rec2.streams.xRAW.data, rec.streams.xRAW.data);
    end
    % 2.1 (no scaling in the file: 0.25 uV per bit)
    b = tmp(tests, 'br21');
    writeBlackrock(b, x, 10000, 'Spec', '2.1', 'Ext', '.ns4');
    rec = readBlackrock([b '.ns4']);
    tests.verifyEqual(rec.streams.xRAW.fs, 10000);
    tests.verifyEqual(double(rec.streams.xRAW.data), x, 'AbsTol', 2e-7);
    % Not an NSx
    f = tmp(tests, 'bad.ns5');
    fid = fopen(f, 'w'); fwrite(fid, uint8('NOTBLACK'), 'uint8'); fwrite(fid, zeros(1, 400), 'uint8'); fclose(fid);
    tests.verifyError(@() readBlackrock(f), 'NeuroAnalyzer:io:blackrock');
end

function testNeuralynx(tests)
    x = 100e-6 * ramp(3, 2000);
    d = tmp(tests, 'nlx');
    names = {'CSC1', 'CSC2', 'CSC10'};
    writeNeuralynx(d, x, 32000, 'Names', names, 'TTL', struct('sample', {300, 500, 1300}, 'value', {1, 0, 1}));
    rec = readNeuralynx(d);
    tests.verifyEqual(rec.streams.xRAW.fs, 32000);
    tests.verifyEqual(rec.info.channelNames, names, 'CSC10 after CSC2');
    tests.verifyEqual(double(rec.streams.xRAW.data), x, 'AbsTol', 2e-8);
    tests.verifyEqual(rec.info.stimNames, {'TTL bit 0'});
    tests.verifyEqual(find(diff([0 double(rec.streams.Whis.data)]) == 1), [300 1300]);
    tests.verifyEqual(rec.info.nGaps, 0);
    % The sign follows InputInverted; a .ncs opens its whole folder
    d2 = tmp(tests, 'nlx2');
    writeNeuralynx(d2, x(1, :), 32000, 'InputInverted', false);
    rec = readNeuralynx(fullfile(d2, 'CSC1.ncs'));
    tests.verifyEqual(double(rec.streams.xRAW.data), x(1, :), 'AbsTol', 2e-8);
    tests.verifyEqual(rec.info.stimNames, {'(no stimulus channel)'});
    e = tmp(tests, 'empty'); mkdir(e);
    tests.verifyError(@() readNeuralynx(e), 'NeuroAnalyzer:io:neuralynx');
end

function testABF(tests)
    % Gap-free int16: mV channels become volts, a pA channel is a stimulus
    x = [ramp(2, 1000); 50 * double(mod(0:999, 250) < 25)];
    f = tmp(tests, 'gapfree.abf');
    writeABF(f, x, 20000, 'Names', {'Vm', 'Vm2', 'Icmd'}, 'Units', {'mV', 'mV', 'pA'});
    rec = readABF(f);
    tests.verifyEqual(rec.info.format, 'abf');
    tests.verifyEqual(rec.streams.xRAW.fs, 20000, 'AbsTol', 1e-6);
    tests.verifyEqual(rec.info.channelNames, {'Vm', 'Vm2'});
    tests.verifyEqual(double(rec.streams.xRAW.data), x(1:2, :) * 1e-3, 'AbsTol', 1e-7);
    tests.verifyEqual(rec.info.stimNames, {'Icmd'});
    tests.verifyEqual(double(rec.streams.Whis.data), x(3, :), 'AbsTol', 0.01);
    tests.verifyEqual(rec.info.nSweeps, 1);
    % Episodic: 3 sweeps of 400 samples, started 1 s apart
    e = reshape(ramp(1, 1200), 1, 400, 3);
    f = tmp(tests, 'episodic.abf');
    writeABF(f, e, 10000, 'SweepStarts', [0 1 2]);
    rec = readABF(f);
    tests.verifyEqual(rec.info.nSweeps, 3);
    tests.verifyEqual(rec.info.sweepStarts, [0 1 2], 'AbsTol', 1e-6);
    tests.verifyEqual(double(rec.streams.xRAW.data), reshape(e, 1, []) * 1e-3, 'AbsTol', 1e-7);
    tests.verifyEqual(rec.info.stimNames, {'(no stimulus channel)'});
    % float32 samples are used as they are
    f = tmp(tests, 'float.abf');
    writeABF(f, x(1, :), 20000, 'Float', true, 'Units', {'V'});
    rec = readABF(f);
    tests.verifyEqual(double(rec.streams.xRAW.data), x(1, :), 'AbsTol', 1e-6);
    % ABF 1 is refused
    f = tmp(tests, 'old.abf');
    fid = fopen(f, 'w'); fwrite(fid, uint8('ABF '), 'uint8'); fwrite(fid, zeros(1, 2044), 'uint8'); fclose(fid);
    tests.verifyError(@() readABF(f), 'NeuroAnalyzer:io:abf');
end

function testOpenEphysLegacy(tests)
    x = 100e-6 * ramp(3, 2500);
    a = 2 * double(mod(0:2499, 1000) < 100);
    d = tmp(tests, 'oe_legacy');
    ttl = struct('channel', {0, 2}, 'on', {[301 1301], 2001}, 'off', {[401 1401], 2101});
    writeOpenEphysLegacy(d, x, 30000, 'ADC', a, 'TTL', ttl, 'FirstTimestamp', 5000);
    rec = readOpenEphysLegacy(d);
    tests.verifyEqual(rec.info.format, 'openephyslegacy');
    tests.verifyEqual(rec.streams.xRAW.fs, 30000);
    tests.verifyEqual(rec.info.channelNames, {'CH1', 'CH2', 'CH3'});
    tests.verifyEqual(size(rec.streams.xRAW.data), [3 2500]);
    tests.verifyEqual(double(rec.streams.xRAW.data), x, 'AbsTol', 2e-7);
    tests.verifyEqual(rec.info.firstTimestamp, 5000);
    tests.verifyEqual(rec.info.stimNames, {'ADC1', 'TTL 1', 'TTL 3'});
    s = double(rec.streams.Whis.data);
    tests.verifyEqual(s(1, :), a, 'AbsTol', 1e-3);
    tests.verifyEqual(find(diff([0 s(2, :)]) == 1), [301 1301]);
    tests.verifyEqual(find(s(3, :)), 2001:2100);
    % A .continuous opens its folder
    rec2 = readOpenEphysLegacy(fullfile(d, '100_CH2.continuous'));
    tests.verifyEqual(rec2.streams.xRAW.data, rec.streams.xRAW.data);
    e = tmp(tests, 'oe_empty'); mkdir(e);
    tests.verifyError(@() readOpenEphysLegacy(e), 'NeuroAnalyzer:io:openephys');
end

function testIntanRHS(tests)
    n = 1000;                                           % padded to 1024
    x = 200e-6 * ramp(2, n);
    din = zeros(2, n); din(1, 101:200) = 1; din(2, 601:700) = 1;
    adc = 1.5 * double(mod(0:n-1, 500) < 50);
    st = zeros(2, n); st(2, 301:310) = -20e-6; st(2, 311:320) = 20e-6;
    f = tmp(tests, 'stim.rhs');
    writeIntanRHS(f, x, 30000, 'DigitalIn', din, 'ADC', adc, 'Stim', st, 'DC', true, 'Names', {'A-000', 'A-001'});
    rec = readIntanRHS(f);
    tests.verifyEqual(rec.info.format, 'intanrhs');
    tests.verifyEqual(rec.streams.xRAW.fs, 30000);
    tests.verifyEqual(rec.info.channelNames, {'A-000', 'A-001'});
    tests.verifyEqual(size(rec.streams.xRAW.data, 2), 1024);
    tests.verifyEqual(double(rec.streams.xRAW.data(:, 1:n)), x, 'AbsTol', 2e-7);
    tests.verifyEqual(rec.info.nGaps, 0);
    tests.verifyEqual(rec.info.stimNames, {'DIGITAL-IN-01', 'DIGITAL-IN-02', 'ANALOG-IN-1', 'Stim current A-001'});
    s = double(rec.streams.Whis.data(:, 1:n));
    tests.verifyEqual(s(1:2, :), din);
    tests.verifyEqual(s(3, :), adc, 'AbsTol', 4e-4);
    tests.verifyEqual(s(4, :), st(2, :), 'AbsTol', 1e-9);
    % Without DC data, inputs or stimulation
    f2 = tmp(tests, 'plain.rhs');
    writeIntanRHS(f2, x, 20000);
    rec = readIntanRHS(f2);
    tests.verifyEqual(double(rec.streams.xRAW.data(:, 1:n)), x, 'AbsTol', 2e-7);
    tests.verifyEqual(rec.info.stimNames, {'(no stimulus channel)'});
    f3 = tmp(tests, 'bad.rhs');
    fid = fopen(f3, 'w'); fwrite(fid, zeros(1, 200), 'uint8'); fclose(fid);
    tests.verifyError(@() readIntanRHS(f3), 'NeuroAnalyzer:io:intan');
end

function testPlexon(tests)
    x = 100e-6 * ramp(3, 2500);
    ai = 2 * double(mod(0:2499, 1000) < 100);
    ev = struct('channel', {1, 3, 257}, 'sample', {[301 1301], 2001, [10 20]});
    sp = struct('channel', {1, 1, 2}, 'unit', {0, 1, 1}, 'sample', {[100 200], 500, [700 800 900]});
    f = tmp(tests, 'rec.plx');
    writePlexon(f, x, 20000, 'AI', ai, 'Events', ev, 'Spikes', sp, 'Start', 4000);
    rec = readPlexon(f);
    tests.verifyEqual(rec.info.format, 'plexon');
    tests.verifyEqual(rec.streams.xRAW.fs, 20000);
    tests.verifyEqual(rec.info.channelNames, {'WB01', 'WB02', 'WB03'});
    tests.verifyEqual(double(rec.streams.xRAW.data), x, 'AbsTol', 1e-7);
    tests.verifyEqual(rec.info.firstTimestamp, 0.1, 'AbsTol', 1e-12);
    tests.verifyEqual(rec.info.stimNames, {'AI01', 'EVT01', 'EVT03'}, 'strobed events left out');
    s = double(rec.streams.Whis.data);
    tests.verifyEqual(s(1, :), ai, 'AbsTol', 1e-4);
    tests.verifyEqual(find(diff([0 s(2, :)]) == 1), [301 1301]);
    tests.verifyEqual(find(s(3, :)), 2001:2020, '1 ms pulse');
    tests.verifyEqual([rec.info.spikes.channel], [1 1 2]);
    tests.verifyEqual([rec.info.spikes.unit], [0 1 1]);
    tests.verifyEqual(rec.info.spikes(3).times, ([700 800 900] - 1) / 20000, 'AbsTol', 1e-9);
    % Version 102 gains, a field-potential channel and a 0.5 s gap
    f2 = tmp(tests, 'old.plx');
    writePlexon(f2, x(1, :), 1000, 'Version', 102, 'Names', {'FP01'}, 'GapAfter', 1, 'GapTicks', 20000);
    rec = readPlexon(f2);
    tests.verifyEqual(rec.info.nGaps, 1);
    v = double(rec.streams.xRAW.data);
    tests.verifyEqual(size(v), [1 3000]);
    tests.verifyEqual(v([1:1000 1501:3000]), x(1, :), 'AbsTol', 1.3e-6);
    tests.verifyEqual(v(1001:1500), zeros(1, 500));
    tests.verifyEqual(rec.info.stimNames, {'(no stimulus channel)'});
    f3 = tmp(tests, 'bad.plx');
    fid = fopen(f3, 'w'); fwrite(fid, zeros(1, 8000), 'uint8'); fclose(fid);
    tests.verifyError(@() readPlexon(f3), 'NeuroAnalyzer:io:plexon');
end
