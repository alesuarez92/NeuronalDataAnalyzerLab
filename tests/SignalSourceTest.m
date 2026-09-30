%% SignalSourceTest.m
% =========================================================================
% PHYSIOLOGY RECORDINGS FROM THE COMMON ACQUISITION SYSTEMS (LDF IMPORT)
% =========================================================================
% core/io/SignalSource.m, readSignalText.m, readBiopacACQ.m and
% writeBiopacACQ.m: every format is built here as its software writes it
% (LabChart .mat with several blocks, rates, an empty channel and
% comments; LabChart and AcqKnowledge text; a PeriSoft / moorVMS-style table
% with a decimal comma and clock times; AcqKnowledge .acq, uncompressed,
% compressed and big-endian, with rates that differ and event markers;
% AcqKnowledge and Spike2 .mat exports), then read back: names, units,
% rates, values, comments / markers and their times, the flow and
% stimulus channels guessed from the names, and the stimulus put on the
% flow channel's time base; the LDF demo written in the other formats
% (core/demo/demoLDFFormats.m) gives the same flow and stimuli in each.
% No display needed.
% =========================================================================

function tests = SignalSourceTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'io'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.dir = tempname;
    mkdir(tests.TestData.dir);
end

function teardownOnce(tests)
    try, rmdir(tests.TestData.dir, 's'); catch, end
end

function f = tmp(tests, name)
    f = fullfile(tests.TestData.dir, name);
end

function writeText(f, s)
    fid = fopen(f, 'w');
    fwrite(fid, unicode2native(s, 'UTF-8'));
    fclose(fid);
end

