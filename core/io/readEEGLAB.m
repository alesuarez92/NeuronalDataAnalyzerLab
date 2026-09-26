%% readEEGLAB.m
% =========================================================================
% READ EEGLAB - AN EEGLAB DATASET (.set, .set + .fdt, OR EEG IN A .mat)
% =========================================================================
% eeg = readEEGLAB(file)
%
% file: an EEGLAB .set file, or a .mat file holding an EEG variable. A .set
% file is a MAT file holding either a variable EEG or the EEG fields at the
% top level (newer pop_saveset). EEG.data holds the numbers, or the name
% of a .fdt file in the same folder (float32, little-endian, channels x
% (samples x trials)).
%
% Returns the common EEG struct (see EEGSource):
%   - trials: the condition of each trial is the type of the event at
%     time 0 of that trial (EEG.event, else EEG.epoch)
%   - continuous data: EEG.event as events (type, latency s, duration s)
%   - channel names and positions from EEG.chanlocs (labels, X, Y, Z,
%     theta, radius; EEGLAB axes: x = nose, y = left ear, z = up)
%   - reference from EEG.ref or the last pop_reref in the history
%   - history: EEG.history in plain sentences (EEGSource.eeglabHistory);
%     nothing in it is run
% Errors: NeuroAnalyzer:io:fileNotFound (file or its .fdt missing),
% NeuroAnalyzer:eeg:notEEGLAB, NeuroAnalyzer:eeg:sizeMismatch,
% NeuroAnalyzer:io:truncated. Toolboxes: none (EEGLAB is not needed).
% =========================================================================

