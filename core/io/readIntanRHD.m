%% readIntanRHD.m
% =========================================================================
% READ INTAN RHD - INTAN RHD2000 (.rhd) RECORDING AS A TDT-LIKE STRUCT
% =========================================================================
% rec = readIntanRHD(file)
% rec = readIntanRHD(file, 'HeaderOnly', true)
%
% Reads an Intan RHD2000 data file saved in the "traditional" single-file
% format (header followed by data blocks) and returns the same struct
% shape as TDTbin2mat, so Extract Ephys can use it unchanged:
%   rec.streams.xRAW.data   amplifier channels x samples (single, volts)
%   rec.streams.xRAW.fs     amplifier sample rate (Hz)
%   rec.streams.Whis.data   candidate stimulus channels x samples (single):
%                           board digital inputs first (0/1), then board
%                           ADC inputs (volts); a zero row if there are none
%   rec.streams.Whis.fs     same as the amplifier rate
%   rec.info                source ('Intan RHD2000'), format ('intan'),
%                           file, blockname, duration (s), channelNames,
%                           nativeChannelNames, stimNames, stimKinds,
%                           firstTimestamp, nGaps, header (parsed header)
% With 'HeaderOnly' true, rec is the parsed header struct only.
%
% Method: implemented from Intan Technologies' published RHD2000 data
% file format documentation (application note, intantech.com); Intan's
% own reader code was not used. Cross-checked during development against
% files read with the independent neo (IntanRawIO) reader.
%   Header (little-endian): uint32 magic 0xC6912702, int16 major / minor
%   version, float32 sample rate, int16 DSP enabled, float32 x 6 (actual
%   DSP cutoff, lower, upper bandwidth; desired same three), int16 notch
%   mode (0 none, 1 = 50 Hz, 2 = 60 Hz), float32 x 2 (desired / actual
%   impedance test frequency), 3 notes (QString); v>=1.1 int16 number of
%   temperature sensors; v>=1.3 int16 board mode; v>=2.0 QString reference
%   channel; int16 number of signal groups, each: QString name, QString
%   prefix, int16 enabled, int16 channels, int16 amplifier channels and,
%   if enabled, one record per channel: QString native / custom name,
%   int16 native order, custom order, signal type (0 amplifier, 1 aux
%   input, 2 supply voltage, 3 board ADC, 4 digital in, 5 digital out),
%   channel enabled, chip channel, board stream, 4 spike-trigger fields,
%   float32 impedance magnitude / phase. QString = uint32 byte length
%   (0xFFFFFFFF = null) + UTF-16LE characters.
%   Data blocks of N samples (N = 60 for major version 1, 128 for >= 2):
%   N timestamps (int32; uint32 before v1.2), N x amplifier channels
%   (uint16), N/4 x aux channels, 1 x supply channels, 1 x temperature
%   sensors (int16), N x ADC channels, N digital-input words, N
%   digital-output words (the last two only if such channels are enabled).
%   Amplifier volts = 0.195e-6 x (value - 32768). Board ADC volts =
%   50.354e-6 x value (board mode 0), 152.59e-6 x (value - 32768) (mode 1)
%   or 312.5e-6 x (value - 32768) (mode 13). Digital input channel k is
%   bit native_order of each word.
%
% Limitations: versions 1.0-3.x; only the single-file format ("one file
%   per signal type" / "one file per channel" .dat folders raise
%   NeuroAnalyzer:io:noData); RHS2000 stimulation files (.rhs) are a
%   different format and are rejected by the magic number. The notch
%   filter setting is reported (info.header.notchFilterHz) but not
%   applied. Aux, supply and temperature channels are skipped. Timestamp
%   gaps are counted (info.nGaps, with a warning) and samples are kept
%   contiguous. UTF-16 surrogate pairs in names are not decoded.
% Errors: NeuroAnalyzer:io:fileNotFound, :badMagic, :unsupportedVersion,
%   :truncated, :noData.
% Toolboxes: none (base MATLAB; also runs in Octave).
% =========================================================================

