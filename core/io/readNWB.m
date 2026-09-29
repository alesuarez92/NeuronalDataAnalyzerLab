%% readNWB.m
% =========================================================================
% READ NWB - NWB 2.x EXTRACELLULAR RECORDING AS A TDT-LIKE STRUCT
% =========================================================================
% rec = readNWB(file)
% rec = readNWB(file, 'Series', name)
%
% Reads an ElectricalSeries (and any stimulus it can find) from a
% Neurodata Without Borders 2.x file (HDF5) and returns the same struct
% shape as TDTbin2mat, so Extract Ephys can use it unchanged:
%   rec.streams.xRAW.data  channels x samples (single, volts)
%   rec.streams.xRAW.fs    series rate (Hz)
%   rec.streams.Whis.data  candidate stimulus channels on one common grid:
%                          stimulus TimeSeries (/stimulus/presentation and
%                          non-ElectricalSeries TimeSeries in /acquisition,
%                          one row per column) and 0/1 square waves from
%                          TimeIntervals (/intervals/trials, ...) and
%                          IntervalSeries; a zero row if none
%   rec.streams.Whis.fs    rate of the first regular stimulus TimeSeries,
%                          else the series rate
%   rec.info               source ('NWB'), format ('nwb'), file, blockname,
%                          duration, channelNames, electrodeIds,
%                          stimNames, stimKinds, stimOnsets, seriesPath,
%                          seriesPaths (all ElectricalSeries found),
%                          nwbVersion, identifier, sessionDescription,
%                          sessionStartTime, startTime (s), spikeUnits
%                          (struct array with spikeTimes, from /units)
%
% Inputs:
%   file     - .nwb file
%   'Series' - ElectricalSeries name or full path. Default: the first one
%              in /acquisition, else the first in /processing (e.g. an LFP
%              exported by writeNWB).
%
% Method: NWB 2.x layout (format specification, nwb-schema.readthedocs.io;
% Rübel O. et al. (2022) The Neurodata Without Borders ecosystem for
% neurophysiological data science. eLife 11:e78362) read with h5info /
% h5read / h5readatt; objects are recognised by their neurodata_type
% attribute. Series data (HDF5 time x channel; MATLAB returns channel x
% time) x conversion (x channel_conversion) + offset gives volts. Timing
% from starting_time + rate, or from timestamps (rate = 1 / median step,
% with a warning when irregular). Stimulus traces are aligned to the
% series' start time and resampled onto the common grid by
% zero-order hold.
% Why not matnwb's nwbRead: it generates class files on first use and is
% not needed to read these datasets; plain HDF5 reads work on any NWB 2.x
% file (including those matnwb writes).
% Limitations: 3-D series (time x channel x sample) are rejected;
% the whole series is loaded into memory; only the first 'data' column
% layout of each stimulus TimeSeries is interpreted (no ImageSeries etc.).
% Errors: NeuroAnalyzer:io:fileNotFound, :notHDF5, :notNWB, :noData.
% Toolboxes: none (MATLAB HDF5 functions).
% =========================================================================

