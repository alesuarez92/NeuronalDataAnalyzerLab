function writePerimedDat(file, V, I, hdr)
% writePerimedDat - Write a synthetic PIMSoft (Perimed PeriCam PSI) .dat file.
%
% writePerimedDat(file, V, I, hdr)
%
% Writes variance images V and intensity images I (H x W x N, same size)
% in the layout readPerimedDat reads (see its header). Used to make demo
% and test files; not a replacement for PIMSoft, and header fields the
% reader does not use are left at zero.
% hdr (struct, every field optional): version (1, 2 or 3; default 2),
% gain (default 1), beta (default 1), name, serial, startTime, durationS,
% distanceMm, frameRateText (e.g. '25 img/s'), resolutionMm.
% Base MATLAB only; also runs in GNU Octave.
%
if nargin < 4, hdr = struct(); end
g = @(f, d) getf(hdr, f, d);
ver = g('version', 2);
[H, W, N] = size(V);
if ~isequal(size(I), size(V)), error('NeuroAnalyzer:io:perimed', 'V and I must have the same size.'); end
switch ver
    case 1, off = 46;
    case 2, off = 540;
    case 3, off = 581 + 32 * N;
    otherwise, error('NeuroAnalyzer:io:perimed', 'Version must be 1, 2 or 3.');
end
fid = fopen(file, 'w', 'ieee-le');
if fid < 0, error('NeuroAnalyzer:io:perimed', 'Cannot write %s', file); end
c = onCleanup(@() fclose(fid));
fwrite(fid, zeros(1, off), 'uint8');
putStr(fid, 0, 'PSI', 10);
fseek(fid, 10, 'bof'); fwrite(fid, ver, 'int32');
fwrite(fid, g('gain', 1), 'double');
fwrite(fid, g('beta', 1), 'double');
fwrite(fid, 2 * N, 'double');
fwrite(fid, W, 'int32');
fwrite(fid, H, 'int32');
if ver >= 2
    putStr(fid, 46, g('name', ''), 80);
    putStr(fid, 126, g('serial', ''), 20);
    putStr(fid, 146, g('startTime', ''), 20);
    fseek(fid, 166, 'bof'); fwrite(fid, g('durationS', 0), 'double');
    fseek(fid, 494, 'bof'); fwrite(fid, g('distanceMm', 0), 'double');
    putStr(fid, 502, g('frameRateText', ''), 20);
    fseek(fid, 522, 'bof'); fwrite(fid, g('resolutionMm', 0), 'double');
end
fseek(fid, off, 'bof');
for k = 1:N, fwrite(fid, double(V(:, :, k)), 'double'); end
for k = 1:N, fwrite(fid, double(I(:, :, k)), 'double'); end
end

function putStr(fid, pos, s, n)
b = zeros(1, n, 'uint8');
s = uint8(char(s));
b(1:min(n, numel(s))) = s(1:min(n, numel(s)));
fseek(fid, pos, 'bof');
fwrite(fid, b, 'uint8');
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
