%% writeIntanRHD.m
% =========================================================================
% WRITE INTAN RHD - SYNTHETIC INTAN RHD2000 (.rhd) FILE FROM ARRAYS
% =========================================================================
% out = writeIntanRHD(file, amp, fs, Name, Value, ...)
%
% Writes amplifier (and optional board digital-input / ADC) signals as an
% Intan RHD2000 data file in the traditional single-file format, laid out
% as described in Intan Technologies' RHD2000 data file format
% documentation (intantech.com; see readIntanRHD for the byte layout).
% Used to make synthetic demo and test files (core/demo/demoFormats.m);
% not a replacement for Intan's acquisition software.
%
% Inputs:
%   file - output .rhd path
%   amp  - amplifier channels x samples, volts. Quantized to 0.195 uV
%          steps (uint16 with offset 32768, i.e. +/-6.389 mV range).
%   fs   - sample rate (Hz), stored as float32
% Options (Name, Value):
%   'Version'        [major minor], default [3 0]. 1.x uses 60-sample data
%                    blocks, >= 2.0 uses 128; < 1.2 writes uint32 timestamps.
%   'DigitalIn'      logical channels x samples (board digital inputs)
%   'ADC'            channels x samples, volts (board ADC inputs, board mode
%                    0: 50.354 uV steps, 0-3.3 V)
%   'ChannelNames'   cellstr custom names for the amplifier channels
%   'Notes'          cellstr of up to 3 notes
%   'NotchMode'      0 none (default), 1 = 50 Hz, 2 = 60 Hz (header only)
%   'FirstTimestamp' timestamp of the first sample (default 0)
%   'AuxChannels', 'SupplyChannels', 'TempSensors'  number of extra aux
%                    input / supply voltage / temperature channels written
%                    with constant values (exercise the block layout)
%   'DisabledChannels' number of extra disabled amplifier channel records
%   'DisabledGroup'  true adds a disabled, empty "Port B" signal group
% Output:
%   out - struct: nSamples written (whole data blocks only; trailing
%         samples that do not fill a block are dropped), samplesPerBlock,
%         headerBytes, bytesPerBlock, nBlocks
% Toolboxes: none (base MATLAB; also runs in Octave).
% =========================================================================

