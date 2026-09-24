%% writeOpenEphysBinary.m
% =========================================================================
% WRITE OPEN EPHYS BINARY - SYNTHETIC OPEN EPHYS RECORDING FOLDER
% =========================================================================
% out = writeOpenEphysBinary(folder, data, fs, Name, Value, ...)
%
% Writes channels as an Open Ephys GUI "binary format" recording, laid out
% as described in the Open Ephys GUI documentation (open-ephys.github.io,
% "Binary format"). Used to make synthetic demo and test recordings
% (core/demo/demoFormats.m); readable by readOpenEphysBinary.
%
% Inputs:
%   folder - session folder to create (the recording goes below it)
%   data   - neural channels x samples, volts; stored as int16 with
%            bit_volts (default 0.195 uV per bit, units "uV")
%   fs     - sample rate (Hz)
% Options (Name, Value):
%   'Version'      '0.6.7' (default; layout of GUI >= 0.6) or '0.5.5'
%                  (layout of GUI 0.5.x)
%   'ChannelNames' cellstr (default CH1, CH2, ...)
%   'BitVolts'     uV per bit for neural channels (default 0.195)
%   'ADC'          channels x samples, volts: extra channels ADC1, ADC2 ...
%                  in the same stream (bit_volts 0.00015258789, units "V")
%   'TTL'          struct array with fields line (1-based), on, off
%                  (1-based sample indices of rising / falling edges)
%   'FirstSample'  sample number of the first sample (default 0)
% Layout written (GUI >= 0.6):
%   <folder>/Record Node 101/experiment1/recording1/
%     structure.oebin                           JSON metadata
%     continuous/Acquisition_Board-100.Rhythm Data/
%       continuous.dat                          int16, channel-interleaved
%       sample_numbers.npy (int64), timestamps.npy (float64 s)
%     events/Acquisition_Board-100.Rhythm Data/TTL/
%       states.npy (int16, +line rising / -line falling),
%       sample_numbers.npy (int64), timestamps.npy (float64), full_words.npy (uint64)
%   GUI 0.5.x: continuous/Rhythm_FPGA-100.0/{continuous.dat, timestamps.npy
%   (int64 sample numbers)} and events/Rhythm_FPGA-100.0/TTL_1/
%   {channel_states.npy, channels.npy, timestamps.npy, full_words.npy}.
% Output:
%   out - struct: recordingDir, oebin, datFile, nSamples, bitVolts
% Toolboxes: none (base MATLAB; also runs in Octave).
% =========================================================================

