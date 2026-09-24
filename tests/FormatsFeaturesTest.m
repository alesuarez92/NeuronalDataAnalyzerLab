%% FormatsFeaturesTest.m
% =========================================================================
% UNIT TESTS FOR core/io: INTAN RHD, OPEN EPHYS BINARY, NWB AND EphysSource
% =========================================================================
% Round trips: the demo tank written by core/demo/demoFormats in each
% format is read back and compared with what was written (samples within
% half a quantization step, sampling rate, channel count, stimulus
% onsets). Because a round trip only proves the reader agrees with our own
% writer, every format also has a hand-built test whose bytes are
% assembled here from the published format descriptions (Intan RHD2000
% header, NumPy .npy header, Open Ephys structure.oebin + continuous.dat,
% an NWB-shaped HDF5 file made with h5create/h5write), plus clear-error
% checks (wrong magic number, missing files, truncated data).
% =========================================================================

function tests = FormatsFeaturesTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'io'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.tmp = fullfile(tempdir, ['NeuroAnalyzerFormatsTest_' char(java.util.UUID.randomUUID)]);
    mkdir(tests.TestData.tmp);
    tests.TestData.demo = demoFormats(fullfile(tests.TestData.tmp, 'demo'));
end

function teardownOnce(tests)
    if exist(tests.TestData.tmp, 'dir') == 7, rmdir(tests.TestData.tmp, 's'); end
end

%% ---------------------------------------------------------------- Intan RHD

function testIntanDemoRoundTrip(tests)
    d = tests.TestData.demo;
    tr = d.truth.intan;
    rec = readIntanRHD(d.intan);
    verifyEqual(tests, rec.streams.xRAW.fs, 20000);
    verifyEqual(tests, size(rec.streams.xRAW.data), [4 tr.nSamples]);
    err = max(abs(double(rec.streams.xRAW.data(:)) - tr.data(:)));
    verifyLessThanOrEqual(tests, err, tr.lsb / 2 + 1e-10, 'amplifier samples within half an LSB');
    verifyEqual(tests, rec.info.stimNames, {'DIGITAL-IN-01', 'ANALOG-IN-1'});
    verifyEqual(tests, rec.info.channelNames, tr.channelNames);
    verifyEqual(tests, double(rec.streams.Whis.data(1, :)), double(tr.digital));
    fs = rec.streams.Whis.fs;
    verifyEqual(tests, EphysSource.risingEdges(rec.streams.Whis.data(1, :), fs), d.truth.onsets, 'AbsTol', 1 / fs);
    verifyEqual(tests, EphysSource.risingEdges(rec.streams.Whis.data(2, :), fs), d.truth.onsets, 'AbsTol', 1 / fs);
    verifyEqual(tests, rec.info.format, 'intan');
    verifyEqual(tests, rec.info.header.samplesPerBlock, 128);    % file format 3.0
end

function testIntanVersionsAndBlockLayout(tests)
    fs = 10000; n = 1000; t = (0:n-1) / fs;
    amp = [200e-6 * sin(2*pi*50*t); -80e-6 * cos(2*pi*30*t)];
    dig = [t >= 0.02 & t < 0.03; t >= 0.05];
    for v = {[1 0], [1 1], [1 2], [1 3], [2 0], [3 0]}
        ver = v{1};
        f = fullfile(tests.TestData.tmp, sprintf('v%d%d.rhd', ver));
        extra = {};
        if ver(1) > 1 || ver(2) >= 1, extra = {'TempSensors', 2}; end
        out = writeIntanRHD(f, amp, fs, 'Version', ver, 'DigitalIn', dig, 'AuxChannels', 3, ...
            'SupplyChannels', 1, 'DisabledChannels', 1, 'DisabledGroup', true, extra{:});
        rec = readIntanRHD(f);
        expN = 60; if ver(1) >= 2, expN = 128; end
        tag = sprintf('v%d.%d', ver);
        verifyEqual(tests, out.samplesPerBlock, expN, tag);
        verifyEqual(tests, rec.info.header.samplesPerBlock, expN, tag);
        verifyEqual(tests, size(rec.streams.xRAW.data), [2 floor(n / expN) * expN], tag);
        verifyLessThanOrEqual(tests, max(max(abs(double(rec.streams.xRAW.data) - amp(:, 1:out.nSamples)))), ...
            0.195e-6 / 2 + 1e-10, tag);
        verifyEqual(tests, double(rec.streams.Whis.data), double(dig(:, 1:out.nSamples)), tag);
        verifyEqual(tests, rec.info.nGaps, 0, tag);
    end
end