function out = writeIntanRHD(file, amp, fs, varargin)
    o = struct('Version', [3 0], 'DigitalIn', [], 'ADC', [], 'ChannelNames', {{}}, ...
        'Notes', {{}}, 'NotchMode', 0, 'FirstTimestamp', 0, 'AuxChannels', 0, ...
        'SupplyChannels', 0, 'TempSensors', 0, 'DisabledChannels', 0, 'DisabledGroup', false);
    for k = 1:2:numel(varargin)
        o.(varargin{k}) = varargin{k+1};
    end
    v = o.Version;
    nAmp = size(amp, 1);
    nDig = size(o.DigitalIn, 1);
    nAdc = size(o.ADC, 1);
    if v(1) == 1, N = 60; else, N = 128; end
    nBlocks = floor(size(amp, 2) / N);
    if nBlocks < 1
        error('NeuroAnalyzer:io:writeFailed', 'writeIntanRHD: need at least %d samples.', N);
    end
    nS = nBlocks * N;
    atLeast = @(ref) v(1) > ref(1) || (v(1) == ref(1) && v(2) >= ref(2));
    if ~atLeast([1 1]) && o.TempSensors > 0
        error('NeuroAnalyzer:io:writeFailed', 'Temperature sensors need file version >= 1.1.');
    end
    if ~atLeast([1 2]) && o.FirstTimestamp < 0
        error('NeuroAnalyzer:io:writeFailed', 'Negative timestamps need file version >= 1.2 (int32).');
    end

    fid = fopen(file, 'w', 'ieee-le');
    if fid < 0
        error('NeuroAnalyzer:io:writeFailed', 'Cannot write %s', file);
    end
    c = onCleanup(@() fclose(fid));

    % ---- Header ----
    fwrite(fid, hex2dec('C6912702'), 'uint32');
    fwrite(fid, v(1:2), 'int16');
    fwrite(fid, fs, 'float32');
    fwrite(fid, 1, 'int16');                                   % DSP enabled
    fwrite(fid, [1 0.1 7500 1 0.1 7500], 'float32');            % actual / desired DSP, lower, upper
    fwrite(fid, o.NotchMode, 'int16');
    fwrite(fid, [1000 1000], 'float32');                        % impedance test frequencies
    notes = [o.Notes(:)' {'', '', ''}];
    for k = 1:3, writeQString(fid, notes{k}); end
    if atLeast([1 1]), fwrite(fid, o.TempSensors, 'int16'); end
    if atLeast([1 3]), fwrite(fid, 0, 'int16'); end             % board mode 0
    if atLeast([2 0]), writeQString(fid, ''); end               % reference channel

    groups = {};
    % Port A: amplifiers, then aux / supply, then disabled records
    ch = {};
    for k = 1:nAmp
        name = sprintf('A-%03d', k - 1);
        custom = name;
        if numel(o.ChannelNames) >= k, custom = o.ChannelNames{k}; end
        ch{end+1} = chanRec(name, custom, k - 1, 0, 1, k - 1); %#ok<AGROW>
    end
    for k = 1:o.AuxChannels
        ch{end+1} = chanRec(sprintf('A-AUX%d', k), sprintf('A-AUX%d', k), k - 1, 1, 1, 32 + k); %#ok<AGROW>
    end
    for k = 1:o.SupplyChannels
        ch{end+1} = chanRec(sprintf('A-VDD%d', k), sprintf('A-VDD%d', k), k - 1, 2, 1, 48); %#ok<AGROW>
    end
    for k = 1:o.DisabledChannels
        ch{end+1} = chanRec(sprintf('A-%03d', nAmp + k - 1), '', nAmp + k - 1, 0, 0, nAmp + k - 1); %#ok<AGROW>
    end
    groups{end+1} = struct('name', 'Port A', 'prefix', 'A', 'enabled', 1, 'ch', {ch}, ...
        'nAmp', nAmp + o.DisabledChannels); %#ok<AGROW>
    if o.DisabledGroup
        groups{end+1} = struct('name', 'Port B', 'prefix', 'B', 'enabled', 0, 'ch', {{}}, 'nAmp', 0);
    end
    if nAdc > 0
        ch = arrayfun(@(k) chanRec(sprintf('ANALOG-IN-%d', k), sprintf('ANALOG-IN-%d', k), ...
            k - 1, 3, 1, 0), 1:nAdc, 'UniformOutput', false);
        groups{end+1} = struct('name', 'Analog Inputs', 'prefix', 'ANALOG-IN', 'enabled', 1, ...
            'ch', {ch}, 'nAmp', 0);
    end
    if nDig > 0
        ch = arrayfun(@(k) chanRec(sprintf('DIGITAL-IN-%02d', k), sprintf('DIGITAL-IN-%02d', k), ...
            k - 1, 4, 1, 0), 1:nDig, 'UniformOutput', false);
        groups{end+1} = struct('name', 'Digital Inputs', 'prefix', 'DIGITAL-IN', 'enabled', 1, ...
            'ch', {ch}, 'nAmp', 0);
    end
    fwrite(fid, numel(groups), 'int16');
    for g = 1:numel(groups)
        G = groups{g};
        writeQString(fid, G.name);
        writeQString(fid, G.prefix);
        fwrite(fid, [G.enabled numel(G.ch) G.nAmp], 'int16');
        for k = 1:numel(G.ch)
            r = G.ch{k};
            writeQString(fid, r.nativeName);
            writeQString(fid, r.customName);
            fwrite(fid, [r.nativeOrder r.nativeOrder r.signalType r.enabled r.chipChannel 0 ...
                0 0 0 0], 'int16');
            fwrite(fid, [1e6 -60], 'float32');                  % impedance magnitude (ohm) / phase (deg)
        end
    end
    headerBytes = ftell(fid);

    % ---- Data blocks, assembled as uint16 words (one column per block) ----
    nAux = o.AuxChannels; nSup = o.SupplyChannels; nTemp = o.TempSensors;
    wpb = 2 * N + N * nAmp + (N / 4) * nAux + nSup + nTemp + N * nAdc + N * (nDig > 0);
    words = zeros(wpb, nBlocks, 'uint16');
    ts = o.FirstTimestamp + (0:nS - 1);
    if atLeast([1 2]), tsw = typecast(int32(ts), 'uint16'); else, tsw = typecast(uint32(ts), 'uint16'); end
    words(1:2 * N, :) = reshape(tsw, 2 * N, nBlocks);
    off = 2 * N;
    q = uint16(min(max(round(double(amp(:, 1:nS)) / 0.195e-6) + 32768, 0), 65535));
    words(off + (1:N * nAmp), :) = blockWords(q, N, nBlocks);
    off = off + N * nAmp;
    if nAux > 0
        words(off + (1:(N / 4) * nAux), :) = 20000;             % ~0.75 V
        off = off + (N / 4) * nAux;
    end
    if nSup > 0
        words(off + (1:nSup), :) = 44118;                       % ~3.3 V
        off = off + nSup;
    end
    if nTemp > 0
        words(off + (1:nTemp), :) = typecast(int16(3700), 'uint16');   % 37.00 C
        off = off + nTemp;
    end
    if nAdc > 0
        qa = uint16(min(max(round(double(o.ADC(:, 1:nS)) / 50.354e-6), 0), 65535));
        words(off + (1:N * nAdc), :) = blockWords(qa, N, nBlocks);
        off = off + N * nAdc;
    end
    if nDig > 0
        w = zeros(1, nS, 'uint16');
        for k = 1:nDig
            w = bitor(w, uint16(logical(o.DigitalIn(k, 1:nS))) * uint16(2^(k - 1)));
        end
        words(off + (1:N), :) = reshape(w, N, nBlocks);
    end
    fwrite(fid, words, 'uint16');

    out = struct('nSamples', nS, 'samplesPerBlock', N, 'headerBytes', headerBytes, ...
        'bytesPerBlock', 2 * wpb, 'nBlocks', nBlocks);
end

%% chanRec - One channel record of the header
function r = chanRec(nativeName, customName, order, signalType, enabled, chipChannel)
    r = struct('nativeName', nativeName, 'customName', customName, 'nativeOrder', order, ...
        'signalType', signalType, 'enabled', enabled, 'chipChannel', chipChannel);
end

%% writeQString - uint32 byte length + UTF-16LE characters (empty: length 0)
function writeQString(fid, s)
    fwrite(fid, 2 * numel(s), 'uint32');
    if ~isempty(s), fwrite(fid, double(s), 'uint16'); end
end

%% blockWords - channels x (N*nBlocks) -> (N*channels) x nBlocks, channel-major per block
function w = blockWords(q, N, nBlocks)
    n = size(q, 1);
    w = reshape(permute(reshape(q, n, N, nBlocks), [2 1 3]), N * n, nBlocks);
end
