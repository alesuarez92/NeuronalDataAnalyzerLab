function writeMCS(file, data, fs, varargin)
% writeMCS - Write a synthetic Multi Channel Systems HDF5 file for tests and demos.
%
% writeMCS(file, data, fs, Name, Value, ...)
%
% data   electrode channels x samples in volts (Stream_0, 'Electrode',
%        int32, 59.605 nV per step, ADZero 0)
% Options: 'Names' (default E1 ...), 'Aux' (rows in volts: Stream_1,
%          'Auxiliary', uint16-like steps of 152.6 uV around ADZero
%          32768), 'Digital' (one row of 16-bit words: Stream_2,
%          'Digital'), 'Events' struct(label, sample, duration): 1-based
%          samples and durations in samples (EventStream/Stream_0),
%          'StartUs' (time of the first sample, default 0), 'Gap' [after
%          gapSamples]: the samples after sample 'after' start gapSamples
%          later (two rows in ChannelDataTimeStamps)
% Layout as readMCS reads it (and as McsPyDataTools reads it). Needs
% MATLAB's HDF5 functions.
%
[nCh, n] = size(data);
o = struct('Names', {{}}, 'Aux', zeros(0, n), 'Digital', zeros(0, n), ...
    'Events', struct('label', {}, 'sample', {}, 'duration', {}), 'StartUs', 0, 'Gap', []);
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
names = o.Names;
for c = numel(names)+1:nCh, names{c} = sprintf('E%d', c); end
if exist(file, 'file') == 2, delete(file); end
tick = round(1e6 / fs);
if isempty(o.Gap)
    ts = [o.StartUs 0 n - 1];
else
    a = o.Gap(1);
    ts = [o.StartUs 0 a - 1; o.StartUs + (a + o.Gap(2)) * tick a n - 1];
end
rg = '/Data/Recording_0';
streams = {struct('sub', 'Electrode', 'label', 'Filter Data1', 'x', data, 'names', {names}, ...
    'unit', 'V', 'cf', 59605, 'ex', -12, 'zero', 0, 'bits', 24)};
if ~isempty(o.Aux)
    streams{end+1} = struct('sub', 'Auxiliary', 'label', 'Analog Data1', 'x', o.Aux, ...
        'names', {arrayfun(@(k) sprintf('A%d', k), 1:size(o.Aux, 1), 'UniformOutput', false)}, ...
        'unit', 'V', 'cf', 1526, 'ex', -7, 'zero', 32768, 'bits', 16);
end
if ~isempty(o.Digital)
    streams{end+1} = struct('sub', 'Digital', 'label', 'Digital Data1', 'x', o.Digital, 'names', {{'D1'}}, ...
        'unit', 'NoUnit', 'cf', 1, 'ex', 0, 'zero', 0, 'bits', 16);