function testIntanHandBuiltHeader(tests)
    % Every byte below follows Intan's "RHD data file formats" description:
    % file format 1.3 (60-sample blocks, int32 timestamps, board mode field,
    % no reference-channel field), one enabled and one disabled amplifier
    % channel, one digital input on bit 3.
    b = [u32(hex2dec('C6912702')), i16(1), i16(3), f32(25000), i16(1), ...
        f32([1 0.1 7500 1 0.1 7500]), i16(2), f32([1000 1000]), ...
        qstr('a'), qstr(''), qstr(''), i16(0), i16(0), ...            % notes, temp sensors, board mode
        i16(2), ...                                                   % signal groups
        qstr('Port A'), qstr('A'), i16([1 2 2]), ...
        qstr('A-000'), qstr('EEG1'), i16([0 0 0 1 0 0 0 0 0 0]), f32([1e6 -45]), ...
        qstr('A-001'), qstr(''), i16([1 1 0 0 1 0 0 0 0 0]), f32([1e6 -45]), ...
        qstr('Board Digital Inputs'), qstr('DIN'), i16([1 1 0]), ...
        qstr('DIN-03'), qstr('TTL'), i16([3 3 4 1 0 0 0 0 0 0]), f32([0 0])];
    verifyEqual(tests, double(b(1:4)), [2 39 145 198], 'magic number 0xC6912702, little-endian');
    headerBytes = numel(b);
    ts = 100:219;                                  % 2 blocks x 60 samples
    ampVal = 32768 + (0:119);                      % 0.195 uV per step above the offset
    digWord = ones(1, 120);                        % bit 0: a channel not in the header
    digWord(51:70) = digWord(51:70) + 8;           % bit 3 = DIN-03 high for samples 51-70
    for k = 1:2
        i = (k - 1) * 60 + (1:60);
        b = [b, typecast(int32(ts(i)), 'uint8'), typecast(uint16(ampVal(i)), 'uint8'), ...
            typecast(uint16(digWord(i)), 'uint8')]; %#ok<AGROW>
    end
    f = fullfile(tests.TestData.tmp, 'handbuilt.rhd');
    writeBytes(f, b);

    rec = readIntanRHD(f);
    h = rec.info.header;
    verifyEqual(tests, h.version, [1 3]);
    verifyEqual(tests, h.sampleRate, 25000);
    verifyEqual(tests, h.notchFilterHz, 60);
    verifyEqual(tests, h.notes{1}, 'a');
    verifyEqual(tests, h.actualUpperBandwidth, 7500);
    verifyEqual(tests, h.headerBytes, headerBytes);
    verifyEqual(tests, h.bytesPerBlock, 60 * 4 + 60 * 2 + 60 * 2);
    verifyEqual(tests, rec.info.channelNames, {'EEG1'});
    verifyEqual(tests, rec.info.stimNames, {'TTL'});
    verifyEqual(tests, rec.streams.xRAW.fs, 25000);
    verifyEqual(tests, double(rec.streams.xRAW.data), 0.195e-6 * (0:119), 'AbsTol', 1e-11);
    expected = zeros(1, 120); expected(51:70) = 1;
    verifyEqual(tests, double(rec.streams.Whis.data), expected);
    verifyEqual(tests, rec.info.firstTimestamp, 100);
    verifyEqual(tests, rec.info.nGaps, 0);

    % The writer produces the same documented leading bytes
    writeIntanRHD(fullfile(tests.TestData.tmp, 'w.rhd'), zeros(1, 128), 20000);
    fid = fopen(fullfile(tests.TestData.tmp, 'w.rhd'), 'r');
    lead = fread(fid, 12, 'uint8=>double')';
    fclose(fid);
    verifyEqual(tests, lead(1:8), [2 39 145 198 3 0 0 0], 'magic + version 3.0');
    verifyEqual(tests, lead(9:12), double(f32(20000)), 'float32 sample rate');
end

