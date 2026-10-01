%% readElectrodes.m
% =========================================================================
% READ ELECTRODES - ELECTRODE POSITIONS FROM A CAP, DIGITIZER OR TABLE FILE
% =========================================================================
% P = readElectrodes(file)
% P = readElectrodes(file, 'Format', fmt)
%
% file: a file of electrode positions. The format comes from the extension,
% or from 'Format' ('auto' (default), 'elc', 'sfp', 'loc', 'locs', 'ced',
% 'xyz', 'elp', 'bvef', 'csv', 'tsv' or 'txt'):
%   .elc   ASA / ANT / FieldTrip / MNE: UnitPosition (mm, cm or m), a
%          Positions section (x y z, or label : x y z) and a Labels
%          section; x = right ear, y = nose, z = up is assumed
%   .sfp   BESA / EGI: label x y z per line, x = right ear, y = nose,
%          z = up; the unit is not stated (EGI HydroCel files are in cm)
%   .loc / .locs  EEGLAB polar: number theta radius label; theta in
%          degrees from the nose (+90 = right ear), radius = angle from the
%          vertex / 180 (0.5 = 90 deg); dots padding the names are removed
%   .ced   EEGLAB channel table: a header row (Number labels theta radius X
%          Y Z sph_theta sph_phi sph_radius type, any order), X / Y / Z
%          with x = nose, y = left ear, else theta / radius as in .loc;
%          rows of type FID are fiducials
%   .xyz   EEGLAB: number X Y Z label (x = nose, y = left ear)
%   .elp   BESA spherical: [type] label theta phi [radius]; theta = angle
%          from the vertex, negative on the left; phi = angle from the
%          right ear towards the nose. Polhemus .elp files are refused.
%   .bvef  BrainVision electrode file (XML: Name, Theta, Phi, Radius in
%          mm; Radius 0, 1 or missing = direction only), BESA angles
%   .txt   'Site Theta Phi' lists (EasyCap, BioSemi): BESA angles
%   .csv / .tsv / other .txt: a header row with a name column (name,
%          label, channel, electrode or site) and x, y, z (x = right ear,
%          y = nose, z = up; unit from a unit column or a header such as
%          'x (mm)'), or theta and phi (BESA), or theta and radius (EEGLAB
%          polar), or ap and ml (skull: mm from bregma, anterior +, right
%          +). A BIDS *_electrodes.tsv is read as stored; when its
%          *_coordsystem.json is next to it, its units are used and the
%          systems with x = nose, y = left ear (CTF, 4DBti, KitYokogawa,
%          EEGLAB, EEGLAB-HJ) are turned.
% Positions with x, y, z that all lie in one plane (same z) are read as a
% skull layout in mm from bregma. Text may be UTF-8 or Latin-1 (or UTF-16
% with a byte-order mark) with any line endings; a decimal comma is read
% where the separator is not a comma.
%
% P (one row per electrode with a position):
%   P.labels     1 x n cell of names (fiducials and rows without a
%                position left out)
%   P.xyz        n x 3: scalp x = right ear, y = nose, z = up; skull
%                [medial-lateral, anterior-posterior, 0] in mm from bregma
%   P.unit       'mm' | 'cm' | 'm' | '' (directions, or unit not stated)
%   P.kind       'scalp' | 'skull'
%   P.fiducials  struct array label, xyz (Nz / NAS / Nasion / FidNz, LPA /
%                FidT9 / LeftEar, RPA / FidT10 / RightEar), same frame and unit
%   P.format     e.g. 'EEGLAB .loc'
%   P.frame      the conversion done, in words
%   P.notes      1 x n cell of plain sentences (rows left out, units, ...)
%   P.file
% The positions are put on the channels by EEGLayout.fromEEG (option
% 'Positions'). writeElectrodes writes the same formats.
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:eeg:unsupportedFormat
% (unknown format, Polhemus .elp), NeuroAnalyzer:eeg:badElectrodeFile (no
% name column, wrong number of values on a line, no positions),
% NeuroAnalyzer:eeg:badOption. Toolboxes: none; also runs in GNU Octave.
% =========================================================================

function P = readElectrodes(file, varargin)
    o = EEGSource.options(struct('Format', 'auto'), varargin);
    file = char(file);
    if ~(exist(file, 'file') == 2)
        error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', file);
    end
    [~, base, ext] = fileparts(file);
    name = [base ext];
    fmt = formatKey(o.Format, ext, name);
    txt = readText(file);
    lines = regexp(txt, '\r\n|\n|\r', 'split');
    switch fmt
        case 'elc',           R = readElc(lines, name);
        case 'sfp',           R = readSfp(lines, name);
        case {'loc', 'locs'}, R = readLoc(lines, name, fmt);
        case 'ced',           R = readCed(lines, name);
        case 'xyz',           R = readXyz(lines, name);
        case 'elp',           R = readElp(lines, name);
        case 'bvef',          R = readBvef(txt, name);
        otherwise,            R = readTable(lines, name, fmt, file);   % csv, tsv, txt
    end
    P = finish(R, file, name);
end

%% ------------------------------------------------------------------------
%  Formats
%% ------------------------------------------------------------------------