function rec = readIntanRHD(file, varargin)
    headerOnly = false;
    for k = 1:2:numel(varargin)
        if strcmpi(varargin{k}, 'HeaderOnly'), headerOnly = logical(varargin{k+1}); end
    end
    if ~(exist(file, 'file') == 2)
        error('NeuroAnalyzer:io:fileNotFound', 'Intan file not found: %s', file);
    end
    fid = fopen(file, 'r', 'ieee-le');
    if fid < 0
        error('NeuroAnalyzer:io:fileNotFound', 'Cannot open Intan file: %s', file);
    end
    c = onCleanup(@() fclose(fid));

    h = readHeader(fid, file);
    if headerOnly
        rec = h;
        return;
    end

    % ---- Data blocks ----
    fseek(fid, 0, 'eof');
    fileBytes = ftell(fid);
    dataBytes = fileBytes - h.headerBytes;
    if dataBytes == 0
        error('NeuroAnalyzer:io:noData', ['%s holds only a header (no data blocks). Intan''s ' ...
            '"one file per signal type" / "one file per channel" formats (info.rhd + .dat files) ' ...
            'are not supported; save in the traditional single-file .rhd format.'], file);
    end
    if mod(dataBytes, h.bytesPerBlock) ~= 0
        error('NeuroAnalyzer:io:truncated', ['%s: %d data bytes is not a whole number of %d-byte ' ...
            'data blocks. The file is truncated or uses an unsupported variant.'], ...
            file, dataBytes, h.bytesPerBlock);
    end
    nBlocks = dataBytes / h.bytesPerBlock;
    N = h.samplesPerBlock;
    wpb = h.bytesPerBlock / 2;
    fseek(fid, h.headerBytes, 'bof');
    words = fread(fid, [wpb, nBlocks], 'uint16=>uint16');
    nS = N * nBlocks;

    % Timestamps: 2 words per sample (little-endian int32 / uint32)
    tsWords = reshape(words(1:2*N, :), [], 1);
    if h.version(1) > 1 || h.version(2) >= 2
        ts = double(typecast(tsWords, 'int32'));
    else
        ts = double(typecast(tsWords, 'uint32'));
    end
    ts = ts(:)';
    nGaps = sum(diff(ts) ~= 1);
    if nGaps > 0
        warning('NeuroAnalyzer:io:timestampGap', ...
            '%s: %d timestamp discontinuities (dropped samples); data are kept contiguous.', file, nGaps);
    end

    off = 2 * N;
    nAmp = numel(h.amplifierChannels);
    amp = channelBlock(words, off, N, nAmp, nBlocks);
    off = off + N * nAmp;
    off = off + (N / 4) * numel(h.auxChannels) + numel(h.supplyChannels) + h.numTempSensors;
    nAdc = numel(h.adcChannels);
    adc = channelBlock(words, off, N, nAdc, nBlocks);
    off = off + N * nAdc;
    din = [];
    if ~isempty(h.digitalInChannels)
        din = reshape(words(off + (1:N), :), 1, nS);
    end

    raw = single((double(amp) - 32768) * 0.195e-6);
    [adcGain, adcOffset] = adcScale(h.evalBoardMode);
    stim = zeros(0, nS, 'single');
    stimNames = {}; stimKinds = {};
    for k = 1:numel(h.digitalInChannels)
        ch = h.digitalInChannels(k);
        stim(end+1, :) = single(bitand(din, uint16(2^ch.nativeOrder)) > 0); %#ok<AGROW>
        stimNames{end+1} = channelLabel(ch); stimKinds{end+1} = 'digital'; %#ok<AGROW>
    end
    for k = 1:nAdc
        stim(end+1, :) = single(adcGain * (double(adc(k, :)) - adcOffset)); %#ok<AGROW>
        stimNames{end+1} = channelLabel(h.adcChannels(k)); stimKinds{end+1} = 'analog'; %#ok<AGROW>
    end

    [~, base] = fileparts(file);
    info = struct('source', 'Intan RHD2000', 'format', 'intan', 'file', file, ...
        'blockname', base, 'duration', nS / h.sampleRate, ...
        'channelNames', {arrayfun(@channelLabel, h.amplifierChannels, 'UniformOutput', false)}, ...
        'nativeChannelNames', {{h.amplifierChannels.nativeName}}, ...
        'stimNames', {stimNames}, 'stimKinds', {stimKinds}, ...
        'firstTimestamp', ts(1), 'nGaps', nGaps, 'header', h);
    if nAmp == 0
        info.nativeChannelNames = {};
    end
    rec = EphysSource.makeRecording(raw, h.sampleRate, stim, h.sampleRate, info);
