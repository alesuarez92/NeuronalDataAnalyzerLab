function writeBlackrock(base, data, fs, varargin)
% writeBlackrock - Write a synthetic Blackrock NSx (and NEV with digital events) for tests and demos.
%
% writeBlackrock(base, data, fs, Name, Value, ...)
%
% base    path without extension: writes base.ns6 (30 kHz) or base.ns5
%         (other rates; see 'Ext'), and base.nev when 'Digital' is given
% data    channels x samples, in volts (stored as int16 with 0.25 uV per
%         bit for amplifier channels, 1 mV per bit for analog inputs)
% fs      sample rate: 30000 / period (period an integer)
% Options: 'ElectrodeIds' (default 1:nCh; ids above 128 are analog
%          inputs, labelled ainp<k>), 'Labels', 'Spec' ('2.3' default,
%          '3.0', '2.1'), 'Ext' ('.ns6' when fs = 30 kHz, else '.ns5'),
%          'Digital' struct(sample (1-based at fs), value uint16) for the
%          NEV digital-input port, 'Blocks' (sample indices where a new
%          data block starts, e.g. [1 5001])
% Layout as readBlackrock reads it (Blackrock's file specification).
% Base MATLAB only; also runs in GNU Octave.
%
[nCh, n] = size(data);
o = struct('ElectrodeIds', 1:nCh, 'Labels', {{}}, 'Spec', '2.3', 'Ext', '', ...
    'Digital', struct('sample', {}, 'value', {}), 'Blocks', 1);
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
period = round(30000 / fs);
if isempty(o.Ext), if period == 1, o.Ext = '.ns6'; else, o.Ext = '.ns5'; end, end
isAnalog = o.ElectrodeIds > 128;
labels = o.Labels;
for k = numel(labels)+1:nCh
    if isAnalog(k), labels{k} = sprintf('ainp%d', o.ElectrodeIds(k) - 128);
    else, labels{k} = sprintf('elec%d', o.ElectrodeIds(k)); end
end
lsb = 0.25e-6 * ones(nCh, 1); lsb(isAnalog) = 1e-3;
q = int16(max(-32767, min(32767, round(data ./ lsb))));
fid = fopen([base o.Ext], 'w', 'ieee-le');
if fid < 0, error('NeuroAnalyzer:io:blackrock', 'Cannot write %s', [base o.Ext]); end
if strcmp(o.Spec, '2.1')
    fwrite(fid, pad('NEURALSG', 8), 'uint8');
    fwrite(fid, pad('synthetic', 16), 'uint8');
    fwrite(fid, [period nCh], 'uint32');
    fwrite(fid, o.ElectrodeIds, 'uint32');
    fwrite(fid, round(double(data) ./ 0.25e-6), 'int16');
    fclose(fid);
else
    v = sscanf(o.Spec, '%d.%d')';
    headerBytes = 314 + 66 * nCh;
    fwrite(fid, pad('NEURALCD', 8), 'uint8');
    fwrite(fid, v, 'uint8');
    fwrite(fid, headerBytes, 'uint32');
    fwrite(fid, pad(sprintf('%g kS/s', fs / 1000), 16), 'uint8');
    fwrite(fid, pad('Neuronal Data Analyzer Lab synthetic file', 256), 'uint8');
    fwrite(fid, [period 30000], 'uint32');
    fwrite(fid, [2026 9 3 30 10 0 0 0], 'uint16');
    fwrite(fid, nCh, 'uint32');
    for k = 1:nCh
        fwrite(fid, uint8('CC'), 'uint8');
        fwrite(fid, o.ElectrodeIds(k), 'uint16');
        fwrite(fid, pad(labels{k}, 16), 'uint8');
        fwrite(fid, [1 k], 'uint8');
        if isAnalog(k)
            fwrite(fid, [-32764 32764 -32764 32764], 'int16');      % 1 mV per bit
            fwrite(fid, pad('mV', 16), 'uint8');
        else
            fwrite(fid, [-32764 32764 -8191 8191], 'int16');        % 0.25 uV per bit
            fwrite(fid, pad('uV', 16), 'uint8');
        end
        fwrite(fid, zeros(1, 20), 'uint8');                          % filters
    end
    starts = unique([1 o.Blocks(:)' n + 1]);
    for b = 1:numel(starts) - 1
        i1 = starts(b); i2 = starts(b + 1) - 1;
        fwrite(fid, 1, 'uint8');
        ts = (i1 - 1) * period;
        if v(1) >= 3, fwrite(fid, ts, 'uint64'); else, fwrite(fid, ts, 'uint32'); end
        fwrite(fid, i2 - i1 + 1, 'uint32');
        fwrite(fid, q(:, i1:i2), 'int16');
    end
    fclose(fid);
end
if ~isempty(o.Digital)
    v = sscanf(o.Spec, '%d.%d')';
    tsBytes = 4 + 4 * (v(1) >= 3);
    packet = tsBytes + 2 + 2 + 2 + 10;                       % room for the 2.1 / 2.2 analog fields
    fid = fopen([base '.nev'], 'w', 'ieee-le');
    fwrite(fid, pad('NEURALEV', 8), 'uint8');
    fwrite(fid, v, 'uint8');
    fwrite(fid, 1, 'uint16');
    fwrite(fid, [336 packet 30000 30000], 'uint32');
    fwrite(fid, [2026 9 3 30 10 0 0 0], 'uint16');
    fwrite(fid, pad('Neuronal Data Analyzer Lab', 32), 'uint8');
    fwrite(fid, zeros(1, 256), 'uint8');
    fwrite(fid, 0, 'uint32');
    for k = 1:numel(o.Digital)
        ts = (o.Digital(k).sample - 1) * period;
        if tsBytes == 8, fwrite(fid, ts, 'uint64'); else, fwrite(fid, ts, 'uint32'); end
        fwrite(fid, 0, 'uint16');
        fwrite(fid, [1 0], 'uint8');
        fwrite(fid, o.Digital(k).value, 'uint16');
        fwrite(fid, zeros(1, packet - tsBytes - 6), 'uint8');
    end
    fclose(fid);
end
end

function b = pad(s, n)
b = zeros(1, n, 'uint8');
s = uint8(s);
b(1:min(n, numel(s))) = s(1:min(n, numel(s)));
end
