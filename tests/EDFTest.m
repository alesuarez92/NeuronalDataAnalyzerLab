%% EDFTest.m
% =========================================================================
% EDF, EDF+ AND BDF FILES
% =========================================================================
% core/io/readEDF on files from writeEDF (checked during development
% against pyedflib and MNE-Python, which read the same values and
% annotations; not part of this test): EDF+C with channels at two rates
% and annotations (with and without duration, UTF-8 text), plain EDF,
% BDF 24-bit with the Status trigger word, EDF+D with a gap, a header
% written by hand from the EDF specification, a file cut short, and
% files that are not EDF. Then the Extract LDF path: SignalSource opens
% an EDF, guesses the LDF and stimulus channels and takes the
% annotations as events. No display needed.
% =========================================================================

function tests = EDFTest
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

function S = signals()
    t = (0:2559) / 256;
    S = struct('label', {'Fz', 'Cz', 'Trigger'}, 'units', {'uV', 'uV', 'V'}, 'fs', {256, 256, 128}, ...
        'data', {50 * sin(2 * pi * 10 * t), 20 * cos(2 * pi * 3 * t) - 5, 5 * double(mod(0:1279, 256) < 26)});
end

function testEDFPlusRoundTrip(tests)
    S = signals();
    A = struct('onset', {1.5, 4.25, 7}, 'duration', {0.5, NaN, 0}, 'text', {'Stim A', 'Stim B', ['R' char(233) 'ponse']});
    f = tmp(tests, 'c.edf');
    writeEDF(f, S, 'Format', 'EDF+C', 'Annotations', A, 'StartTime', '2026-09-30 13:45:10');
    E = readEDF(f);
    tests.verifyEqual(E.format, 'EDF+C');
    tests.verifyEqual(E.startTime, '2026-09-30 13:45:10');
    tests.verifyEqual({E.signals.label}, {'Fz', 'Cz', 'Trigger'});
    tests.verifyEqual({E.signals.units}, {'uV', 'uV', 'V'});
    tests.verifyEqual([E.signals.fs], [256 256 128]);
    for k = 1:3
        step = (E.signals(k).physMax - E.signals(k).physMin) / 65535;
        tests.verifyEqual(E.signals(k).data, S(k).data, 'AbsTol', step / 2 + 1e-9, S(k).label);
    end
    tests.verifyEqual([E.annotations.onset], [1.5 4.25 7]);
    tests.verifyEqual([E.annotations.duration], [0.5 NaN 0]);
    tests.verifyEqual({E.annotations.text}, {'Stim A', 'Stim B', ['R' char(233) 'ponse']});
    tests.verifyEqual(E.nRecords, 10);
    tests.verifyEqual(E.nGaps, 0);
    % Plain EDF: no annotation signal
    writeEDF(tmp(tests, 'p.edf'), S(1:2));
    E = readEDF(tmp(tests, 'p.edf'));
    tests.verifyEqual(E.format, 'EDF');
    tests.verifyEmpty(E.annotations);
    tests.verifyEqual(numel(E.signals), 2);
end

function testBDFStatus(tests)
    S = signals();
    st = zeros(1, 2560); st(257:280) = 3; st(1025:1100) = 65536 + 12;   % high byte: not a trigger
    f = tmp(tests, 'b.bdf');
    writeEDF(f, struct('label', {'Fz', 'Status'}, 'units', {'uV', ''}, 'fs', 256, 'data', {S(1).data, st}), 'Format', 'BDF');
    E = readEDF(f);
    tests.verifyEqual(E.format, 'BDF');
    step = (E.signals(1).physMax - E.signals(1).physMin) / (2^24 - 1);
    tests.verifyEqual(E.signals(1).data, S(1).data, 'AbsTol', step / 2 + 1e-12);
    tests.verifyLessThan(step, 1e-4, '24 bits');
    tests.verifyEqual(unique(E.signals(2).data), [0 3 12]);
    tests.verifyEqual(find(E.signals(2).data == 3), 257:280);
end

function testEDFPlusDiscontinuous(tests)
    S = signals();
    f = tmp(tests, 'd.edf');
    writeEDF(f, S(1), 'Format', 'EDF+D', 'RecordStarts', [0 1 2 5 6 7 8 9 10 11], ...
        'Annotations', struct('onset', 5.5, 'duration', NaN, 'text', 'after the gap'));
    E = readEDF(f);
    tests.verifyEqual(E.format, 'EDF+D');
    tests.verifyEqual(E.nGaps, 1);
    tests.verifyEqual(E.recordStarts, [0 1 2 5 6 7 8 9 10 11]);
    x = E.signals(1).data;
    tests.verifyEqual(numel(x), 12 * 256);
    tests.verifyEqual(x(3 * 256 + 1:5 * 256), zeros(1, 512), 'gap filled with zeros');
    tests.verifyEqual(x(5 * 256 + (1:256)), S(1).data(3 * 256 + (1:256)), 'AbsTol', 1e-3);
    tests.verifyEqual(E.annotations.onset, 5.5);
    tests.verifyNotEmpty(E.notes);
