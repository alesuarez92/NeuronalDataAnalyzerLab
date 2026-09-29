%% readEEGMatrix.m
% =========================================================================
% READ EEG MATRIX - EEG KEPT AS A PLAIN NUMBER ARRAY IN A .mat FILE
% =========================================================================
% eeg = readEEGMatrix(file, map)
%
% map says what the variables in the file are (the EEG window fills it in
% with a form; EEGSource.guessMatrixMap suggests one):
%   data        name of the variable holding the numbers (required)
%   fs          sampling rate in Hz, or the name of a variable holding it (required)
%   dims        what each dimension of the data is, e.g.
%               {'channel', 'time'} or {'trial', 'channel', 'time'}
%               (default: {'channel', 'time', 'trial'})
%   labels      channel names: a variable name or a cell of names ('' = Ch 1, Ch 2, ...)
%   times       time of each sample in s: a variable name ('' = from tStart)
%   tStart      time of the first sample in s (default 0; e.g. -0.2 for trials)
%   conditions  condition of each trial: a variable name, or a cell / numbers
%   events      continuous data: variable with event times in s ('' = none)
%   eventName   name given to those events (default: the variable name)
%   unit        'auto' (default: values below 0.01 are taken as volts), 'uV', 'mV', 'V'
%
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:eeg:unknownVariable,
% NeuroAnalyzer:eeg:sizeMismatch, NeuroAnalyzer:eeg:badOption.
% Toolboxes: none.
% =========================================================================

function eeg = readEEGMatrix(file, map)
    s = EEGSource.loadMat(file);
    def = struct('data', '', 'fs', [], 'dims', {{'channel', 'time', 'trial'}}, 'labels', '', ...
        'times', '', 'tStart', 0, 'conditions', '', 'events', '', 'eventName', '', 'unit', 'auto');
    for f = fieldnames(map)'
        if ~isfield(def, f{1})
            error('NeuroAnalyzer:eeg:badOption', 'Unknown map field ''%s''.', f{1});
        end
        if ~isempty(map.(f{1})), def.(f{1}) = map.(f{1}); end
    end
    map = def;
    if isempty(map.data)
        error('NeuroAnalyzer:eeg:badOption', 'Say which variable holds the EEG (map.data).');
    end
    x = getVar(s, map.data);
    if ~isnumeric(x)
        error('NeuroAnalyzer:eeg:sizeMismatch', 'The variable ''%s'' does not hold numbers.', map.data);
    end

    % ---- Arrange as channels x samples x trials ----
    dims = lower(map.dims);
    nd = ndims(x);
    if numel(dims) < nd
        error('NeuroAnalyzer:eeg:sizeMismatch', ['''%s'' has %d dimensions, but only %d are ' ...
            'described (%s).'], map.data, nd, numel(dims), strjoin(dims, ', '));
    end
    order = [find(strcmp(dims, 'channel')), find(strcmp(dims, 'time')), find(strcmp(dims, 'trial'))];
    if numel(order) ~= numel(dims) || sum(strcmp(dims, 'channel')) ~= 1 || sum(strcmp(dims, 'time')) ~= 1 ...
            || sum(strcmp(dims, 'trial')) > 1
        error('NeuroAnalyzer:eeg:badOption', ['Each dimension must be called channel, time or trial, ' ...
            'with one channel and one time dimension (got %s).'], strjoin(dims, ', '));
    end
    if numel(order) == 2, order(3) = 3; end
    data = permute(x, order);
    [nCh, nS, nTr] = size(data);
    hasTrials = any(strcmp(dims, 'trial'));

    % ---- Sampling rate and time ----
    fs = map.fs;
    if ischar(fs), fs = getVar(s, fs); end
    if ~(isnumeric(fs) && isscalar(fs) && fs > 0)
        error('NeuroAnalyzer:eeg:badOption', 'The sampling rate must be one positive number (Hz).');
    end
    fs = double(fs);
    if ~isempty(map.times)
        times = double(getVar(s, map.times));
        if numel(times) ~= nS
            error('NeuroAnalyzer:eeg:sizeMismatch', ['''%s'' has %d time points, but the data have ' ...
                '%d samples.'], map.times, numel(times), nS);
        end
    else
        times = map.tStart + (0:nS - 1) / fs;
    end

    % ---- Channel names ----
    labels = map.labels;
    if ischar(labels) && ~isempty(labels), labels = getVar(s, labels); end
    labels = EEGSource.cellRow(labels);
    if ~isempty(labels) && numel(labels) ~= nCh
        error('NeuroAnalyzer:eeg:sizeMismatch', 'There are %d channel names for %d channels.', numel(labels), nCh);
    end

    % ---- Conditions and events ----
    cond = map.conditions;
    if ischar(cond) && ~isempty(cond), cond = getVar(s, cond); end
    if ~isempty(cond) && numel(cond) ~= nTr
        error('NeuroAnalyzer:eeg:sizeMismatch', 'There are %d conditions for %d trials.', numel(cond), nTr);
    end
    isEp = hasTrials && (nTr > 1 || times(1) < 0);
    events = [];
    if ~isempty(map.events)
        t = double(getVar(s, map.events));
        nm = map.eventName;
        if isempty(nm), nm = map.events; end
        events = struct('type', nm, 'latency', num2cell(t(:)'), 'duration', 0);
    end

    eeg = EEGSource.make(data, fs, 'Times', times, 'Labels', labels, 'Conditions', cond, ...
        'Events', events, 'Unit', map.unit, 'IsEpoched', isEp, ...
        'Source', 'MATLAB matrix', 'Format', 'matrix', 'File', file);
end

%% getVar - A variable of the file, or a plain error listing what is there
function v = getVar(s, name)
    if ~isfield(s, name)
        error('NeuroAnalyzer:eeg:unknownVariable', 'The file has no variable called ''%s''. Variables in the file: %s.', ...
            name, strjoin(fieldnames(s)', ', '));
    end
    v = s.(name);
end
