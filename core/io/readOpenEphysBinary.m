%% readOpenEphysBinary.m
% =========================================================================
% READ OPEN EPHYS BINARY - OPEN EPHYS GUI RECORDING AS A TDT-LIKE STRUCT
% =========================================================================
% rec = readOpenEphysBinary(p)
% rec = readOpenEphysBinary(p, 'Stream', s)
%
% Reads one continuous stream of an Open Ephys GUI recording saved in the
% "binary" format (GUI 0.5 and later) and returns the same struct shape as
% TDTbin2mat, so Extract Ephys can use it unchanged:
%   rec.streams.xRAW.data   neural channels x samples (single, volts)
%   rec.streams.xRAW.fs     stream sample rate (Hz)
%   rec.streams.Whis.data   candidate stimulus channels: one 0/1 square wave
%                           per TTL line (from the events folders), then the
%                           stream's ADC channels (volts); zero row if none
%   rec.streams.Whis.fs     same as the continuous rate
%   rec.info                source ('Open Ephys'), format ('openephys'),
%                           file (structure.oebin), blockname, duration,
%                           channelNames, stimNames, stimKinds, stimOnsets
%                           (cell of TTL onset times, s), firstSample,
%                           guiVersion, streamName, skippedChannels
%
% Inputs:
%   p    - the recording folder (holding structure.oebin), the
%          structure.oebin file itself, or a parent folder (session /
%          Record Node / experiment): the first structure.oebin found in
%          sorted order is used and the rest are listed in info.otherRecordings
%   'Stream' - continuous stream index (default 1) or folder/stream name
%
% Method (Open Ephys GUI documentation, "Binary format",
% open-ephys.github.io): structure.oebin is JSON listing the continuous
% streams (folder_name, sample_rate, num_channels, channels with
% channel_name, bit_volts, units) and the event streams. continuous.dat
% holds int16 samples interleaved by channel (sample 1 of every channel,
% then sample 2 ...); value x bit_volts is in the channel's units (uV for
% headstage channels, V for ADC channels). The first sample number comes
% from sample_numbers.npy (GUI >= 0.6) or timestamps.npy (0.5.x, integer
% sample numbers). TTL events: states.npy (>= 0.6) or channel_states.npy
% (0.5.x), +line for a rising and -line for a falling edge, at
% sample_numbers.npy (>= 0.6) or timestamps.npy (0.5.x) in the clock of
% their stream. Edges are placed at (sample - first continuous sample) on
% the continuous grid and turned into a square wave per line.
%
% Limitations: channels named ADC* become stimulus candidates and AUX*
% (headstage accelerometer) channels are skipped (info.skippedChannels);
% text/message events and spikes are ignored; events from another stream
% with a different clock are aligned through that stream's first sample
% number; one stream and one recording per call.
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:noData,
%   NeuroAnalyzer:io:badHeader.
% Toolboxes: none (jsondecode; base MATLAB, also runs in Octave >= 7).
% =========================================================================