end

%% readHeader - Parse the RHD header; adds derived sizes and channel lists
function h = readHeader(fid, file)
    magic = fread(fid, 1, 'uint32=>double');
    if isempty(magic) || magic ~= hex2dec('C6912702')
        if isempty(magic), magic = 0; end
        error('NeuroAnalyzer:io:badMagic', ['%s is not an Intan RHD2000 file: magic number 0x%08X ' ...
            '(expected 0xC6912702). RHS2000 (.rhs) files are not supported.'], file, magic);
    end
    h.magic = magic;
    h.version = double(fread(fid, 2, 'int16=>double'))';
    if h.version(1) < 1 || h.version(1) > 3
        error('NeuroAnalyzer:io:unsupportedVersion', ...
            '%s: RHD file format version %d.%d is not supported (1.0-3.x).', file, h.version);
    end
    h.sampleRate = fread(fid, 1, 'float32=>double');
    h.dspEnabled = fread(fid, 1, 'int16=>double');
    f = fread(fid, 6, 'float32=>double');
    h.actualDspCutoff = f(1); h.actualLowerBandwidth = f(2); h.actualUpperBandwidth = f(3);
    h.desiredDspCutoff = f(4); h.desiredLowerBandwidth = f(5); h.desiredUpperBandwidth = f(6);
    h.notchFilterMode = fread(fid, 1, 'int16=>double');
    notchHz = [0 50 60];
    h.notchFilterHz = 0;
    if h.notchFilterMode >= 0 && h.notchFilterMode <= 2, h.notchFilterHz = notchHz(h.notchFilterMode + 1); end
    f = fread(fid, 2, 'float32=>double');
    h.desiredImpedanceTestFrequency = f(1); h.actualImpedanceTestFrequency = f(2);
    h.notes = {readQString(fid, file), readQString(fid, file), readQString(fid, file)};
    h.numTempSensors = 0;
    if atLeast(h.version, [1 1]), h.numTempSensors = fread(fid, 1, 'int16=>double'); end
    h.evalBoardMode = 0;
    if atLeast(h.version, [1 3]), h.evalBoardMode = fread(fid, 1, 'int16=>double'); end
    h.referenceChannel = '';
    if atLeast(h.version, [2 0]), h.referenceChannel = readQString(fid, file); end

    nGroups = fread(fid, 1, 'int16=>double');
    if isempty(nGroups) || nGroups < 0
        error('NeuroAnalyzer:io:truncated', '%s: header ends before the signal groups.', file);
    end
    emptyCh = struct('nativeName', {}, 'customName', {}, 'nativeOrder', {}, 'customOrder', {}, ...
        'signalType', {}, 'enabled', {}, 'chipChannel', {}, 'boardStream', {}, ...
        'impedanceMagnitude', {}, 'impedancePhase', {}, 'group', {});
    channels = emptyCh;
    h.groups = struct('name', {}, 'prefix', {}, 'enabled', {}, 'numChannels', {}, 'numAmpChannels', {});
    for g = 1:nGroups
        grp.name = readQString(fid, file);
        grp.prefix = readQString(fid, file);
        v = fread(fid, 3, 'int16=>double');
        if numel(v) < 3
            error('NeuroAnalyzer:io:truncated', '%s: header ends inside signal group %d.', file, g);
        end
        grp.enabled = v(1); grp.numChannels = v(2); grp.numAmpChannels = v(3);
        h.groups(g) = grp;
        if grp.enabled && grp.numChannels > 0
            for k = 1:grp.numChannels
                ch.nativeName = readQString(fid, file);
                ch.customName = readQString(fid, file);
                v = fread(fid, 10, 'int16=>double');
                imp = fread(fid, 2, 'float32=>double');
                if numel(v) < 10 || numel(imp) < 2
                    error('NeuroAnalyzer:io:truncated', '%s: header ends inside a channel record.', file);
                end
                ch.nativeOrder = v(1); ch.customOrder = v(2); ch.signalType = v(3);
                ch.enabled = v(4); ch.chipChannel = v(5); ch.boardStream = v(6);
                % v(7:10): spike-scope trigger mode, threshold, digital channel, edge polarity
                ch.impedanceMagnitude = imp(1); ch.impedancePhase = imp(2);
                ch.group = grp.name;
                channels(end+1) = ch; %#ok<AGROW>
            end
        end
    end
    h.headerBytes = ftell(fid);
    h.channels = channels;
    en = channels([channels.enabled] ~= 0);
    types = [en.signalType];
    h.amplifierChannels = en(types == 0);
    h.auxChannels = en(types == 1);
    h.supplyChannels = en(types == 2);
    h.adcChannels = en(types == 3);
    h.digitalInChannels = en(types == 4);
    h.digitalOutChannels = en(types == 5);
    if isempty(en)
        h.amplifierChannels = emptyCh; h.auxChannels = emptyCh; h.supplyChannels = emptyCh;
        h.adcChannels = emptyCh; h.digitalInChannels = emptyCh; h.digitalOutChannels = emptyCh;
    end

    if h.version(1) == 1, N = 60; else, N = 128; end
    h.samplesPerBlock = N;
    h.bytesPerBlock = N * 4 + N * 2 * numel(h.amplifierChannels) ...
        + (N / 4) * 2 * numel(h.auxChannels) + 2 * numel(h.supplyChannels) ...
        + 2 * h.numTempSensors + N * 2 * numel(h.adcChannels) ...
        + N * 2 * ~isempty(h.digitalInChannels) + N * 2 * ~isempty(h.digitalOutChannels);
