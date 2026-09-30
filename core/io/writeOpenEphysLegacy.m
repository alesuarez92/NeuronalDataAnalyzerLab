function writeOpenEphysLegacy(folder, data, fs, varargin)
% writeOpenEphysLegacy - Write synthetic Open Ephys legacy .continuous files (+ all_channels.events).
%
% writeOpenEphysLegacy(folder, data, fs, Name, Value, ...)
%
% data   channels x samples in volts: 100_CH<k>.continuous (0.195 uV per bit)
% Options: 'ADC' (rows in volts: 100_ADC<k>.continuous, 0.00015259 V per
%          bit), 'TTL' struct(channel (0-based), on, off: 1-based samples),
%          'FirstTimestamp' (samples, default 0)
% Layout as readOpenEphysLegacy reads it (the GUI's pre-0.6 format).
% Base MATLAB only; also runs in GNU Octave.
%
o = struct('ADC', [], 'TTL', struct('channel', {}, 'on', {}, 'off', {}), 'FirstTimestamp', 0);
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
if ~exist(folder, 'dir'), mkdir(folder); end
for c = 1:size(data, 1), writeOne(fullfile(folder, sprintf('100_CH%d.continuous', c)), sprintf('CH%d', c), data(c, :) / 0.195e-6, fs, 0.195, o.FirstTimestamp); end
for c = 1:size(o.ADC, 1), writeOne(fullfile(folder, sprintf('100_ADC%d.continuous', c)), sprintf('ADC%d', c), o.ADC(c, :) / 0.00015259, fs, 0.00015259, o.FirstTimestamp); end
if ~isempty(o.TTL)
    fid = fopen(fullfile(folder, 'all_channels.events'), 'w', 'ieee-le');
    fwrite(fid, header('all channels', 'Event', fs, 1), 'uint8');
    for k = 1:numel(o.TTL)
        e = o.TTL(k);
        t = [e.on(:)' e.off(:)']; id = [ones(1, numel(e.on)) zeros(1, numel(e.off))];
        [t, i] = sort(t); id = id(i);
        for j = 1:numel(t)
            fwrite(fid, o.FirstTimestamp + t(j) - 1, 'int64');
            fwrite(fid, 0, 'int16');
            fwrite(fid, [3 100 id(j) e.channel], 'uint8');
            fwrite(fid, 0, 'uint16');
        end
    end
    fclose(fid);
end
end

function writeOne(f, name, q, fs, bitVolts, t0)
q = round(q(:)');
n = numel(q);
nR = ceil(n / 1024);
q(end+1:nR*1024) = 0;
fid = fopen(f, 'w', 'ieee-le');
fwrite(fid, header(name, 'Continuous', fs, bitVolts), 'uint8');
for r = 1:nR
    fwrite(fid, t0 + (r - 1) * 1024, 'int64');
    fwrite(fid, [min(1024, n - (r - 1) * 1024) 0], 'uint16');
    fwrite(fid, q((r - 1) * 1024 + (1:1024)), 'int16', 0, 'ieee-be');
    fwrite(fid, 0:9, 'uint8');
end
fclose(fid);
end

function h = header(name, type, fs, bitVolts)
t = sprintf(['header.format = ''Open Ephys Data Format'';\nheader.version = 0.4;\nheader.header_bytes = 1024;\n' ...
    'header.description = ''each record contains one 64-bit timestamp, one 16-bit sample count (N), 1 uint16 ' ...
    'recordingNumber, N 16-bit samples, and one 10-byte record marker (0 1 2 3 4 5 6 7 8 9)'';\n' ...
    'header.date_created = ''30-Sep-2026 100000'';\nheader.channel = ''%s'';\nheader.channelType = ''%s'';\n' ...
    'header.sampleRate = %d;\nheader.blockLength = 1024;\nheader.bufferSize = 1024;\nheader.bitVolts = %.10g;\n'], ...
    name, type, round(fs), bitVolts);
h = zeros(1, 1024, 'uint8');
h(1:numel(t)) = uint8(t);
end