%% formatKey - 'elc', 'sfp', ... from the 'Format' option or the extension
function fmt = formatKey(want, ext, name)
    known = {'elc', 'sfp', 'loc', 'locs', 'ced', 'xyz', 'elp', 'bvef', 'csv', 'tsv', 'txt'};
    list = '.elc, .sfp, .loc, .locs, .ced, .xyz, .elp, .bvef, .csv, .tsv or .txt';
    if isempty(want) || strcmpi(want, 'auto')
        fmt = lower(regexprep(ext, '^\.', ''));
        if ~any(strcmp(fmt, known))
            error('NeuroAnalyzer:eeg:unsupportedFormat', ['%s is not a known electrode file. Electrode ' ...
                'positions are read from %s files; save them in one of these formats, or name the ' ...
                'format with ''Format''.'], name, list);
        end
    else
        fmt = lower(regexprep(strtrim(char(want)), '^\.', ''));
        if ~any(strcmp(fmt, known))
            error('NeuroAnalyzer:eeg:unsupportedFormat', 'Unknown electrode file format ''%s'' (%s).', ...
                char(want), list);
        end
    end
end

%% readElc - ASA .elc: UnitPosition, NumberPositions=, Positions, Labels
function R = readElc(lines, name)
    unitText = '';
    nDecl = NaN;
    mode = '';
    pos = zeros(0, 3);
    inl = {};
    labLines = {};
    keys = '^(UnitPosition|ReferenceLabel|NumberPositions|NumberPolygons|TypePolygons|Positions|Labels|Polygons|NumberHeadShapePoints|HeadShapePoints)\s*(=|\s|$)(.*)$';
    for k = 1:numel(lines)
        t = strtrim(lines{k});
        if isempty(t) || isComment(t), continue; end
        tok = regexpi(t, keys, 'tokens', 'once');
        if ~isempty(tok)
            switch lower(tok{1})
                case 'unitposition',    unitText = strtrim(tok{3});
                case 'numberpositions', nDecl = num(strtrim(tok{3}));
                case 'positions',       mode = 'positions';
                case 'labels',          mode = 'labels';
                case 'referencelabel'
                otherwise,              mode = '';
            end
            continue;
        end
        switch mode
            case 'positions'
                c = find(t == ':', 1);
                if isempty(c)
                    lab = '';
                    v = num(regexp(t, '\s+', 'split'));
                else
                    lab = strtrim(t(1:c - 1));
                    v = num(regexp(strtrim(t(c + 1:end)), '\s+', 'split'));
                end
                if numel(v) ~= 3 || any(~isfinite(v))
                    error('NeuroAnalyzer:eeg:badElectrodeFile', ['Line %d of %s does not read as ''x y z'' ' ...
                        'or ''label : x y z'' (Positions section of an ASA .elc file): %s'], k, name, t);
                end
                pos(end + 1, :) = v(:)'; %#ok<AGROW>
                inl{end + 1} = lab; %#ok<AGROW>
            case 'labels'
                labLines{end + 1} = t; %#ok<AGROW>
        end
    end
    n = size(pos, 1);
    if n == 0
        error('NeuroAnalyzer:eeg:badElectrodeFile', '%s has no Positions section with x y z values (ASA .elc).', name);
    end
    tok = regexp(strtrim(strjoin(labLines, ' ')), '\s+', 'split');
    tok = tok(~cellfun(@isempty, tok));
    if numel(labLines) == n
        labels = labLines;
    elseif numel(tok) == n
        labels = tok;
    elseif isempty(labLines) && all(~cellfun(@isempty, inl))
        labels = inl;
    else
        error('NeuroAnalyzer:eeg:badElectrodeFile', ['%s has %d positions but %d labels; the Labels section ' ...
            'must name every position (ASA .elc).'], name, n, numel(tok));
    end
    notes = {};
    if isfinite(nDecl) && nDecl ~= n
        notes{end + 1} = sprintf('NumberPositions says %d, but %d positions are listed; all listed positions were read.', nDecl, n);
    end
    [unit, unitNote] = unitFromText(unitText, 'UnitPosition');
    notes = [notes, unitNote];
    R = makeR(labels, pos, unit, 'ASA .elc', ...
        'x = right ear, y = nose, z = up, as stored (assumed: .elc files do not state their axes)', notes);
    R.cartesian = true;
end

%% readSfp - BESA / EGI .sfp: label x y z per line
function R = readSfp(lines, name)
    labels = {};
    xyz = zeros(0, 3);
    nHead = 0;
    for k = 1:numel(lines)
        t = strtrim(lines{k});
        if isempty(t) || isComment(t), continue; end
        tok = regexp(t, '\s+', 'split');
        v = num(tok(max(1, end - 2):end));
        if numel(tok) < 4 || any(~isfinite(v))
            error('NeuroAnalyzer:eeg:badElectrodeFile', ['Line %d of %s does not read as ''name x y z'' ' ...
                '(BESA / EGI .sfp): %s'], k, name, t);
        end
        lab = strjoin(tok(1:end - 3), ' ');
        if strcmpi(lab, 'headshape'), nHead = nHead + 1; continue; end
        labels{end + 1} = lab; %#ok<AGROW>
        xyz(end + 1, :) = v(:)'; %#ok<AGROW>
    end
    notes = {'Units not stated in the file (.sfp files have none; EGI HydroCel files are in cm).'};
    if nHead > 0
        notes{end + 1} = sprintf('%d head shape point(s) were left out.', nHead);
    end
    R = makeR(labels, xyz, '', 'BESA / EGI .sfp', 'x = right ear, y = nose, z = up, as stored (BESA / EGI .sfp)', notes);
    R.cartesian = true;
