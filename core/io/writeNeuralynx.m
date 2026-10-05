function writeNeuralynx(folder, data, fs, varargin)
% writeNeuralynx - Write synthetic Neuralynx .ncs files (and Events.nev) for tests and demos.
%
% writeNeuralynx(folder, data, fs, Name, Value, ...)
%
% data   channels x samples in volts; one CSC<k>.ncs per channel
% Options: 'Names' (default CSC1 ...), 'ADBitVolts' (default 3.0518e-8,
%          a 1 mV input range), 'InputInverted' (default true, as Cheetah
%          writes), 'StartUs' (first timestamp, default 1e6), 'TTL'
%          struct(sample (1-based), value) for Events.nev
% Layout as readNeuralynx reads it (16 kB text header, 1044-byte records;
% 184-byte event records), from the vendor's published "Neuralynx Data
% File Formats" document (see readNeuralynx). Base MATLAB only; also runs in GNU Octave.
%
[nCh, n] = size(data);
o = struct('Names', {{}}, 'ADBitVolts', 1e-3 / 32768, 'InputInverted', true, 'StartUs', 1e6, ...
    'TTL', struct('sample', {}, 'value', {}));
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
if ~exist(folder, 'dir'), mkdir(folder); end
sgn = 1 - 2 * o.InputInverted;
nRec = ceil(n / 512);
for c = 1:nCh
    nm = sprintf('CSC%d', c);
    if numel(o.Names) >= c, nm = o.Names{c}; end
    q = int16(max(-32767, min(32767, round(sgn * data(c, :) / o.ADBitVolts))));
    q(end+1:nRec*512) = 0;
    h = header({'-FileType NCS', '-RecordSize 1044', sprintf('-AcqEntName %s', nm), ...
        sprintf('-ADChannel %d', c - 1), '-InputRange 1000', sprintf('-InputInverted %s', tf(o.InputInverted)), ...
        sprintf('-SamplingFrequency %.10g', fs), sprintf('-ADBitVolts %.12g', o.ADBitVolts), '-ADMaxValue 32767', ...
        '-DSPLowCutFilterEnabled True', '-DspLowCutFrequency 0.1', '-DspLowCutNumTaps 0', '-DspLowCutFilterType DCO', ...
        '-DSPHighCutFilterEnabled True', '-DspHighCutFrequency 9000', '-DspHighCutNumTaps 64', '-DspHighCutFilterType FIR', ...
        '-DspDelayCompensation Enabled'});
    fid = fopen(fullfile(folder, [nm '.ncs']), 'w', 'ieee-le');
    fwrite(fid, h, 'uint8');
    for r = 1:nRec
        fwrite(fid, round(o.StartUs + (r - 1) * 512 / fs * 1e6), 'uint64');
        fwrite(fid, [c - 1, round(fs), min(512, n - (r - 1) * 512)], 'uint32');
        fwrite(fid, q((r - 1) * 512 + (1:512)), 'int16');
    end
    fclose(fid);
end
if ~isempty(o.TTL)
    h = header({'-FileType Event', '-RecordSize 184'});
    fid = fopen(fullfile(folder, 'Events.nev'), 'w', 'ieee-le');
    fwrite(fid, h, 'uint8');
    for k = 1:numel(o.TTL)
        fwrite(fid, [0 0 2], 'int16');
        fwrite(fid, round(o.StartUs + (o.TTL(k).sample - 1) / fs * 1e6), 'uint64');
        fwrite(fid, [11 o.TTL(k).value 0 0 0], 'int16');
        fwrite(fid, zeros(1, 8), 'int32');
        txt = zeros(1, 128, 'uint8');
        s = uint8(sprintf('TTL Input on AcqSystem1_0 board 0 port 0 value (0x%04X).', o.TTL(k).value));
        txt(1:min(128, numel(s))) = s(1:min(128, numel(s)));
        fwrite(fid, txt, 'uint8');
    end
    fclose(fid);
end
end

function h = header(lines)
t = sprintf('######## Neuralynx Data File Header\r\n-FileVersion 3.4\r\n-ApplicationName Cheetah "6.4.1"\r\n');
t = [t sprintf('-TimeCreated 2026/09/30 10:00:00\r\n-TimeClosed 2026/09/30 10:10:00\r\n-AcquisitionSystem AcqSystem1 DigitalLynxSX\r\n-HardwareSubSystemName AcqSystem1\r\n-HardwareSubSystemType DigitalLynxSX\r\n')];
t = [t sprintf('%s\r\n', lines{:})];
h = zeros(1, 16384, 'uint8');
h(1:numel(t)) = uint8(t);
end

function s = tf(x)
if x, s = 'True'; else, s = 'False'; end
end
