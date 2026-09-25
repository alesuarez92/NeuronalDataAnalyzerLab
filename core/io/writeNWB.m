%% writeNWB.m
% =========================================================================
% WRITE NWB - EXPORT PROCESSED EPHYS AS AN NWB 2.x-SHAPED HDF5 FILE
% =========================================================================
% out = writeNWB(file, results)
% out = writeNWB(file, results, 'Engine', engine, 'DryRun', tf)
%
% Writes processed LFP (and optionally raw data, a stimulus trace, trial
% times and spike times) as a Neurodata Without Borders 2.x file.
%   Engine 'auto' (default): matnwb (NwbFile / nwbExport) when it is on the
%          path, otherwise the built-in minimal writer. If the matnwb export
%          fails, a warning is issued and the minimal writer is used.
%   Engine 'matnwb' / 'minimal': force one writer.
%   DryRun true: return the minimal writer's planned HDF5 layout in
%          out.layout without writing anything.
%
% results (struct; every field optional except one of raw / lfp):
%   .lfp   struct: data (channels x samples, volts), fs (Hz), channels
%          (electrode ids, default 1:n), description, filtering (text),
%          startTime (s, default 0) -> /processing/ecephys/LFP/ElectricalSeries
%   .raw   same fields (+ conversion: volts per stored unit, for integer
%          data) -> /acquisition/ElectricalSeries
%   .stim  struct: data (channels x samples), fs, name (default
%          'stimulus'), unit (default 'a.u.'), description, startTime
%          -> /stimulus/presentation/<name> (TimeSeries)
%   .trials struct: start, stop (s) -> /intervals/trials (TimeIntervals)
%   .units struct array: spikeTimes (s) -> /units (Units: spike_times +
%          spike_times_index)
%   .unitsResolution  smallest spike-time difference (s), e.g. 1/fs
%   .electrodes struct: location (default 'unknown'), groupName
%          ('shank0'), groupDescription, device ('recording_device'),
%          deviceDescription, manufacturer, names (cellstr per id)
%   .subject struct: subject_id, species, sex, age (ISO 8601 duration,
%          e.g. 'P90D'), description -> /general/subject (only if given)
%   .sessionDescription, .identifier (default: random UUID),
%   .sessionStartTime (datetime or ISO 8601 text; default: now),
%   .experimenter, .lab, .institution, .experimentDescription, .source
%   (text: where the data came from, stored in /general/data_collection),
%   .notes
% out: struct file, engine ('matnwb' | 'minimal'), nwbVersion, identifier,
%   validated (always false: nothing here runs the NWB validator), notes,
%   layout (DryRun only).
%
% Minimal writer (MATLAB low-level HDF5 API: H5F, H5G, H5D, H5A, H5T,
% H5S, H5R, H5L): builds the groups, datasets and attributes of the NWB
% 2.x core schema for the objects above: root attributes nwb_version,
% neurodata_type 'NWBFile', namespace 'core', object_id; root datasets
% identifier, session_description, session_start_time,
% timestamps_reference_time, file_create_date; groups acquisition,
% analysis, processing, stimulus/presentation, stimulus/templates,
% general, general/devices, general/extracellular_ephys (+ electrodes
% DynamicTable with id, location, group (object references), group_name,
% label), intervals, units. Text is written as variable-length UTF-8,
% electrode groups link to their Device with an HDF5 soft link, and
% DynamicTableRegion / VectorIndex use object-reference attributes.
% ElectricalSeries data are written time x channels (HDF5 order), with
% starting_time + rate, unit 'volts', conversion, offset and resolution.
% Not written: the cached schema (/specifications), compression /
% chunking, electrode x/y/z/impedance, units' electrodes/waveforms.
% This layout was checked against pynwb's validator via a Python mirror
% during development; the MATLAB file
% itself is not validated at run time, so the UI calls it an "NWB-style
% export (not validated)". References: NWB 2.x format specification
% (nwb-schema.readthedocs.io); Rübel O. et al. (2022) The Neurodata
% Without Borders ecosystem for neurophysiological data science. eLife
% 11:e78362.
% Errors: NeuroAnalyzer:io:writeFailed, NeuroAnalyzer:io:badInput.
% Toolboxes: none (MATLAB HDF5 low-level API; matnwb optional).
% =========================================================================