function rec = readNWB(file, varargin)
    seriesSel = '';
    for k = 1:2:numel(varargin)
        if strcmpi(varargin{k}, 'Series'), seriesSel = varargin{k+1}; end
    end
    if ~(exist(file, 'file') == 2)
        error('NeuroAnalyzer:io:fileNotFound', 'NWB file not found: %s', file);
    end
    if ~isHDF5(file)
        error('NeuroAnalyzer:io:notHDF5', '%s is not an HDF5 file, so it cannot be an NWB 2.x file.', file);
    end
    try
        ver = toChar(h5readatt(file, '/', 'nwb_version'));
    catch
        ver = '';
    end
    if isempty(ver)
        error('NeuroAnalyzer:io:notNWB', ['%s is an HDF5 file without the NWB root attribute ' ...
            'nwb_version; it is not an NWB 2.x file.'], file);
    end

    % ---- Find ElectricalSeries ----
    acq = safeInfo(file, '/acquisition');
    proc = safeInfo(file, '/processing');
    esAcq = findTyped(acq, {'ElectricalSeries'});
    esProc = findTyped(proc, {'ElectricalSeries'});
    found = [esAcq, esProc];
    if isempty(found)
        error('NeuroAnalyzer:io:noData', 'No ElectricalSeries in /acquisition or /processing of %s.', file);
    end
    if isempty(seriesSel)
        sp = found{1};
    else
        [~, names] = cellfun(@fileparts, found, 'UniformOutput', false);
        k = find(strcmp(found, seriesSel) | strcmp(names, seriesSel), 1);
        if isempty(k)
            error('NeuroAnalyzer:io:noData', 'No ElectricalSeries ''%s'' in %s (found: %s).', ...
                seriesSel, file, strjoin(found, ', '));
        end
        sp = found{k};
    end

    % ---- Series data, timing, electrodes ----
    sInfo = h5info(file, sp);
    [x, fs, t0] = readTimeSeries(file, sp, sInfo);
    if ndims(x) > 2
        error('NeuroAnalyzer:io:noData', '%s: 3-D ElectricalSeries data are not supported.', sp);
    end
    nCh = size(x, 1);
    nS = size(x, 2);
    [ids, names] = electrodeNames(file, sp, sInfo, nCh);

    % ---- Stimulus candidates ----
    stimSeries = {};
    pres = safeInfo(file, '/stimulus/presentation');
    stimSeries = [stimSeries, findWithData(pres)];
    notStim = {'ElectricalSeries', 'SpikeEventSeries', 'ImageSeries', 'TwoPhotonSeries', ...
        'OnePhotonSeries', 'ImageMaskSeries', 'OpticalSeries'};
    for k = 1:numel(acq.Groups)
        g = acq.Groups(k);
        if hasDataset(g, 'data') && ~any(strcmp(attrOf(g, 'neurodata_type'), notStim))
            stimSeries{end+1} = g.Name; %#ok<AGROW>
        end
    end
    intervals = findTyped(safeInfo(file, '/intervals'), {'TimeIntervals'});

    % Common stimulus grid: rate of the first regular TimeSeries, else the series rate
    fsW = fs;
    for k = 1:numel(stimSeries)
        gi = h5info(file, stimSeries{k});
        if hasDataset(gi, 'starting_time') && ~strcmp(attrOf(gi, 'neurodata_type'), 'IntervalSeries')
            fsW = double(attrOr(dsInfo(gi, 'starting_time'), 'rate', fs));
            break;
        end
    end
    nW = max(1, round(nS / fs * fsW));
    tW = (0:nW - 1) / fsW;                   % relative to the series start t0
    stim = zeros(0, nW, 'single'); stimNames = {}; stimKinds = {}; stimOnsets = {};
    for k = 1:numel(stimSeries)
        p = stimSeries{k};
        gi = h5info(file, p);
        [~, nm] = fileparts(p);
        if strcmp(attrOf(gi, 'neurodata_type'), 'IntervalSeries')
            v = double(h5read(file, [p '/data']));
            ts = double(h5read(file, [p '/timestamps'])) - t0;
            on = ts(v(:) > 0); off = ts(v(:) < 0);
            stim(end+1, :) = EphysSource.eventsToSquare(on * fsW + 1, off * fsW + 1, nW); %#ok<AGROW>
            stimNames{end+1} = nm; stimKinds{end+1} = 'intervals'; stimOnsets{end+1} = on(:)'; %#ok<AGROW>
            continue;
        end
        try
            [y, fsS, t0S, ts] = readTimeSeries(file, p, gi);
        catch
            continue;
        end
        if isempty(ts), ts = t0S + (0:size(y, 2) - 1) / fsS; end
        ts = ts - t0;
        for r = 1:size(y, 1)
            stim(end+1, :) = single(holdResample(ts, double(y(r, :)), tW)); %#ok<AGROW>
            if size(y, 1) > 1, stimNames{end+1} = sprintf('%s [%d]', nm, r); %#ok<AGROW>
            else, stimNames{end+1} = nm; end %#ok<AGROW>
            stimKinds{end+1} = 'timeseries'; stimOnsets{end+1} = []; %#ok<AGROW>
        end
    end
    for k = 1:numel(intervals)
        p = intervals{k};
        gi = h5info(file, p);
        if ~hasDataset(gi, 'start_time'), continue; end
        on = double(h5read(file, [p '/start_time'])) - t0;
        if hasDataset(gi, 'stop_time')
            off = double(h5read(file, [p '/stop_time'])) - t0;
        else
            off = on + 1 / fsW;
        end
        stim(end+1, :) = EphysSource.eventsToSquare(on * fsW + 1, off * fsW + 1, nW); %#ok<AGROW>
        [~, nm] = fileparts(p);
        stimNames{end+1} = sprintf('%s (intervals)', nm); stimKinds{end+1} = 'intervals'; %#ok<AGROW>
        stimOnsets{end+1} = on(:)'; %#ok<AGROW>
    end

    % ---- Metadata ----
    [~, base] = fileparts(file);
    info = struct('source', 'NWB', 'format', 'nwb', 'file', file, 'blockname', base, ...
        'duration', nS / fs, 'channelNames', {names}, 'electrodeIds', ids, ...
        'stimNames', {stimNames}, 'stimKinds', {stimKinds}, 'stimOnsets', {stimOnsets}, ...
        'seriesPath', sp, 'seriesPaths', {found}, 'nwbVersion', ver, ...
        'identifier', readText(file, '/identifier'), ...
        'sessionDescription', readText(file, '/session_description'), ...
        'sessionStartTime', readText(file, '/session_start_time'), 'startTime', t0, ...
        'spikeUnits', readUnits(file));
    if isempty(stim), fsStim = fs; else, fsStim = fsW; end
    rec = EphysSource.makeRecording(x, fs, stim, fsStim, info);
