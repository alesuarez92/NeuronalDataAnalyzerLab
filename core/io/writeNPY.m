%% writeNPY.m
% =========================================================================
% WRITE NPY - MINIMAL WRITER FOR NUMPY .npy ARRAY FILES
% =========================================================================
% writeNPY(file, x)
%
% Writes a numeric or logical array as a NumPy .npy file (format version
% 1.0, little-endian, C order), readable by numpy.load and readNPY. Used
% to build Open Ephys binary folders for the synthetic demo / tests.
%
% Inputs:
%   file - output path (.npy)
%   x    - numeric or logical array. Vectors are written as 1-D arrays of
%          shape (n,); matrices / N-D arrays keep their shape.
%          Class sets the dtype: double <f8, single <f4, int64 <i8,
%          uint64 <u8, int32 <i4, uint32 <u4, int16 <i2, uint16 <u2,
%          int8 |i1, uint8 |u1, logical |b1.
%
% Method (NumPy "npy" format specification, version 1.0): magic
% \x93NUMPY, bytes 1 and 0 (version), uint16 header length, then the
% Python dict header padded with spaces and ending in '\n' so that the
% data start on a 64-byte boundary, then the raw little-endian data.
% Toolboxes: none (base MATLAB; also runs in Octave).
% =========================================================================

function writeNPY(file, x)
    switch class(x)
        case 'double',  descr = '<f8'; prec = 'double';
        case 'single',  descr = '<f4'; prec = 'single';
        case 'int64',   descr = '<i8'; prec = 'int64';
        case 'uint64',  descr = '<u8'; prec = 'uint64';
        case 'int32',   descr = '<i4'; prec = 'int32';
        case 'uint32',  descr = '<u4'; prec = 'uint32';
        case 'int16',   descr = '<i2'; prec = 'int16';
        case 'uint16',  descr = '<u2'; prec = 'uint16';
        case 'int8',    descr = '|i1'; prec = 'int8';
        case 'uint8',   descr = '|u1'; prec = 'uint8';
        case 'logical', descr = '|b1'; prec = 'uint8'; x = uint8(x);
        otherwise
            error('NeuroAnalyzer:io:npyUnsupported', 'writeNPY: unsupported class %s', class(x));
    end
    if isvector(x) || isempty(x)
        shape = sprintf('(%d,)', numel(x));
        data = x(:);
    else
        dims = size(x);
        shape = ['(' strjoin(arrayfun(@(d) sprintf('%d', d), dims, 'UniformOutput', false), ', ') ')'];
        data = permute(x, ndims(x):-1:1);   % C order: last axis fastest
        data = data(:);
    end
    header = sprintf('{''descr'': ''%s'', ''fortran_order'': False, ''shape'': %s, }', descr, shape);
    total = 10 + numel(header) + 1;             % magic(6) + version(2) + hlen(2) + header + '\n'
    pad = mod(64 - mod(total, 64), 64);
    header = [header repmat(' ', 1, pad) newline];

    fid = fopen(file, 'w', 'ieee-le');
    if fid < 0
        error('NeuroAnalyzer:io:writeFailed', 'Cannot write %s', file);
    end
    c = onCleanup(@() fclose(fid));
    fwrite(fid, [147 double('NUMPY') 1 0], 'uint8');
    fwrite(fid, numel(header), 'uint16');
    fwrite(fid, double(header), 'uint8');
    fwrite(fid, data, prec);
end
