%% writeElectrodes.m
% =========================================================================
% WRITE ELECTRODES - ELECTRODE POSITIONS IN THE NATIVE CONVENTION OF A FORMAT
% =========================================================================
% out = writeElectrodes(file, labels, xyz, Name, Value, ...)
%
% labels: 1 x n names. xyz: n x 3 positions, x = right ear, y = nose,
% z = up (scalp; any unit), or [medial-lateral, anterior-posterior(, 0)]
% in the unit 'Unit' from bregma (skull). Each format is written in its
% own convention, as the program that makes it does, so readElectrodes
% reads the same positions back:
%   .elc   ASA: UnitPosition, NumberPositions=, Positions (x y z), Labels
%   .sfp   BESA / EGI: label x y z
%   .loc / .locs  EEGLAB polar: number theta radius label (directions)
%   .ced   EEGLAB channel table: X = nose, Y = left ear, Z = up, with
%          theta / radius and sph_theta / sph_phi / sph_radius; fiducials
%          as rows of type FID
%   .xyz   EEGLAB: number X Y Z label (X = nose, Y = left ear)
%   .elp   BESA: EEG label theta phi (and the radius when 'Unit' is set)
%   .bvef  BrainVision electrode file (XML): Theta, Phi and Radius (in mm;
%          1 when 'Unit' is '')
%   .txt   Site Theta Phi (BESA angles); skull: name ap ml (tab-separated)
%   .csv / .tsv  name, x, y, z (the unit in the header, 'x (mm)');
%          skull: name, ap (mm), ml (mm)
%
% Options:
%   'Format'     'auto' (default: from the extension) or 'elc', 'sfp',
%                'loc', 'locs', 'ced', 'xyz', 'elp', 'bvef', 'txt', 'csv', 'tsv'
%   'Unit'       'mm', 'cm', 'm' or '' (default: directions / not stated);
%                the formats with angles only keep the directions
%   'Kind'       'scalp' (default) or 'skull' (.csv, .tsv and .txt only)
%   'Fiducials'  struct array label, xyz (as readElectrodes returns them in
%                P.fiducials), written as named rows; [] = none
% Rows of xyz with NaN are written as n/a (.csv, .tsv), empty (.ced) or
% left out. out: the path written.
% Errors: NeuroAnalyzer:eeg:unsupportedFormat, NeuroAnalyzer:eeg:badOption,
% NeuroAnalyzer:eeg:write. Toolboxes: none; also runs in GNU Octave.
% Used by the electrode tests and the demo.
% =========================================================================