function testIntanErrors(tests)
    tmp = tests.TestData.tmp;
    verifyError(tests, @() readIntanRHD(fullfile(tmp, 'missing.rhd')), 'NeuroAnalyzer:io:fileNotFound');
    f = fullfile(tmp, 'badmagic.rhd');
    writeBytes(f, [u32(hex2dec('12345678')), zeros(1, 60, 'uint8')]);
    verifyError(tests, @() readIntanRHD(f), 'NeuroAnalyzer:io:badMagic');
    f = fullfile(tmp, 'v9.rhd');
    writeBytes(f, [u32(hex2dec('C6912702')), i16(9), i16(0), zeros(1, 60, 'uint8')]);
    verifyError(tests, @() readIntanRHD(f), 'NeuroAnalyzer:io:unsupportedVersion');
    % Truncated: drop the last 10 bytes of a valid file
    src = tests.TestData.demo.intan;
    fid = fopen(src, 'r'); bytes = fread(fid, Inf, 'uint8=>uint8')'; fclose(fid);
    f = fullfile(tmp, 'truncated.rhd');
    writeBytes(f, bytes(1:end-10));
    verifyError(tests, @() readIntanRHD(f), 'NeuroAnalyzer:io:truncated');
    % Header only (Intan's one-file-per-signal info.rhd)
    h = readIntanRHD(src, 'HeaderOnly', true);
    f = fullfile(tmp, 'headeronly.rhd');
    writeBytes(f, bytes(1:h.headerBytes));
    verifyError(tests, @() readIntanRHD(f), 'NeuroAnalyzer:io:noData');
end

%% ---------------------------------------------------------- Open Ephys binary

function testOpenEphysDemoRoundTrip(tests)
    d = tests.TestData.demo;
    tr = d.truth.openephys;
    rec = readOpenEphysBinary(d.openephys);
    verifyEqual(tests, rec.streams.xRAW.fs, 30000);
    verifyEqual(tests, size(rec.streams.xRAW.data), [4 tr.nSamples]);
    err = max(abs(double(rec.streams.xRAW.data(:)) - tr.data(:)));
    verifyLessThanOrEqual(tests, err, tr.lsb / 2 + 1e-10, 'samples within half a bit_volts step');
    verifyEqual(tests, rec.info.stimNames, {'TTL line 1', 'ADC1'});
    verifyEqual(tests, rec.info.firstSample, 512000);
    verifyEqual(tests, rec.info.stimOnsets{1}, d.truth.onsets, 'AbsTol', 1 / 30000);
    fs = rec.streams.Whis.fs;
    verifyEqual(tests, EphysSource.risingEdges(rec.streams.Whis.data(1, :), fs), d.truth.onsets, 'AbsTol', 1 / fs);
    verifyEqual(tests, EphysSource.risingEdges(rec.streams.Whis.data(2, :), fs), d.truth.onsets, 'AbsTol', 1 / fs);
    verifyEqual(tests, rec.info.channelNames, {'CH1', 'CH2', 'CH3', 'CH4'});
    % The recording folder and structure.oebin itself open the same recording
    rec2 = readOpenEphysBinary(fileparts(rec.info.file));
    rec3 = readOpenEphysBinary(rec.info.file);
    verifyEqual(tests, rec2.streams.xRAW.data, rec.streams.xRAW.data);
    verifyEqual(tests, rec3.streams.Whis.data, rec.streams.Whis.data);
end

function testOpenEphysLegacyLayout(tests)
    fs = 30000; n = 3000; t = (0:n-1) / fs;
    x = [150e-6 * sin(2*pi*40*t); 20e-6 * ones(1, n)];
    d = fullfile(tests.TestData.tmp, 'oe05');
    writeOpenEphysBinary(d, x, fs, 'Version', '0.5.5', 'FirstSample', 1000, ...
        'TTL', struct('line', 2, 'on', [301 1501], 'off', [601 1801]));
    rec = readOpenEphysBinary(d);
    verifyLessThanOrEqual(tests, max(max(abs(double(rec.streams.xRAW.data) - x))), 0.195e-6 / 2 + 1e-10);
    verifyEqual(tests, rec.info.stimNames, {'TTL line 2'});
    verifyEqual(tests, rec.info.stimOnsets{1}, [300 1500] / fs, 'AbsTol', 1e-12);
    verifyEqual(tests, sum(rec.streams.Whis.data), single(600));
end

function testOpenEphysHandBuilt(tests)
    % structure.oebin, continuous.dat and .npy files written byte by byte
    % as documented: int16 samples interleaved by channel, value x
    % bit_volts in the channel's units; TTL states +line / -line.
    rd = fullfile(tests.TestData.tmp, 'oe_hand', 'experiment1', 'recording1');
    cdir = fullfile(rd, 'continuous', 'Board-100.0');
    ed = fullfile(rd, 'events', 'Board-100.0', 'TTL');
    mkdir(cdir); mkdir(ed);
    json = ['{"GUI version": "0.6.4", "continuous": [{"folder_name": "Board-100.0/", ' ...
        '"sample_rate": 1000.0, "stream_name": "Board", "num_channels": 3, "channels": [' ...
        '{"channel_name": "CH1", "bit_volts": 0.195, "units": "uV"}, ' ...
        '{"channel_name": "CH2", "bit_volts": 2.0, "units": "uV"}, ' ...
        '{"channel_name": "ADC1", "bit_volts": 0.5, "units": "V"}]}], ' ...
        '"events": [{"folder_name": "Board-100.0/TTL/", "sample_rate": 1000.0, ' ...
        '"stream_name": "Board", "channel_name": "TTL"}], "spikes": []}'];
    writeBytes(fullfile(rd, 'structure.oebin'), uint8(json));
    v = int16([100 -200 1; 300 -400 0; 5 6 1; 7 8 1; 9 10 0])';   % 3 channels x 5 samples
    writeBytes(fullfile(cdir, 'continuous.dat'), typecast(v(:)', 'uint8'));
    writeBytes(fullfile(cdir, 'sample_numbers.npy'), npyBytes('<i8', 5, typecast(int64(50:54), 'uint8')));
    writeBytes(fullfile(ed, 'states.npy'), npyBytes('<i2', 2, typecast(int16([1 -1]), 'uint8')));
    writeBytes(fullfile(ed, 'sample_numbers.npy'), npyBytes('<i8', 2, typecast(int64([51 53]), 'uint8')));

    rec = readOpenEphysBinary(rd);
    verifyEqual(tests, rec.streams.xRAW.fs, 1000);
    verifyEqual(tests, double(rec.streams.xRAW.data(1, :)), [100 300 5 7 9] * 0.195e-6, 'AbsTol', 1e-9);
    verifyEqual(tests, double(rec.streams.xRAW.data(2, :)), [-200 -400 6 8 10] * 2e-6, 'AbsTol', 1e-9);
    verifyEqual(tests, rec.info.stimNames, {'TTL line 1', 'ADC1'});
    verifyEqual(tests, double(rec.streams.Whis.data(1, :)), [0 1 1 0 0]);      % samples 51-52 high
    verifyEqual(tests, double(rec.streams.Whis.data(2, :)), [1 0 1 1 0] * 0.5, 'AbsTol', 1e-12);
    verifyEqual(tests, rec.info.firstSample, 50);
end

function testNpyHandBuilt(tests)
    f = fullfile(tests.TestData.tmp, 'hand.npy');
    writeBytes(f, npyBytes('<i8', 3, typecast(int64([7 -8 9]), 'uint8')));
    x = readNPY(f);
    verifyEqual(tests, x, int64([7; -8; 9]));
    % Big-endian float32, 2 x 2 in C order
    be = fliplr(reshape(typecast(single([1 2 3 4]), 'uint8'), 4, []).');   % byte-swap each value
    raw = reshape(be.', 1, []);
    writeBytes(f, npyBytes('>f4', [2 2], raw));
    verifyEqual(tests, readNPY(f), single([1 2; 3 4]));
    % writeNPY -> readNPY
    writeNPY(f, int16([1 -2 3]));
    verifyEqual(tests, readNPY(f), int16([1; -2; 3]));
    fid = fopen(f, 'r'); lead = fread(fid, 10, 'uint8=>double')'; fclose(fid);
    verifyEqual(tests, lead(1:8), [147 double('NUMPY') 1 0], 'magic \x93NUMPY + version 1.0');
    verifyEqual(tests, mod(10 + lead(9) + 256 * lead(10), 64), 0, 'header padded to 64 bytes');
    writeBytes(f, uint8('not numpy'));
    verifyError(tests, @() readNPY(f), 'NeuroAnalyzer:io:badMagic');
end

function testOpenEphysErrors(tests)
    tmp = tests.TestData.tmp;
    empty = fullfile(tmp, 'oe_empty'); mkdir(empty);
    verifyError(tests, @() readOpenEphysBinary(empty), 'NeuroAnalyzer:io:fileNotFound');
    verifyError(tests, @() readOpenEphysBinary(fullfile(tmp, 'nope')), 'NeuroAnalyzer:io:fileNotFound');
    d = fullfile(tmp, 'oe_nodat'); mkdir(d);
    writeBytes(fullfile(d, 'structure.oebin'), uint8(['{"continuous": [{"folder_name": "X-1/", ' ...
        '"sample_rate": 1000, "num_channels": 1, "channels": [{"channel_name": "CH1", "bit_volts": 1}]}]}']));
    verifyError(tests, @() readOpenEphysBinary(d), 'NeuroAnalyzer:io:fileNotFound');
    writeBytes(fullfile(d, 'structure.oebin'), uint8('{ not json'));
    verifyError(tests, @() readOpenEphysBinary(d), 'NeuroAnalyzer:io:badHeader');
end

%% ----------------------------------------------------------------------- NWB

function testNWBDemoRead(tests)
    d = tests.TestData.demo;
    tr = d.truth.nwb;
    rec = readNWB(d.nwb);
    verifyEqual(tests, rec.streams.xRAW.fs, tr.fs);
    verifyEqual(tests, size(rec.streams.xRAW.data), [4 tr.nSamples]);
    err = max(abs(double(rec.streams.xRAW.data(:)) - tr.data(:)));
    verifyLessThanOrEqual(tests, err, tr.lsb / 2 + 1e-9, 'int16 x conversion within half an LSB');
    verifyEqual(tests, rec.info.electrodeIds, d.truth.channels);
    verifyEqual(tests, rec.info.channelNames, {'tank ch3', 'tank ch4', 'tank ch5', 'tank ch6'});
    verifyEqual(tests, rec.info.stimNames, {'whisker_stimulus', 'trials (intervals)'});
    verifyEqual(tests, rec.streams.Whis.fs, tr.stimFs, 'common grid = stimulus TimeSeries rate');
    verifyEqual(tests, rec.info.stimOnsets{2}, d.truth.onsets, 'AbsTol', 1e-12);
    fs = rec.streams.Whis.fs;
    for r = 1:2
        verifyEqual(tests, EphysSource.risingEdges(rec.streams.Whis.data(r, :), fs), d.truth.onsets, ...
            'AbsTol', 1.01 / fs);
    end
    verifyEqual(tests, rec.info.identifier, 'neuroanalyzer-demo-tank');
    verifyEqual(tests, rec.info.seriesPath, '/acquisition/ElectricalSeries');
end

function testNWBWriteReadRoundTrip(tests)
    fs = 1000; n = 2500; t = (0:n-1) / fs;
    lfp = [100e-6 * sin(2*pi*8*t); -60e-6 * cos(2*pi*13*t); 30e-6 * sin(2*pi*3*t)];
    stim = double(t >= 0.5 & t < 0.52 | t >= 1.5 & t < 1.52);
    r.lfp = struct('data', lfp, 'fs', fs, 'channels', [2 4 7], 'filtering', 'test filter');
    r.stim = struct('data', stim, 'fs', fs, 'name', 'stim');
    r.trials = struct('start', [0.5 1.5], 'stop', [0.52 1.52]);
    r.units = struct('spikeTimes', {[0.1 0.25 0.7], 1.2, []});
    r.electrodes = struct('names', {{'A', 'B', 'C'}});
    r.sessionStartTime = '2026-01-02T03:04:05.000+00:00';
    f = fullfile(tests.TestData.tmp, 'roundtrip.nwb');
    out = writeNWB(f, r, 'Engine', 'minimal');
    verifyEqual(tests, out.engine, 'minimal');
    verifyFalse(tests, out.validated);
    rec = readNWB(f);
    verifyEqual(tests, rec.info.seriesPath, '/processing/ecephys/LFP/ElectricalSeries');
    verifyEqual(tests, rec.streams.xRAW.fs, fs);
    verifyEqual(tests, double(rec.streams.xRAW.data), lfp, 'AbsTol', 1e-11);   % single precision
    verifyEqual(tests, rec.info.electrodeIds, [2 4 7]);
    verifyEqual(tests, rec.info.channelNames, {'A', 'B', 'C'});
    verifyEqual(tests, rec.info.stimNames, {'stim', 'trials (intervals)'});
    verifyEqual(tests, double(rec.streams.Whis.data(1, :)), stim);
    verifyEqual(tests, rec.info.stimOnsets{2}, [0.5 1.5], 'AbsTol', 1e-12);
    verifyEqual(tests, numel(rec.info.spikeUnits), 3);
    verifyEqual(tests, rec.info.spikeUnits(1).spikeTimes, [0.1 0.25 0.7]);
    verifyEqual(tests, rec.info.spikeUnits(2).spikeTimes, 1.2);
    verifyEmpty(tests, rec.info.spikeUnits(3).spikeTimes);
    verifyEqual(tests, rec.info.sessionStartTime, '2026-01-02T03:04:05.000+00:00');
    % Raw int16 + conversion in /acquisition takes precedence over the LFP
    r.raw = struct('data', int16([1 2 3; 4 5 6]), 'fs', 30000, 'channels', [2 4], 'conversion', 1e-6);
    writeNWB(f, r, 'Engine', 'minimal');
    rec = readNWB(f);
    verifyEqual(tests, rec.info.seriesPath, '/acquisition/ElectricalSeries');
    verifyEqual(tests, double(rec.streams.xRAW.data), [1 2 3; 4 5 6] * 1e-6, 'AbsTol', 1e-12);
    rec = readNWB(f, 'Series', '/processing/ecephys/LFP/ElectricalSeries');
    verifyEqual(tests, rec.streams.xRAW.fs, fs);
end

function testNWBRequiredTopLevel(tests)
    % Required NWB 2.x file-level objects and neurodata_type attributes
    f = fullfile(tests.TestData.tmp, 'toplevel.nwb');
    r.lfp = struct('data', randnLike(2, 100), 'fs', 500);
    r.sessionDescription = 'top-level test';
    r.identifier = 'id-123';
    writeNWB(f, r, 'Engine', 'minimal');
    fid = fopen(f, 'r'); sig = fread(fid, 8, 'uint8=>double')'; fclose(fid);
    verifyEqual(tests, sig, [137 72 68 70 13 10 26 10], 'HDF5 format signature');
    verifyEqual(tests, txt(h5readatt(f, '/', 'nwb_version')), '2.7.0');
    verifyEqual(tests, txt(h5readatt(f, '/', 'neurodata_type')), 'NWBFile');
    verifyEqual(tests, txt(h5readatt(f, '/', 'namespace')), 'core');
    verifyEqual(tests, numel(txt(h5readatt(f, '/', 'object_id'))), 36);
    verifyEqual(tests, txt(h5read(f, '/identifier')), 'id-123');
    verifyEqual(tests, txt(h5read(f, '/session_description')), 'top-level test');
    verifyNotEmpty(tests, regexp(txt(h5read(f, '/session_start_time')), ...
        '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d', 'once'));
    verifyNotEmpty(tests, txt(h5read(f, '/timestamps_reference_time')));
    verifyNotEmpty(tests, txt(h5read(f, '/file_create_date')));
    info = h5info(f, '/');
    groups = {info.Groups.Name};
    for g = {'/acquisition', '/analysis', '/processing', '/stimulus', '/general'}
        verifyTrue(tests, any(strcmp(groups, g{1})), g{1});
    end
    st = h5info(f, '/stimulus');
    verifyEqual(tests, sort({st.Groups.Name}), {'/stimulus/presentation', '/stimulus/templates'});
    verifyEqual(tests, txt(h5readatt(f, '/processing/ecephys', 'neurodata_type')), 'ProcessingModule');
    verifyEqual(tests, txt(h5readatt(f, '/processing/ecephys/LFP', 'neurodata_type')), 'LFP');
    es = '/processing/ecephys/LFP/ElectricalSeries';
    verifyEqual(tests, txt(h5readatt(f, es, 'neurodata_type')), 'ElectricalSeries');
    verifyEqual(tests, txt(h5readatt(f, [es '/data'], 'unit')), 'volts');
    verifyEqual(tests, double(h5readatt(f, [es '/starting_time'], 'rate')), 500);
    verifyEqual(tests, txt(h5readatt(f, [es '/electrodes'], 'neurodata_type')), 'DynamicTableRegion');
    verifyEqual(tests, txt(h5readatt(f, [es '/electrodes'], 'namespace')), 'hdmf-common');
    di = h5info(f, [es '/data']);
    verifyEqual(tests, double(di.Dataspace.Size(:))', [2 100], 'HDF5 (time, channel) = MATLAB channel x time');
    tbl = '/general/extracellular_ephys/electrodes';
    verifyEqual(tests, txt(h5readatt(f, tbl, 'neurodata_type')), 'DynamicTable');
    verifyEqual(tests, double(h5read(f, [tbl '/id']))', [1 2]);
end

function testNWBHandBuiltFile(tests)
    % An NWB-shaped file made with the high-level HDF5 functions only (not
    % writeNWB): documented paths and attribute names, fixed-length text.
    f = fullfile(tests.TestData.tmp, 'handbuilt.nwb');
    fs = 2000; n = 400;
    q = int16([1:n; -(1:n)]);                                   % 2 channels x n
    h5create(f, '/acquisition/probe/data', [2 n], 'Datatype', 'int16');
    h5write(f, '/acquisition/probe/data', q);
    h5create(f, '/acquisition/probe/starting_time', 1);
    h5write(f, '/acquisition/probe/starting_time', 10);
    h5create(f, '/stimulus/presentation/ttl/data', 3);
    h5write(f, '/stimulus/presentation/ttl/data', [1 0 1]');
    h5create(f, '/stimulus/presentation/ttl/timestamps', 3);
    h5write(f, '/stimulus/presentation/ttl/timestamps', [10.05 10.06 10.1]');
    h5writeatt(f, '/', 'nwb_version', '2.5.0');
    h5writeatt(f, '/acquisition/probe', 'neurodata_type', 'ElectricalSeries');
    h5writeatt(f, '/acquisition/probe/data', 'conversion', 5e-6);
    h5writeatt(f, '/acquisition/probe/starting_time', 'rate', fs);
    h5writeatt(f, '/stimulus/presentation/ttl', 'neurodata_type', 'TimeSeries');
    rec = readNWB(f);
    verifyEqual(tests, rec.streams.xRAW.fs, fs);
    verifyEqual(tests, double(rec.streams.xRAW.data), double(q) * 5e-6, 'AbsTol', 1e-9);   % single precision
    verifyEqual(tests, rec.info.startTime, 10);
    verifyEqual(tests, rec.info.nwbVersion, '2.5.0');
    verifyEqual(tests, rec.info.stimNames, {'ttl'});
    s = double(rec.streams.Whis.data);
    % Zero-order hold of the samples at 0.05, 0.06, 0.1 s (after the series start):
    % 1 from 0.05 s (sample 101), 0 from 0.06 s (sample 121), 1 from 0.1 s
    % (sample 201) for one median step (0.025 s), 0 outside the samples
    verifyEqual(tests, s(100:102), [0 1 1]);
    verifyEqual(tests, s(120:121), [1 0]);
    verifyEqual(tests, s([200 201 240 260]), [0 1 1 0]);
end

function testNWBErrors(tests)
    tmp = tests.TestData.tmp;
    verifyError(tests, @() readNWB(fullfile(tmp, 'missing.nwb')), 'NeuroAnalyzer:io:fileNotFound');
    f = fullfile(tmp, 'text.nwb');
    writeBytes(f, uint8('this is not HDF5'));
    verifyError(tests, @() readNWB(f), 'NeuroAnalyzer:io:notHDF5');
    f = fullfile(tmp, 'plain.h5');
    h5create(f, '/x', 3); h5write(f, '/x', [1 2 3]');
    verifyError(tests, @() readNWB(f), 'NeuroAnalyzer:io:notNWB');
    h5writeatt(f, '/', 'nwb_version', '2.7.0');
    verifyError(tests, @() readNWB(f), 'NeuroAnalyzer:io:noData');
    verifyError(tests, @() writeNWB(fullfile(tmp, 'x.nwb'), struct('stim', 1)), 'NeuroAnalyzer:io:badInput');
end

function testNWBDryRunLayout(tests)
    r.lfp = struct('data', zeros(2, 10), 'fs', 100, 'channels', [5 6]);
    r.units = struct('spikeTimes', {0.1, [0.2 0.3]});
    out = writeNWB('', r, 'DryRun', true);
    paths = cellfun(@(n) n.path, out.layout, 'UniformOutput', false);
    for p = {'/', '/identifier', '/session_description', '/session_start_time', ...
            '/timestamps_reference_time', '/file_create_date', '/stimulus/presentation', ...
            '/stimulus/templates', '/general/extracellular_ephys/electrodes/group', ...
            '/processing/ecephys/LFP/ElectricalSeries/electrodes', '/units/spike_times_index'}
        verifyTrue(tests, any(strcmp(paths, p{1})), p{1});
    end
    % Every typed object has its own UUID object_id
    ids = {};
    for k = 1:numel(out.layout)
        a = out.layout{k}.attrs;
        if any(strcmp({a.name}, 'neurodata_type'))
            id = a(strcmp({a.name}, 'object_id')).value;
            verifyNotEmpty(tests, regexp(id, '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', ...
                'once', 'ignorecase'), out.layout{k}.path);
            ids{end+1} = id; %#ok<AGROW>
        end
    end
    verifyEqual(tests, numel(unique(ids)), numel(ids), 'object_id values are unique');
    idx = out.layout{strcmp(paths, '/units/spike_times_index')};
    verifyEqual(tests, double(idx.data(:))', [1 3]);
end

function testNWBWithMatnwb(tests)
    tests.assumeTrue(~isempty(which('nwbExport')) && ~isempty(which('NwbFile')), 'matnwb not installed');
    r.lfp = struct('data', randnLike(3, 200), 'fs', 1000, 'channels', 1:3);
    f = fullfile(tests.TestData.tmp, 'matnwb.nwb');
    out = writeNWB(f, r, 'Engine', 'matnwb');
    verifyEqual(tests, out.engine, 'matnwb');
    rec = readNWB(f);
    verifyEqual(tests, double(rec.streams.xRAW.data), r.lfp.data, 'AbsTol', 1e-9);
    verifyEqual(tests, rec.streams.xRAW.fs, 1000);
end

%% --------------------------------------------------------------- EphysSource

function testEphysSourceDetectAndOpen(tests)
    d = tests.TestData.demo;
    verifyEqual(tests, EphysSource.detect(d.intan), 'intan');
    verifyEqual(tests, EphysSource.detect(d.openephys), 'openephys');
    verifyEqual(tests, EphysSource.detect(d.nwb), 'nwb');
    verifyEqual(tests, EphysSource.detect(DemoData.file('tdtTank')), 'tdt');
    f = fullfile(tests.TestData.tmp, 'mystery.bin');
    writeBytes(f, uint8(1:32));
    verifyError(tests, @() EphysSource.detect(f), 'NeuroAnalyzer:io:unknownFormat');
    copyfile(d.intan, fullfile(tests.TestData.tmp, 'renamed.dat'));
    verifyEqual(tests, EphysSource.detect(fullfile(tests.TestData.tmp, 'renamed.dat')), 'intan', 'by magic number');
    verifyError(tests, @() EphysSource.open(d.intan, 'plexon'), 'NeuroAnalyzer:io:unknownFormat');
    for fmt = {'intan', 'openephys', 'nwb'}
        rec = EphysSource.open(d.(fmt{1}), 'auto');
        verifyEqual(tests, rec.info.format, fmt{1});
        verifyEqual(tests, size(rec.streams.xRAW.data, 1), 4);
        verifyEqual(tests, rec.streams.xRAW.channel, 1:4);
        verifyEqual(tests, rec.streams.Whis.channel, 1:size(rec.streams.Whis.data, 1));
        verifyClass(tests, rec.streams.xRAW.data, 'single');
        verifyEqual(tests, numel(rec.info.stimNames), size(rec.streams.Whis.data, 1));
    end
    tank = EphysSource.open(DemoData.file('tdtTank'), 'tdt');
    verifyEqual(tests, tank.info.format, 'tdt');
    verifyEqual(tests, tank.streams.xRAW.fs, DemoData.FsRaw);
end

function testEphysSourceHelpers(tests)
    x = EphysSource.eventsToSquare([3 8], [5 9], 10);
    verifyEqual(tests, double(x), [0 0 1 1 0 0 0 1 0 0]);
    x = EphysSource.eventsToSquare(6, 2, 8);            % high at start, then on without off
    verifyEqual(tests, double(x), [1 0 0 0 0 1 1 1]);
    verifyEqual(tests, EphysSource.risingEdges([0 0 1 1 0 1], 10), [0.2 0.5], 'AbsTol', 1e-12);
    verifyEmpty(tests, EphysSource.risingEdges(zeros(1, 5), 10));
    rec = EphysSource.makeRecording(ones(2, 5), 100, [], [], struct('source', 'test'));
    verifyEqual(tests, rec.info.stimNames, {'(no stimulus channel)'});
    verifyEqual(tests, size(rec.streams.Whis.data), [1 5]);
    verifyEqual(tests, rec.streams.Whis.fs, 100);
    verifyEqual(tests, rec.info.duration, 0.05);
    verifyEqual(tests, rec.info.channelNames, {'Ch 1', 'Ch 2'});
    list = EphysSource.formats();
    verifyEqual(tests, {list.key}, {'tdt', 'intan', 'openephys', 'nwb'});
end

function testDemoFormatsCache(tests)
    a = demoFormats();
    b = demoFormats();
    verifyEqual(tests, b.intan, a.intan);
    verifyTrue(tests, exist(a.intan, 'file') == 2 && exist(a.nwb, 'file') == 2 && exist(a.openephys, 'dir') == 7);
    verifyFalse(tests, isfield(b.truth.intan, 'data'), 'cache keeps no sample arrays');
    verifyEqual(tests, b.truth.onsets, [1 3 5]);
end

%% ------------------------------------------------------------------ helpers

function b = u32(x), b = typecast(uint32(x), 'uint8'); end
function b = i16(x), b = typecast(int16(x), 'uint8'); end
function b = f32(x), b = typecast(single(x), 'uint8'); end

%% qstr - Qt QString: uint32 byte length + UTF-16LE characters
function b = qstr(s)
    b = u32(2 * numel(s));
    if ~isempty(s), b = [b, typecast(uint16(double(s)), 'uint8')]; end
end

%% npyBytes - .npy v1.0 file: magic, version, header length, padded dict header, data
function b = npyBytes(descr, shape, data)
    if isscalar(shape), shp = sprintf('(%d,)', shape); else, shp = sprintf('(%d, %d)', shape); end
    h = sprintf('{''descr'': ''%s'', ''fortran_order'': False, ''shape'': %s, }', descr, shp);
    pad = mod(64 - mod(10 + numel(h) + 1, 64), 64);
    h = [h repmat(' ', 1, pad) newline];
    b = [uint8([147 double('NUMPY') 1 0]), typecast(uint16(numel(h)), 'uint8'), uint8(h), uint8(data(:)')];
end

function writeBytes(f, b)
    fid = fopen(f, 'w');
    fwrite(fid, b, 'uint8');
    fclose(fid);
end

%% txt - char from an HDF5 text value (char, cell or string)
function s = txt(v)
    if iscell(v), v = v{1}; end
    if isstring(v), v = char(v(1)); end
    s = strtrim(regexprep(char(v(:)'), '\x00+$', ''));
end

%% randnLike - deterministic pseudo-random matrix (no global RNG side effects)
function x = randnLike(r, c)
    rs = RandStream('mt19937ar', 'Seed', 7);
    x = 1e-5 * randn(rs, r, c);
end