function eeg = readEEGLAB(file)
    s = EEGSource.loadMat(file);
    if isfield(s, 'EEG') && isstruct(s.EEG)
        EEG = s.EEG;
    elseif isfield(s, 'data') && isfield(s, 'srate')
        EEG = s;
    else
        error('NeuroAnalyzer:eeg:notEEGLAB', ['%s does not hold an EEGLAB dataset (no EEG ' ...
            'variable, and no EEGLAB fields such as srate and data).'], file);
    end
    notes = {};
    if numel(EEG) > 1
        notes{end + 1} = sprintf('The file holds %d datasets; the first one is used.', numel(EEG));
        EEG = EEG(1);
    end
    if ~isfield(EEG, 'srate') || ~isfield(EEG, 'data')
        error('NeuroAnalyzer:eeg:notEEGLAB', 'The EEG variable in %s has no srate or data field.', file);
    end
    fs = double(EEG.srate);

    % ---- Numbers: inline or in the .fdt file ----
    if ischar(EEG.data)
        nb = sizeField(EEG, 'nbchan', file);
        pnts = sizeField(EEG, 'pnts', file);
        tr = 1;
        if isfield(EEG, 'trials') && ~isempty(EEG.trials), tr = double(EEG.trials); end
        data = readFdt(file, EEG, nb, pnts, tr);
    else
        data = EEG.data;
        sz = size(data);
        nb = getOr(EEG, 'nbchan', sz(1));
        pnts = getOr(EEG, 'pnts', sz(2));
        tr = getOr(EEG, 'trials', numel(data) / max(1, nb * pnts));
        if numel(data) ~= nb * pnts * tr
            error('NeuroAnalyzer:eeg:sizeMismatch', ['The data in %s hold %d values, but the file ' ...
                'says %d channels x %d samples x %d trials (%d values).'], file, numel(data), nb, pnts, tr, nb * pnts * tr);
        end
        data = reshape(data, nb, pnts, tr);
    end

    % ---- Time ----
    xmin = getOr(EEG, 'xmin', 0);
    if isfield(EEG, 'times') && numel(EEG.times) == pnts
        times = double(EEG.times(:)') / 1000;          % EEGLAB stores ms
    else
        times = xmin + (0:pnts - 1) / fs;
    end

    % ---- Channels ----
    labels = arrayfun(@(c) sprintf('Ch %d', c), 1:nb, 'UniformOutput', false);
    locs = struct('label', labels, 'x', NaN, 'y', NaN, 'z', NaN, 'theta', NaN, 'radius', NaN);
    if isfield(EEG, 'chanlocs') && numel(EEG.chanlocs) == nb && isstruct(EEG.chanlocs)
        cl = EEG.chanlocs;
        for k = 1:nb
            if isfield(cl, 'labels') && ~isempty(cl(k).labels)
                labels{k} = strtrim(EEGSource.valueText(cl(k).labels));
            end
            locs(k).label = labels{k};
            locs(k).x = num(cl, k, 'X');
            locs(k).y = num(cl, k, 'Y');
            locs(k).z = num(cl, k, 'Z');
            locs(k).theta = num(cl, k, 'theta');
            locs(k).radius = num(cl, k, 'radius');
        end
    elseif isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs)
        notes{end + 1} = sprintf(['The file lists %d channel positions for %d channels; ' ...
            'the channels are called Ch 1, Ch 2, ...'], numel(EEG.chanlocs), nb);
    end
    coord = 'EEGLAB (x = nose, y = left ear, z = up)';
    if isfield(EEG, 'chaninfo') && isstruct(EEG.chaninfo) && isfield(EEG.chaninfo, 'coordsys') ...
            && ~isempty(EEG.chaninfo.coordsys)
        coord = sprintf('%s; %s', coord, char(EEG.chaninfo.coordsys));
    end

    % ---- Trials and events ----
    isEp = tr > 1 || (isfield(EEG, 'epoch') && ~isempty(EEG.epoch));
    cond = {};
    events = [];
    if isEp
        cond = trialConditions(EEG, tr, pnts, fs, xmin);
    elseif isfield(EEG, 'event') && ~isempty(EEG.event)
        ev = EEG.event;
        events = struct('type', {}, 'latency', {}, 'duration', {});
        for k = 1:numel(ev)
            d = 0;
            if isfield(ev, 'duration') && isnumeric(ev(k).duration) && ~isempty(ev(k).duration)
                d = double(ev(k).duration) / fs;
            end
            events(end + 1) = struct('type', typeText(ev(k).type), ...
                'latency', (double(ev(k).latency) - 1) / fs + times(1), 'duration', d); %#ok<AGROW>
        end
    end

    % ---- History and reference ----
    hist = '';
    if isfield(EEG, 'history'), hist = EEG.history; end
    [lines, info] = EEGSource.eeglabHistory(hist, labels);
    ref = 'unknown';
    if isfield(EEG, 'ref') && ischar(EEG.ref) && ~isempty(EEG.ref)
        switch lower(EEG.ref)
            case {'averef', 'average'}, ref = 'average of all channels';
            case 'common', ref = 'unknown';
            otherwise, ref = EEG.ref;
        end
    end
    if strcmp(ref, 'unknown') && ~isempty(info.reference), ref = info.reference; end
    if isfield(EEG, 'icaweights') && ~isempty(EEG.icaweights)
        notes{end + 1} = sprintf(['The file also holds an ICA decomposition (%d components). ' ...
            'It is left as it is: the data used are the cleaned channels.'], size(EEG.icaweights, 1));
    end

    eeg = EEGSource.make(data, fs, 'Times', times, 'Labels', labels, 'Chanlocs', locs, ...
        'CoordSystem', coord, 'Conditions', cond, 'Events', events, 'Reference', ref, ...
        'History', lines, 'Notes', notes, 'Unit', 'auto', 'IsEpoched', isEp, ...
        'Source', 'EEGLAB', 'Format', 'eeglab', 'File', file);
end

