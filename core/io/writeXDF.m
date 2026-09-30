function writeXDF(file, streams, varargin)
% writeXDF - Write a synthetic XDF (Lab Streaming Layer) file for tests and demos.
%
% writeXDF(file, streams, Name, Value, ...)
%
% streams  struct array: name, type, fs (nominal rate, 0 = irregular),
%          format ('float32', 'double64', 'int16', 'int32' or 'string'),
%          labels, units (1 x channels cells), timeStamps (1 x samples,
%          s), data (channels x samples; a cell of strings for 'string');
%          optional clockOffsets [collectionTime offset] rows (the file
%          stores time stamps minus the offset, as LSL does)
% Options: 'ChunkSize' (samples per Samples chunk, default 500),
%          'Deduce' (true: only the first sample of each chunk carries a
%          time stamp, the others are deduced from the nominal rate)
% Chunks: FileHeader, StreamHeader per stream, Samples (streams
% interleaved chunk by chunk), ClockOffset, Boundary, StreamFooter.
% Layout as readXDF reads it (and as pyxdf reads it). Base MATLAB only;
% also runs in GNU Octave.
%
o = struct('ChunkSize', 500, 'Deduce', false);
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
fid = fopen(file, 'w', 'ieee-le');
if fid < 0, error('NeuroAnalyzer:io:xdf', 'Cannot write %s', file); end
c = onCleanup(@() fclose(fid));
fwrite(fid, uint8('XDF:'), 'uint8');
chunk(fid, 1, uint8('<?xml version="1.0"?><info><version>1.0</version></info>'));
for k = 1:numel(streams)
    s = streams(k);
    ch = '';
    for j = 1:numel(s.labels)
        u = ''; if numel(s.units) >= j, u = s.units{j}; end
        ch = [ch sprintf('<channel><label>%s</label><unit>%s</unit><type>%s</type></channel>', s.labels{j}, u, s.type)]; %#ok<AGROW>
    end
    xml = sprintf(['<?xml version="1.0"?><info><name>%s</name><type>%s</type><channel_count>%d</channel_count>' ...
        '<nominal_srate>%.10g</nominal_srate><channel_format>%s</channel_format><source_id>ndal-%d</source_id>' ...
        '<created_at>100</created_at><desc><channels>%s</channels></desc></info>'], ...
        s.name, s.type, numel(s.labels), s.fs, s.format, k, ch);
    chunk(fid, 2, [idBytes(k) utf8(xml)]);
end
% Samples, stream after stream within each round of chunks
nS = arrayfun(@(s) numel(s.timeStamps), streams);
for first = 1:o.ChunkSize:max(nS)
    for k = 1:numel(streams)
        s = streams(k);
        i = first:min(nS(k), first + o.ChunkSize - 1);
        if isempty(i), continue; end
        off = 0;
        if isfield(s, 'clockOffsets') && ~isempty(s.clockOffsets)
            b = [s.clockOffsets(:, 1) ones(size(s.clockOffsets, 1), 1)] \ s.clockOffsets(:, 2);
            if size(s.clockOffsets, 1) == 1, b = [0; s.clockOffsets(1, 2)]; end
        end
        body = [idBytes(k) varlen(numel(i))];
        parts = cell(1, numel(i));
        for j = 1:numel(i)
            t = s.timeStamps(i(j));
            if isfield(s, 'clockOffsets') && ~isempty(s.clockOffsets), off = b(1) * t + b(2); end
            if o.Deduce && j > 1 && s.fs > 0
                st = uint8(0);
            else
                st = [uint8(8) typecast(double(t - off), 'uint8')];
            end
            if strcmp(s.format, 'string')
                v = [];
                for ch = 1:size(s.data, 1)
                    e = utf8(s.data{ch, i(j)});
                    v = [v varlen(numel(e)) e]; %#ok<AGROW>
                end
            else
                v = typecast(cast(s.data(:, i(j))', prec(s.format)), 'uint8');
            end
            parts{j} = [st v];
        end
        chunk(fid, 3, [body parts{:}]);
    end
end
for k = 1:numel(streams)
    s = streams(k);
    if isfield(s, 'clockOffsets')
        for j = 1:size(s.clockOffsets, 1)
            chunk(fid, 4, [idBytes(k) typecast(double(s.clockOffsets(j, :)), 'uint8')]);
        end
    end
end
chunk(fid, 5, uint8([67 175 73 125 197 72 72 76 172 137 234 208 60 55 51 88]));   % boundary UUID
for k = 1:numel(streams)
    s = streams(k);
    ft = sprintf(['<?xml version="1.0"?><info><first_timestamp>%.10g</first_timestamp><last_timestamp>%.10g' ...
        '</last_timestamp><sample_count>%d</sample_count></info>'], s.timeStamps(1), s.timeStamps(end), nS(k));
    chunk(fid, 6, [idBytes(k) utf8(ft)]);
end
end

function chunk(fid, tag, content)
fwrite(fid, [varlen(numel(content) + 2) typecast(uint16(tag), 'uint8') uint8(content)], 'uint8');
end

function b = varlen(n)
if n < 256, b = uint8([1 n]);
elseif n < 2^32, b = [uint8(4) typecast(uint32(n), 'uint8')];
else, b = [uint8(8) typecast(uint64(n), 'uint8')];
end
end

function b = idBytes(k)
b = typecast(uint32(k), 'uint8');
end

function p = prec(fmt)
switch fmt
    case 'float32', p = 'single';
    case 'double64', p = 'double';
    otherwise, p = fmt;
end
end

function b = utf8(s)
try
    b = unicode2native(s, 'UTF-8');
catch
    b = uint8(s);
end
b = uint8(b(:)');
end