function out = writeNWB(file, results, varargin)
    o = struct('Engine', 'auto', 'DryRun', false);
    for k = 1:2:numel(varargin)
        o.(varargin{k}) = varargin{k+1};
    end
    r = normalizeResults(results);
    out = struct('file', file, 'engine', 'minimal', 'nwbVersion', nwbVersion(), ...
        'identifier', r.identifier, 'validated', false, 'notes', '', 'layout', []);

    engine = lower(o.Engine);
    if strcmp(engine, 'auto')
        if hasMatnwb() && ~o.DryRun, engine = 'matnwb'; else, engine = 'minimal'; end
    end
    if strcmp(engine, 'matnwb')
        if ~hasMatnwb()
            error('NeuroAnalyzer:io:writeFailed', 'matnwb (NwbFile, nwbExport) is not on the MATLAB path.');
        end
        try
            writeWithMatnwb(file, r);
            out.engine = 'matnwb';
            out.nwbVersion = matnwbVersion();
            out.notes = 'Written with matnwb (schema objects built by matnwb; not validated here).';
            return;
        catch ME
            warning('NeuroAnalyzer:io:matnwbFailed', ...
                'matnwb export failed (%s); using the built-in minimal NWB writer instead.', ME.message);
            engine = 'minimal';
        end
    end

    L = buildLayout(r);
    out.notes = ['NWB-style export (not validated): minimal built-in writer, NWB ' nwbVersion() ...
        ' core layout without the cached schema.'];
    if o.DryRun
        out.layout = L;
        return;
    end
    commitLayout(file, L);
end

%% nwbVersion - NWB schema version whose layout the minimal writer follows
function v = nwbVersion()
    v = '2.7.0';
end

%% ------------------------------------------------------------------------
%% normalizeResults - Defaults and validation of the results struct
function r = normalizeResults(r)
    if ~isstruct(r) || ~(isfield(r, 'lfp') || isfield(r, 'raw'))
        error('NeuroAnalyzer:io:badInput', 'writeNWB: results needs an .lfp or .raw field.');
    end
    d = struct('sessionDescription', 'Extracellular recording processed with NeuroAnalyzer', ...
        'identifier', newUUID(), 'sessionStartTime', [], 'experimenter', '', 'lab', '', ...
        'institution', '', 'experimentDescription', '', 'source', '', 'notes', '', ...
        'electrodes', struct(), 'subject', [], 'unitsResolution', []);
    f = fieldnames(d);
    for k = 1:numel(f)
        if ~isfield(r, f{k}) || isempty(r.(f{k})), r.(f{k}) = d.(f{k}); end
    end
    r.sessionStartTime = isoTime(r.sessionStartTime);
    for s = {'raw', 'lfp'}
        if isfield(r, s{1}) && ~isempty(r.(s{1}))
            x = r.(s{1});
            if ~isfield(x, 'data') || ~isfield(x, 'fs') || isempty(x.data) || ~(x.fs > 0)
                error('NeuroAnalyzer:io:badInput', 'writeNWB: results.%s needs data and fs > 0.', s{1});
            end
            if ~isfield(x, 'channels') || isempty(x.channels), x.channels = 1:size(x.data, 1); end
            if numel(x.channels) ~= size(x.data, 1)
                error('NeuroAnalyzer:io:badInput', 'writeNWB: results.%s.channels must list one id per row.', s{1});
            end
            x = withDefaults(x, struct('description', '', 'filtering', '', 'startTime', 0, 'conversion', 1));
            r.(s{1}) = x;
        else
            r.(s{1}) = [];
        end
    end
    if isfield(r, 'stim') && ~isempty(r.stim)
        r.stim = withDefaults(r.stim, struct('name', 'stimulus', 'unit', 'a.u.', ...
            'description', 'Stimulus trace', 'startTime', 0));
    else
        r.stim = [];
    end
    if ~isfield(r, 'trials'), r.trials = []; end
    if ~isfield(r, 'units'), r.units = []; end
    r.electrodes = withDefaults(r.electrodes, struct('location', 'unknown', 'groupName', 'shank0', ...
        'groupDescription', 'Recording electrodes', 'device', 'recording_device', ...
        'deviceDescription', 'Acquisition system', 'manufacturer', '', 'names', {{}}));
end