end
for s = 1:numel(streams)
    S = streams{s};
    g = sprintf('%s/AnalogStream/Stream_%d', rg, s - 1);
    q = round(S.x / (S.cf * 10^S.ex)) + S.zero;
    m = size(q, 1);
    h5create(file, [g '/ChannelData'], [n m], 'Datatype', 'int32');
    h5write(file, [g '/ChannelData'], int32(q'));
    h5create(file, [g '/ChannelDataTimeStamps'], [3 size(ts, 1)], 'Datatype', 'int64');
    h5write(file, [g '/ChannelDataTimeStamps'], int64(ts'));
    z = zeros(m, 1);
    empty = repmat({''}, m, 1);
    compound(file, [g '/InfoChannel'], { ...
        'ChannelID', 'int32', (0:m-1)'; 'RowIndex', 'int32', (0:m-1)'; 'GroupID', 'int32', z; ...
        'ElectrodeGroup', 'int32', z; 'Label', 'str', S.names(:); 'RawDataType', 'str', repmat({'Int'}, m, 1); ...
        'Unit', 'str', repmat({S.unit}, m, 1); 'Exponent', 'int32', S.ex + z; 'ADZero', 'int32', S.zero + z; ...
        'Tick', 'int64', tick + z; 'ConversionFactor', 'int64', S.cf + z; 'ADCBits', 'int32', S.bits + z; ...
        'HighPassFilterType', 'str', empty; 'HighPassFilterCutOffFrequency', 'str', empty; ...
        'HighPassFilterOrder', 'int32', z; 'LowPassFilterType', 'str', empty; ...
        'LowPassFilterCutOffFrequency', 'str', empty; 'LowPassFilterOrder', 'int32', z});
    h5writeatt(file, [g '/InfoChannel'], 'InfoVersion', int32(1));
    streamAttrs(file, g, S.sub, S.label, 'Analog');
end
if ~isempty(o.Events)
    g = [rg '/EventStream/Stream_0'];
    ne = numel(o.Events);
    for k = 1:ne
        e = o.Events(k);
        t = o.StartUs + (e.sample(:) - 1) * tick;
        d = e.duration(:) .* ones(size(t)) * tick;
        ds = sprintf('%s/EventEntity_%d', g, k - 1);
        h5create(file, ds, [numel(t) 2], 'Datatype', 'int64');
        h5write(file, ds, int64([t d]));
    end
    z = zeros(ne, 1);
    compound(file, [g '/InfoEvent'], {'EventID', 'int32', (0:ne-1)'; 'GroupID', 'int32', z; ...
        'Label', 'str', {o.Events.label}'; 'RawDataBytes', 'int32', z; ...
        'SourceChannelIDs', 'str', repmat({''}, ne, 1); 'SourceChannelLabels', 'str', repmat({''}, ne, 1)});
    h5writeatt(file, [g '/InfoEvent'], 'InfoVersion', int32(1));
    streamAttrs(file, g, 'DigitalInput', 'Digital Events1', 'Event');
end
h5writeatt(file, '/', 'McsHdf5ProtocolType', 'RawData');
h5writeatt(file, '/', 'McsHdf5ProtocolVersion', int32(3));
h5writeatt(file, '/Data', 'Date', datestr(now, 'dddd, mmmm dd, yyyy'));
h5writeatt(file, '/Data', 'DateInTicks', int64(0));
h5writeatt(file, '/Data', 'FileGUID', '00000000-0000-0000-0000-000000000001');
h5writeatt(file, '/Data', 'ProgramName', 'NDAL synthetic');
h5writeatt(file, '/Data', 'ProgramVersion', '1');
for a = {'Comment', 'MeaLayout', 'MeaSN', 'MeaName'}, h5writeatt(file, '/Data', a{1}, ' '); end
h5writeatt(file, rg, 'Duration', int64((ts(end, 1) - ts(1, 1)) + (ts(end, 3) - ts(end, 2) + 1) * tick));
h5writeatt(file, rg, 'RecordingID', int32(0));
h5writeatt(file, rg, 'TimeStamp', int64(0));
for a = {'Comment', 'Label', 'RecordingType'}, h5writeatt(file, rg, a{1}, ' '); end
end

function streamAttrs(file, g, sub, label, type)
h5writeatt(file, g, 'StreamInfoVersion', int32(1));
h5writeatt(file, g, 'DataSubType', sub);
h5writeatt(file, g, 'Label', label);
h5writeatt(file, g, 'SourceStreamGUID', '00000000-0000-0000-0000-000000000000');
h5writeatt(file, g, 'StreamGUID', '00000000-0000-0000-0000-000000000002');
h5writeatt(file, g, 'StreamType', type);
end

function compound(file, path, cols)
% One-dimensional compound dataset; cols: {name, 'int32' | 'int64' | 'str', column}
fid = H5F.open(file, 'H5F_ACC_RDWR', 'H5P_DEFAULT');
c = onCleanup(@() H5F.close(fid));
nF = size(cols, 1);
t = cell(1, nF); sz = zeros(1, nF);
for k = 1:nF
    switch cols{k, 2}
        case 'int32', t{k} = H5T.copy('H5T_NATIVE_INT');
        case 'int64', t{k} = H5T.copy('H5T_NATIVE_LLONG');
        otherwise
            t{k} = H5T.copy('H5T_C_S1');
            H5T.set_size(t{k}, 'H5T_VARIABLE');
    end
    sz(k) = H5T.get_size(t{k});
end
off = [0 cumsum(sz(1:end-1))];
tt = H5T.create('H5T_COMPOUND', sum(sz));
w = struct();
for k = 1:nF
    H5T.insert(tt, cols{k, 1}, off(k), t{k});
    v = cols{k, 3};
    switch cols{k, 2}
        case 'int32', v = int32(v);
        case 'int64', v = int64(v);
    end
    w.(cols{k, 1}) = v;
end
n = numel(cols{1, 3});
space = H5S.create_simple(1, n, []);
lcpl = H5P.create('H5P_LINK_CREATE');
H5P.set_create_intermediate_group(lcpl, 1);
ds = H5D.create(fid, path, tt, space, lcpl, 'H5P_DEFAULT', 'H5P_DEFAULT');
H5D.write(ds, tt, 'H5S_ALL', 'H5S_ALL', 'H5P_DEFAULT', w);
H5D.close(ds); H5P.close(lcpl); H5S.close(space); H5T.close(tt);
for k = 1:nF, H5T.close(t{k}); end
end