function out = writeElectrodes(file, labels, xyz, varargin)
    o = EEGSource.options(struct('Format', 'auto', 'Unit', '', 'Kind', 'scalp', 'Fiducials', []), varargin);
    file = char(file);
    [~, base, ext] = fileparts(file);
    fmt = formatKey(o.Format, ext, [base ext]);
    labels = EEGSource.cellRow(labels);
    kind = lower(char(o.Kind));
    if ~any(strcmp(kind, {'scalp', 'skull'}))
        error('NeuroAnalyzer:eeg:badOption', 'Kind must be ''scalp'' or ''skull'', not ''%s''.', char(o.Kind));
    end
    unit = lower(strtrim(char(o.Unit)));
    if ~any(strcmp(unit, {'', 'mm', 'cm', 'm'}))
        error('NeuroAnalyzer:eeg:badOption', 'Unit must be ''mm'', ''cm'', ''m'' or '''' (not stated), not ''%s''.', char(o.Unit));
    end
    if ~isnumeric(xyz) || size(xyz, 1) ~= numel(labels) || size(xyz, 2) < 2 || ...
            (strcmp(kind, 'scalp') && size(xyz, 2) ~= 3)
        error('NeuroAnalyzer:eeg:badOption', ['The positions must have one row per name (%d names) and ' ...
            'three columns x, y, z (skull: ml, ap); got %d x %d.'], numel(labels), size(xyz, 1), size(xyz, 2));
    end
    xyz = double(xyz);
    if strcmp(kind, 'skull')
        if ~any(strcmp(fmt, {'csv', 'tsv', 'txt'}))
            error('NeuroAnalyzer:eeg:badOption', ['Skull positions (mm from bregma) are written as .csv, ' ...
                '.tsv or .txt (columns name, ap, ml); .%s holds scalp positions.'], fmt);
        end
        L = skullTable(labels, xyz, unit, fmt);
        writeLines(file, L, false);
        out = file;
        return;
    end
    % Fiducials as named rows (first, as ASA and EGI write them; type FID at the end of a .ced)
    isFid = false(1, numel(labels));
    F = o.Fiducials;
    if ~isempty(F)
        if ~isstruct(F) || ~all(isfield(F, {'label', 'xyz'}))
            error('NeuroAnalyzer:eeg:badOption', 'Fiducials must be a struct array with fields label and xyz.');
        end
        fl = cellfun(@char, {F.label}, 'UniformOutput', false);
        fx = reshape([F.xyz], 3, [])';
        if strcmp(fmt, 'ced')
            labels = [labels, fl]; xyz = [xyz; fx]; isFid = [isFid, true(1, numel(fl))];
        else
            labels = [fl, labels]; xyz = [fx; xyz]; isFid = [true(1, numel(fl)), isFid];
        end
    end
    switch fmt
        case 'elc',           L = elc(labels, xyz, unit);
        case 'sfp',           L = sfp(labels, xyz);
        case {'loc', 'locs'}, L = loc(labels, xyz);
        case 'ced',           L = ced(labels, xyz, isFid);
        case 'xyz',           L = eeglabXyz(labels, xyz);
        case 'elp',           L = elp(labels, xyz, unit);
        case 'bvef',          L = bvef(labels, xyz, unit);
        case 'txt',           L = thetaPhi(labels, xyz);
        otherwise,            L = xyzTable(labels, xyz, unit, fmt);   % csv, tsv
    end
    writeLines(file, L, strcmp(fmt, 'bvef'));
    out = file;
end

%% formatKey - 'elc', 'sfp', ... from the 'Format' option or the extension
function fmt = formatKey(want, ext, name)
    known = {'elc', 'sfp', 'loc', 'locs', 'ced', 'xyz', 'elp', 'bvef', 'csv', 'tsv', 'txt'};
    list = '.elc, .sfp, .loc, .locs, .ced, .xyz, .elp, .bvef, .csv, .tsv or .txt';
    if isempty(want) || strcmpi(want, 'auto')
        fmt = lower(regexprep(ext, '^\.', ''));
        if ~any(strcmp(fmt, known))
            error('NeuroAnalyzer:eeg:unsupportedFormat', ['Cannot write electrode positions as %s: use one ' ...
                'of %s, or name the format with ''Format''.'], name, list);
        end
    else
        fmt = lower(regexprep(strtrim(char(want)), '^\.', ''));
        if ~any(strcmp(fmt, known))
            error('NeuroAnalyzer:eeg:unsupportedFormat', 'Unknown electrode file format ''%s'' (%s).', char(want), list);
        end
    end
end

%% ------------------------------------------------------------------------
%  Formats
%% ------------------------------------------------------------------------

%% elc - ASA electrode file
function L = elc(labels, xyz, unit)
    ok = all(isfinite(xyz), 2);
    L = {'# ASA electrode file', sprintf('ReferenceLabel\tavg')};
    if ~isempty(unit), L{end + 1} = sprintf('UnitPosition\t%s', unit); end
    L = [L, {sprintf('NumberPositions=\t%d', sum(ok)), 'Positions'}];
    for k = find(ok(:)')
        L{end + 1} = sprintf('%s %s %s', n2s(xyz(k, 1)), n2s(xyz(k, 2)), n2s(xyz(k, 3))); %#ok<AGROW>
    end
    L = [L, {'Labels'}, labels(ok)];
end

%% sfp - BESA / EGI: label x y z
function L = sfp(labels, xyz)
    L = {};
    for k = find(all(isfinite(xyz), 2)')
        L{end + 1} = sprintf('%s\t%s\t%s\t%s', labels{k}, n2s(xyz(k, 1)), n2s(xyz(k, 2)), n2s(xyz(k, 3))); %#ok<AGROW>
    end
end

%% loc - EEGLAB polar: number theta radius label
function L = loc(labels, xyz)
    L = {};
    [theta, radius] = toPolar(xyz);
    i = 0;
    for k = find(isfinite(theta(:)'))
        i = i + 1;
        L{end + 1} = sprintf('%d\t%s\t%s\t%s', i, n2s(theta(k)), n2s(radius(k)), labels{k}); %#ok<AGROW>
    end
end

%% ced - EEGLAB channel table (as pop_chanedit saves it)
function L = ced(labels, xyz, isFid)
    tab = sprintf('\t');
    L = {strjoin({'Number', 'labels', 'theta', 'radius', 'X', 'Y', 'Z', 'sph_theta', 'sph_phi', 'sph_radius', 'type'}, tab)};
    [theta, radius] = toPolar(xyz);
    X = xyz(:, 2); Y = -xyz(:, 1); Z = xyz(:, 3);
    for k = 1:numel(labels)
        type = 'EEG';
        if isFid(k), type = 'FID'; end
        if all(isfinite(xyz(k, :)))
            r = norm(xyz(k, :));
            v = {n2s(theta(k)), n2s(radius(k)), n2s(X(k)), n2s(Y(k)), n2s(Z(k)), n2s(atan2d(Y(k), X(k))), ...
                n2s(atan2d(Z(k), hypot(X(k), Y(k)))), n2s(r)};
        else
            v = repmat({''}, 1, 8);
        end
        L{end + 1} = strjoin([{sprintf('%d', k), labels{k}}, v, {type}], tab); %#ok<AGROW>
    end
end

%% eeglabXyz - EEGLAB .xyz: number X Y Z label (X = nose, Y = left ear)
function L = eeglabXyz(labels, xyz)
    L = {};
    i = 0;
    for k = find(all(isfinite(xyz), 2)')
        i = i + 1;
        L{end + 1} = sprintf('%d\t%s\t%s\t%s\t%s', i, n2s(xyz(k, 2)), n2s(-xyz(k, 1)), n2s(xyz(k, 3)), labels{k}); %#ok<AGROW>
    end
end

%% elp - BESA spherical: EEG label theta phi [radius]
function L = elp(labels, xyz, unit)
    L = {};
    for k = find(all(isfinite(xyz), 2)')
        [r, th, ph] = toSpherical(xyz(k, :));
        s = sprintf('EEG\t%s\t%s\t%s', labels{k}, n2s(th), n2s(ph));
        if ~isempty(unit), s = sprintf('%s\t%s', s, n2s(r)); end
        L{end + 1} = s; %#ok<AGROW>
    end
end

%% bvef - BrainVision electrode file (XML)
function L = bvef(labels, xyz, unit)
    f = 1;
    switch unit
        case 'cm', f = 10;
        case 'm',  f = 1000;
    end
    L = {'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>', ...
        '<BrainVisionElectrodeFile Version="1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'};
    i = 0;
    for k = find(all(isfinite(xyz), 2)')
        [r, th, ph] = toSpherical(xyz(k, :));
        if isempty(unit), r = 1; else, r = r * f; end
        i = i + 1;
        L = [L, {sprintf('\t<Electrode>'), sprintf('\t\t<Name>%s</Name>', xmlEscape(labels{k})), ...
            sprintf('\t\t<Theta>%s</Theta>', n2s(th)), sprintf('\t\t<Phi>%s</Phi>', n2s(ph)), ...
            sprintf('\t\t<Radius>%s</Radius>', n2s(r)), sprintf('\t\t<Number>%d</Number>', i), ...
            sprintf('\t</Electrode>')}]; %#ok<AGROW>
    end
    L{end + 1} = '</BrainVisionElectrodeFile>';
end

%% thetaPhi - Site Theta Phi list (EasyCap / BioSemi style, BESA angles)
function L = thetaPhi(labels, xyz)
    L = {sprintf('Site\tTheta\tPhi')};
    for k = find(all(isfinite(xyz), 2)')
        [~, th, ph] = toSpherical(xyz(k, :));
        L{end + 1} = sprintf('%s\t%s\t%s', labels{k}, n2s(th), n2s(ph)); %#ok<AGROW>
    end
end

%% xyzTable - name, x, y, z (.csv comma-separated, .tsv tab-separated)
function L = xyzTable(labels, xyz, unit, fmt)
    d = ',';
    if strcmp(fmt, 'tsv'), d = sprintf('\t'); end
    u = '';
    if ~isempty(unit), u = [' (' unit ')']; end
    L = {strjoin({'name', ['x' u], ['y' u], ['z' u]}, d)};
    for k = 1:numel(labels)
        L{end + 1} = strjoin([{field(labels{k}, d)}, arrayfun(@na, xyz(k, :), 'UniformOutput', false)], d); %#ok<AGROW>
    end
end

%% skullTable - name, ap, ml (mm from bregma unless 'Unit' says otherwise)
function L = skullTable(labels, xyz, unit, fmt)
    d = ',';
    if ~strcmp(fmt, 'csv'), d = sprintf('\t'); end
    if isempty(unit), unit = 'mm'; end
    L = {strjoin({'name', sprintf('ap (%s)', unit), sprintf('ml (%s)', unit)}, d)};
    for k = 1:numel(labels)
        L{end + 1} = strjoin({field(labels{k}, d), na(xyz(k, 2)), na(xyz(k, 1))}, d); %#ok<AGROW>
    end
end

%% ------------------------------------------------------------------------
%  Angles and text
%% ------------------------------------------------------------------------

%% toPolar - x right, y nose, z up -> EEGLAB theta (0 = nose, +90 = right ear) and radius (angle from the vertex / 180)
function [theta, radius] = toPolar(xyz)
    r = sqrt(sum(xyz .^ 2, 2));
    theta = atan2d(xyz(:, 1), xyz(:, 2));
    radius = acosd(max(-1, min(1, xyz(:, 3) ./ r))) / 180;
    theta(r == 0) = NaN;
end

%% toSpherical - x right, y nose, z up -> BESA radius, theta, phi (degrees)
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

%% n2s - A number with up to 6 decimals, trailing zeros removed
function s = n2s(v)
    s = sprintf('%.6f', v);
    if any(s == '.'), s = regexprep(regexprep(s, '0+$', ''), '\.$', ''); end
    if strcmp(s, '-0'), s = '0'; end
end

%% na - A number, or n/a for NaN
function s = na(v)
    if isfinite(v), s = n2s(v); else, s = 'n/a'; end
end

%% field - A name quoted when it holds the delimiter or a quote
function s = field(s, d)
    if any(s == d) || any(s == '"'), s = ['"' strrep(s, '"', '""') '"']; end
end

%% xmlEscape - Characters with a meaning in XML
function s = xmlEscape(s)
    s = strrep(s, '&', '&amp;');
    s = strrep(s, '<', '&lt;');
    s = strrep(s, '>', '&gt;');
end

%% writeLines - Lines as UTF-8 text (CRLF line ends when crlf, as Windows programs write them)
function writeLines(p, lines, crlf)
    nl = sprintf('\n');
    if crlf, nl = sprintf('\r\n'); end
    txt = [strjoin(lines, nl) nl];
    fid = fopen(p, 'w');
    if fid < 0, error('NeuroAnalyzer:eeg:write', 'Cannot write %s', p); end
    fwrite(fid, unicode2native(txt, 'UTF-8'), 'uint8');
    fclose(fid);
end
