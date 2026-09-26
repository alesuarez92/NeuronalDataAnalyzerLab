%% writeBrainVision.m
% =========================================================================
% WRITE BRAINVISION - AN EEG STRUCT AS .vhdr + .vmrk + .eeg
% =========================================================================
% out = writeBrainVision(file, eeg, Name, Value, ...)
%
% file: the header path (.vhdr); the .vmrk and .eeg files get the same
% name. eeg: the common EEG struct (EEGSource.make), in microvolts.
% Continuous data: a New Segment marker at the first sample, then one
% Stimulus marker per event (description = event type). Trials: written
% as an Analyzer export (SegmentationType MARKERBASED): per segment a New
% Segment marker, a Stimulus marker with the trial's condition at time 0
% and a Time 0 marker.
%
% Options:
%   'BinaryFormat'  'IEEE_FLOAT_32' (default), 'INT_16' or 'INT_32'
%   'Resolution'    microvolts per stored unit (default 1 for floats, 0.1
%                   for integers); values are rounded to it
%   'Orientation'   'MULTIPLEXED' (default) or 'VECTORIZED'
%   'Positions'     channels x 3 positions, x = right ear, y = nose, z = up
%                   (any unit; written as radius, theta, phi), or [] (none)
%   'Reference'     name of the reference channel for every channel, or ''
%   'Comment'       cell of lines for the [Comment] section
%   'Version'       1 (default, Latin-1) or 2 (UTF-8)
%
% out: struct with vhdr, vmrk and eeg paths.
% Toolboxes: none. Used by core/demo/demoEEG and the EEG tests.
% =========================================================================

function out = writeBrainVision(file, eeg, varargin)
    o = struct('BinaryFormat', 'IEEE_FLOAT_32', 'Resolution', [], 'Orientation', 'MULTIPLEXED', ...
        'Positions', [], 'Reference', '', 'Comment', {{}}, 'Version', 1);
    o = EEGSource.options(o, varargin);
    [folder, base] = fileparts(file);
    if isempty(folder), folder = pwd; end
    out = struct('vhdr', fullfile(folder, [base '.vhdr']), 'vmrk', fullfile(folder, [base '.vmrk']), ...
        'eeg', fullfile(folder, [base '.eeg']));
    [nCh, nS, nTr] = size(eeg.data);
    bf = upper(o.BinaryFormat);
    switch bf
        case 'IEEE_FLOAT_32', prec = 'float32'; lim = Inf; defRes = 1;
        case 'INT_16', prec = 'int16'; lim = 32767; defRes = 0.1;
        case 'INT_32', prec = 'int32'; lim = 2^31 - 1; defRes = 0.1;
        otherwise, error('NeuroAnalyzer:eeg:badOption', 'Unknown BinaryFormat ''%s''.', o.BinaryFormat);
    end
    res = o.Resolution;
    if isempty(res), res = defRes; end
    mu = char(181);

    % ---- Numbers: segments one after the other ----
    X = double(reshape(eeg.data, nCh, nS * nTr)) / res;
    if isfinite(lim)
        X = round(X);
        if any(abs(X(:)) > lim)
            error('NeuroAnalyzer:eeg:badOption', ['The values do not fit in %s with a resolution of %g ' ...
                'uV; use a coarser resolution or IEEE_FLOAT_32.'], bf, res);
        end
    end
    if strcmpi(o.Orientation, 'VECTORIZED'), X = X'; end
    fid = fopen(out.eeg, 'w', 'ieee-le');
    if fid < 0, error('NeuroAnalyzer:eeg:write', 'Cannot write %s', out.eeg); end
    fwrite(fid, X, prec);
    fclose(fid);

    % ---- Header ----
    if o.Version == 2
        L = {'BrainVision Data Exchange Header File Version 2.0'};
    else
        L = {'Brain Vision Data Exchange Header File Version 1.0'};
    end
    L = [L, {'; Data written by NeuroAnalyzer (writeBrainVision)', '', '[Common Infos]'}];
    if o.Version == 2, L{end + 1} = 'Codepage=UTF-8'; end
    L = [L, {['DataFile=' base '.eeg'], ['MarkerFile=' base '.vmrk'], 'DataFormat=BINARY', ...
        ['DataOrientation=' upper(o.Orientation)], 'DataType=TIMEDOMAIN', sprintf('NumberOfChannels=%d', nCh), ...
        sprintf('SamplingInterval=%.10g', 1e6 / eeg.fs)}];
    if eeg.isEpoched
        L = [L, {'SegmentationType=MARKERBASED', sprintf('SegmentDataPoints=%d', nS)}];
    end
    L = [L, {'', '[Binary Infos]', ['BinaryFormat=' bf], '', '[Channel Infos]', ...
        '; Each entry: Ch<Channel number>=<Name>,<Reference channel name>,<Resolution in "Unit">,<Unit>'}];
    for c = 1:nCh
        L{end + 1} = sprintf('Ch%d=%s,%s,%.10g,%sV', c, strrep(eeg.labels{c}, ',', '\1'), o.Reference, res, mu); %#ok<AGROW>
    end
    P = o.Positions;
    if ~isempty(P)
        L = [L, {'', '[Coordinates]'}];
        for c = 1:nCh
            [r, th, ph] = toSpherical(P(c, :));
            L{end + 1} = sprintf('Ch%d=%.10g,%.10g,%.10g', c, r, th, ph); %#ok<AGROW>
        end
    end
    if ~isempty(o.Comment)
        L = [L, {'', '[Comment]'}, EEGSource.cellRow(o.Comment)];
    end
    writeText(out.vhdr, L, o.Version);

    % ---- Markers ----
    if o.Version == 2
        K = {'BrainVision Data Exchange Marker File, Version 2.0'};
    else
        K = {'Brain Vision Data Exchange Marker File, Version 1.0'};
    end
    K = [K, {'', '[Common Infos]'}];
    if o.Version == 2, K{end + 1} = 'Codepage=UTF-8'; end
    K = [K, {['DataFile=' base '.eeg'], '', '[Marker Infos]', ...
        '; Each entry: Mk<Marker number>=<Type>,<Description>,<Position in data points>,<Size in data points>,<Channel number (0 = marker is related to all channels)>'}];
    n = 0;
    if eeg.isEpoched
        [~, t0] = min(abs(eeg.times));
        for k = 1:nTr
            s0 = (k - 1) * nS;
            n = n + 1; K{end + 1} = sprintf('Mk%d=New Segment,,%d,1,0', n, s0 + 1); %#ok<AGROW>
            n = n + 1; K{end + 1} = sprintf('Mk%d=Stimulus,%s,%d,1,0', n, esc(eeg.trials.condition{k}), s0 + t0); %#ok<AGROW>
            n = n + 1; K{end + 1} = sprintf('Mk%d=Time 0,,%d,1,0', n, s0 + t0); %#ok<AGROW>
        end
    else
        n = n + 1; K{end + 1} = sprintf('Mk%d=New Segment,,1,1,0', n);
        for k = 1:numel(eeg.events)
            e = eeg.events(k);
            pts = max(1, round(e.duration * eeg.fs));
            n = n + 1;
            K{end + 1} = sprintf('Mk%d=Stimulus,%s,%d,%d,0', n, esc(e.type), round(e.latency * eeg.fs) + 1, pts); %#ok<AGROW>
        end
    end
    writeText(out.vmrk, K, o.Version);