end

%% readLoc - EEGLAB .loc / .locs: number theta radius label
function R = readLoc(lines, name, fmt)
    labels = {};
    th = zeros(0, 1);
    rd = zeros(0, 1);
    dots = false;
    for k = 1:numel(lines)
        t = strtrim(lines{k});
        if isempty(t) || isComment(t), continue; end
        tok = regexp(t, '\s+', 'split');
        v = num(tok(1:min(3, end)));
        if numel(tok) < 4 || any(~isfinite(v))
            error('NeuroAnalyzer:eeg:badElectrodeFile', ['Line %d of %s does not read as ''number theta ' ...
                'radius name'' (EEGLAB .%s): %s'], k, name, fmt, t);
        end
        lab = strjoin(tok(4:end), ' ');
        stripped = regexprep(lab, '\.+$', '');
        if ~strcmp(stripped, lab) && ~isempty(stripped), dots = true; lab = stripped; end
        labels{end + 1} = lab; %#ok<AGROW>
        th(end + 1, 1) = v(2); %#ok<AGROW>
        rd(end + 1, 1) = v(3); %#ok<AGROW>
    end
    notes = {};
    if dots, notes{end + 1} = 'Dots padding the channel names (EEGLAB .loc style, e.g. ''Fz..'') were removed.'; end
    R = makeR(labels, polarToRAS(th, rd), '', ['EEGLAB .' fmt], polarFrame(), notes);
end

%% readCed - EEGLAB .ced channel table (tab-separated, header row)
function R = readCed(lines, name)
    T = parseTable(lines, sprintf('\t'), name);
    R = cedTable(T, name, 'EEGLAB .ced');
end

%% cedTable - Rows of an EEGLAB channel table: X / Y / Z, else theta / radius
function R = cedTable(T, name, format)
    cn = find(ismember(T.keys, {'labels', 'label', 'name'}), 1);
    if isempty(cn)
        error('NeuroAnalyzer:eeg:badElectrodeFile', ['%s has no ''labels'' column in its first row ' ...
            '(EEGLAB channel table; found: %s).'], name, strjoin(T.heads, ', '));
    end
    c = @(k) find(strcmp(T.keys, k), 1);
    cX = c('x'); cY = c('y'); cZ = c('z'); cTh = c('theta'); cR = c('radius'); cT = c('type');
    checkRows(T, cn, name);
    labels = colText(T, cn);
    n = numel(labels);
    E = colNum(T, [cX cY cZ]);
    if size(E, 2) < 3, E = NaN(n, 3); end
    A = colNum(T, [cTh cR]);
    if size(A, 2) < 2, A = NaN(n, 2); end
    hasXYZ = all(isfinite(E), 2);
    hasPolar = ~hasXYZ & all(isfinite(A), 2);
    isFid = isFiducial(labels);
    if ~isempty(cT), isFid = isFid | strcmpi(colText(T, cT), 'FID'); end
    xyz = NaN(n, 3);
    xyz(hasXYZ, :) = [-E(hasXYZ, 2), E(hasXYZ, 1), E(hasXYZ, 3)];
    xyz(hasPolar, :) = polarToRAS(A(hasPolar, 1), A(hasPolar, 2));
    notes = {};
    if any(hasXYZ)
        frame = 'EEGLAB (x = nose, y = left ear, z = up) turned to x = right ear, y = nose, z = up';
        r = sqrt(sum(xyz(hasXYZ & ~isFid(:), :) .^ 2, 2));
        if isempty(r), r = sqrt(sum(xyz(hasXYZ, :) .^ 2, 2)); end
        if any(hasPolar)
            xyz(hasPolar, :) = xyz(hasPolar, :) * median(r);
            notes{end + 1} = sprintf(['%d channel(s) had only theta and radius (no X, Y, Z); they were put ' ...
                'on a sphere of the median radius of the others.'], sum(hasPolar));
        end
        if any(abs(r - 1) > 1e-3)
            notes{end + 1} = 'Units not stated in the file (EEGLAB files have none).';
        end
    else
        frame = polarFrame();
    end
    R = makeR(labels, xyz, '', format, frame, notes);
    R.cartesian = any(hasXYZ) && ~any(hasPolar);
    R.isFid = isFid;
end

%% readXyz - EEGLAB .xyz: number X Y Z label (x = nose, y = left ear)
function R = readXyz(lines, name)
    labels = {};
    xyz = zeros(0, 3);
    for k = 1:numel(lines)
        t = strtrim(lines{k});
        if isempty(t) || isComment(t), continue; end
        tok = regexp(t, '\s+', 'split');
        v = num(tok(1:min(4, end)));
        if numel(tok) < 5 || any(~isfinite(v))
            error('NeuroAnalyzer:eeg:badElectrodeFile', ['Line %d of %s does not read as ''number X Y Z ' ...
                'name'' (EEGLAB .xyz): %s'], k, name, t);
        end
        labels{end + 1} = strjoin(tok(5:end), ' '); %#ok<AGROW>
        xyz(end + 1, :) = [-v(3), v(2), v(4)]; %#ok<AGROW>
    end
    notes = {};
    if ~isempty(xyz) && any(abs(sqrt(sum(xyz .^ 2, 2)) - 1) > 1e-3)
        notes{end + 1} = 'Units not stated in the file (EEGLAB files have none).';
    end
    R = makeR(labels, xyz, '', 'EEGLAB .xyz', ...
        'EEGLAB (x = nose, y = left ear, z = up) turned to x = right ear, y = nose, z = up', notes);
    R.cartesian = true;