function out = writeOpenEphysBinary(folder, data, fs, varargin)
    o = struct('Version', '0.6.7', 'ChannelNames', {{}}, 'BitVolts', 0.195, 'ADC', [], ...
        'TTL', struct('line', {}, 'on', {}, 'off', {}), 'FirstSample', 0);
    for k = 1:2:numel(varargin)
        o.(varargin{k}) = varargin{k+1};
    end
    legacy = strncmp(o.Version, '0.5', 3);
    nNeu = size(data, 1);
    nAdc = size(o.ADC, 1);
    nS = size(data, 2);
    names = arrayfun(@(k) sprintf('CH%d', k), 1:nNeu, 'UniformOutput', false);
    names(1:numel(o.ChannelNames)) = o.ChannelNames;
    adcBitVolts = 0.00015258789;

    if legacy
        recDir = fullfile(folder, 'experiment1', 'recording1');
        contName = 'Rhythm_FPGA-100.0';
        evName = 'Rhythm_FPGA-100.0/TTL_1';
    else
        recDir = fullfile(folder, 'Record Node 101', 'experiment1', 'recording1');
        contName = 'Acquisition_Board-100.Rhythm Data';
        evName = 'Acquisition_Board-100.Rhythm Data/TTL';
    end
    contDir = fullfile(recDir, 'continuous', contName);
    mkdirs(contDir);

    % ---- continuous.dat: int16, sample-major (all channels of sample 1, then sample 2 ...) ----
    q = [round(double(data) / (o.BitVolts * 1e-6)); round(double(o.ADC) / adcBitVolts)];
    q = int16(min(max(q, -32768), 32767));
    datFile = fullfile(contDir, 'continuous.dat');
    fid = fopen(datFile, 'w', 'ieee-le');
    if fid < 0
        error('NeuroAnalyzer:io:writeFailed', 'Cannot write %s', datFile);
    end
    fwrite(fid, q, 'int16');            % column-major = channel-interleaved
    fclose(fid);
    samples = int64(o.FirstSample + (0:nS - 1));
    if legacy
        writeNPY(fullfile(contDir, 'timestamps.npy'), samples);
    else
        writeNPY(fullfile(contDir, 'sample_numbers.npy'), samples);
        writeNPY(fullfile(contDir, 'timestamps.npy'), double(samples) / fs);
    end

    % ---- TTL events ----
    hasTTL = ~isempty(o.TTL);
    if hasTTL
        evDir = fullfile(recDir, 'events', strrep(evName, '/', filesep));
        mkdirs(evDir);
        st = []; smp = [];
        for k = 1:numel(o.TTL)
            L = o.TTL(k).line;
            st = [st; repmat(L, numel(o.TTL(k).on), 1); repmat(-L, numel(o.TTL(k).off), 1)]; %#ok<AGROW>
            smp = [smp; o.TTL(k).on(:); o.TTL(k).off(:)]; %#ok<AGROW>
        end
        [smp, order] = sort(smp);
        st = st(order);
        evSamples = int64(o.FirstSample + smp - 1);    % 1-based index -> sample number
        words = zeros(numel(st), 1);                   % full_words: TTL state after each event
        cur = 0;
        for k = 1:numel(st)
            bit = 2^(abs(st(k)) - 1);
            if st(k) > 0
                cur = bitor(cur, bit);
            elseif bitand(cur, bit) > 0
                cur = cur - bit;
            end
            words(k) = cur;
        end
        if legacy
            writeNPY(fullfile(evDir, 'channel_states.npy'), int16(st));
            writeNPY(fullfile(evDir, 'channels.npy'), int16(abs(st)));
            writeNPY(fullfile(evDir, 'timestamps.npy'), evSamples);
            writeNPY(fullfile(evDir, 'full_words.npy'), uint8(words));
        else
            writeNPY(fullfile(evDir, 'states.npy'), int16(st));
            writeNPY(fullfile(evDir, 'sample_numbers.npy'), evSamples);
            writeNPY(fullfile(evDir, 'timestamps.npy'), double(evSamples) / fs);
            writeNPY(fullfile(evDir, 'full_words.npy'), uint64(words));
        end
    end

    % ---- structure.oebin (JSON) ----
    chans = cell(1, nNeu + nAdc);
    for k = 1:nNeu
        chans{k} = sprintf(['        {"channel_name": %s, "description": "Headstage data channel", ' ...
            '"identifier": "genericdata.continuous", "history": "Acquisition Board", ' ...
            '"bit_volts": %.10g, "units": "uV", "source_processor_index": %d, ' ...
            '"recorded_processor_index": %d}'], jstr(names{k}), o.BitVolts, k - 1, k - 1);
    end
    for k = 1:nAdc
        chans{nNeu + k} = sprintf(['        {"channel_name": "ADC%d", "description": "ADC data channel", ' ...
            '"identifier": "genericdata.continuous", "history": "Acquisition Board", ' ...
            '"bit_volts": %.10g, "units": "V", "source_processor_index": %d, ' ...
            '"recorded_processor_index": %d}'], k, adcBitVolts, nNeu + k - 1, nNeu + k - 1);
    end
    chanText = strjoin(chans, sprintf(',\n'));
    if legacy
        cont = sprintf(['    {"folder_name": "%s/", "sample_rate": %.10g, ' ...
            '"source_processor_name": "Rhythm FPGA", "source_processor_id": 100, ' ...
            '"source_processor_sub_idx": 0, "recorded_processor": "Rhythm FPGA", ' ...
            '"recorded_processor_id": 100, "num_channels": %d, "channels": [\n%s\n    ]}'], ...
            contName, fs, nNeu + nAdc, chanText);
        ev = sprintf(['    {"folder_name": "%s/", "channel_name": "TTL Input", ' ...
            '"description": "TTL Events coming from the hardware source processor", ' ...
            '"identifier": "sourceevent", "sample_rate": %.10g, "type": "int16", ' ...
            '"num_channels": 8, "source_processor": "Rhythm FPGA"}'], evName, fs);
    else
        cont = sprintf(['    {"folder_name": "%s/", "sample_rate": %.10g, ' ...
            '"source_processor_name": "Acquisition Board", "source_processor_id": 100, ' ...
            '"stream_name": "Rhythm Data", "recorded_processor": "Acquisition Board", ' ...
            '"recorded_processor_id": 100, "num_channels": %d, "channels": [\n%s\n    ]}'], ...
            contName, fs, nNeu + nAdc, chanText);
        ev = sprintf(['    {"folder_name": "%s/", "channel_name": "Rhythm Data TTL Input", ' ...
            '"description": "TTL Events coming from the hardware source processor", ' ...
            '"identifier": "", "sample_rate": %.10g, "type": "int16", "num_channels": 8, ' ...
            '"source_processor": "Acquisition Board", "stream_name": "Rhythm Data"}'], evName, fs);
    end
    if ~hasTTL, ev = ''; else, ev = [newline ev newline '  ']; end
    json = sprintf('{\n  "GUI version": "%s",\n  "continuous": [\n%s\n  ],\n  "events": [%s],\n  "spikes": []\n}\n', ...
        o.Version, cont, ev);
    oebin = fullfile(recDir, 'structure.oebin');
    fid = fopen(oebin, 'w');
    if fid < 0
        error('NeuroAnalyzer:io:writeFailed', 'Cannot write %s', oebin);
    end
    fwrite(fid, json, 'char');
    fclose(fid);

    out = struct('recordingDir', recDir, 'oebin', oebin, 'datFile', datFile, ...
        'nSamples', nS, 'bitVolts', o.BitVolts);
end

%% mkdirs - mkdir -p
function mkdirs(d)
    if ~(exist(d, 'dir') == 7), mkdir(d); end
end

%% jstr - JSON string literal (escapes quotes and backslashes)
function s = jstr(txt)
    s = ['"' strrep(strrep(txt, '\', '\\'), '"', '\"') '"'];
end
