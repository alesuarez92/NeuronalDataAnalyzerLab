%% writeFieldTrip.m
% =========================================================================
% WRITE FIELDTRIP - AN EEG STRUCT AS FIELDTRIP DATA IN A .mat FILE
% =========================================================================
% writeFieldTrip(file, eeg, Name, Value, ...)
%
% eeg: the common EEG struct (EEGSource.make). Positions in eeg.chanlocs
% are written as elec.elecpos / chanpos as they are.
%
% Options:
%   'Kind'            'raw' (default): label, trial, time, fsample,
%                     trialinfo, sampleinfo; 'timelock': avg over trials
%                     (dimord 'chan_time'); 'timelockTrials': trial as
%                     rpt x chan x time (dimord 'rpt_chan_time')
%   'Variable'        variable name (default 'data')
%   'Cfg'             cfg struct to store (with its cfg.previous chain)
%   'ConditionCodes'  trialinfo codes, one per trial (default: position
%                     of the trial's condition in ConditionNames, or else
%                     in eeg.conditions)
%   'ConditionNames'  also save these names as the variable conditionNames
%   'Coordsys', 'Unit'  elec.coordsys / elec.unit (default 'unknown', 'mm')
%   'Scale'           multiply the numbers (e.g. 1e-6 to store volts)
% Continuous data: eeg.events are also saved as a FieldTrip event struct
% (type, sample, value, duration) in the variable event.
% Toolboxes: none. Used by core/demo/demoEEG and the EEG tests.
% =========================================================================

function writeFieldTrip(file, eeg, varargin)
    o = struct('Kind', 'raw', 'Variable', 'data', 'Cfg', [], 'ConditionCodes', [], ...
        'ConditionNames', {{}}, 'Coordsys', 'unknown', 'Unit', 'mm', 'Scale', 1);
    o = EEGSource.options(o, varargin);
    [nCh, nS, nTr] = size(eeg.data);
    x = double(eeg.data) * o.Scale;
    codes = o.ConditionCodes;
    if isempty(codes) && eeg.isEpoched
        names = eeg.conditions;
        if ~isempty(o.ConditionNames), names = o.ConditionNames; end
        [~, codes] = ismember(eeg.trials.condition, names);
    end
    d = struct();
    d.label = eeg.labels(:);
    switch lower(o.Kind)
        case 'raw'
            d.fsample = eeg.fs;
            d.trial = arrayfun(@(k) x(:, :, k), 1:nTr, 'UniformOutput', false);
            d.time = repmat({eeg.times}, 1, nTr);
            if ~isempty(codes), d.trialinfo = codes(:); end
            d.sampleinfo = [(0:nTr - 1)' * nS + 1, (1:nTr)' * nS];
        case 'timelock'
            d.avg = mean(x, 3);
            d.var = var(x, 0, 3);
            d.dof = repmat(nTr, nCh, nS);
            d.time = eeg.times;
            d.dimord = 'chan_time';
        case 'timelocktrials'
            d.trial = permute(x, [3 1 2]);
            d.time = eeg.times;
            d.dimord = 'rpt_chan_time';
            if ~isempty(codes), d.trialinfo = codes(:); end
        otherwise
            error('NeuroAnalyzer:eeg:badOption', 'Unknown kind ''%s'' (raw, timelock or timelockTrials).', o.Kind);
    end
    if any(isfinite([eeg.chanlocs.x]))
        pos = [[eeg.chanlocs.x]', [eeg.chanlocs.y]', [eeg.chanlocs.z]'];
        d.elec = struct('label', {eeg.labels(:)}, 'elecpos', pos, 'chanpos', pos, ...
            'unit', o.Unit, 'coordsys', o.Coordsys);
    end
    if ~isempty(o.Cfg), d.cfg = o.Cfg; end

    S = struct();
    S.(o.Variable) = d;
    if ~isempty(o.ConditionNames), S.conditionNames = o.ConditionNames; end
    if ~eeg.isEpoched && ~isempty(eeg.events)
        ev = eeg.events;
        S.event = struct('type', {ev.type}, ...
            'sample', num2cell(round(([ev.latency] - eeg.times(1)) * eeg.fs) + 1), ...
            'value', [], 'duration', num2cell(round([ev.duration] * eeg.fs)), 'offset', []);
    end
    save(file, '-struct', 'S', '-mat', '-v7');
end