end

%% readElp - BESA spherical .elp: [type] label theta phi [radius]
function R = readElp(lines, name)
    data = {};
    lineNo = [];
    for k = 1:numel(lines)
        t = strtrim(lines{k});
        if isempty(t), continue; end
        if t(1) == '%' || strncmp(t, '//', 2)
            polhemus(name);
        end
        if t(1) == '#' || t(1) == ';', continue; end
        data{end + 1} = t; %#ok<AGROW>
        lineNo(end + 1) = k; %#ok<AGROW>
    end
    if ~isempty(data)
        tok = regexp(data{1}, '\s+', 'split');
        if all(isfinite(num(tok)))
            if numel(tok) >= 2, polhemus(name); end
            data = data(2:end);                   % a count of electrodes
            lineNo = lineNo(2:end);
        end
    end
    n = numel(data);
    labels = cell(1, n);
    ang = NaN(n, 2);
    rad = NaN(n, 1);
    for k = 1:n
        tok = regexp(data{k}, '\s+', 'split');
        switch numel(tok)
            case 3, lab = tok{1}; v = num(tok(2:3));
            case 4
                if isfinite(num(tok{2}))          % label theta phi radius
                    lab = tok{1}; v = num(tok(2:4));
                else                              % type label theta phi
                    lab = tok{2}; v = num(tok(3:4));
                end
            case 5, lab = tok{2}; v = num(tok(3:5));
            otherwise, v = NaN;
        end
        if numel(v) < 2 || any(~isfinite(v(1:2)))
            error('NeuroAnalyzer:eeg:badElectrodeFile', ['Line %d of %s does not read as ''[type] name theta ' ...
                'phi [radius]'' (BESA .elp): %s'], lineNo(k), name, data{k});
        end
        labels{k} = lab;
        ang(k, :) = v(1:2);
        if numel(v) >= 3, rad(k) = v(3); end
    end
    [xyz, unit, notes] = besaPositions(ang(:, 1), ang(:, 2), rad, '');
    R = makeR(labels, xyz, unit, 'BESA .elp', besaFrame(), notes);
end

%% polhemus - A Polhemus .elp is not a BESA electrode file
function polhemus(name)
    error('NeuroAnalyzer:eeg:unsupportedFormat', ['%s is a Polhemus digitizer .elp file, not a BESA ' ...
        'electrode file. Open it in the digitizer software (or in EEGLAB / FieldTrip) and export the ' ...
        'positions as .sfp or .elc.'], name);
end

%% readBvef - BrainVision electrode file (XML): Name, Theta, Phi, Radius
function R = readBvef(txt, name)
    blocks = regexp(txt, '<Electrode(?:\s[^>]*)?>([\s\S]*?)</Electrode>', 'tokens');
    if isempty(blocks)
        error('NeuroAnalyzer:eeg:badElectrodeFile', '%s has no <Electrode> entries (BrainVision .bvef).', name);
    end
    n = numel(blocks);
    labels = cell(1, n);
    ang = NaN(n, 2);
    rad = NaN(n, 1);
    for k = 1:n
        b = blocks{k}{1};
        labels{k} = xmlText(xmlTag(b, 'Name'));
        ang(k, :) = [num(xmlTag(b, 'Theta')), num(xmlTag(b, 'Phi'))];
        rad(k) = num(xmlTag(b, 'Radius'));
    end
    [xyz, unit, notes] = besaPositions(ang(:, 1), ang(:, 2), rad, 'mm');
    R = makeR(labels, xyz, unit, 'BrainVision .bvef', besaFrame(), notes);
end

%% xmlTag - Text inside <tag>...</tag> ('' when missing)
function s = xmlTag(b, tag)
    tok = regexpi(b, ['<' tag '>([\s\S]*?)</' tag '>'], 'tokens', 'once');
    s = '';
    if ~isempty(tok), s = strtrim(tok{1}); end
end