%% readFdt - float32 channels x (samples x trials) from the .fdt next to the .set
function data = readFdt(file, EEG, nb, pnts, tr)
    folder = fileparts(file);
    names = {EEG.data};
    if isfield(EEG, 'datfile') && ischar(EEG.datfile) && ~isempty(EEG.datfile)
        names{end + 1} = EEG.datfile;
    end
    f = '';
    for k = 1:numel(names)
        [~, b, e] = fileparts(strrep(names{k}, '\', '/'));    % any stored folder is ignored
        c = fullfile(folder, [b e]);
        if exist(c, 'file') == 2, f = c; break; end
    end
    if isempty(f)
        [~, b, e] = fileparts(strrep(names{end}, '\', '/'));
        [~, sb, se] = fileparts(file);
        error('NeuroAnalyzer:io:fileNotFound', ['The numbers of %s are kept in a separate ' ...
            'file, %s, which is not in the same folder. Copy %s next to %s and try again.'], ...
            [sb se], [b e], [b e], [sb se]);
    end
    n = nb * pnts * tr;
    fid = fopen(f, 'r', 'ieee-le');
    if fid < 0
        error('NeuroAnalyzer:io:fileNotFound', 'Cannot open %s', f);
    end
    x = fread(fid, n, 'float32=>single');
    fclose(fid);
    if numel(x) < n
        error('NeuroAnalyzer:io:truncated', ['%s holds %d values, but %d channels x %d samples ' ...
            'x %d trials need %d. The file is incomplete.'], f, numel(x), nb, pnts, tr, n);
    end
    data = reshape(x, nb, pnts, tr);
end

%% trialConditions - Type of the event at time 0 of each trial
function cond = trialConditions(EEG, tr, pnts, fs, xmin)
    cond = repmat({''}, 1, tr);
    z = round(-xmin * fs) + 1;                    % sample of time 0 within a trial
    if isfield(EEG, 'event') && ~isempty(EEG.event) && isfield(EEG.event, 'latency')
        ev = EEG.event;
        for k = 1:numel(ev)
            lat = double(ev(k).latency);
            if isempty(lat), continue; end
            if isfield(ev, 'epoch') && ~isempty(ev(k).epoch)
                e = double(ev(k).epoch);
            else
                e = floor((lat - 1) / pnts) + 1;
            end
            if e >= 1 && e <= tr && isempty(cond{e}) && abs(lat - ((e - 1) * pnts + z)) <= 0.5
                cond{e} = typeText(ev(k).type);
            end
        end
    end
    if any(cellfun(@isempty, cond)) && isfield(EEG, 'epoch') && numel(EEG.epoch) == tr ...
            && isfield(EEG.epoch, 'eventlatency')
        for e = find(cellfun(@isempty, cond))
            lat = EEG.epoch(e).eventlatency;
            typ = EEG.epoch(e).eventtype;
            if ~iscell(lat), lat = num2cell(lat); end
            if ~iscell(typ), typ = num2cell(typ); end
            i = find(cellfun(@(v) isnumeric(v) && ~isempty(v) && abs(double(v(1))) < 1e-6, lat), 1);
            if ~isempty(i) && i <= numel(typ), cond{e} = typeText(typ{i}); end
        end
    end
    empty = cellfun(@isempty, cond);
    if all(empty)
        cond = repmat({'All trials'}, 1, tr);
    else
        cond(empty) = {'No event at 0 s'};
    end
end

%% typeText - Event type (text or number) as text
function t = typeText(x)
    if iscell(x) && ~isempty(x), x = x{1}; end
    if isempty(x)
        t = '(no type)';
    else
        t = EEGSource.valueText(x);
    end
end

%% num - Scalar field of chanlocs(k), NaN if missing or empty
function v = num(cl, k, f)
    v = NaN;
    if isfield(cl, f) && isnumeric(cl(k).(f)) && isscalar(cl(k).(f))
        v = double(cl(k).(f));
    end
end

%% getOr - Numeric field or a default
function v = getOr(s, f, d)
    v = d;
    if isfield(s, f) && isnumeric(s.(f)) && isscalar(s.(f)), v = double(s.(f)); end
end

%% sizeField - Required size field of a dataset whose numbers are in a .fdt
function v = sizeField(EEG, f, file)
    if ~isfield(EEG, f) || isempty(EEG.(f))
        error('NeuroAnalyzer:eeg:sizeMismatch', ['%s keeps its numbers in a separate file but ' ...
            'does not say how many %s there are (%s is missing).'], file, ...
            strrep(strrep(f, 'nbchan', 'channels'), 'pnts', 'samples'), f);
    end
    v = double(EEG.(f));
end