end

%% readQString - uint32 byte length (0xFFFFFFFF = null) + UTF-16LE text
function s = readQString(fid, file)
    len = fread(fid, 1, 'uint32=>double');
    if isempty(len)
        error('NeuroAnalyzer:io:truncated', '%s: header ends inside a text field.', file);
    end
    if len == hex2dec('FFFFFFFF') || len == 0
        s = '';
        return;
    end
    if mod(len, 2) ~= 0 || len > 1e6
        error('NeuroAnalyzer:io:badHeader', '%s: invalid text field length %d in the header.', file, len);
    end
    u = fread(fid, len / 2, 'uint16=>double');
    if numel(u) < len / 2
        error('NeuroAnalyzer:io:truncated', '%s: header ends inside a text field.', file);
    end
    s = char(u(:)');
end

%% channelBlock - n channels x (N*nBlocks) uint16 from channel-major block words
function x = channelBlock(words, off, N, n, nBlocks)
    if n == 0
        x = zeros(0, N * nBlocks, 'uint16');
        return;
    end
    x = reshape(words(off + (1:N * n), :), N, n, nBlocks);
    x = reshape(permute(x, [2 1 3]), n, N * nBlocks);
end

%% adcScale - Board ADC volts = gain * (value - offset) for the board mode
function [gain, offset] = adcScale(mode)
    switch mode
        case 1,  gain = 152.59e-6; offset = 32768;
        case 13, gain = 312.5e-6;  offset = 32768;
        otherwise, gain = 50.354e-6; offset = 0;
    end
end

%% atLeast - version [major minor] >= ref
function tf = atLeast(v, ref)
    tf = v(1) > ref(1) || (v(1) == ref(1) && v(2) >= ref(2));
end

%% channelLabel - Custom channel name, or the native name when empty
function s = channelLabel(ch)
    s = ch.customName;
    if isempty(s), s = ch.nativeName; end
end