%% xmlText - XML entities to characters
function s = xmlText(s)
    s = strrep(s, '&lt;', '<');
    s = strrep(s, '&gt;', '>');
    s = strrep(s, '&quot;', '"');
    s = strrep(s, '&apos;', '''');
    s = strrep(s, '&amp;', '&');
end

%% ------------------------------------------------------------------------
%  Tables (.csv, .tsv, .txt)
%% ------------------------------------------------------------------------

%% readTable - Header row, a name column and x/y/z, theta/phi, theta/radius or ap/ml
function R = readTable(lines, name, fmt, file)
    T = parseTable(lines, '', name, fmt);
    if any(strcmp(T.keys, 'sphtheta')) || all(ismember({'labels', 'theta', 'radius', 'x', 'y', 'z'}, T.keys))
        R = cedTable(T, name, sprintf('EEGLAB channel table (.%s)', fmt));
        return;
    end
    cn = find(ismember(T.keys, {'name', 'names', 'label', 'labels', 'channel', 'channels', 'channelname', ...
        'chname', 'electrode', 'electrodes', 'electrodename', 'site', 'sites', 'sensor'}), 1);
    if isempty(cn)
        error('NeuroAnalyzer:eeg:badElectrodeFile', ['%s has no column of electrode names. The first row ' ...
            'must name the columns, one of them name, label, channel, electrode or site (found: %s).'], ...
            name, strjoin(T.heads, ', '));
    end
    c = @(varargin) find(ismember(T.keys, varargin), 1);
    cAP = c('ap', 'anteriorposterior'); cML = c('ml', 'mediolateral', 'mediallateral');
    cX = c('x'); cY = c('y'); cZ = c('z');
    cTh = c('theta'); cPh = c('phi'); cR = c('radius');
    cU = c('unit', 'units');
    labels = colText(T, cn);
    n = numel(labels);
    notes = {};
    isBIDS = strcmp(fmt, 'tsv') && ~isempty(regexpi(name, '_electrodes\.tsv$', 'once'));
    format = sprintf('Table (.%s)', fmt);
    if isBIDS, format = 'BIDS electrodes.tsv'; end
    if ~isempty(cAP) && ~isempty(cML)
        checkRows(T, [cn cAP cML], name);
        V = colNum(T, [cML cAP]);
        units = rowUnits(T, [cAP cML], cU, n);
        f = toMm(units);
        if any(cellfun(@isempty, cellfun(@unitKey, units, 'UniformOutput', false)))
            notes{end + 1} = 'The file does not state the unit of ap and ml (mm, cm or m); millimetres were assumed.';
        end
        R = makeR(labels, [V .* [f f], zeros(n, 1)], 'mm', format, skullFrame(), notes);
        R.kind = 'skull';
    elseif ~isempty(cX) && ~isempty(cY) && ~isempty(cZ)
        checkRows(T, [cn cX cY cZ], name);
        xyz = colNum(T, [cX cY cZ]);
        units = rowUnits(T, [cX cY cZ], cU, n);
        frame = 'x = right ear, y = nose, z = up, as stored (assumed for tables with x, y, z)';
        if isBIDS
            [sys, bu] = bidsCoordSystem(file);
            frame = 'x = right ear, y = nose, z = up, as stored (BIDS)';
            if all(cellfun(@isempty, units)) && ~isempty(bu), units = repmat({bu}, n, 1); end
            if ~isempty(sys)
                if any(strcmpi(sys, {'CTF', '4DBti', 'KitYokogawa', 'EEGLAB', 'EEGLAB-HJ'}))
                    xyz = [-xyz(:, 2), xyz(:, 1), xyz(:, 3)];
                    frame = sprintf('BIDS %s (x = nose, y = left ear, z = up) turned to x = right ear, y = nose, z = up', sys);
                else
                    frame = sprintf('BIDS %s: x = right ear, y = nose, z = up, as stored', sys);
                end
            end
        end
        [xyz, unit, un] = commonUnit(xyz, units);
        notes = [notes, un];
        R = makeR(labels, xyz, unit, format, frame, notes);
        R.cartesian = true;
    elseif ~isempty(cTh) && ~isempty(cPh)
        checkRows(T, [cn cTh cPh cR], name);
        A = colNum(T, [cTh cPh]);
        rad = NaN(n, 1);
        if ~isempty(cR), rad = colNum(T, cR); end
        [xyz, unit, notes] = besaPositions(A(:, 1), A(:, 2), rad, '');
        if strcmp(fmt, 'txt'), format = 'Theta / phi list (.txt)'; end
        R = makeR(labels, xyz, unit, format, besaFrame(), notes);
    elseif ~isempty(cTh) && ~isempty(cR)
        checkRows(T, [cn cTh cR], name);
        A = colNum(T, [cTh cR]);
        R = makeR(labels, polarToRAS(A(:, 1), A(:, 2)), '', format, polarFrame(), notes);
    else
        error('NeuroAnalyzer:eeg:badElectrodeFile', ['%s names the electrodes but holds no positions: ' ...
            'expected columns x, y, z, or theta and phi, or theta and radius, or ap and ml (found: %s).'], ...
            name, strjoin(T.heads, ', '));
    end
end

%% parseTable - Header row and rows of fields (delimiter '' = guess from the header)
function T = parseTable(lines, delim, name, fmt)
    if nargin < 4, fmt = ''; end
    keep = false(1, numel(lines));
    for k = 1:numel(lines)
        t = strtrim(lines{k});
        keep(k) = ~isempty(t) && t(1) ~= '#';
    end
    idx = find(keep);
    if isempty(idx)
        error('NeuroAnalyzer:eeg:badElectrodeFile', '%s is empty.', name);
    end
    header = lines{idx(1)};
    tab = sprintf('\t');
    if isempty(delim)
        if strcmp(fmt, 'tsv') || any(header == tab), delim = tab;
        elseif any(header == ';') && (~any(header == ',') || ~strcmp(fmt, 'csv')), delim = ';';
        elseif any(header == ','), delim = ',';
        else, delim = ' ';
        end
    end
    heads = splitFields(header, delim);
    while ~isempty(heads) && isempty(heads{end}), heads(end) = []; end
    keys = cell(size(heads));
    units = cell(size(heads));
    for c = 1:numel(heads)
        h = heads{c};
        tok = regexp(h, '^(.*?)\s*[\(\[]\s*([^\)\]]*?)\s*[\)\]]$', 'tokens', 'once');
        u = '';
        if ~isempty(tok), h = tok{1}; u = tok{2}; end
        keys{c} = lower(regexprep(h, '[^A-Za-z0-9]', ''));
        units{c} = u;
    end
    rows = cell(1, numel(idx) - 1);
    for r = 2:numel(idx)
        f = splitFields(lines{idx(r)}, delim);
        if ~strcmp(delim, ' ') && numel(f) ~= numel(heads)
            g = splitFields(lines{idx(r)}, ' ');          % columns lined up with spaces
            if numel(g) == numel(heads), f = g; end
        end
        rows{r - 1} = f;
    end
    T = struct('heads', {heads}, 'keys', {keys}, 'units', {units}, 'rows', {rows}, ...
        'line', idx(2:end), 'delim', delim);
end

%% splitFields - Fields of one line (delimiter ' ' = any white space); quotes removed
function f = splitFields(line, delim)
    if strcmp(delim, ' ')
        f = regexp(strtrim(line), '\s+', 'split');
        return;
    end
    if ~any(line == '"')
        f = strtrim(strsplit(line, delim, 'CollapseDelimiters', false));
        return;
    end
    f = {};
    cur = '';
    inQ = false;
    k = 1;
    while k <= numel(line)
        ch = line(k);
        if inQ
            if ch == '"' && k < numel(line) && line(k + 1) == '"'
                cur(end + 1) = '"'; k = k + 1; %#ok<AGROW>
            elseif ch == '"'
                inQ = false;
            else
                cur(end + 1) = ch; %#ok<AGROW>
            end
        elseif ch == '"'
            inQ = true;
        elseif ch == delim
            f{end + 1} = strtrim(cur); cur = ''; %#ok<AGROW>
        else
            cur(end + 1) = ch; %#ok<AGROW>
        end
        k = k + 1;
    end
    f{end + 1} = strtrim(cur);
end

%% checkRows - Every row holds the needed columns and no more fields than the header
function checkRows(T, need, name)
    nH = numel(T.heads);
    for r = 1:numel(T.rows)
        f = T.rows{r};
        extra = f(nH + 1:end);
        if numel(f) < max(need) || any(~cellfun(@isempty, extra))
            hint = '';
            if strcmp(T.delim, ',')
                hint = [' (a decimal comma in a comma-separated file splits the numbers: use a semicolon ' ...
                    'or a tab between the columns)'];
            end
            error('NeuroAnalyzer:eeg:badElectrodeFile', 'Line %d of %s has %d values, but the first row names %d columns%s.', ...
                T.line(r), name, numel(f), nH, hint);
        end
    end
end

%% colText - One column as a n x 1 cell ('' for n/a or a missing field)
function v = colText(T, c)
    v = cell(1, numel(T.rows));
    for r = 1:numel(T.rows)
        f = T.rows{r};
        s = '';
        if c <= numel(f), s = f{c}; end
        if strcmpi(s, 'n/a'), s = ''; end
        v{r} = s;
    end
end

%% colNum - Columns as numbers (NaN for n/a or empty)
function V = colNum(T, cols)
    V = NaN(numel(T.rows), numel(cols));
    for j = 1:numel(cols)
        V(:, j) = num(colText(T, cols(j)))';
    end
end

%% rowUnits - Unit of each row: from the headers ('x (mm)'), else the unit column, else ''
function u = rowUnits(T, cols, cU, n)
    hu = T.units(cols);
    hu = hu(~cellfun(@isempty, hu));
    if ~isempty(hu)
        u = repmat(hu(1), n, 1);
    elseif ~isempty(cU)
        u = colText(T, cU)';
    else
        u = repmat({''}, n, 1);
    end
end

%% commonUnit - Keep the rows' unit when they agree, else convert all to mm
function [xyz, unit, notes] = commonUnit(xyz, units)
    notes = {};
    key = cellfun(@unitKey, units, 'UniformOutput', false);
    bad = ~cellfun(@isempty, units) & cellfun(@isempty, key);
    if any(bad)
        notes{end + 1} = sprintf('Unit ''%s'' is not a length unit (mm, cm or m); it was ignored.', units{find(bad, 1)});
    end
    u = unique(key(~cellfun(@isempty, key)));
    if isempty(u)
        unit = '';
    elseif numel(u) == 1 && ~any(cellfun(@isempty, key))
        unit = u{1};
    else
        f = toMm(units);
        xyz = xyz .* [f f f];
        unit = 'mm';
        notes{end + 1} = 'The rows used different units; all positions were converted to mm.';
    end
end

%% toMm - Factor of each row to mm ('' or unknown: 1)
function f = toMm(units)
    f = ones(numel(units), 1);
    for k = 1:numel(units)
        switch unitKey(units{k})
            case 'cm', f(k) = 10;
            case 'm',  f(k) = 1000;
        end
    end
end

%% bidsCoordSystem - EEGCoordinateSystem and EEGCoordinateUnits of the *_coordsystem.json next to it
function [sys, unit] = bidsCoordSystem(file)
    sys = '';
    unit = '';
    j = regexprep(file, '_electrodes\.tsv$', '_coordsystem.json', 'ignorecase');
    if ~(exist(j, 'file') == 2)
        d = dir(fullfile(fileparts(file), '*_coordsystem.json'));
        if numel(d) ~= 1, return; end
        j = fullfile(fileparts(file), d(1).name);
    end
    try
        txt = readText(j);
    catch
        return;
    end
    tok = regexp(txt, '"EEGCoordinateSystem"\s*:\s*"([^"]*)"', 'tokens', 'once');
    if ~isempty(tok), sys = strtrim(tok{1}); end
    tok = regexp(txt, '"EEGCoordinateUnits"\s*:\s*"([^"]*)"', 'tokens', 'once');
    if ~isempty(tok), unit = unitKey(tok{1}); end
    if strcmpi(sys, 'n/a') || strcmpi(sys, 'Other'), sys = ''; end
end

%% ------------------------------------------------------------------------
%  Angles, units, result
%% ------------------------------------------------------------------------

%% polarToRAS - EEGLAB polar (theta from the nose, +90 = right ear; radius = angle from the vertex / 180)
function xyz = polarToRAS(theta, radius)
    p = radius(:) * 180;
    t = theta(:);
    xyz = [sind(p) .* sind(t), sind(p) .* cosd(t), cosd(p)];
end

%% besaPositions - BESA theta / phi (degrees) with an optional radius
% theta: angle from the vertex, negative on the left; phi: angle from the
% right ear towards the nose (from the left ear for left electrodes).
% A radius of 0, 1 or none means a direction only.
function [xyz, unit, notes] = besaPositions(theta, phi, rad, radiusUnit)
    notes = {};
    t = theta(:);
    f = phi(:);
    xyz = [sind(t) .* cosd(f), sind(t) .* sind(f), cosd(t)];
    rad = rad(:);
    given = isfinite(rad) & rad ~= 0;
    unit = '';
    if any(given & abs(rad - 1) > 1e-9)
        rm = median(rad(given));
        rad(~given) = rm;
        xyz = xyz .* [rad rad rad];
        if any(~given)
            notes{end + 1} = sprintf(['%d electrode(s) had no radius; they were put at the median radius ' ...
                'of the others.'], sum(~given));
        end
        unit = radiusUnit;
        if isempty(unit), notes{end + 1} = 'The radius is given, but its unit is not stated in the file.'; end
    end
end

%% unitFromText - 'mm' | 'cm' | 'm' from a unit text, with a note when missing or unknown
function [unit, notes] = unitFromText(s, what)
    notes = {};
    unit = unitKey(s);
    if isempty(s)
        notes{end + 1} = sprintf('The file does not state the unit (no %s line).', what);
    elseif isempty(unit)
        notes{end + 1} = sprintf('Unit ''%s'' (%s) is not mm, cm or m; it was ignored.', s, what);
    end
end

%% unitKey - 'mm', 'cm', 'm' or '' (not a known length unit)
function k = unitKey(s)
    s = lower(strtrim(char(s)));
    switch s
        case {'mm', 'millimeter', 'millimeters', 'millimetre', 'millimetres'}, k = 'mm';
        case {'cm', 'centimeter', 'centimeters', 'centimetre', 'centimetres'}, k = 'cm';
        case {'m', 'meter', 'meters', 'metre', 'metres'},                      k = 'm';
        otherwise, k = '';
    end
end

%% polarFrame / besaFrame / skullFrame - P.frame texts
function s = polarFrame()
    s = ['EEGLAB polar (theta from the nose, +90 = right ear; radius = angle from the vertex / 180) ' ...
        'turned to x = right ear, y = nose, z = up'];
end

function s = besaFrame()
    s = ['BESA angles (theta from the vertex, negative on the left; phi from the right ear towards the ' ...
        'nose) turned to x = right ear, y = nose, z = up'];
end

function s = skullFrame()
    s = 'mm from bregma: x = medial-lateral (right +), y = anterior-posterior (anterior +)';
end

%% makeR - What a format reader returns before the common checks
function R = makeR(labels, xyz, unit, format, frame, notes)
    labels = labels(:)';
    R = struct('labels', {labels}, 'xyz', xyz, 'isFid', false(1, numel(labels)), 'unit', unit, ...
        'kind', 'scalp', 'format', format, 'frame', frame, 'notes', {notes}, 'cartesian', false);
end

%% finish - Fiducials apart, rows without a position left out, planar layouts as skull, notes
function P = finish(R, file, name)
    labels = R.labels;
    xyz = R.xyz;
    notes = R.notes;
    unit = R.unit;
    kind = R.kind;
    frame = R.frame;
    isF = R.isFid(:)' | isFiducial(labels);
    ok = all(isfinite(xyz), 2)';
    named = ~cellfun(@isempty, labels);
    if any(~named & ok)
        notes{end + 1} = sprintf('%d row(s) without a name were left out.', sum(~named & ok));
    end
    missing = labels(~ok & ~isF & named);
    if ~isempty(missing)
        notes{end + 1} = sprintf('No position for %s (left out).', EEGSource.listText(missing));
    end
    fk = isF & ok & named;
    fid = xyz(fk, :);
    fidLab = labels(fk);
    keep = ok & ~isF & named;
    labels = labels(keep);
    xyz = xyz(keep, :);
    if isempty(labels)
        error('NeuroAnalyzer:eeg:badElectrodeFile', '%s holds no electrode positions.', name);
    end
    % Planar layouts (all z equal): skull positions in mm from bregma
    n = size(xyz, 1);
    if strcmp(kind, 'scalp') && R.cartesian && n >= 3 && ...
            all(abs(xyz(:, 3) - xyz(1, 3)) <= 1e-9 * max(1, max(abs(xyz(:)))))
        f = 1;
        switch unit
            case 'cm', f = 10;
            case 'm',  f = 1000;
            case '',   notes{end + 1} = 'The unit is not stated; millimetres from bregma were assumed.';
        end
        xyz = [xyz(:, 1:2) * f, zeros(n, 1)];
        if ~isempty(fid), fid = [fid(:, 1:2) * f, zeros(size(fid, 1), 1)]; end
        unit = 'mm';
        kind = 'skull';
        frame = [frame '; all positions lie in one plane, so they were read as a skull layout in ' skullFrame()];
    end
    % Names used twice
    [~, ~, j] = unique(lower(labels));
    cnt = accumarray(j(:), 1);
    for k = find(cnt(:)' > 1)
        notes{end + 1} = sprintf('%s appears %d times in the file; each is kept.', labels{find(j == k, 1)}, cnt(k)); %#ok<AGROW>
    end
    if isempty(fidLab)
        F = struct('label', {}, 'xyz', {});
    else
        F = struct('label', fidLab, 'xyz', num2cell(fid, 2)');
    end
    if strcmp(kind, 'scalp'), notes = fiducialCheck(F, notes); end
    P = struct();
    P.labels = labels;
    P.xyz = xyz;
    P.unit = unit;
    P.kind = kind;
    P.fiducials = F;
    P.format = R.format;
    P.frame = frame;
    P.notes = notes;
    P.file = file;
end

%% isFiducial - Names of the nasion and the ear points (case ignored)
function tf = isFiducial(labels)
    tf = ismember(lower(labels), {'nz', 'nas', 'nasion', 'fidnz', 'lpa', 'rpa', 'fidt9', 'fidt10', 'leftear', 'rightear'});
end

%% fiducialCheck - A note when the nasion and ears do not point along y = nose, x = right ear
function notes = fiducialCheck(F, notes)
    if isempty(F), return; end
    lab = lower({F.label});
    pick = @(names) F(find(ismember(lab, names), 1));
    nz = pick({'nz', 'nas', 'nasion', 'fidnz'});
    l = pick({'lpa', 'fidt9', 'leftear'});
    r = pick({'rpa', 'fidt10', 'rightear'});
    if isempty(nz) || isempty(l) || isempty(r), return; end
    lr = r.xyz - l.xyz;
    fw = nz.xyz - (l.xyz + r.xyz) / 2;
    [~, a] = max(abs(lr));
    [~, b] = max(abs(fw));
    if a == 1 && lr(1) > 0 && b == 2 && fw(2) > 0, return; end
    if a == 2 && lr(2) < 0 && b == 1 && fw(1) > 0
        notes{end + 1} = ['The fiducials say x = nose and y = left ear (as in CTF or EEGLAB files), not ' ...
            'x = right ear and y = nose; the positions were kept as stored, so check the orientation.'];
    else
        notes{end + 1} = ['The fiducials (nasion, left and right ear) do not point along x = right ear and ' ...
            'y = nose; check the orientation of the layout.'];
    end
end

%% ------------------------------------------------------------------------
%  Text
%% ------------------------------------------------------------------------

%% isComment - Comment lines of the plain-text formats
function tf = isComment(t)
    tf = t(1) == '#' || t(1) == '%' || t(1) == ';' || strncmp(t, '//', 2);
end

%% num - Text to numbers, a decimal comma read as a point (NaN when not a number)
function v = num(c)
    v = str2double(strrep(c, ',', '.'));
end

%% readText - A text file as characters (UTF-16 with a byte-order mark, UTF-8 when valid, else Latin-1)
function txt = readText(p)
    fid = fopen(p, 'r');
    if fid < 0, error('NeuroAnalyzer:io:fileNotFound', 'Cannot open %s', p); end
    b = fread(fid, Inf, '*uint8')';
    fclose(fid);
    if numel(b) >= 2 && (isequal(b(1:2), uint8([255 254])) || isequal(b(1:2), uint8([254 255])))
        enc = 'UTF-16LE';
        if b(1) == 254, enc = 'UTF-16BE'; end
        b = b(3:end);
        b = b(1:2 * floor(numel(b) / 2));
        txt = native2unicode(b, enc);
        txt = txt(:)';
        return;
    end
    if numel(b) >= 3 && isequal(b(1:3), uint8([239 187 191])), b = b(4:end); end   % UTF-8 byte-order mark
    txt = char(b);
    if any(b > 127)
        enc = 'ISO-8859-1';
        if isUtf8(b), enc = 'UTF-8'; end
        try
            txt = native2unicode(b, enc);
        catch
        end
    end
    txt = txt(:)';
end

%% isUtf8 - The bytes form valid UTF-8 multi-byte sequences
function tf = isUtf8(b)
    tf = true;
    k = 1;
    n = numel(b);
    while k <= n
        c = b(k);
        if c < 128, k = k + 1; continue; end
        if c >= 194 && c <= 223, m = 1;
        elseif c >= 224 && c <= 239, m = 2;
        elseif c >= 240 && c <= 244, m = 3;
        else, tf = false; return;
        end
        if k + m > n || any(b(k + 1:k + m) < 128 | b(k + 1:k + m) > 191), tf = false; return; end
        k = k + m + 1;
    end
end
