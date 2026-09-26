%% writeEEGLAB.m
% =========================================================================
% WRITE EEGLAB - AN EEG STRUCT AS AN EEGLAB .set (OPTIONALLY WITH .fdt)
% =========================================================================
% out = writeEEGLAB(file, eeg, Name, Value, ...)
%
% eeg: the common EEG struct (EEGSource.make). Positions in eeg.chanlocs
% are written as EEGLAB X / Y / Z as they are (EEGLAB axes: x = nose,
% y = left ear, z = up); theta / radius are computed from them when missing.
% Epoched data get one event per trial at time 0, typed with the trial's
% condition (EEG.event and EEG.epoch), as pop_epoch leaves them.
%
% Options:
%   'DataFile'  true: numbers in <name>.fdt (float32, little-endian,
%               channels x (samples x trials)); false (default): inline
%   'Layout'    'EEG' (default): one variable EEG; 'fields': the EEG
%               fields at the top level of the file (newer pop_saveset)
%   'History'   text for EEG.history (EEGLAB command lines)
%   'CoordSys'  text for EEG.chaninfo.coordsys (e.g. 'bregma, mm'), or ''
%   'IcaComponents'  number of ICA components to store (identity weights
%               on the first channels; only to test the note), default 0
%
% out: struct with set (and fdt) paths.
% Toolboxes: none. Used by core/demo/demoEEG and the EEG tests.
% =========================================================================

function out = writeEEGLAB(file, eeg, varargin)
    o = struct('DataFile', false, 'Layout', 'EEG', 'History', '', 'CoordSys', '', 'IcaComponents', 0);
    o = EEGSource.options(o, varargin);
    [folder, base] = fileparts(file);
    if isempty(folder), folder = pwd; end
    [nb, pnts, tr] = size(eeg.data);
    fs = eeg.fs;
    xmin = eeg.times(1);

    EEG = struct();
    EEG.setname = base;
    EEG.filename = [base '.set'];
    EEG.filepath = folder;
    EEG.subject = '';
    EEG.group = '';
    EEG.condition = '';
    EEG.session = [];
    EEG.comments = 'Written by NeuroAnalyzer';
    EEG.nbchan = nb;
    EEG.trials = tr;
    EEG.pnts = pnts;
    EEG.srate = fs;
    EEG.xmin = xmin;
    EEG.xmax = eeg.times(end);
    EEG.times = eeg.times * 1000;
    EEG.data = [];
    EEG.icaact = [];
    nIca = o.IcaComponents;
    EEG.icawinv = eye(nb, nIca);
    EEG.icasphere = eye(nb) * (nIca > 0);
    EEG.icaweights = eye(nIca, nb);
    EEG.icachansind = 1:nb * (nIca > 0);
    if nIca == 0
        EEG.icawinv = []; EEG.icasphere = []; EEG.icaweights = []; EEG.icachansind = [];
    end
    EEG.chanlocs = chanlocs(eeg);
    EEG.urchanlocs = [];
    EEG.chaninfo = struct('plotrad', [], 'shrink', [], 'nosedir', '+X', 'nodatchans', [], ...
        'icachansind', []);
    if ~isempty(o.CoordSys), EEG.chaninfo.coordsys = o.CoordSys; end
    if strcmp(eeg.reference, 'average of all channels')
        EEG.ref = 'average';
    elseif strcmp(eeg.reference, 'unknown')
        EEG.ref = 'common';
    else
        EEG.ref = eeg.reference;
    end

    % ---- Events ----
    ev = struct('type', {}, 'latency', {}, 'duration', {}, 'urevent', {}, 'epoch', {});
    ep = struct('event', {}, 'eventtype', {}, 'eventlatency', {}, 'eventduration', {});
    if eeg.isEpoched
        z = round(-xmin * fs) + 1;
        for e = 1:tr
            ev(e) = struct('type', eeg.trials.condition{e}, 'latency', (e - 1) * pnts + z, ...
                'duration', 0, 'urevent', e, 'epoch', e);
            ep(e) = struct('event', e, 'eventtype', {eeg.trials.condition(e)}, ...
                'eventlatency', {{0}}, 'eventduration', {{0}});
        end
    else
        for k = 1:numel(eeg.events)
            ev(k) = struct('type', eeg.events(k).type, ...
                'latency', (eeg.events(k).latency - xmin) * fs + 1, ...
                'duration', eeg.events(k).duration * fs, 'urevent', k, 'epoch', []);
        end
        ev = rmfield(ev, 'epoch');
    end
    EEG.event = ev;
    EEG.urevent = [];
    EEG.eventdescription = {};
    EEG.epoch = ep;
    EEG.epochdescription = {};
    EEG.reject = [];
    EEG.stats = [];
    EEG.specdata = [];
    EEG.specicaact = [];
    EEG.splinefile = '';
    EEG.icasplinefile = '';
    EEG.dipfit = [];
    EEG.history = o.History;
    EEG.saved = 'justloaded';
    EEG.etc = struct();
    EEG.run = [];
    EEG.datfile = '';

    out = struct('set', fullfile(folder, [base '.set']), 'fdt', '');
    if o.DataFile
        fdt = fullfile(folder, [base '.fdt']);
        fid = fopen(fdt, 'w', 'ieee-le');
        if fid < 0
            error('NeuroAnalyzer:io:fileNotFound', 'Cannot write %s', fdt);
        end
        fwrite(fid, reshape(single(eeg.data), nb, pnts * tr), 'float32');
        fclose(fid);
        EEG.data = [base '.fdt'];
        EEG.datfile = [base '.fdt'];
        out.fdt = fdt;
    else
        EEG.data = single(eeg.data);
    end
    if strcmpi(o.Layout, 'fields')
        save(out.set, '-struct', 'EEG', '-mat', '-v7');
    else
        save(out.set, 'EEG', '-mat', '-v7');
    end
end

%% chanlocs - EEGLAB chanlocs from eeg.chanlocs (theta / radius from X, Y, Z)
function cl = chanlocs(eeg)
    n = numel(eeg.labels);
    cl = struct('labels', eeg.labels, 'type', 'EEG', 'theta', [], 'radius', [], ...
        'X', [], 'Y', [], 'Z', [], 'sph_theta', [], 'sph_phi', [], 'sph_radius', [], ...
        'urchan', num2cell(1:n), 'ref', '');
    for k = 1:n
        L = eeg.chanlocs(k);
        if ~all(isfinite([L.x L.y L.z])), continue; end
        cl(k).X = L.x; cl(k).Y = L.y; cl(k).Z = L.z;
        r = sqrt(L.x^2 + L.y^2 + L.z^2);
        az = atan2(L.y, L.x) * 180 / pi;              % positive towards the left ear
        el = asin(L.z / max(r, eps)) * 180 / pi;
        cl(k).sph_theta = az;
        cl(k).sph_phi = el;
        cl(k).sph_radius = r;
        if isfinite(L.theta), cl(k).theta = L.theta; else, cl(k).theta = -az; end
        if isfinite(L.radius), cl(k).radius = L.radius; else, cl(k).radius = 0.5 - el / 180; end
    end
end
