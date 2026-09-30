function writeABF(file, data, fs, varargin)
% writeABF - Write a synthetic Axon ABF 2 file (gap-free or episodic) for tests and demos.
%
% writeABF(file, data, fs, Name, Value, ...)
%
% data   channels x samples (gap-free), or channels x samples x sweeps
%        (episodic), in the channels' units
% Options: 'Names' (default IN 0 ...), 'Units' (default mV), 'SweepStarts'
%          (s, one per sweep; default back to back), 'Float' (true: float32
%          samples; default int16 with per-channel scale factors)
% Layout as readABF reads it (the ABF 2 layout documented by pyABF):
% 512-byte blocks, section map at 76; fields the readers do not use are
% zero. Not a replacement for pCLAMP. Base MATLAB only; also runs in GNU
% Octave.
%
[nCh, n, nSw] = size(data);
o = struct('Names', {{}}, 'Units', {{}}, 'SweepStarts', [], 'Float', false);
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
names = o.Names; units = o.Units;
for c = numel(names)+1:nCh, names{c} = sprintf('IN %d', c - 1); end
for c = numel(units)+1:nCh, units{c} = 'mV'; end
episodic = nSw > 1;
% Strings: after a double zero byte: '', 'Clampex', '', then name / unit pairs
strs = [{'', 'Clampex', 'protocol.pro'}, reshape([names; units], 1, [])];
blob = [uint8('NDAL synthetic strings') 0 0];
for k = 2:numel(strs), blob = [blob uint8(strs{k}) 0]; end %#ok<AGROW>
nameIdx = 3 + 2 * (0:nCh-1); unitIdx = nameIdx + 1;
% Scale factors: full scale about 1.05 x the largest value
range = 10; res = 32768;
isf = zeros(1, nCh);
for c = 1:nCh
    m = max(abs(reshape(data(c, :, :), 1, [])));
    if m == 0, m = 1; end
    isf(c) = range / (1.05 * m);
end
x = reshape(data, nCh, []);                             % sweeps one after the other
if o.Float
    samples = single(x); bps = 4; prec = 'float32';
else
    samples = int16(round(x .* (isf' * res / range))); bps = 2; prec = 'int16';
end
blocks = @(bytes) ceil(bytes / 512);
bProt = 1; bADC = 2; bStr = bADC + blocks(128 * nCh);
bSyn = bStr + blocks(numel(blob));
nSyn = episodic * nSw;
bData = bSyn + blocks(8 * nSyn);
fid = fopen(file, 'w', 'ieee-le');
if fid < 0, error('NeuroAnalyzer:io:abf', 'Cannot write %s', file); end
fwrite(fid, zeros(1, bData * 512), 'uint8');
fseek(fid, 0, 'bof'); fwrite(fid, uint8('ABF2'), 'uint8');
fwrite(fid, [0 0 6 2], 'uint8');                         % version 2.6.0.0
fwrite(fid, [512 nSw 20260930 36000000 0], 'uint32');
fwrite(fid, [0 o.Float 0 0], 'uint16');
fseek(fid, 60, 'bof'); fwrite(fid, 1, 'uint32');         % creator name index (Clampex)
fseek(fid, 72, 'bof'); fwrite(fid, 2, 'uint32');         % protocol path index
map = zeros(18, 3);
map(1, :) = [bProt 512 1];
map(2, :) = [bADC 128 nCh];
map(10, :) = [bStr numel(blob) 1];
map(11, :) = [bData bps numel(samples)];
if nSyn > 0, map(16, :) = [bSyn 8 nSyn]; end
for s = 1:18
    fseek(fid, 76 + (s - 1) * 16, 'bof');
    fwrite(fid, map(s, 1:2), 'uint32');
    fwrite(fid, map(s, 3), 'int64');
end
P = bProt * 512;
put(fid, P, 3 + 2 * episodic, 'int16');                   % 3 gap-free, 5 episodic
put(fid, P + 2, 1e6 / fs, 'float32');
put(fid, P + 14, 0, 'float32');                           % synch times in samples
put(fid, P + 22, n * nCh, 'int32');                       % samples per episode
put(fid, P + 110, range, 'float32');
put(fid, P + 114, range, 'float32');
put(fid, P + 118, res, 'int32');
put(fid, P + 122, res, 'int32');
for c = 1:nCh
    A = bADC * 512 + (c - 1) * 128;
    put(fid, A, c - 1, 'int16');
    put(fid, A + 26, c - 1, 'int16');                     % sampling sequence
    put(fid, A + 28, 1, 'float32');                       % programmable gain
    put(fid, A + 32, 1, 'float32');
    put(fid, A + 40, isf(c), 'float32');                  % instrument scale factor (V per unit)
    put(fid, A + 48, 1, 'float32');                       % signal gain
    put(fid, A + 74, nameIdx(c), 'int32');
    put(fid, A + 78, unitIdx(c), 'int32');
end
fseek(fid, bStr * 512, 'bof'); fwrite(fid, blob, 'uint8');
if nSyn > 0
    st = o.SweepStarts;
    if isempty(st), st = (0:nSw-1) * n / fs; end
    fseek(fid, bSyn * 512, 'bof');
    for k = 1:nSw, fwrite(fid, [round(st(k) * fs) n * nCh], 'int32'); end
end
fseek(fid, bData * 512, 'bof');
fwrite(fid, samples, prec);
fclose(fid);
end

function put(fid, pos, v, prec)
fseek(fid, pos, 'bof');
fwrite(fid, v, prec);
end