function rec = readOpenEphysBinary(p, varargin)
    streamSel = 1;
    for k = 1:2:numel(varargin)
        if strcmpi(varargin{k}, 'Stream'), streamSel = varargin{k+1}; end
    end
    [oebin, others] = locateOebin(p);
    recDir = fileparts(oebin);
    try
        S = jsondecode(fileread(oebin));
    catch ME
        error('NeuroAnalyzer:io:badHeader', 'Cannot parse %s as JSON: %s', oebin, ME.message);
    end
    if ~isfield(S, 'continuous') || isempty(S.continuous)
        error('NeuroAnalyzer:io:noData', '%s lists no continuous streams.', oebin);
    end
    conts = asCell(S.continuous);
    si = pickStream(conts, streamSel, oebin);
    st = conts{si};
    fs = double(st.sample_rate);
    chans = asCell(st.channels);
    nCh = double(st.num_channels);
    if numel(chans) ~= nCh
        error('NeuroAnalyzer:io:badHeader', '%s: num_channels (%d) does not match the channel list (%d).', ...
            oebin, nCh, numel(chans));
    end
    contDir = fullfile(recDir, 'continuous', stripSlash(st.folder_name));
    datFile = fullfile(contDir, 'continuous.dat');
    if ~(exist(datFile, 'file') == 2)
        error('NeuroAnalyzer:io:fileNotFound', 'Missing %s (listed in %s).', datFile, oebin);
    end

    % ---- Continuous samples ----
    fid = fopen(datFile, 'r', 'ieee-le');
    if fid < 0
        error('NeuroAnalyzer:io:fileNotFound', 'Cannot open %s', datFile);
    end
    x = fread(fid, [nCh, Inf], 'int16=>int16');
    fclose(fid);
    nS = size(x, 2);
    names = cell(1, nCh); bitVolts = zeros(nCh, 1); scale = zeros(nCh, 1);
    for c = 1:nCh
        ch = chans{c};
        names{c} = fieldOr(ch, 'channel_name', sprintf('CH%d', c));
        bitVolts(c) = double(fieldOr(ch, 'bit_volts', 0.195));
        scale(c) = unitScale(fieldOr(ch, 'units', 'uV'));
    end
    upperNames = upper(names);
    isAdc = strncmp(upperNames, 'ADC', 3);
    isAux = strncmp(upperNames, 'AUX', 3);
    neural = ~isAdc & ~isAux;
    if ~any(neural), neural = true(1, nCh); isAdc(:) = false; isAux(:) = false; end
    raw = bsxfun(@times, double(x(neural, :)), bitVolts(neural) .* scale(neural));
    adc = bsxfun(@times, double(x(isAdc, :)), bitVolts(isAdc) .* scale(isAdc));
    clear x;

    firstSample = firstSampleOf(contDir);

    % ---- TTL events -> square waves on the continuous grid ----
    stim = zeros(0, nS, 'single'); stimNames = {}; stimKinds = {}; stimOnsets = {};
    if isfield(S, 'events') && ~isempty(S.events)
        evs = asCell(S.events);
        nTTL = 0;
        for e = 1:numel(evs)
            ev = evs{e};
            evDir = fullfile(recDir, 'events', stripSlash(ev.folder_name));
            [states, evSamples] = readTTL(evDir);
            if isempty(states), continue; end
            nTTL = nTTL + 1;
            % Clock of the event stream: same continuous stream, or the one it names
            [evFirst, evFs] = eventClock(ev, conts, si, recDir, firstSample, fs);
            tRel = (double(evSamples) - evFirst) / evFs;
            idx = round(tRel * fs) + 1;
            lines = unique(abs(double(states(:)')));
            lines = lines(lines > 0);
            for L = lines
                on = idx(states == L);
                off = idx(states == -L);
                stim(end+1, :) = EphysSource.eventsToSquare(on, off, nS); %#ok<AGROW>
                stimNames{end+1} = sprintf('TTL line %d', L); %#ok<AGROW>
                stimKinds{end+1} = 'ttl'; %#ok<AGROW>
                stimOnsets{end+1} = (on(on >= 1 & on <= nS) - 1) / fs; %#ok<AGROW>
            end
        end
        if nTTL > 1
            warning('NeuroAnalyzer:io:multipleEventStreams', ...
                '%s: %d TTL event streams; lines with the same number are listed once per stream.', ...
                oebin, nTTL);
        end
    end
    adcNames = names(isAdc);
    for k = 1:size(adc, 1)
        stim(end+1, :) = single(adc(k, :)); %#ok<AGROW>
        stimNames{end+1} = adcNames{k}; %#ok<AGROW>
        stimKinds{end+1} = 'analog'; %#ok<AGROW>
        stimOnsets{end+1} = []; %#ok<AGROW>
    end

    info = struct('source', 'Open Ephys', 'format', 'openephys', 'file', oebin, ...
        'blockname', recordingName(recDir), 'duration', nS / fs, ...
        'channelNames', {names(neural)}, 'stimNames', {stimNames}, 'stimKinds', {stimKinds}, ...
        'stimOnsets', {stimOnsets}, 'firstSample', firstSample, ...
        'guiVersion', fieldOr(S, 'GUIVersion', ''), 'streamName', stripSlash(st.folder_name), ...
        'skippedChannels', {names(isAux)}, 'otherRecordings', {others});
    rec = EphysSource.makeRecording(raw, fs, stim, fs, info);
end

%% locateOebin - structure.oebin for a file / recording folder / parent folder
function [oebin, others] = locateOebin(p)
    others = {};
    if exist(p, 'file') == 2
        [~, n, e] = fileparts(p);
        if strcmpi([n e], 'structure.oebin')
            oebin = p;
            return;
        end
        p = fileparts(p);
    end
    if ~(exist(p, 'dir') == 7)
        error('NeuroAnalyzer:io:fileNotFound', 'Open Ephys folder not found: %s', p);
    end
    found = findAll(p, 'structure.oebin', 5);
    if isempty(found)
        error('NeuroAnalyzer:io:fileNotFound', ['No structure.oebin found under %s. Choose an Open Ephys ' ...
            'binary recording folder (…/Record Node */experiment*/recording*) or a folder above it.'], p);
    end
    oebin = found{1};
    others = found(2:end);
end

%% findAll - Every file called name below root (depth-limited, sorted)
function out = findAll(root, name, depth)
    out = {};
    if exist(fullfile(root, name), 'file') == 2
        out = {fullfile(root, name)};
    end
    if depth <= 0, return; end
    d = dir(root);
    d = d([d.isdir] & ~ismember({d.name}, {'.', '..'}));
    sub = sort({d.name});
    for k = 1:numel(sub)
        out = [out, findAll(fullfile(root, sub{k}), name, depth - 1)]; %#ok<AGROW>
    end
end

%% pickStream - Continuous stream by index or (partial) folder / stream name
function si = pickStream(conts, sel, oebin)
    if isnumeric(sel)
        if sel < 1 || sel > numel(conts)
            error('NeuroAnalyzer:io:noData', '%s has %d continuous stream(s); stream %d requested.', ...
                oebin, numel(conts), sel);
        end
        si = sel;
        return;
    end
    for k = 1:numel(conts)
        c = conts{k};
        if ~isempty(strfind(c.folder_name, sel)) || strcmp(fieldOr(c, 'stream_name', ''), sel) %#ok<STREMP>
            si = k;
            return;
        end
    end
    error('NeuroAnalyzer:io:noData', 'No continuous stream matching ''%s'' in %s.', sel, oebin);
end

%% firstSampleOf - First sample number of a continuous stream folder (0 if unknown)
function s0 = firstSampleOf(contDir)
    s0 = 0;
    f = fullfile(contDir, 'sample_numbers.npy');
    if ~(exist(f, 'file') == 2)
        f = fullfile(contDir, 'timestamps.npy');
        if ~(exist(f, 'file') == 2), return; end
    end
    v = readNPY(f);
    if isempty(v), return; end
    if isinteger(v)
        s0 = double(v(1));
    end
end

%% readTTL - states and sample numbers of an event folder ([] if not TTL)
function [states, samples] = readTTL(evDir)
    states = []; samples = [];
    if ~(exist(evDir, 'dir') == 7), return; end
    f = fullfile(evDir, 'states.npy');
    if ~(exist(f, 'file') == 2), f = fullfile(evDir, 'channel_states.npy'); end
    if ~(exist(f, 'file') == 2), return; end
    states = double(readNPY(f));
    g = fullfile(evDir, 'sample_numbers.npy');
    if ~(exist(g, 'file') == 2), g = fullfile(evDir, 'timestamps.npy'); end
    if ~(exist(g, 'file') == 2)
        states = [];
        return;
    end
    samples = readNPY(g);
    if ~isinteger(samples)
        % Float timestamps only (seconds): not a sample clock we can align
        warning('NeuroAnalyzer:io:eventTimestamps', ...
            '%s: events have no integer sample numbers; skipped.', evDir);
        states = []; samples = [];
        return;
    end
    n = min(numel(states), numel(samples));
    states = states(1:n)'; samples = double(samples(1:n))';
end

%% eventClock - First sample number and rate of the stream an event folder belongs to
function [s0, evFs] = eventClock(ev, conts, si, recDir, firstSample, fs)
    s0 = firstSample; evFs = fs;
    evStream = fieldOr(ev, 'stream_name', '');
    evFolder = stripSlash(ev.folder_name);
    for k = 1:numel(conts)
        c = conts{k};
        cf = stripSlash(c.folder_name);
        sameName = ~isempty(evStream) && strcmp(fieldOr(c, 'stream_name', ''), evStream);
        sameFolder = strncmp(evFolder, [cf '/'], numel(cf) + 1) || strncmp(evFolder, [cf filesep], numel(cf) + 1);
        if sameName || sameFolder
            if k ~= si
                s0 = firstSampleOf(fullfile(recDir, 'continuous', cf));
                evFs = double(c.sample_rate);
            end
            return;
        end
    end
end

%% recordingName - "<session>_<experiment>_<recording>" from the folder path
function name = recordingName(recDir)
    [p1, rec] = fileparts(recDir);
    [p2, exp] = fileparts(p1);
    [p3, node] = fileparts(p2);
    if strncmp(node, 'Record Node', 11)
        [~, session] = fileparts(p3);
    else
        session = node;
    end
    if isempty(regexp(exp, '^experiment\d+$', 'once'))
        name = rec;
    else
        name = sprintf('%s_%s_%s', session, exp, rec);
    end
    name = regexprep(name, '[^\w-]', '_');
end

%% unitScale - Volts per unit
function s = unitScale(u)
    u = strtrim(u);
    if numel(u) == 2 && lower(u(2)) == 'v' && any(double(u(1)) == [117 85 181 956])   % uV, µV, μV
        s = 1e-6;
    elseif strcmpi(u, 'mV')
        s = 1e-3;
    elseif strcmpi(u, 'V')
        s = 1;
    else
        s = 1e-6;                       % Open Ephys default: headstage channels in uV
    end
end

%% asCell - struct array or cell (jsondecode output) -> cell row
function c = asCell(x)
    if iscell(x)
        c = x(:)';
    else
        c = num2cell(x(:)');
    end
end

%% fieldOr - s.(f) if present and non-empty, else default
function v = fieldOr(s, f, default)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f))
        v = s.(f);
    else
        v = default;
    end
end

%% stripSlash - Folder name without trailing / or \ (as written in the oebin)
function s = stripSlash(s)
    s = regexprep(s, '[/\\]+$', '');
    s = strrep(s, '/', filesep);
end