end

%% readTimeSeries - data (channels x samples, scaled), rate, start time, timestamps
function [x, fs, t0, ts] = readTimeSeries(file, p, gi)
    di = dsInfo(gi, 'data');
    x = h5read(file, [p '/data']);
    if islogical(x), x = double(x); end
    if numel(di.Dataspace.Size) <= 1
        x = x(:)';                          % 1-D HDF5 (time,) -> 1 x samples
    end
    conv = double(attrOr(di, 'conversion', 1));
    offs = double(attrOr(di, 'offset', 0));
    x = double(x) * conv;
    if hasDataset(gi, 'channel_conversion')
        cc = double(h5read(file, [p '/channel_conversion']));
        if numel(cc) == size(x, 1), x = bsxfun(@times, x, cc(:)); end
    end
    x = x + offs;
    ts = [];
    if hasDataset(gi, 'starting_time')
        t0 = double(h5read(file, [p '/starting_time']));
        fs = double(attrOr(dsInfo(gi, 'starting_time'), 'rate', NaN));
    elseif hasDataset(gi, 'timestamps')
        ts = double(h5read(file, [p '/timestamps']));
        ts = ts(:)';
        t0 = ts(1);
        d = diff(ts);
        fs = 1 / median(d);
        if numel(d) > 1 && (max(d) - min(d)) > 0.01 / fs
            warning('NeuroAnalyzer:io:irregularTimestamps', ...
                '%s: timestamps are irregular; using the median rate %.4g Hz.', p, fs);
        end
    else
        error('NeuroAnalyzer:io:noData', '%s has neither starting_time nor timestamps.', p);
    end
    if ~(fs > 0)
        error('NeuroAnalyzer:io:noData', '%s: no valid sampling rate.', p);
    end
end