end

%% toSpherical - x right, y nose, z up -> BrainVision radius, theta, phi (degrees)
% theta: angle from the vertex, negative on the left; phi: angle from the
% right ear towards the nose (from the left ear for left electrodes).
function [r, th, ph] = toSpherical(p)
    r = norm(p);
    if r == 0, th = 0; ph = 0; return; end
    th = acosd(max(-1, min(1, p(3) / r)));
    sg = 1;
    if p(1) < -1e-12 * r, sg = -1; end
    th = sg * th;
    ph = atan2d(sg * p(2), sg * p(1));
    if abs(th) < 1e-9, ph = 0; end
end

%% esc - Commas inside a marker description are written as \1
function s = esc(s)
    s = strrep(s, ',', '\1');
end

%% writeText - Lines as Latin-1 (version 1) or UTF-8 (version 2), CRLF as BrainVision does
function writeText(p, lines, version)
    txt = [strjoin(lines, sprintf('\r\n')) sprintf('\r\n')];
    b = uint8(double(txt));                      % the text holds Latin-1 characters only (e.g. the micro sign)
    if version == 2                              % UTF-8: each byte above 127 becomes two bytes
        hi = b > 127;
        v = double(b);
        c = num2cell(v);
        c(hi) = arrayfun(@(x) [192 + floor(x / 64), 128 + mod(x, 64)], v(hi), 'UniformOutput', false);
        b = uint8([c{:}]);
    end
    fid = fopen(p, 'w');
    if fid < 0, error('NeuroAnalyzer:eeg:write', 'Cannot write %s', p); end
    fwrite(fid, b, 'uint8');
    fclose(fid);
end