end

function testHandWrittenHeader(tests)
    % One signal, 2 records of 4 samples, written field by field from the
    % EDF specification (edfplus.info): physical -100..100 uV, digital
    % -2048..2047, start 30.09.26 08.15.00
    fld = @(s, n) [s repmat(' ', 1, n - numel(s))];
    h = [fld('0', 8) fld('X X X X', 80) fld('Startdate 30-SEP-2026 X X X', 80) '30.09.26' '08.15.00' ...
        fld('512', 8) fld('', 44) fld('2', 8) fld('0.5', 8) fld('1', 4) ...
        fld('EEG Oz', 16) fld('AgAgCl electrode', 80) fld('uV', 8) fld('-100', 8) fld('100', 8) ...
        fld('-2048', 8) fld('2047', 8) fld('HP:0.1Hz LP:75Hz', 80) fld('4', 8) fld('', 32)];
    tests.verifyEqual(numel(h), 512);
    d = int16([-2048 0 2047 1000, -1000 -1 1 2]);
    f = tmp(tests, 'hand.edf');
    fid = fopen(f, 'w', 'ieee-le'); fwrite(fid, uint8(h), 'uint8'); fwrite(fid, d, 'int16'); fclose(fid);
    E = readEDF(f);
    tests.verifyEqual(E.format, 'EDF');
    tests.verifyEqual(E.startTime, '2026-09-30 08:15:00');
    tests.verifyEqual(E.signals.label, 'EEG Oz');
    tests.verifyEqual(E.signals.transducer, 'AgAgCl electrode');
    tests.verifyEqual(E.signals.prefilter, 'HP:0.1Hz LP:75Hz');
    tests.verifyEqual(E.signals.fs, 8);
    g = 200 / 4095;
    tests.verifyEqual(E.signals.data, (double(d) + 2048) * g - 100, 'AbsTol', 1e-12);
    % Cut short: the header says 2 records, the file holds 1
    f2 = tmp(tests, 'short.edf');
    fid = fopen(f2, 'w', 'ieee-le'); fwrite(fid, uint8(h), 'uint8'); fwrite(fid, d(1:4), 'int16'); fclose(fid);
    E = readEDF(f2);
    tests.verifyEqual(numel(E.signals.data), 4);
    tests.verifyNotEmpty(E.notes);
end

function testNotEDF(tests)
    f = tmp(tests, 'x.edf');
    fid = fopen(f, 'w'); fprintf(fid, 'this is a text file that is long enough %s', repmat('x', 1, 300)); fclose(fid);
    tests.verifyError(@() readEDF(f), 'NeuroAnalyzer:io:edf');
    fid = fopen(f, 'w'); fwrite(fid, uint8('0       '), 'uint8'); fclose(fid);
    tests.verifyError(@() readEDF(f), 'NeuroAnalyzer:io:edf');
    tests.verifyError(@() readEDF(tmp(tests, 'missing.edf')), 'NeuroAnalyzer:io:fileNotFound');
end

function testSignalSourceEDF(tests)
    % Extract LDF: an EDF export with an LDF channel, a trigger and annotations
    t = (0:9999) / 100;
    ldf = 120 + 10 * double(mod(t, 20) >= 5 & mod(t, 20) < 10);
    trig = 5 * double(mod(t, 20) >= 5 & mod(t, 20) < 5.2);
    S = struct('label', {'Blood pressure', 'LDF 1', 'Trigger'}, 'units', {'mmHg', 'PU', 'V'}, 'fs', 100, ...
        'data', {80 + 0 * t, ldf, trig});
    f = tmp(tests, 'ldf.edf');
    writeEDF(f, S, 'Format', 'EDF+C', 'Annotations', struct('onset', {5, 25}, 'duration', NaN, 'text', 'Puff'));
    tests.verifyEqual(SignalSource.detect(f), 'edf');
    rec = SignalSource.open(f);
    tests.verifyEqual(rec.names, {'Blood pressure', 'LDF 1', 'Trigger'});
    tests.verifyEqual(rec.units, {'mmHg', 'PU', 'V'});
    [iFlow, iStim] = SignalSource.guessChannels(rec);
    tests.verifyEqual([iFlow iStim], [2 3]);
    tests.verifyEqual(rec.channels(2).data, ldf, 'AbsTol', 1e-3);
    tests.verifyEqual([rec.events.time], [5 25]);
    tests.verifyEqual({rec.events.text}, {'Puff', 'Puff'});
end
