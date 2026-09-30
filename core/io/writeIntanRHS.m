function writeIntanRHS(file, data, fs, varargin)
% writeIntanRHS - Write a synthetic Intan RHS2000 (.rhs) file for tests and demos.
%
% writeIntanRHS(file, data, fs, Name, Value, ...)
%
% data   amplifier channels x samples, volts (0.195 uV per bit)
% Options: 'DigitalIn' (rows of 0/1: DIGITAL-IN-01 ...), 'ADC' (rows in
%          volts: ANALOG-IN-1 ..., 312.5 uV per bit), 'Stim' (amplifier
%          channels x samples, amps: the stimulation current),
%          'StepSize' (A, default 1e-6), 'DC' (true: DC amplifier data
%          saved, written as mid-scale), 'Names' (amplifier channel names)
% Samples are padded to whole 128-sample blocks. Layout as readIntanRHS
% reads it (Intan's published RHS2000 file format). Base MATLAB only;
% also runs in GNU Octave.
%
[nA, n] = size(data);
o = struct('DigitalIn', [], 'ADC', [], 'Stim', [], 'StepSize', 1e-6, 'DC', false, 'Names', {{}});
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
nD = size(o.DigitalIn, 1); nX = size(o.ADC, 1);
nB = ceil(n / 128); N = nB * 128;
padTo = @(x) [x zeros(size(x, 1), N - size(x, 2))];
fid = fopen(file, 'w', 'ieee-le');
if fid < 0, error('NeuroAnalyzer:io:intan', 'Cannot write %s', file); end
fwrite(fid, hex2dec('D69127AC'), 'uint32');
fwrite(fid, [3 2], 'int16');
fwrite(fid, fs, 'float32');
fwrite(fid, 1, 'int16');
fwrite(fid, [1 0.1 1000 7500 1 0.1 1000 7500], 'float32');
fwrite(fid, 0, 'int16');
fwrite(fid, [1000 1000], 'float32');
fwrite(fid, [0 0], 'int16');
fwrite(fid, o.StepSize, 'float32');
fwrite(fid, [1e-6 0], 'float32');
for k = 1:3, qstr(fid, ''); end
fwrite(fid, double(o.DC), 'int16');
fwrite(fid, 13, 'int16');
qstr(fid, 'hardware');
groups = {};
if nA, groups{end+1} = {'Port A', 'A', 0, nA}; end
if nX, groups{end+1} = {'Analog Input Ports', 'ANALOG-IN', 3, nX}; end
if nD, groups{end+1} = {'Digital Input Ports', 'DIGITAL-IN', 5, nD}; end
fwrite(fid, numel(groups), 'int16');
for g = 1:numel(groups)
    G = groups{g};
    qstr(fid, G{1}); qstr(fid, G{2});
    fwrite(fid, [1 G{4} (G{3} == 0) * G{4}], 'int16');
    for k = 1:G{4}
        switch G{3}
            case 0
                nat = sprintf('A-%03d', k - 1);
                cus = nat; if numel(o.Names) >= k, cus = o.Names{k}; end
            case 3, nat = sprintf('ANALOG-IN-%d', k); cus = nat;
            case 5, nat = sprintf('DIGITAL-IN-%02d', k); cus = nat;
        end
        qstr(fid, nat); qstr(fid, cus);
        fwrite(fid, [k - 1, k - 1, G{3}, 1, k - 1, 0, 0, 0, 0, 0, 0], 'int16');
        fwrite(fid, [0 0], 'float32');
    end
end
A = uint16(padTo(round(data / 0.195e-6) + 32768));
S = zeros(nA, N);
if ~isempty(o.Stim)
    m = round(abs(o.Stim) / o.StepSize);
    S(:, 1:size(o.Stim, 2)) = min(m, 255) + 256 * (o.Stim < 0);
end
X = uint16(padTo(round(o.ADC / 312.5e-6) + 32768));
Dw = zeros(1, N);
for k = 1:nD, Dw(1:size(o.DigitalIn, 2)) = Dw(1:size(o.DigitalIn, 2)) + (o.DigitalIn(k, :) ~= 0) * 2^(k - 1); end
for b = 1:nB
    i = (b - 1) * 128 + (1:128);
    fwrite(fid, i - 1, 'int32');
    if nA, fwrite(fid, A(:, i)', 'uint16'); end
    if o.DC && nA, fwrite(fid, 512 * ones(128, nA), 'uint16'); end
    if nA, fwrite(fid, S(:, i)', 'uint16'); end
    if nX, fwrite(fid, X(:, i)', 'uint16'); end
    if nD, fwrite(fid, Dw(i), 'uint16'); end
end
fclose(fid);
end

function qstr(fid, s)
if isempty(s), fwrite(fid, hex2dec('FFFFFFFF'), 'uint32'); return; end
fwrite(fid, 2 * numel(s), 'uint32');
fwrite(fid, double(s), 'uint16');
end