%% holdResample - Values at times ts held until the next sample, sampled at tq
% The last value is held for one median step; 0 before the first and after that.
function y = holdResample(ts, v, tq)
    y = zeros(size(tq));
    if isempty(ts), return; end
    if numel(ts) == 1
        y(abs(tq - ts) < eps(max(1, abs(ts)))) = v;
        return;
    end
    step = median(diff(ts(:)'));
    ts = [ts(:)', ts(end) + step];
    v = [v(:)', v(end)];
    % Tolerance of a millionth of a step so grids that coincide pick the same sample
    y = interp1(ts, v, tq + 1e-6 * step, 'previous', 0);
end

%% electrodeNames - Electrode ids and labels of the series' rows
function [ids, names] = electrodeNames(file, p, gi, nCh)
    ids = 1:nCh;
    names = arrayfun(@(c) sprintf('Ch %d', c), ids, 'UniformOutput', false);
    if ~hasDataset(gi, 'electrodes'), return; end
    try
        rows = double(h5read(file, [p '/electrodes']));
        rows = rows(:)' + 1;
        tbl = '/general/extracellular_ephys/electrodes';
        allIds = double(h5read(file, [tbl '/id']));
        if numel(rows) ~= nCh || any(rows > numel(allIds)), return; end
        ids = allIds(rows)';
        names = arrayfun(@(c) sprintf('e%d', c), ids, 'UniformOutput', false);
        ti = h5info(file, tbl);
        for col = {'label', 'channel_name'}
            if hasDataset(ti, col{1})
                lab = cellstr(toCellText(h5read(file, [tbl '/' col{1}])));
                if numel(lab) >= max(rows), names = lab(rows); names = names(:)'; end
                break;
            end
        end
    catch
        % keep defaults when the electrodes table is missing or unusual
    end
end

%% readUnits - Units table spike times (struct array, empty if absent)
function u = readUnits(file)
    u = struct('spikeTimes', {});
    try
        st = double(h5read(file, '/units/spike_times'));
        idx = double(h5read(file, '/units/spike_times_index'));
    catch
        return;
    end
    st = st(:)'; idx = idx(:)';
    prev = 0;
    for k = 1:numel(idx)
        u(k).spikeTimes = st(prev + 1:idx(k));
        prev = idx(k);
    end
end

%% findTyped - Full paths of groups (recursive) whose neurodata_type is one of types
function out = findTyped(info, types)
    out = {};
    if isempty(info) || ~isfield(info, 'Groups'), return; end
    for k = 1:numel(info.Groups)
        g = info.Groups(k);
        if any(strcmp(attrOf(g, 'neurodata_type'), types))
            out{end+1} = g.Name; %#ok<AGROW>
        end
        out = [out, findTyped(g, types)]; %#ok<AGROW>
    end
end

%% findWithData - Full paths of child groups that hold a 'data' dataset
function out = findWithData(info)
    out = {};
    if isempty(info) || ~isfield(info, 'Groups'), return; end
    for k = 1:numel(info.Groups)
        if hasDataset(info.Groups(k), 'data'), out{end+1} = info.Groups(k).Name; end %#ok<AGROW>
    end
end

%% safeInfo - h5info of a group, [] when it does not exist
function info = safeInfo(file, p)
    try
        info = h5info(file, p);
    catch
        info = struct('Groups', struct('Name', {}), 'Datasets', struct('Name', {}), 'Attributes', []);
    end
end

%% hasDataset / dsInfo - Dataset of a group info by name
function tf = hasDataset(gi, name)
    tf = isfield(gi, 'Datasets') && ~isempty(gi.Datasets) && any(strcmp({gi.Datasets.Name}, name));
end
function di = dsInfo(gi, name)
    di = gi.Datasets(strcmp({gi.Datasets.Name}, name));
end

%% attrOf / attrOr - Attribute value (text as char) from an h5info struct
function v = attrOf(info, name)
    v = toChar(attrOr(info, name, ''));
end
function v = attrOr(info, name, default)
    v = default;
    if ~isfield(info, 'Attributes') || isempty(info.Attributes), return; end
    k = find(strcmp({info.Attributes.Name}, name), 1);
    if ~isempty(k), v = info.Attributes(k).Value; end
end

%% readText - Scalar text dataset as char ('' if missing)
function s = readText(file, p)
    try
        s = toChar(h5read(file, p));
    catch
        s = '';
    end
end

%% toChar - char from char / string / cellstr (first element), nulls trimmed
function s = toChar(v)
    if iscell(v)
        if isempty(v), s = ''; return; end
        v = v{1};
    end
    if isstring(v), v = char(v); end
    if ~ischar(v)
        s = '';
        return;
    end
    s = strtrim(regexprep(v(:)', '\x00+$', ''));
end

%% toCellText - cellstr from a char matrix / string array / cell
function c = toCellText(v)
    if iscell(v)
        c = v;
    elseif isstring(v)
        c = cellstr(v);
    else
        c = cellstr(v');
    end
end

%% isHDF5 - HDF5 signature at offset 0, 512, 1024 or 2048 (user block)
function tf = isHDF5(file)
    tf = false;
    fid = fopen(file, 'r');
    if fid < 0, return; end
    c = onCleanup(@() fclose(fid));
    sig = [137 72 68 70 13 10 26 10];
    for off = [0 512 1024 2048]
        if fseek(fid, off, 'bof') ~= 0, return; end
        b = fread(fid, 8, 'uint8=>double')';
        if isequal(b, sig)
            tf = true;
            return;
        end
    end
end