function testLabChartDemoExport(tests)
    d = DemoData.ldfExport();
    rec = SignalSource.fromStruct(d, 'demo.mat');
    tests.verifyEqual(rec.info.format, 'labchart');
    tests.verifyEqual(rec.nChannels, 8);
    [iFlow, iStim] = SignalSource.guessChannels(rec);
    tests.verifyEqual([iFlow iStim], [8 6], 'LDF and Stimulus found by name');
    L = SignalSource.toLDF(rec, iFlow, iStim, 1);
    % The same numbers as the long-standing loader (channels 6 and 8)
    A = DataLoader.load(struct('RawStim', [], 'RawLDF', [], 'SamplingRate', 1000, 'FilePath', '', ...
        'Metadata', struct()), 'FromStruct', d);
    tests.verifyEqual(L.LDF, double(A.RawLDF(:))', 'AbsTol', 1e-12);
    tests.verifyEqual(L.stim, double(A.RawStim(:))', 'AbsTol', 1e-12);
    tests.verifyEqual(L.Fs, 1000);
    tests.verifyEqual(L.flowName, 'LDF');
    % Unnamed channels: the old convention (stimulus 6, LDF 8) still applies
    d.titles = char(arrayfun(@(k) sprintf('Channel %d', k), 1:8, 'UniformOutput', false));
    [iFlow, iStim] = SignalSource.guessChannels(SignalSource.fromStruct(d));
    tests.verifyEqual([iFlow iStim], [8 6]);
end

function testLabChartBlocksRatesAndComments(tests)
    % 3 channels x 2 blocks: Trigger at 1000 Hz, Flux at 100 Hz, Temp empty in block 2
    fsT = 1000; fsF = 100;
    trig1 = zeros(1, 5000); trig1(1001:1200) = 5; trig1(3001:3200) = 5;     % 1 s and 3 s
    flux1 = 50 + (0:499) / 10;
    temp1 = 37 * ones(1, 50);
    trig2 = zeros(1, 2000); trig2(501:600) = 5;                            % 0.5 s
    flux2 = 80 * ones(1, 200);
    data = [trig1 flux1 temp1 trig2 flux2];
    d.data = data;
    d.datastart = [1 5551; 5001 7551; 5501 -1];
    d.dataend = [5000 7550; 5500 7750; 5550 -1];
    d.samplerate = [fsT fsT; fsF fsF; 10 10];
    d.titles = char('Trigger', 'Laser Doppler Flux', 'Temperature');
    d.unittext = char('V', 'PU', 'degC');
    d.unittextmap = [1 1; 2 2; 3 -1];
    d.tickrate = [1000 1000];
    d.blocktimes = [datenum(2026, 9, 30, 10, 0, 0) datenum(2026, 9, 30, 10, 5, 0)];
    d.firstsampleoffset = zeros(3, 2);
    d.com = [-1 1 1000 1 1; 2 1 3000 2 2; -1 2 500 1 1];
    d.comtext = char('stim', 'marker B');
    f = tmp(tests, 'labchart_blocks.mat');
    save(f, '-struct', 'd');
    tests.verifyEqual(SignalSource.detect(f), 'labchart');
    rec = SignalSource.open(f);
    tests.verifyEqual([rec.nChannels rec.nBlocks], [3 2]);
    tests.verifyEqual(rec.names, {'Trigger', 'Laser Doppler Flux', 'Temperature'});
    tests.verifyEqual(rec.units, {'V', 'PU', 'degC'});
    tests.verifyEmpty(SignalSource.channel(rec, 3, 2), 'empty channel in block 2 skipped');
    tests.verifyEqual(SignalSource.channel(rec, 2, 2).data, flux2);
    tests.verifyEqual(rec.info.blockStart{2}(1:19), '2026-09-30T10:05:00');
    tests.verifyEqual([rec.events.time], [1 3 0.5], 'AbsTol', 1e-12);
    tests.verifyEqual({rec.events.text}, {'stim', 'marker B', 'stim'});
    tests.verifyEqual({rec.events.type}, {'comment', 'marker', 'comment'});
    tests.verifyEqual([rec.events.channel], [0 2 0]);
    [iFlow, iStim] = SignalSource.guessChannels(rec);
    tests.verifyEqual([iFlow iStim], [2 1]);
    items = SignalSource.channelItems(rec);
    tests.verifyEqual(items{2}, '2: Laser Doppler Flux (PU, 100 Hz)');
    [sItems, sVals] = SignalSource.stimItems(rec);
    tests.verifyEqual(sItems(end-3:end), {'Comments / markers (3)', 'Comments "stim" (2)', ...
        'Comments "marker B" (1)', 'None'});
    tests.verifyEqual(sVals{end}, 0);
    % A faster trigger onto the 100 Hz flux: the maximum of each interval (pulses kept)
    L = SignalSource.toLDF(rec, 2, 1, 1);
    tests.verifyEqual(numel(L.stim), 500);
    tests.verifyEqual(find(diff([0 L.stim]) > 0), [101 301], 'onsets at 1 s and 3 s');
    tests.verifyEqual(max(L.stim), 5);
    % Comments as the stimulus: 0.5 s pulses at the comment times
    L = SignalSource.toLDF(rec, 2, 'events:stim', 1);
    tests.verifyEqual(L.onsets, 1);
    tests.verifyEqual(find(L.stim), 101:150);
    L = SignalSource.toLDF(rec, 2, 'events', 1);
    tests.verifyEqual(L.onsets, [1 3]);
    L2 = SignalSource.toLDF(rec, 2, 1, 2);
    tests.verifyEqual(find(diff([0 L2.stim]) > 0), 51, 'block 2: onset at 0.5 s');
    tests.verifyError(@() SignalSource.toLDF(rec, 3, 1, 2), 'NeuroAnalyzer:io:noChannels');
end

function testLabChartTextExport(tests)
    t = (0:399) * 0.01;
    stim = 5 * double(t >= 1 & t < 1.2);
    ldf = 120 + 10 * sin(2 * pi * 0.25 * t);
    rows = cell(1, 400);
    for k = 1:400
        rows{k} = sprintf('%.2f\t%.4f\t%.3f', t(k), stim(k), ldf(k));
        if k == 101, rows{k} = [rows{k} sprintf('\t#* stim on')]; end
    end
    head = sprintf(['Interval=\t0.01 s\nExcelDateTime=\t4.6294e+04\t9/30/2026 10:00:00.000\n' ...
        'TimeFormat=\tStartOfBlock\nDateFormat=\tM/d/yyyy\nChannelTitle=\tStim\tLaser Doppler\n' ...
        'Range=\t10.000 V\t1000.0 PU\n']);
    block2 = sprintf('Interval=\t0.01 s\nChannelTitle=\tStim\tLaser Doppler\nRange=\t10.000 V\t1000.0 PU\n0\t0\t90\n0.01\t5\t91\n');
    f = tmp(tests, 'labchart_export.txt');
    writeText(f, [head strjoin(rows, newline) newline block2]);
    tests.verifyEqual(SignalSource.detect(f), 'text');
    rec = SignalSource.open(f);
    tests.verifyEqual(rec.info.label, 'LabChart text export');
    tests.verifyEqual(rec.names, {'Stim', 'Laser Doppler'});
    tests.verifyEqual(rec.units, {'V', 'PU'});
    tests.verifyEqual(rec.nBlocks, 2);
    c = SignalSource.channel(rec, 2, 1);
    tests.verifyEqual(c.fs, 100, 'AbsTol', 1e-9);
    tests.verifyEqual(c.data, ldf, 'AbsTol', 5e-4);
    tests.verifyEqual(SignalSource.channel(rec, 2, 2).data, [90 91]);
    tests.verifyEqual(numel(rec.events), 1);
    tests.verifyEqual(rec.events(1).time, 1, 'AbsTol', 1e-9);
    tests.verifyEqual(rec.events(1).text, 'stim on');
    [iFlow, iStim] = SignalSource.guessChannels(rec);
    tests.verifyEqual([iFlow iStim], [2 1]);
end

function testAcqKnowledgeTextAndMat(tests)
    % Text export with header (msec/sample, channels, name / unit lines)
    rows = arrayfun(@(k) sprintf('%g\t%g\t%g', (k - 1) * 25, 100 + k, double(k >= 10 && k < 15)), 1:40, ...
        'UniformOutput', false);
    s = sprintf('C:\\Data\\rat3.acq\n25 msec/sample\n2 channels\nLDF100C\nBPU\nStim\nVolts\nmin\tCH1\tCH2\n');
    f = tmp(tests, 'acq_export.txt');
    writeText(f, [s strjoin(rows, newline)]);
    rec = SignalSource.open(f);
    tests.verifyEqual(rec.info.label, 'AcqKnowledge text export');
    tests.verifyEqual(rec.names, {'LDF100C', 'Stim'});
    tests.verifyEqual(rec.units, {'BPU', 'Volts'});
    tests.verifyEqual(rec.channels(1).fs, 40, 'AbsTol', 1e-9);
    tests.verifyEqual(rec.channels(1).data, 100 + (1:40));
    [iFlow, iStim] = SignalSource.guessChannels(rec);
    tests.verifyEqual([iFlow iStim], [1 2], 'BPU units: the flow channel');
    % MATLAB export: data (samples x channels), labels, units, isi (ms)
    d = struct('data', [(1:10)' 5 * double((1:10)' > 5)], 'labels', char('Flow', 'TTL'), ...
        'units', char('BPU', 'V'), 'isi', 2, 'isi_units', 'ms');
    f = tmp(tests, 'acq_export.mat');
    save(f, '-struct', 'd');
    tests.verifyEqual(SignalSource.detect(f), 'acqmat');
    rec = SignalSource.open(f);
    tests.verifyEqual(rec.channels(1).fs, 500);
    tests.verifyEqual(rec.names, {'Flow', 'TTL'});
    tests.verifyEqual(rec.channels(2).data, 5 * double((1:10) > 5));
end

function testGenericTables(tests)
    % PeriSoft / spreadsheet style: semicolons, decimal comma, units in brackets
    s = sprintf('Time [s];Perfusion [PU];Stimulus\n0,000;101,5;0\n0,025;102,5;0\n0,050;103,5;1\n0,075;104,5;1\n');
    f = tmp(tests, 'perisoft.txt');
    writeText(f, s);
    rec = SignalSource.open(f);
    tests.verifyEqual(rec.names, {'Perfusion', 'Stimulus'});
    tests.verifyEqual(rec.units, {'PU', ''});
    tests.verifyEqual(rec.channels(1).fs, 40, 'AbsTol', 1e-9);
    tests.verifyEqual(rec.channels(1).data, [101.5 102.5 103.5 104.5], 'AbsTol', 1e-12);
    % Clock times (hh:mm:ss.sss) in the first column, tab separated, a units row
    s = sprintf('Time\tFlux\tDC\n\tPU\tAU\n23:59:59.900\t10\t1\n23:59:59.925\t11\t1\n23:59:59.950\t12\t1\n23:59:59.975\t13\t1\n00:00:00.000\t14\t1\n');
    f = tmp(tests, 'moor.txt');
    writeText(f, s);
    rec = SignalSource.open(f);
    tests.verifyEqual(rec.names, {'Flux', 'DC'});
    tests.verifyEqual(rec.units, {'PU', 'AU'});
    tests.verifyEqual(rec.channels(1).fs, 40, 'RelTol', 1e-6, 'past midnight handled');
    tests.verifyEqual(rec.channels(1).data, 10:14);
    % No header and no time column: the rate must be given
    f = tmp(tests, 'plain.csv');
    writeText(f, sprintf('1.5,5\n1.7,6\n1.6,5\n1.9,6\n'));      % first column not rising: no time
    tests.verifyError(@() readSignalText(f), 'NeuroAnalyzer:io:noRate');
    rec = readSignalText(f, struct('Fs', 10));
    tests.verifyEqual(rec.channels(1).fs, 10);
    tests.verifyEqual(rec.names, {'Column 1', 'Column 2'});
    tests.verifyEqual(rec.channels(2).data, [5 6 5 6]);
    % Time in ms (named column)
    writeText(f, sprintf('ms,LDF\n0,1\n10,2\n20,3\n'));
    rec = readSignalText(f);
    tests.verifyEqual(rec.channels(1).fs, 100, 'AbsTol', 1e-9);
    writeText(f, sprintf('no numbers here\n'));
    tests.verifyError(@() readSignalText(f), 'NeuroAnalyzer:io:text');
end

function testSpike2Export(tests)
    d.Ch1 = struct('title', 'LDF', 'interval', 0.01, 'start', 2, 'values', (1:300)', 'units', 'PU');
    d.Ch2 = struct('title', 'Stim', 'interval', 0.001, 'start', 2, 'values', zeros(3000, 1), 'units', 'V');
    d.Ch2.values(1001:1100) = 5;                          % 1 s after the start of the channel
    d.Ch3 = struct('title', 'Keyboard', 'times', [2.5; 3.5], 'codes', [49 0 0 0; 50 0 0 0]);
    f = tmp(tests, 'spike2.mat');
    save(f, '-struct', 'd');
    rec = SignalSource.open(f);
    tests.verifyEqual(rec.info.format, 'spike2');
    tests.verifyEqual(rec.names, {'LDF', 'Stim'});
    tests.verifyEqual(rec.channels(1).t0, 2);
    tests.verifyEqual([rec.events.time], [2.5 3.5]);
    tests.verifyEqual({rec.events.text}, {'Keyboard 49', 'Keyboard 50'});
    L = SignalSource.toLDF(rec, 1, 2, 1);
    tests.verifyEqual(find(diff([0 L.stim]) > 0), 101);
    L = SignalSource.toLDF(rec, 1, 'events', 1);
    tests.verifyEqual(find(diff([0 L.stim]) > 0), [51 151], 'event times relative to the LDF start (2 s)');
end

function testBiopacACQ(tests)
    t = (0:3999) / 1000;
    ch = struct('name', {'LDF100C', 'Stimulus', 'Temp'}, 'units', {'BPU', 'Volts', 'degC'}, ...
        'data', {200 + 50 * sin(2 * pi * 0.5 * t), 5 * double(mod(t, 1) < 0.2), 37 + 0.001 * (0:1000)}, ...
        'divider', {1, 1, 4}, 'type', {'int16', 'double', 'int16'});
    mk = struct('sample', {1000, 2500}, 'channel', {0, 2}, 'type', {'stm', 'usr'}, 'text', {'stim on', 'drug'});
    variants = {{'ByteOrder', 'le'}, {'ByteOrder', 'be'}};
    if usejava('jvm')
        variants{end+1} = {'Compressed', true};
        variants{end+1} = {'Compressed', true, 'ByteOrder', 'be'};
    end
    for v = 1:numel(variants)
        f = tmp(tests, sprintf('biopac_%d.acq', v));
        writeBiopacACQ(f, ch, 1, 'Markers', mk, variants{v}{:});
        a = readBiopacACQ(f);
        where = sprintf('variant %d', v);
        tests.verifyEqual({a.channels.name}, {'LDF100C', 'Stimulus', 'Temp'}, where);
        tests.verifyEqual({a.channels.units}, {'BPU', 'Volts', 'degC'}, where);
        tests.verifyEqual([a.channels.fs], [1000 1000 250], where);
        tests.verifyEqual(numel(a.channels(3).data), 1001, [where ': the extra sample of the slow channel']);
        tests.verifyEqual(a.channels(1).data, ch(1).data, 'AbsTol', 100 / 65000, where);
        tests.verifyEqual(a.channels(2).data, ch(2).data, where);      % float64: exact
        tests.verifyEqual(a.channels(3).data, ch(3).data, 'AbsTol', 1 / 65000, where);
        tests.verifyEqual([a.events.time], [1 2.5], 'AbsTol', 1e-12, where);
        tests.verifyEqual({a.events.text}, {'stim on', 'drug'}, where);
        tests.verifyEqual([a.events.channel], [0 2], where);
        tests.verifyEqual({a.events.type}, {'stm', 'usr'}, where);
        tests.verifyEqual(a.info.revision, 84);
    end
    tests.verifyEqual(a.info.version, '4.1');
    % Through SignalSource: flow and stimulus by name, markers as events
    rec = SignalSource.open(f);
    tests.verifyEqual(rec.info.format, 'acq');
    [iFlow, iStim] = SignalSource.guessChannels(rec);
    tests.verifyEqual([iFlow iStim], [1 2]);
    L = SignalSource.toLDF(rec, 1, 'events:stim on', 1);
    tests.verifyEqual(L.onsets, 1);
    % Not an .acq file
    g = tmp(tests, 'bad.acq');
    writeText(g, 'hello world, this is text');
    tests.verifyError(@() readBiopacACQ(g), 'NeuroAnalyzer:io:acq');
end

function testCroppedAndErrors(tests)
    d = DemoData.ldfCropped();
    f = tmp(tests, 'cropped.mat');
    save(f, '-struct', 'd');
    tests.verifyEqual(SignalSource.detect(f), 'ldfcropped');
    rec = SignalSource.open(f);
    [iFlow, iStim] = SignalSource.guessChannels(rec);
    tests.verifyEqual([iFlow iStim], [2 1]);
    L = SignalSource.toLDF(rec, iFlow, iStim, 1);
    tests.verifyEqual(L.LDF, double(d.LDF(:))');
    x = struct('something', 1);
    g = tmp(tests, 'other.mat');
    save(g, '-struct', 'x');
    tests.verifyError(@() SignalSource.open(g), 'NeuroAnalyzer:io:unknownFormat');
    tests.verifyError(@() SignalSource.open(tmp(tests, 'missing.acq')), 'NeuroAnalyzer:io:fileNotFound');
    tests.verifyError(@() SignalSource.detect(tmp(tests, 'x.xyz')), 'NeuroAnalyzer:io:fileNotFound');
end

function testDemoLDFFormats(tests)
    f = demoLDFFormats(tmp(tests, 'ldf_formats'));
    tr = f.truth;
    kinds = {'labchartText', 'acq', 'table', 'spike2'};
    flows = {'LDF', 'LDF100C', 'Perfusion', 'LDF'};
    for k = 1:numel(kinds)
        rec = SignalSource.open(f.(kinds{k}));
        [iFlow, iStim] = SignalSource.guessChannels(rec);
        stim = iStim;
        if iStim == 0, stim = 'events'; end
        L = SignalSource.toLDF(rec, iFlow, stim, 1);
        tests.verifyEqual(L.flowName, flows{k}, kinds{k});
        tests.verifyEqual(L.Fs, tr.fs, 'AbsTol', 1e-9, kinds{k});
        tests.verifyEqual(L.LDF, tr.ldf, 'AbsTol', 1e-4, kinds{k});
        on = L.t(diff([0 L.stim > 0.5]) == 1);
        tests.verifyEqual(on, tr.onsets, 'AbsTol', 0.011, kinds{k});
    end
    % Comments / markers are the onsets as well
    rec = SignalSource.open(f.labchartText);
    tests.verifyEqual(sort([rec.events.time]), tr.onsets, 'AbsTol', 1e-9);
    rec = SignalSource.open(f.acq);
    tests.verifyEqual(sort([rec.events.time]), tr.onsets, 'AbsTol', 1e-9);
    tests.verifyEqual(rec.channels(1).fs, 1000, 'AbsTol', 1e-9, 'trigger at the base rate');
    % No time column: the rate is given
    tests.verifyError(@() SignalSource.open(f.noTime), 'NeuroAnalyzer:io:noRate');
    rec = SignalSource.open(f.noTime, '', struct('Fs', 100));
    [iFlow, iStim] = SignalSource.guessChannels(rec);
    tests.verifyEqual([iFlow iStim], [1 2]);
    tests.verifyEqual(rec.channels(1).data, tr.ldf, 'AbsTol', 1e-4);
end

function testGuessSkipsPressure(tests)
    % 'Blood pressure' is not the flow channel; a strong name wins over 'flow'
    ch = struct('chan', {1, 2, 3}, 'block', 1, 'name', {'Blood pressure', 'Cortical flow', 'TTL'}, ...
        'units', {'mmHg', '', 'V'}, 'fs', 100, 'data', {ones(1, 20), ones(1, 20), [zeros(1, 15) ones(1, 5)]}, 't0', 0);
    rec = SignalSource.makeRec(ch, SignalSource.emptyEvents(), {ch.name}, {ch.units}, 'text', '');
    [iFlow, iStim] = SignalSource.guessChannels(rec);
    tests.verifyEqual([iFlow iStim], [2 3]);
    rec.names{1} = 'Laser Doppler'; rec.units{1} = 'PU';
    [iFlow, ~] = SignalSource.guessChannels(rec);
    tests.verifyEqual(iFlow, 1);
end
