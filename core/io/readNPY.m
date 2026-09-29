%% readNPY.m
% =========================================================================
% READ NPY - MINIMAL READER FOR NUMPY .npy ARRAY FILES
% =========================================================================
% x = readNPY(file)
%
% Reads a NumPy .npy file as written by numpy.save (used by the Open Ephys
% binary format for sample numbers, timestamps and TTL states).
%
% Inputs:
%   file - path to a .npy file
% Output:
%   x    - the array in its native class (int64, double, int16, logical…).
%          1-D arrays of shape (n,) are returned as n x 1 columns; 2-D
%          arrays keep their shape (C order is transposed back for you).
%
% Method (NumPy "npy" format specification, format versions 1.0-3.0):
%   bytes 0-5   magic string \x93NUMPY
%   byte  6-7   major / minor format version
%   then        header length: uint16 (v1.x) or uint32 (v2.x, v3.x), little-endian
%   then        ASCII (v3: UTF-8) Python dict literal, e.g.
%               {'descr': '<i8', 'fortran_order': False, 'shape': (3,), }
%   then        raw data. descr = byte order (< little, > big, | n/a,
%               = native) + kind (b bool, i int, u uint, f float) + bytes.
% Supported: b1, i1, u1, i2, u2, i4, u4, i8, u8, f4, f8; arrays of any
% rank (returned in MATLAB column-major order with the numpy shape).
% Not supported: structured / object / string / complex dtypes, which
% raise NeuroAnalyzer:io:npyUnsupported.
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:badMagic.
% Toolboxes: none (base MATLAB; also runs in Octave).
% =========================================================================

function x = readNPY(file)
    if ~(exist(file, 'file') == 2)
        error('NeuroAnalyzer:io:fileNotFound', 'NPY file not found: %s', file);
    end
    fid = fopen(file, 'r', 'ieee-le');
    if fid < 0
        error('NeuroAnalyzer:io:fileNotFound', 'Cannot open NPY file: %s', file);
    end
    c = onCleanup(@() fclose(fid));

    magic = fread(fid, 6, 'uint8=>uint8')';
    if numel(magic) < 6 || ~isequal(magic, uint8([147 double('NUMPY')]))
        error('NeuroAnalyzer:io:badMagic', ...
            'Not a NumPy .npy file (missing \\x93NUMPY magic string): %s', file);
    end
    ver = fread(fid, 2, 'uint8=>double')';
    if ver(1) == 1
        hlen = fread(fid, 1, 'uint16=>double');
    elseif ver(1) == 2 || ver(1) == 3
        hlen = fread(fid, 1, 'uint32=>double');
    else
        error('NeuroAnalyzer:io:npyUnsupported', 'Unsupported .npy format version %d.%d in %s', ...
            ver(1), ver(2), file);
    end
    header = fread(fid, hlen, 'uint8=>char')';

    tok = regexp(header, '''descr''\s*:\s*''([<>|=]?)([biuf])(\d+)''', 'tokens', 'once');
    if isempty(tok)
        error('NeuroAnalyzer:io:npyUnsupported', ...
            'Unsupported .npy dtype in %s (header: %s)', file, strtrim(header));
    end
    fortranOrder = ~isempty(regexp(header, '''fortran_order''\s*:\s*True', 'once'));
    shp = regexp(header, '''shape''\s*:\s*\(([^)]*)\)', 'tokens', 'once');
    if isempty(shp)
        error('NeuroAnalyzer:io:npyUnsupported', 'No shape in .npy header of %s', file);
    end
    dims = str2double(regexp(shp{1}, '\d+', 'match'));

    [prec, cls] = npyPrecision(tok{2}, str2double(tok{3}), file);
    if strcmp(tok{1}, '>')
        % Re-open big-endian at the data offset
        pos = ftell(fid);
        clear c;
        fid = fopen(file, 'r', 'ieee-be');
        c = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fseek(fid, pos, 'bof');
    end

    n = prod(dims);                     % prod([]) = 1 for a 0-d scalar
    if strcmp(cls, 'logical'), outCls = 'uint8'; else, outCls = cls; end
    x = fread(fid, n, [prec '=>' outCls]);
    if numel(x) < n
        error('NeuroAnalyzer:io:truncated', '%s holds %d of %d values (truncated file).', ...
            file, numel(x), n);
    end
    if strcmp(cls, 'logical'), x = x ~= 0; end

    if numel(dims) <= 1
        x = x(:);                       % (n,) -> n x 1; () -> scalar
    elseif fortranOrder
        x = reshape(x, dims);
    else
        % C order: last axis varies fastest -> reshape reversed, permute back
        x = permute(reshape(x, fliplr(dims)), numel(dims):-1:1);
    end
end

%% npyPrecision - fread precision and output class for a numpy kind/size
function [prec, cls] = npyPrecision(kind, nbytes, file)
    key = sprintf('%s%d', kind, nbytes);
    switch key
        case 'b1', prec = 'uint8';  cls = 'logical';
        case 'i1', prec = 'int8';   cls = 'int8';
        case 'u1', prec = 'uint8';  cls = 'uint8';
        case 'i2', prec = 'int16';  cls = 'int16';
        case 'u2', prec = 'uint16'; cls = 'uint16';
        case 'i4', prec = 'int32';  cls = 'int32';
        case 'u4', prec = 'uint32'; cls = 'uint32';
        case 'i8', prec = 'int64';  cls = 'int64';
        case 'u8', prec = 'uint64'; cls = 'uint64';
        case 'f4', prec = 'single'; cls = 'single';
        case 'f8', prec = 'double'; cls = 'double';
        otherwise
            error('NeuroAnalyzer:io:npyUnsupported', 'Unsupported .npy dtype ''%s'' in %s', key, file);
    end
end
