%% readMCS.m
% =========================================================================
% READ MCS - MULTI CHANNEL SYSTEMS HDF5 (MEA2100, W2100, ME2100) AS A TDT-LIKE STRUCT
% =========================================================================
% rec = readMCS(file)
%
% Multi Channel Systems HDF5 raw data (Multi Channel DataManager export or
% Multi Channel Experimenter; the layout McsPyDataTools reads): root
% attribute McsHdf5ProtocolType 'RawData'; /Data/Recording_0 with
%   AnalogStream/Stream_<k>: attributes Label, DataSubType ('Electrode',
%     'Auxiliary', 'Digital' ...); InfoChannel (compound: ChannelID,
%     RowIndex, Label, Unit, Exponent, ADZero, Tick (us), ConversionFactor
%     ...); ChannelData (channels x samples, int32 / uint16);
%     ChannelDataTimeStamps (rows of start time (us), first and last
%     sample index, one row per continuous piece).
%     value = (raw - ADZero) x ConversionFactor x 10^Exponent (in Unit);
%     sample rate = 1e6 / Tick.
%   EventStream/Stream_<k>: InfoEvent (EventID, Label ...) and
%     EventEntity_<EventID> (timestamps (us), durations (us), ...).
% Neural channels: the first 'Electrode' stream (else the first stream in
% volts), placed by the time stamps (gaps filled with zeros, info.nGaps).
% Stimulus candidates, on the neural time base: the channels of the other
% analog streams (digital streams: each bit that changes), then each
% event entity (high for the event's duration, at least 1 ms). Only the
% first recording is read (info.notes). Needs MATLAB's HDF5 functions
% (h5info / h5read); not available in GNU Octave.
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:mcs.
% Toolboxes: none.
% =========================================================================

function rec = readMCS(p)
if exist(p, 'file') ~= 2
    error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', p);
end
[~, base, ext] = fileparts(p);
try
    I = h5info(p, '/');
catch
    error('NeuroAnalyzer:io:mcs', '%s%s is not an HDF5 file.', base, ext);
end
if ~any(strcmp({I.Attributes.Name}, 'McsHdf5ProtocolType'))
    error('NeuroAnalyzer:io:mcs', ['%s%s is not a Multi Channel Systems HDF5 file (no McsHdf5ProtocolType): ' ...
        'export the .msrd / .mcd recording to HDF5 with Multi Channel DataManager.'], base, ext);
end
notes = {};
recs = subgroups(p, '/Data', 'Recording_');
if isempty(recs)
    error('NeuroAnalyzer:io:mcs', '%s%s has no /Data/Recording_ group.', base, ext);
end
if numel(recs) > 1, notes{end+1} = sprintf('%d recordings in the file: the first is used.', numel(recs)); end
rg = recs{1};
% Analog streams
A = struct('label', {}, 'subtype', {}, 'x', {}, 'names', {}, 'units', {}, 'tick', {}, 'ts', {});
for s = subgroups(p, [rg '/AnalogStream'], 'Stream_')
    g = s{1};
    ic = h5read(p, [g '/InfoChannel']);
    D = double(h5read(p, [g '/ChannelData']));             % samples x rows
    nC = numel(ic.ChannelID);
    if size(D, 2) ~= nC && size(D, 1) == nC, D = D'; end
    names = cellText(ic.Label, nC);
    units = cellText(ic.Unit, nC);
    x = zeros(nC, size(D, 1));
    for k = 1:nC
        x(k, :) = (D(:, double(ic.RowIndex(k)) + 1)' - double(ic.ADZero(k))) ...
            * double(ic.ConversionFactor(k)) * 10^double(ic.Exponent(k));
    end
    ts = double(h5read(p, [g '/ChannelDataTimeStamps']));
    if size(ts, 1) ~= 3 && size(ts, 2) == 3, ts = ts'; end
    A(end+1) = struct('label', attr(p, g, 'Label'), 'subtype', attr(p, g, 'DataSubType'), 'x', x, ...
        'names', {names}, 'units', {units}, 'tick', double(ic.Tick(1)), 'ts', ts); %#ok<AGROW>
end
if isempty(A)
    error('NeuroAnalyzer:io:mcs', '%s%s has no analog streams.', base, ext);
end
iN = find(strcmpi({A.subtype}, 'Electrode'), 1);
if isempty(iN), iN = find(arrayfun(@(a) all(strcmp(a.units, 'V')), A), 1); end
if isempty(iN), iN = 1; end
N = A(iN);
t0 = N.ts(1, 1);
tick = N.tick;
fs = 1e6 / tick;
[raw, nGaps] = place(N.x, N.ts, t0, tick, 0);
n = size(raw, 2);
tN = t0 + (0:n-1) * tick;
stim = []; stimNames = {}; stimKinds = {};
for k = setdiff(1:numel(A), iN)
    [v, ~] = place(A(k).x, A(k).ts, A(k).ts(1, 1), A(k).tick, 0);
    tv = A(k).ts(1, 1) + (0:size(v, 2)-1) * A(k).tick;
    if size(v, 2) > 1
        v = interp1(tv, v', tN, 'nearest', 0)';
        if size(v, 1) ~= size(A(k).x, 1), v = v'; end
    else
        v = zeros(size(A(k).x, 1), n);
    end
    if strcmpi(A(k).subtype, 'Digital')
        w = mod(round(v(1, :)), 65536);
        for b = 0:15
            bit = bitget(w, b + 1);
            if ~any(bit) || all(bit), continue; end
            stim(end+1, :) = bit; %#ok<AGROW>
            stimNames{end+1} = sprintf('%s bit %d', A(k).label, b); %#ok<AGROW>
            stimKinds{end+1} = 'digital'; %#ok<AGROW>
        end
    else
        stim = [stim; v]; %#ok<AGROW>
        stimNames = [stimNames, A(k).names]; %#ok<AGROW>
        stimKinds = [stimKinds, repmat({'analog'}, 1, size(v, 1))]; %#ok<AGROW>
    end
end
% Event streams
minW = max(1, round(fs * 1e-3));
for s = subgroups(p, [rg '/EventStream'], 'Stream_')
    g = s{1};
    ie = h5read(p, [g '/InfoEvent']);
    labels = cellText(ie.Label, numel(ie.EventID));
    for k = 1:numel(ie.EventID)
        ds = sprintf('%s/EventEntity_%d', g, ie.EventID(k));
        try, E = double(h5read(p, ds)); catch, continue; end
        if isempty(E), continue; end
        if size(E, 2) > 5 && size(E, 1) <= 5, E = E'; end   % events x (time, duration, ...)
        on = round((E(:, 1)' - t0) / tick) + 1;
        if size(E, 2) >= 2, len = max(minW, round(E(:, 2)' / tick)); else, len = minW * ones(size(on)); end
        stim(end+1, :) = EphysSource.eventsToSquare(on, on + len, n); %#ok<AGROW>
        nm = labels{k};
        if isempty(nm), nm = sprintf('Event %d', ie.EventID(k)); end
        stimNames{end+1} = nm; stimKinds{end+1} = 'digital'; %#ok<AGROW>
    end
end
info = struct('source', 'Multi Channel Systems HDF5', 'format', 'mcs', 'file', p, ...
    'blockname', base, 'channelNames', {N.names}, 'streamLabel', N.label, ...
    'nGaps', nGaps, 'firstTimestampUs', t0);
if ~isempty(notes), info.notes = notes; end
if ~isempty(stimNames)
    info.stimNames = stimNames;
    info.stimKinds = stimKinds;
end
rec = EphysSource.makeRecording(raw, fs, stim, fs, info);
end

function [y, nGaps] = place(x, ts, t0, tick, n)
% Samples of each continuous piece placed by its start time
start = round((ts(1, :) - t0) / tick) + 1;
len = ts(3, :) - ts(2, :) + 1;
if n == 0, n = max(start + len - 1); end
y = zeros(size(x, 1), n);
for r = 1:size(ts, 2)
    src = ts(2, r) + 1 + (0:len(r) - 1);
    dst = start(r) + (0:len(r) - 1);
    ok = dst >= 1 & dst <= n & src <= size(x, 2);
    y(:, dst(ok)) = x(:, src(ok));
end
nGaps = sum(start(2:end) ~= start(1:end-1) + len(1:end-1));
end

function list = subgroups(p, path, prefix)
list = {};
try, G = h5info(p, path); catch, return; end
for k = 1:numel(G.Groups)
    nm = G.Groups(k).Name;
    [~, leaf] = fileparts(nm);
    if strncmp(leaf, prefix, numel(prefix)), list{end+1} = nm; end %#ok<AGROW>
end
num = cellfun(@(s) str2double(regexp(s, '\d+$', 'match', 'once')), list);
[~, o] = sort(num);
list = list(o);
end

function s = attr(p, loc, name)
try
    s = h5readatt(p, loc, name);
    if iscell(s), s = s{1}; end
    s = strtrim(char(s(:)'));
catch
    s = '';
end
end

function c = cellText(v, n)
% Strings of a compound field: cell (variable length) or char matrix
if iscell(v)
    c = cellfun(@(s) strtrim(char(s(:)')), v(:)', 'UniformOutput', false);
elseif ischar(v)
    if size(v, 1) ~= n && size(v, 2) == n, v = v'; end
    c = cellfun(@(s) strtrim(s(s ~= 0)), cellstr(v)', 'UniformOutput', false);
else
    c = repmat({''}, 1, n);
end
end