%% ------------------------------------------------------------------------
%% buildLayout - The HDF5 objects of the file, as a cell array of nodes
% node: type ('group'|'dataset'|'link'), path, data, dtype ('double',
% 'single', integer classes, 'text', 'ref'), dims (HDF5 / C order, []
% = scalar), attrs (struct array name/value/dtype), target (links).
% Data are stored MATLAB-style, i.e. an HDF5 (time, channel) dataset is
% a channels x time MATLAB array.
function L = buildLayout(r)
    L = {};
    created = isoTime([]);
    L{end+1} = grp('/', 'NWBFile', 'core', attr('nwb_version', nwbVersion(), 'text'));
    L{end+1} = txt('/identifier', r.identifier);
    L{end+1} = txt('/session_description', r.sessionDescription);
    L{end+1} = txt('/session_start_time', r.sessionStartTime);
    L{end+1} = txt('/timestamps_reference_time', r.sessionStartTime);
    L{end+1} = dset('/file_create_date', {created}, 'text', 1);
    for g = {'/acquisition', '/analysis', '/processing', '/stimulus', '/stimulus/presentation', ...
            '/stimulus/templates', '/general', '/general/devices'}
        L{end+1} = grp(g{1}); %#ok<AGROW>
    end
    note = 'NWB-style export written by NeuroAnalyzer writeNWB (minimal writer, not validated).';
    if ~isempty(r.notes), note = [r.notes ' ' note]; end
    L{end+1} = txt('/general/notes', note);
    if ~isempty(r.source), L{end+1} = txt('/general/data_collection', r.source); end
    if ~isempty(r.lab), L{end+1} = txt('/general/lab', r.lab); end
    if ~isempty(r.institution), L{end+1} = txt('/general/institution', r.institution); end
    if ~isempty(r.experimentDescription)
        L{end+1} = txt('/general/experiment_description', r.experimentDescription);
    end
    if ~isempty(r.subject)
        L{end+1} = grp('/general/subject', 'Subject', 'core');
        for f = {'subject_id', 'species', 'sex', 'age', 'description'}
            if isfield(r.subject, f{1}) && ~isempty(r.subject.(f{1}))
                L{end+1} = txt(['/general/subject/' f{1}], r.subject.(f{1})); %#ok<AGROW>
            end
        end
    end
    if ~isempty(r.experimenter)
        ex = cellstr(r.experimenter);
        L{end+1} = dset('/general/experimenter', ex(:), 'text', numel(ex));
    end

    % ---- Electrodes: device, one electrode group, electrodes table ----
    E = r.electrodes;
    ids = [];
    if ~isempty(r.raw), ids = [ids, r.raw.channels(:)']; end
    if ~isempty(r.lfp), ids = [ids, r.lfp.channels(:)']; end
    ids = unique(ids);
    n = numel(ids);
    devPath = ['/general/devices/' E.device];
    grpPath = ['/general/extracellular_ephys/' E.groupName];
    tblPath = '/general/extracellular_ephys/electrodes';
    devAttrs = attr('description', E.deviceDescription, 'text');
    if ~isempty(E.manufacturer), devAttrs = [devAttrs, attr('manufacturer', E.manufacturer, 'text')]; end
    L{end+1} = grp(devPath, 'Device', 'core', devAttrs);
    L{end+1} = grp('/general/extracellular_ephys');
    L{end+1} = grp(grpPath, 'ElectrodeGroup', 'core', [attr('description', E.groupDescription, 'text'), ...
        attr('location', E.location, 'text')]);
    L{end+1} = struct('type', 'link', 'path', [grpPath '/device'], 'data', [], 'dtype', '', ...
        'dims', [], 'attrs', noAttrs(), 'target', devPath);
    labels = arrayfun(@(c) sprintf('ch%d', c), ids, 'UniformOutput', false);
    if numel(E.names) == n, labels = E.names(:)'; end
    cols = {'location', 'group', 'group_name', 'label'};
    L{end+1} = grp(tblPath, 'DynamicTable', 'hdmf-common', [attr('colnames', cols, 'text[]'), ...
        attr('description', 'Electrodes used in this file', 'text')]);
    L{end+1} = typed(dset([tblPath '/id'], int64(ids(:)), 'int64', n), 'ElementIdentifiers', 'hdmf-common');
    L{end+1} = column([tblPath '/location'], repmat({E.location}, n, 1), 'text', 'Brain location of the electrode');
    L{end+1} = column([tblPath '/group'], repmat({grpPath}, n, 1), 'ref', 'Electrode group (object reference)');
    L{end+1} = column([tblPath '/group_name'], repmat({E.groupName}, n, 1), 'text', 'Name of the electrode group');
    L{end+1} = column([tblPath '/label'], labels(:), 'text', 'Channel label in the source recording');

    % ---- Raw (acquisition) and LFP (processing/ecephys/LFP) ----
    if ~isempty(r.raw)
        L = [L, series('/acquisition/ElectricalSeries', r.raw, ids, tblPath, ...
            defaultText(r.raw.description, 'Raw extracellular recording'))];
    end
    if ~isempty(r.lfp)
        L{end+1} = grp('/processing/ecephys', 'ProcessingModule', 'core', ...
            attr('description', 'Processed extracellular electrophysiology', 'text'));
        L{end+1} = grp('/processing/ecephys/LFP', 'LFP', 'core');
        L = [L, series('/processing/ecephys/LFP/ElectricalSeries', r.lfp, ids, tblPath, ...
            defaultText(r.lfp.description, 'Local field potential'))];
    end

    % ---- Stimulus TimeSeries ----
    if ~isempty(r.stim)
        s = r.stim;
        p = ['/stimulus/presentation/' regexprep(s.name, '[^\w-]', '_')];
        L{end+1} = grp(p, 'TimeSeries', 'core', [attr('description', s.description, 'text'), ...
            attr('comments', 'no comments', 'text')]);
        L{end+1} = dataNode([p '/data'], s.data, s.unit, 1);
        L{end+1} = startNode([p '/starting_time'], s.startTime, s.fs);
    end

    % ---- Trials ----
    if ~isempty(r.trials)
        t0 = r.trials.start(:); t1 = r.trials.stop(:);
        m = numel(t0);
        L{end+1} = grp('/intervals');
        L{end+1} = grp('/intervals/trials', 'TimeIntervals', 'core', ...
            [attr('colnames', {'start_time', 'stop_time'}, 'text[]'), ...
            attr('description', 'Stimulus trials', 'text')]);
        L{end+1} = typed(dset('/intervals/trials/id', int64((0:m-1)'), 'int64', m), 'ElementIdentifiers', 'hdmf-common');
        L{end+1} = column('/intervals/trials/start_time', double(t0), 'double', 'Start time of the trial (s)');
        L{end+1} = column('/intervals/trials/stop_time', double(t1), 'double', 'Stop time of the trial (s)');
    end

    % ---- Units (spike times) ----
    if ~isempty(r.units)
        u = r.units;
        nu = numel(u);
        st = cell(1, nu);
        for k = 1:nu, st{k} = double(u(k).spikeTimes(:)); end
        idx = cumsum(cellfun(@numel, st));
        L{end+1} = grp('/units', 'Units', 'core', [attr('colnames', {'spike_times'}, 'text[]'), ...
            attr('description', 'Sorted units', 'text')]);
        L{end+1} = typed(dset('/units/id', int64((0:nu-1)'), 'int64', nu), 'ElementIdentifiers', 'hdmf-common');
        allT = vertcat(st{:});
        if isempty(allT), allT = zeros(0, 1); end
        stNode = column('/units/spike_times', allT, 'double', 'Spike times of each unit (s)');
        if ~isempty(r.unitsResolution)
            stNode.attrs = [stNode.attrs, attr('resolution', double(r.unitsResolution), 'double')];
        end
        L{end+1} = stNode;
        vi = typed(dset('/units/spike_times_index', uint64(idx(:)), 'uint64', nu), 'VectorIndex', 'hdmf-common');
        vi.attrs = [vi.attrs, attr('description', 'Index into spike_times', 'text'), ...
            attr('target', '/units/spike_times', 'ref')];
        L{end+1} = vi;
    end
end

%% series - ElectricalSeries group + data / starting_time / electrodes nodes
function N = series(p, x, ids, tblPath, desc)
    [~, rows] = ismember(x.channels(:)', ids);
    attrs = [attr('description', desc, 'text'), attr('comments', 'no comments', 'text')];
    if ~isempty(x.filtering), attrs = [attrs, attr('filtering', x.filtering, 'text')]; end
    N = {grp(p, 'ElectricalSeries', 'core', attrs)};
    N{end+1} = dataNode([p '/data'], x.data, 'volts', x.conversion);
    N{end+1} = startNode([p '/starting_time'], x.startTime, x.fs);
    region = typed(dset([p '/electrodes'], int64(rows(:) - 1), 'int64', numel(rows)), ...
        'DynamicTableRegion', 'hdmf-common');
    region.attrs = [region.attrs, attr('description', 'Electrodes of this series', 'text'), ...
        attr('table', tblPath, 'ref')];
    N{end+1} = region;
end

%% dataNode - TimeSeries data: channels x samples -> HDF5 (time) or (time, channel)
function n = dataNode(p, x, unit, conversion)
    cls = class(x);
    if islogical(x), x = uint8(x); cls = 'uint8'; end
    if size(x, 1) == 1
        n = dset(p, x(:), cls, numel(x));
    else
        n = dset(p, x, cls, [size(x, 2) size(x, 1)]);
    end
    n.attrs = [attr('unit', unit, 'text'), attr('conversion', double(conversion), 'double'), ...
        attr('offset', 0, 'double'), attr('resolution', -1, 'double')];
end

%% startNode - starting_time scalar with rate and unit attributes
function n = startNode(p, t0, fs)
    n = dset(p, double(t0), 'double', []);
    n.attrs = [attr('rate', double(fs), 'double'), attr('unit', 'seconds', 'text')];
end

%% column - VectorData column of a DynamicTable
function n = column(p, data, dtype, desc)
    n = typed(dset(p, data, dtype, numel(data)), 'VectorData', 'hdmf-common');
    n.attrs = [n.attrs, attr('description', desc, 'text')];
end

%% grp - Group node, optionally typed (neurodata_type, namespace, object_id)
function n = grp(p, ntype, ns, extra)
    n = struct('type', 'group', 'path', p, 'data', [], 'dtype', '', 'dims', [], ...
        'attrs', noAttrs(), 'target', '');
    if nargin >= 2 && ~isempty(ntype), n = typed(n, ntype, ns); end
    if nargin >= 4, n.attrs = [n.attrs, extra]; end
end

%% dset - Dataset node
function n = dset(p, data, dtype, dims)
    n = struct('type', 'dataset', 'path', p, 'data', {data}, 'dtype', dtype, 'dims', dims, ...
        'attrs', noAttrs(), 'target', '');
end

%% txt - Scalar text dataset
function n = txt(p, s)
    n = dset(p, s, 'text', []);
end

%% typed - Add neurodata_type / namespace / object_id attributes
function n = typed(n, ntype, ns)
    n.attrs = [n.attrs, attr('neurodata_type', ntype, 'text'), attr('namespace', ns, 'text'), ...
        attr('object_id', newUUID(), 'text')];
end

%% attr / noAttrs - Attribute records
function a = attr(name, value, dtype)
    a = struct('name', name, 'value', {value}, 'dtype', dtype);
end
function a = noAttrs()
    a = struct('name', {}, 'value', {}, 'dtype', {});
end

%% ------------------------------------------------------------------------
%% commitLayout - Write the layout with MATLAB's low-level HDF5 API
% Pass 1: groups, datasets and non-reference attributes (parents first).
% Pass 2: soft links and object references (their targets now exist).
function commitLayout(file, L)
    if exist(file, 'file') == 2, delete(file); end
    fid = H5F.create(file, 'H5F_ACC_TRUNC', 'H5P_DEFAULT', 'H5P_DEFAULT');
    c = onCleanup(@() H5F.close(fid));
    for k = 1:numel(L)
        n = L{k};
        switch n.type
            case 'group'
                if strcmp(n.path, '/')
                    id = H5G.open(fid, '/');
                else
                    id = H5G.create(fid, n.path, 'H5P_DEFAULT', 'H5P_DEFAULT', 'H5P_DEFAULT');
                end
                writeAttrs(id, n.attrs, false, fid);
                H5G.close(id);
            case 'dataset'
                if strcmp(n.dtype, 'ref'), continue; end
                id = writeDataset(fid, n);
                writeAttrs(id, n.attrs, false, fid);
                H5D.close(id);
        end
    end
    for k = 1:numel(L)
        n = L{k};
        switch n.type
            case 'link'
                [parent, name] = splitPath(n.path);
                gid = H5G.open(fid, parent);
                H5L.create_soft(n.target, gid, name, 'H5P_DEFAULT', 'H5P_DEFAULT');
                H5G.close(gid);
            case 'dataset'
                if strcmp(n.dtype, 'ref')
                    id = writeDataset(fid, n);
                    writeAttrs(id, n.attrs, false, fid);
                    writeAttrs(id, n.attrs, true, fid);
                    H5D.close(id);
                elseif any(strcmp({n.attrs.dtype}, 'ref'))
                    id = H5D.open(fid, n.path);
                    writeAttrs(id, n.attrs, true, fid);
                    H5D.close(id);
                end
            case 'group'
                if any(strcmp({n.attrs.dtype}, 'ref'))
                    id = H5G.open(fid, n.path);
                    writeAttrs(id, n.attrs, true, fid);
                    H5G.close(id);
                end
        end
    end
end

%% writeDataset - Create and write one dataset; returns its open id
function id = writeDataset(fid, n)
    if isempty(n.dims)
        space = H5S.create('H5S_SCALAR');
    else
        space = H5S.create_simple(numel(n.dims), n.dims, []);
    end
    switch n.dtype
        case 'text'
            t = vlenText();
            id = H5D.create(fid, n.path, t, space, 'H5P_DEFAULT');
            H5D.write(id, t, 'H5S_ALL', 'H5S_ALL', 'H5P_DEFAULT', cellstr(n.data));
            H5T.close(t);
        case 'ref'
            refs = objectRefs(fid, cellstr(n.data));
            id = H5D.create(fid, n.path, 'H5T_STD_REF_OBJ', space, 'H5P_DEFAULT');
            H5D.write(id, 'H5T_STD_REF_OBJ', 'H5S_ALL', 'H5S_ALL', 'H5P_DEFAULT', refs);
        otherwise
            t = fileType(n.dtype);
            id = H5D.create(fid, n.path, t, space, 'H5P_DEFAULT');
            if ~isempty(n.data)
                H5D.write(id, 'H5ML_DEFAULT', 'H5S_ALL', 'H5S_ALL', 'H5P_DEFAULT', cast(n.data, n.dtype));
            end
    end
    H5S.close(space);
end

%% writeAttrs - Write the reference (refs = true) or the other attributes of an object
function writeAttrs(id, attrs, refs, fid)
    for k = 1:numel(attrs)
        a = attrs(k);
        if strcmp(a.dtype, 'ref') ~= refs, continue; end
        switch a.dtype
            case 'text'
                t = vlenText();
                space = H5S.create('H5S_SCALAR');
                aid = H5A.create(id, a.name, t, space, 'H5P_DEFAULT');
                H5A.write(aid, t, {a.value});
                H5T.close(t);
            case 'text[]'
                t = vlenText();
                v = cellstr(a.value);
                space = H5S.create_simple(1, numel(v), []);
                aid = H5A.create(id, a.name, t, space, 'H5P_DEFAULT');
                H5A.write(aid, t, v(:));
                H5T.close(t);
            case 'ref'
                space = H5S.create('H5S_SCALAR');
                aid = H5A.create(id, a.name, 'H5T_STD_REF_OBJ', space, 'H5P_DEFAULT');
                H5A.write(aid, 'H5T_STD_REF_OBJ', objectRefs(fid, {a.value}));
            otherwise
                space = H5S.create('H5S_SCALAR');
                aid = H5A.create(id, a.name, fileType(a.dtype), space, 'H5P_DEFAULT');
                H5A.write(aid, 'H5ML_DEFAULT', cast(a.value, a.dtype));
        end
        H5A.close(aid);
        H5S.close(space);
    end
end

%% vlenText - Variable-length UTF-8 string type
function t = vlenText()
    t = H5T.copy('H5T_C_S1');
    H5T.set_size(t, 'H5T_VARIABLE');
    H5T.set_cset(t, H5ML.get_constant_value('H5T_CSET_UTF8'));
end

%% objectRefs - 8-byte object references (uint8, 8 x n) to the given paths
function refs = objectRefs(fid, paths)
    refs = zeros(8, numel(paths), 'uint8');
    for k = 1:numel(paths)
        refs(:, k) = H5R.create(fid, paths{k}, 'H5R_OBJECT', -1);
    end
end

%% fileType - Little-endian HDF5 file type for a MATLAB class
function t = fileType(cls)
    switch cls
        case 'double', t = 'H5T_IEEE_F64LE';
        case 'single', t = 'H5T_IEEE_F32LE';
        case 'int8',   t = 'H5T_STD_I8LE';
        case 'uint8',  t = 'H5T_STD_U8LE';
        case 'int16',  t = 'H5T_STD_I16LE';
        case 'uint16', t = 'H5T_STD_U16LE';
        case 'int32',  t = 'H5T_STD_I32LE';
        case 'uint32', t = 'H5T_STD_U32LE';
        case 'int64',  t = 'H5T_STD_I64LE';
        case 'uint64', t = 'H5T_STD_U64LE';
        otherwise
            error('NeuroAnalyzer:io:writeFailed', 'writeNWB: unsupported data class %s', cls);
    end
end

%% splitPath - '/a/b/c' -> '/a/b', 'c'
function [parent, name] = splitPath(p)
    i = find(p == '/', 1, 'last');
    parent = p(1:i-1);
    if isempty(parent), parent = '/'; end
    name = p(i+1:end);
end

%% ------------------------------------------------------------------------
%% hasMatnwb - matnwb's NwbFile class and nwbExport on the path
function tf = hasMatnwb()
    tf = ~isempty(which('NwbFile')) && ~isempty(which('nwbExport'));
end

%% matnwbVersion - Schema version matnwb writes (best effort)
function v = matnwbVersion()
    v = 'matnwb';
    try
        v = char(util.getSchemaVersion()); %#ok<*NASGU>
    catch
    end
end

%% writeWithMatnwb - Same content through matnwb (NwbFile, types.core.*, nwbExport)
function writeWithMatnwb(file, r)
    t0 = datetime(r.sessionStartTime, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSSxxx', ...
        'TimeZone', 'local');
    nwb = NwbFile('session_description', r.sessionDescription, 'identifier', r.identifier, ...
        'session_start_time', t0, 'timestamps_reference_time', t0, ...
        'general_notes', 'Written by NeuroAnalyzer writeNWB via matnwb.');
    if ~isempty(r.source), nwb.general_data_collection = r.source; end
    E = r.electrodes;
    dev = types.core.Device('description', E.deviceDescription);
    nwb.general_devices.set(E.device, dev);
    eg = types.core.ElectrodeGroup('description', E.groupDescription, 'location', E.location, ...
        'device', types.untyped.SoftLink(dev));
    nwb.general_extracellular_ephys.set(E.groupName, eg);
    ids = [];
    if ~isempty(r.raw), ids = [ids, r.raw.channels(:)']; end
    if ~isempty(r.lfp), ids = [ids, r.lfp.channels(:)']; end
    ids = unique(ids);
    n = numel(ids);
    tbl = types.hdmf_common.DynamicTable('colnames', {'location', 'group', 'group_name'}, ...
        'description', 'Electrodes used in this file', ...
        'id', types.hdmf_common.ElementIdentifiers('data', int64(ids(:))), ...
        'location', types.hdmf_common.VectorData('data', repmat({E.location}, n, 1), ...
            'description', 'Brain location of the electrode'), ...
        'group', types.hdmf_common.VectorData('data', repmat(types.untyped.ObjectView(eg), n, 1), ...
            'description', 'Electrode group'), ...
        'group_name', types.hdmf_common.VectorData('data', repmat({E.groupName}, n, 1), ...
            'description', 'Name of the electrode group'));
    nwb.general_extracellular_ephys_electrodes = tbl;
    mk = @(x, desc) types.core.ElectricalSeries( ...
        'electrodes', types.hdmf_common.DynamicTableRegion('table', types.untyped.ObjectView(tbl), ...
            'description', 'Electrodes of this series', 'data', int64(indexOf(x.channels, ids) - 1)), ...
        'data', x.data, 'data_unit', 'volts', 'data_conversion', double(x.conversion), ...
        'starting_time', double(x.startTime), 'starting_time_rate', double(x.fs), ...
        'description', desc, 'filtering', x.filtering);
    if ~isempty(r.raw)
        nwb.acquisition.set('ElectricalSeries', mk(r.raw, defaultText(r.raw.description, 'Raw extracellular recording')));
    end
    if ~isempty(r.lfp)
        lfp = types.core.LFP('ElectricalSeries', mk(r.lfp, defaultText(r.lfp.description, 'Local field potential')));
        mod = types.core.ProcessingModule('description', 'Processed extracellular electrophysiology');
        mod.nwbdatainterface.set('LFP', lfp);
        nwb.processing.set('ecephys', mod);
    end
    if ~isempty(r.stim)
        s = r.stim;
        ts = types.core.TimeSeries('data', s.data, 'data_unit', s.unit, 'description', s.description, ...
            'starting_time', double(s.startTime), 'starting_time_rate', double(s.fs));
        nwb.stimulus_presentation.set(regexprep(s.name, '[^\w-]', '_'), ts);
    end
    if ~isempty(r.trials)
        trials = types.core.TimeIntervals('colnames', {'start_time', 'stop_time'}, ...
            'description', 'Stimulus trials', ...
            'id', types.hdmf_common.ElementIdentifiers('data', int64(0:numel(r.trials.start) - 1)'), ...
            'start_time', types.hdmf_common.VectorData('data', double(r.trials.start(:)), ...
                'description', 'Start time of the trial (s)'), ...
            'stop_time', types.hdmf_common.VectorData('data', double(r.trials.stop(:)), ...
                'description', 'Stop time of the trial (s)'));
        nwb.intervals_trials = trials;
    end
    if ~isempty(r.units)
        st = arrayfun(@(u) double(u.spikeTimes(:)), r.units, 'UniformOutput', false);
        [data, idx] = util.create_indexed_column(st);
        nwb.units = types.core.Units('colnames', {'spike_times'}, 'description', 'Sorted units', ...
            'id', types.hdmf_common.ElementIdentifiers('data', int64(0:numel(st) - 1)'), ...
            'spike_times', data, 'spike_times_index', idx);
    end
    if exist(file, 'file') == 2, delete(file); end
    nwbExport(nwb, file);
end

%% indexOf - Position of each id in ids
function k = indexOf(x, ids)
    [~, k] = ismember(x(:)', ids);
end

%% ------------------------------------------------------------------------
%% isoTime - ISO 8601 text with UTC offset (default: now)
function s = isoTime(t)
    if ischar(t) && ~isempty(t)
        s = t;
        return;
    end
    try
        if isempty(t), t = datetime('now', 'TimeZone', 'local'); end
        if isempty(t.TimeZone), t.TimeZone = 'local'; end
        t.Format = 'yyyy-MM-dd''T''HH:mm:ss.SSSxxx';
        s = char(t);
    catch
        % No datetime (e.g. Octave): assume the clock is UTC
        s = [datestr(now, 'yyyy-mm-ddTHH:MM:SS.FFF') '+00:00']; %#ok<TNOW1,DATST>
    end
end

%% newUUID - Random (version 4) UUID text
function u = newUUID()
    persistent rs
    try
        u = char(java.util.UUID.randomUUID());
        return;
    catch
    end
    % No JVM: one clock-seeded stream per session, so successive ids differ
    if isempty(rs)
        try
            rs = RandStream('mt19937ar', 'Seed', 'shuffle');
        catch
            rs = 0;
        end
    end
    if isobject(rs)
        b = randi(rs, [0 255], 1, 16);
    else
        b = floor(rand(1, 16) * 256);
    end
    b(7) = bitor(bitand(b(7), 15), 64);      % version 4
    b(9) = bitor(bitand(b(9), 63), 128);     % RFC 4122 variant
    h = lower(reshape(dec2hex(b, 2)', 1, []));
    u = [h(1:8) '-' h(9:12) '-' h(13:16) '-' h(17:20) '-' h(21:32)];
end

%% withDefaults - Fill missing fields
function s = withDefaults(s, d)
    if isempty(s), s = struct(); end
    f = fieldnames(d);
    for k = 1:numel(f)
        if ~isfield(s, f{k}) || isempty(s.(f{k}))
            s.(f{k}) = d.(f{k});
        end
    end
end

%% defaultText - s, or d when s is empty
function s = defaultText(s, d)
    if isempty(s), s = d; end
end
