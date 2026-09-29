%% readBrainVision.m
% =========================================================================
% READ BRAINVISION - BRAIN PRODUCTS .vhdr + .vmrk + .eeg (RECORDER, ANALYZER)
% =========================================================================
% eeg = readBrainVision(file)
%
% file: the header file (.vhdr). It names the data file (.eeg) and the
% marker file (.vmrk), which are looked for in the same folder (a file with
% the header's own name is used when the named one is missing, e.g. after
% renaming). Versions 1.0 (BrainVision Recorder, Analyzer, EEGLAB / MNE
% exports) and 2.0 (UTF-8) of the header are read.
%
% Data: binary (INT_16, UINT_16, INT_32 or IEEE_FLOAT_32, little- or
% big-endian) or ASCII (any decimal symbol, skipped lines and columns),
% multiplexed or vectorized. Each channel is multiplied by its resolution
% and converted from its unit (nV, uV, mV, V) to microvolts.
%
% Returns the common EEG struct (see EEGSource):
%   - continuous recordings: the Stimulus / Response (and other) markers
%     as events; type = the marker description with spaces collapsed
%     ('S  1' -> 'S 1'); latency and duration in s
%   - segmented data (Analyzer export, SegmentationType MARKERBASED or
%     FIXTIME): one trial per segment, time 0 at the 'Time 0' marker, the
%     condition of a trial = the description of the marker at time 0
%   - channel names, and positions from [Coordinates] (radius, theta, phi
%     in degrees) as x = right ear, y = nose, z = up
%   - reference: the reference channel named in [Channel Infos]
%   - notes: amplifier filters when recording, software filters, pauses,
%     bad intervals, averages, units that are not volts
% Nothing is run and BrainVision software is not needed.
% Errors: NeuroAnalyzer:io:fileNotFound (header, or data file missing),
% NeuroAnalyzer:eeg:notBrainVision, NeuroAnalyzer:eeg:unsupported,
% NeuroAnalyzer:io:truncated. Toolboxes: none.
% =========================================================================

function eeg = readBrainVision(file)
    if ~(exist(file, 'file') == 2)
        error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', file);
    end
    [folder, base, ext] = fileparts(file);
    if ~strcmpi(ext, '.vhdr')
        error('NeuroAnalyzer:eeg:notBrainVision', ['%s is not a BrainVision header. Choose the .vhdr ' ...
            'file (it names the .eeg and .vmrk files next to it).'], [base ext]);
    end
    [H, first] = readIni(file);
    if isempty(regexpi(first, 'Brain ?Vision|Vision Data Exchange', 'once'))
        error('NeuroAnalyzer:eeg:notBrainVision', ['%s does not start like a BrainVision header ' ...
            '("Brain Vision Data Exchange Header File ...").'], [base ext]);
    end
    notes = {};
    history = {};

    % ---- [Common Infos] ----
    nCh = str2double(iniGet(H, 'Common Infos', 'NumberOfChannels', ''));
    if ~(isfinite(nCh) && nCh >= 1)
        error('NeuroAnalyzer:eeg:notBrainVision', 'The header %s does not say how many channels there are.', [base ext]);
    end
    si = str2double(iniGet(H, 'Common Infos', 'SamplingInterval', ''));
    if ~(isfinite(si) && si > 0)
        error('NeuroAnalyzer:eeg:notBrainVision', 'The header %s has no sampling interval.', [base ext]);
    end
    fs = 1e6 / si;                                  % SamplingInterval is in microseconds
    if abs(fs - round(fs)) < 1e-6 * fs, fs = round(fs); end
    dataType = upper(iniGet(H, 'Common Infos', 'DataType', 'TIMEDOMAIN'));
    if ~strcmp(dataType, 'TIMEDOMAIN')
        error('NeuroAnalyzer:eeg:unsupported', ['%s holds %s data; only time-domain EEG (voltages ' ...
            'over time) can be read.'], [base ext], lower(dataType));
    end
    dataFile = findPart(folder, base, iniGet(H, 'Common Infos', 'DataFile', ''), '.eeg', true);
    markerFile = findPart(folder, base, iniGet(H, 'Common Infos', 'MarkerFile', ''), '.vmrk', false);
    if isempty(markerFile)
        notes{end + 1} = 'There is no marker file (.vmrk), so no events or conditions are known.';
    end

    % ---- [Channel Infos] ----
    [labels, refs, res, units] = channelInfos(H, nCh);

    % ---- Numbers ----
    fmt = upper(iniGet(H, 'Common Infos', 'DataFormat', 'BINARY'));
    orient = upper(iniGet(H, 'Common Infos', 'DataOrientation', 'MULTIPLEXED'));
    if ~any(strcmp(orient, {'MULTIPLEXED', 'VECTORIZED'}))
        error('NeuroAnalyzer:eeg:unsupported', 'Unknown DataOrientation ''%s'' in %s.', orient, [base ext]);
    end
    if strcmp(fmt, 'BINARY')
        [X, note] = readBinary(dataFile, H, nCh, orient);
    elseif strcmp(fmt, 'ASCII')
        [X, note] = readAscii(dataFile, H, nCh, orient);
    else
        error('NeuroAnalyzer:eeg:unsupported', 'Unknown DataFormat ''%s'' in %s (BINARY or ASCII).', fmt, [base ext]);
    end
    if ~isempty(note), notes{end + 1} = note; end
    [scale, unitNotes] = unitScale(units, labels);
    notes = [notes, unitNotes];
    X = X .* (res(:) .* scale(:));
    nS = size(X, 2);

    % ---- Markers ----
    M = readMarkers(markerFile);
    seg = upper(iniGet(H, 'Common Infos', 'SegmentationType', 'NOTSEGMENTED'));
    averaged = strcmpi(iniGet(H, 'Common Infos', 'Averaged', 'NO'), 'YES');
    isEp = any(strcmp(seg, {'MARKERBASED', 'FIXTIME'})) || averaged;
    if isEp
        [X, times, cond, epNotes] = segments(X, H, M, fs, base, ext);
        notes = [notes, epNotes];
        events = [];
        if averaged
            n = iniGet(H, 'Common Infos', 'AveragedSegments', '');
            if isempty(n)
                notes{end + 1} = 'The file holds averages (Analyzer), not single trials.';
            else
                notes{end + 1} = sprintf('The file holds averages of %s segments (Analyzer), not single trials.', n);
            end
        end
    else
        times = (0:nS - 1) / fs;
        cond = {};
        [events, evNotes] = continuousEvents(M, fs);
        notes = [notes, evNotes];
    end

    % ---- Positions, reference, recording settings ----
    [locs, coord] = coordinates(H, labels);
    ref = referenceText(refs);
    [recNotes, recHistory] = commentSettings(H);
    notes = [notes, recNotes];
    history = [history, recHistory];
    if strcmp(seg, 'MARKERBASED') || strcmp(seg, 'FIXTIME')
        history{end + 1} = sprintf('Cut into %d segments of %g to %g ms (BrainVision Analyzer segmentation).', ...
            size(X, 3), times(1) * 1000, times(end) * 1000);
    end

    eeg = EEGSource.make(X, fs, 'Times', times, 'Labels', labels, 'Chanlocs', locs, 'CoordSystem', coord, ...
        'Conditions', cond, 'Events', events, 'Reference', ref, 'History', history, 'Notes', notes, ...
        'Unit', 'uV', 'Source', 'BrainVision', 'Format', 'brainvision', 'File', file, 'IsEpoched', isEp);
end

%% ------------------------------------------------------------------------
%  Header (INI-like text)
%% ------------------------------------------------------------------------

%% readIni - Sections of a .vhdr / .vmrk file: H.<section> = {keys; values}, H.raw.<section> = lines
function [H, first] = readIni(p)
    txt = readText(p);
    lines = regexp(txt, '\r\n|\n|\r', 'split');
    first = '';
    if ~isempty(lines), first = strtrim(lines{1}); end
    H = struct('names', {{}}, 'keys', {{}}, 'values', {{}}, 'raw', {{}});
    cur = 0;
    for k = 2:numel(lines)
        L = lines{k};
        t = strtrim(L);
        tok = regexp(t, '^\[(.+)\]$', 'tokens', 'once');
        if ~isempty(tok)
            H.names{end + 1} = strtrim(tok{1});
            H.keys{end + 1} = {}; H.values{end + 1} = {}; H.raw{end + 1} = {};
            cur = numel(H.names);
            continue;
        end
        if cur == 0, continue; end
        H.raw{cur}{end + 1} = L;
        if isempty(t) || t(1) == ';', continue; end
        i = find(t == '=', 1);
        if isempty(i), continue; end
        H.keys{cur}{end + 1} = strtrim(t(1:i - 1));
        H.values{cur}{end + 1} = strtrim(t(i + 1:end));
    end
end

%% readText - A text file as characters (UTF-8 when it is valid UTF-8 with non-ASCII bytes, else Latin-1)
function txt = readText(p)
    fid = fopen(p, 'r');
    if fid < 0, error('NeuroAnalyzer:io:fileNotFound', 'Cannot open %s', p); end
    b = fread(fid, Inf, '*uint8')';
    fclose(fid);
    if numel(b) >= 3 && isequal(b(1:3), uint8([239 187 191])), b = b(4:end); end   % UTF-8 byte-order mark
    txt = char(b);
    if any(b > 127)
        enc = 'ISO-8859-1';                       % version 1 headers are Latin-1
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

%% iniGet - Value of a key in a section (case-insensitive), or the default
function v = iniGet(H, section, key, default)
    v = default;
    s = find(strcmpi(H.names, section), 1);
    if isempty(s), return; end
    i = find(strcmpi(H.keys{s}, key), 1);
    if ~isempty(i), v = H.values{s}{i}; end
end

%% iniSection - Keys and values of a section ({} when missing)
function [keys, values, raw] = iniSection(H, section)
    s = find(strcmpi(H.names, section), 1);
    if isempty(s), keys = {}; values = {}; raw = {}; return; end
    keys = H.keys{s}; values = H.values{s}; raw = H.raw{s};
end

%% findPart - Data or marker file named by the header, else the header's name with ext
function p = findPart(folder, base, named, ext, required)
    p = '';
    cand = {};
    if ~isempty(named)
        [~, n, e] = fileparts(strrep(named, '\', '/'));   % names may carry a Windows path
        cand{end + 1} = fullfile(folder, [n e]);
    end
    cand{end + 1} = fullfile(folder, [base ext]);
    for k = 1:numel(cand)
        if exist(cand{k}, 'file') == 2, p = cand{k}; return; end
    end
    if required
        want = [base ext];
        if ~isempty(named), want = named; end
        error('NeuroAnalyzer:io:fileNotFound', ['The data file %s named in the header was not found ' ...
            'next to it (%s). Keep the .vhdr, .vmrk and .eeg files together in one folder.'], want, folder);
    end
end

%% channelInfos - Names, reference names, resolutions and units of the channels
function [labels, refs, res, units] = channelInfos(H, nCh)
    labels = arrayfun(@(c) sprintf('Ch %d', c), 1:nCh, 'UniformOutput', false);
    refs = repmat({''}, 1, nCh);
    res = ones(1, nCh);
    units = repmat({'uV'}, 1, nCh);
    [keys, values] = iniSection(H, 'Channel Infos');
    for i = 1:numel(keys)
        c = sscanf(keys{i}, 'Ch%d');
        if isempty(c) || c < 1 || c > nCh, continue; end
        f = strsplit(values{i}, ',', 'CollapseDelimiters', false);
        f = strrep(f, '\1', ',');                    % commas inside names are written as \1
        if numel(f) >= 1 && ~isempty(strtrim(f{1})), labels{c} = strtrim(f{1}); end
        if numel(f) >= 2, refs{c} = strtrim(f{2}); end
        if numel(f) >= 3 && ~isempty(strtrim(f{3}))
            r = str2double(f{3});
            if isfinite(r), res(c) = r; end
        end
        if numel(f) >= 4 && ~isempty(strtrim(f{4})), units{c} = strtrim(f{4}); end
    end
end

%% unitScale - Factor per channel to microvolts; notes for other units
function [scale, notes] = unitScale(units, labels)
    scale = ones(1, numel(units));
    notes = {};
    other = {};
    conv = {};
    for c = 1:numel(units)
        u = unitKey(units{c});
        switch lower(u)
            case {'uv', ''}
            case 'nv', scale(c) = 1e-3; conv{end + 1} = 'nV'; %#ok<AGROW>
            case 'mv', scale(c) = 1e3; conv{end + 1} = 'mV'; %#ok<AGROW>
            case 'v', scale(c) = 1e6; conv{end + 1} = 'V'; %#ok<AGROW>
            otherwise, other{end + 1} = sprintf('%s (%s)', labels{c}, units{c}); %#ok<AGROW>
        end
    end
    uV = [char(181) 'V'];
    if ~isempty(conv)
        notes{end + 1} = sprintf('Some channels were stored in %s; they were converted to %s.', ...
            EEGSource.listText(EEGSource.stableUnique(conv)), uV);
    end
    if ~isempty(other)
        notes{end + 1} = sprintf('%s: not in volts, so the values were kept as they are.', EEGSource.listText(other));
    end
end

%% unitKey - 'uv', 'nv', 'mv', 'v' or the unit itself (the micro sign in any encoding counts as u)
function k = unitKey(u)
    u = strtrim(u);
    k = lower(u);
    if isempty(u), k = 'uv'; return; end
    if any(strcmpi(u, {'microvolt', 'microvolts'})), k = 'uv'; return; end
    if any(strcmpi(u, {'millivolt', 'millivolts'})), k = 'mv'; return; end
    if any(strcmpi(u, {'volt', 'volts'})), k = 'v'; return; end
    if u(end) ~= 'V', return; end
    pre = u(1:end - 1);
    if isempty(pre), k = 'v';
    elseif strcmp(pre, 'm'), k = 'mv';
    elseif strcmp(pre, 'n'), k = 'nv';
    elseif strcmpi(pre, 'u') || all(double(pre) > 127), k = 'uv';   % micro sign (Latin-1, UTF-8 or Greek mu)
    end
end

%% ------------------------------------------------------------------------
%  Data file
%% ------------------------------------------------------------------------

%% readBinary - channels x samples (double, in file units x 1)
function [X, note] = readBinary(p, H, nCh, orient)
    note = '';
    bf = upper(iniGet(H, 'Binary Infos', 'BinaryFormat', 'INT_16'));
    switch bf
        case 'INT_16', prec = 'int16';
        case 'UINT_16', prec = 'uint16';
        case 'INT_32', prec = 'int32';
        case 'IEEE_FLOAT_32', prec = 'float32';
        case 'IEEE_FLOAT_64', prec = 'float64';
        otherwise
            error('NeuroAnalyzer:eeg:unsupported', 'Unknown BinaryFormat ''%s'' in the header.', bf);
    end
    mf = 'ieee-le';
    if strcmpi(iniGet(H, 'Binary Infos', 'UseBigEndianOrder', 'NO'), 'YES'), mf = 'ieee-be'; end
    fid = fopen(p, 'r', mf);
    if fid < 0, error('NeuroAnalyzer:io:fileNotFound', 'Cannot open %s', p); end
    raw = fread(fid, Inf, [prec '=>double']);
    fclose(fid);
    [X, note] = arrange(raw, nCh, orient, p);
end

%% readAscii - channels x samples from a text data file
function [X, note] = readAscii(p, H, nCh, orient)
    skipLines = str2double(iniGet(H, 'ASCII Infos', 'SkipLines', '0'));
    skipCols = str2double(iniGet(H, 'ASCII Infos', 'SkipColumns', '0'));
    dec = iniGet(H, 'ASCII Infos', 'DecimalSymbol', '.');
    if ~isfinite(skipLines), skipLines = 0; end
    if ~isfinite(skipCols), skipCols = 0; end
    lines = regexp(readText(p), '\r\n|\n|\r', 'split');
    lines = lines(skipLines + 1:end);
    lines = lines(~cellfun(@(s) isempty(strtrim(s)), lines));
    rows = cell(numel(lines), 1);
    for k = 1:numel(lines)
        t = strtrim(lines{k});
        if strcmp(dec, ','), t = strrep(t, ',', '.'); end
        tok = regexp(t, '[\s;]+', 'split');
        rows{k} = str2double(tok(skipCols + 1:end));
    end
    n = cellfun(@numel, rows);
    if isempty(n) || any(n ~= n(1))
        error('NeuroAnalyzer:io:truncated', 'The lines of the text data file %s do not all have the same number of values.', p);
    end
    A = cat(1, rows{:});
    note = '';
    if strcmp(orient, 'VECTORIZED')              % one line per channel
        if size(A, 1) ~= nCh
            error('NeuroAnalyzer:io:truncated', 'The text data file %s has %d lines of values for %d channels.', ...
                p, size(A, 1), nCh);
        end
        X = A;
    else                                         % one line per sample
        if size(A, 2) ~= nCh
            error('NeuroAnalyzer:io:truncated', 'The text data file %s has %d values per line for %d channels.', ...
                p, size(A, 2), nCh);
        end
        X = A';
    end
end

%% arrange - A column of numbers into channels x samples
function [X, note] = arrange(raw, nCh, orient, p)
    note = '';
    nS = floor(numel(raw) / nCh);
    if nS < 1
        error('NeuroAnalyzer:io:truncated', 'The data file %s holds fewer numbers than one sample of %d channels.', p, nCh);
    end
    extra = numel(raw) - nS * nCh;
    if extra > 0
        if strcmp(orient, 'VECTORIZED')
            error('NeuroAnalyzer:io:truncated', ['The data file %s holds %d numbers, which do not ' ...
                'divide into %d channels.'], p, numel(raw), nCh);
        end
        note = sprintf(['The data file ended in the middle of a sample (the recording may have been ' ...
            'cut short); the last %d number(s) were left out.'], extra);
        raw = raw(1:nS * nCh);
    end
    if strcmp(orient, 'VECTORIZED')
        X = reshape(raw, nS, nCh)';
    else
        X = reshape(raw, nCh, nS);
    end
end

%% ------------------------------------------------------------------------
%  Markers, segments, events
%% ------------------------------------------------------------------------

%% readMarkers - Struct array type, desc, pos (1-based sample), points, channel
function M = readMarkers(p)
    M = struct('type', {}, 'desc', {}, 'pos', {}, 'points', {}, 'channel', {});
    if isempty(p), return; end
    H = readIni(p);
    [keys, values] = iniSection(H, 'Marker Infos');
    num = zeros(1, numel(keys));
    for i = 1:numel(keys)
        n = sscanf(keys{i}, 'Mk%d');
        if isempty(n), num(i) = NaN; continue; end
        num(i) = n;
        f = strsplit(values{i}, ',', 'CollapseDelimiters', false);
        f = strrep(f, '\1', ',');
        f(end + 1:5) = {''};
        M(end + 1) = struct('type', strtrim(f{1}), 'desc', strtrim(f{2}), 'pos', str2double(f{3}), ...
            'points', str2double(f{4}), 'channel', str2double(f{5})); %#ok<AGROW>
    end
    num = num(isfinite(num));
    [~, order] = sort(num);
    M = M(order);
    M = M(isfinite([M.pos]));
end

%% eventName - Marker description with spaces collapsed ('S  1' -> 'S 1'), else its type
function s = eventName(m)
    s = strtrim(regexprep(m.desc, '\s+', ' '));
    if isempty(s), s = m.type; end
end

%% isAdmin - Markers that are not events (segment starts, time 0, sync, comments, bad intervals)
function tf = isAdmin(m)
    tf = any(strcmpi(m.type, {'New Segment', 'Time 0', 'SyncStatus', 'Comment', 'Bad Interval', ...
        'DC Correction', 'Impedance'}));
end

%% continuousEvents - Events of a continuous recording, with notes on pauses and bad intervals
function [ev, notes] = continuousEvents(M, fs)
    notes = {};
    ev = struct('type', {}, 'latency', {}, 'duration', {});
    for k = 1:numel(M)
        m = M(k);
        if isAdmin(m), continue; end
        d = 0;
        if isfinite(m.points) && m.points > 1, d = m.points / fs; end
        ev(end + 1) = struct('type', eventName(m), 'latency', (m.pos - 1) / fs, 'duration', d); %#ok<AGROW>
    end
    types = {M.type};
    nSeg = sum(strcmpi(types, 'New Segment'));
    if nSeg > 1
        notes{end + 1} = sprintf(['The recording was paused or restarted %d time(s) (New Segment markers); ' ...
            'the pieces follow each other in the data.'], nSeg - 1);
    end
    nBad = sum(strcmpi(types, 'Bad Interval'));
    if nBad > 0
        notes{end + 1} = sprintf(['%d bad interval(s) are marked in the file. They are not removed here: ' ...
            'remove them in Analyzer or EEGLAB before exporting if they should be left out.'], nBad);
    end
    nCom = sum(strcmpi(types, 'Comment'));
    if nCom > 0
        notes{end + 1} = sprintf('%d comment marker(s) in the file (not used as events).', nCom);
    end
end

%% segments - Cut the concatenated segments into trials; conditions from the marker at time 0
function [X3, times, cond, notes] = segments(X, H, M, fs, base, ext)
    notes = {};
    nS = size(X, 2);
    segPts = str2double(iniGet(H, 'Common Infos', 'SegmentDataPoints', ''));
    starts = [M(strcmpi({M.type}, 'New Segment')).pos];
    if ~(isfinite(segPts) && segPts >= 1)
        if numel(starts) >= 2
            segPts = starts(2) - starts(1);
        else
            segPts = nS;
        end
    end
    nSeg = nS / segPts;
    if nSeg ~= round(nSeg)
        error('NeuroAnalyzer:io:truncated', ['%s: the data (%d samples) do not divide into segments of %d ' ...
            'samples.'], [base ext], nS, segPts);
    end
    X3 = reshape(X, size(X, 1), segPts, nSeg);
    segStart = (0:nSeg - 1) * segPts + 1;
    t0 = [M(strcmpi({M.type}, 'Time 0')).pos];
    t0rel = [];
    if ~isempty(t0)
        t0rel = t0(1) - segStart(find(segStart <= t0(1), 1, 'last')) + 1;
    end
    if isempty(t0rel)
        t0rel = 1;
        notes{end + 1} = 'The file has no Time 0 marker, so each segment starts at 0 s.';
    end
    times = ((1:segPts) - t0rel) / fs;
    cond = repmat({''}, 1, nSeg);
    for k = 1:numel(M)
        m = M(k);
        if isAdmin(m), continue; end
        s = floor((m.pos - 1) / segPts) + 1;
        if s < 1 || s > nSeg, continue; end
        if m.pos - segStart(s) + 1 == t0rel && isempty(cond{s})
            cond{s} = eventName(m);
        end
    end
    missing = cellfun(@isempty, cond);
    if all(missing)
        cond = repmat({'All trials'}, 1, nSeg);
    elseif any(missing)
        cond(missing) = {'No marker at time 0'};
        notes{end + 1} = sprintf('%d segment(s) have no marker at time 0.', sum(missing));
    end
    nBad = sum(strcmpi({M.type}, 'Bad Interval'));
    if nBad > 0
        notes{end + 1} = sprintf(['%d bad interval(s) are marked inside the segments. They are not removed ' ...
            'here: reject those segments in Analyzer before exporting.'], nBad);
    end
end

%% ------------------------------------------------------------------------
%  Positions, reference, recording settings
%% ------------------------------------------------------------------------

%% coordinates - [Coordinates] (radius, theta, phi in degrees) as x right, y nose, z up
function [locs, coord] = coordinates(H, labels)
    n = numel(labels);
    locs = struct('label', labels, 'x', NaN, 'y', NaN, 'z', NaN, 'theta', NaN, 'radius', NaN);
    coord = '';
    [keys, values] = iniSection(H, 'Coordinates');
    radii = [];
    for i = 1:numel(keys)
        c = sscanf(keys{i}, 'Ch%d');
        if isempty(c) || c < 1 || c > n, continue; end
        v = str2double(strsplit(values{i}, ',', 'CollapseDelimiters', false));
        if numel(v) < 3 || any(~isfinite(v(1:3))) || v(1) == 0, continue; end   % radius 0: no position
        r = v(1); th = v(2) * pi / 180; ph = v(3) * pi / 180;
        locs(c).x = r * sin(th) * cos(ph);
        locs(c).y = r * sin(th) * sin(ph);
        locs(c).z = r * cos(th);
        radii(end + 1) = r; %#ok<AGROW>
    end
    if ~isempty(radii)
        coord = 'BrainVision (x = right ear, y = nose, z = up)';
        if all(abs(radii - 1) < 1e-9), coord = [coord '; on a unit sphere']; end
    end
end

%% referenceText - Plain words for the reference channels of [Channel Infos]
function s = referenceText(refs)
    r = EEGSource.stableUnique(refs(~cellfun(@isempty, refs)));
    if isempty(r)
        s = 'unknown';
    elseif numel(r) == 1 && all(~cellfun(@isempty, refs))
        s = sprintf('channel %s', r{1});
    else
        s = sprintf('differs between channels (%s)', EEGSource.listText(r));
    end
end

%% commentSettings - Amplifier and software filters from the Recorder's [Comment] section
function [notes, history] = commentSettings(H)
    notes = {};
    history = {};
    [~, ~, raw] = iniSection(H, 'Comment');
    if isempty(raw), return; end
    try
        soft = find(~cellfun(@isempty, regexpi(raw, 'S\s*o\s*f\s*t\s*w\s*a\s*r\s*e\s+F\s*i\s*l\s*t\s*e\s*r', 'once')), 1);
        head = find(~cellfun(@isempty, regexpi(raw, 'Low Cutoff', 'once')));
        amp = head(head < min([soft, numel(raw) + 1]));
        if ~isempty(amp)
            f = filterRows(raw, amp(1));
            if ~isempty(f)
                notes{end + 1} = ['When recorded, the amplifier filtered ' f '.'];
            end
        end
        if ~isempty(soft)
            if any(~cellfun(@isempty, regexpi(raw(soft:min(end, soft + 3)), 'Disabled', 'once')))
                notes{end + 1} = 'No software filter was applied while recording.';
            else
                sh = head(head > soft);
                if ~isempty(sh)
                    f = filterRows(raw, sh(1));
                    if ~isempty(f)
                        history{end + 1} = ['Filtered while recording (Recorder software filter): ' f '.'];
                    end
                end
            end
        end
    catch
        % The comment is free text: when it cannot be read, it is simply not described
    end
end

%% filterRows - Common low / high cutoff and notch of a Recorder filter table, in words
function s = filterRows(raw, headRow)
    s = '';
    vals = {};
    for k = headRow + 1:numel(raw)
        t = strtrim(raw{k});
        if isempty(t), if isempty(vals), continue; else, break; end, end
        tok = regexp(t, '\s+', 'split');
        if isnan(str2double(tok{1})), if isempty(vals), continue; else, break; end, end
        if numel(tok) < 4, break; end
        vals(end + 1, :) = tok(end - 2:end); %#ok<AGROW>
    end
    if isempty(vals), return; end
    lo = EEGSource.stableUnique(vals(:, 1)');
    hi = EEGSource.stableUnique(vals(:, 2)');
    no = EEGSource.stableUnique(vals(:, 3)');
    if numel(lo) > 1 || numel(hi) > 1 || numel(no) > 1
        s = 'with settings that differ between channels (see the [Comment] section of the .vhdr file)';
        return;
    end
    parts = {};
    tau = str2double(lo{1});
    if strcmpi(lo{1}, 'DC') || (isfinite(tau) && tau == 0)
        parts{end + 1} = 'from DC (no high-pass)';
    elseif isfinite(tau)
        parts{end + 1} = sprintf('from %.3g Hz (time constant %g s)', 1 / (2 * pi * tau), tau);
    end
    h = str2double(hi{1});
    if isfinite(h), parts{end + 1} = sprintf('up to %g Hz', h); end
    if strcmpi(no{1}, 'Off')
        parts{end + 1} = 'no notch filter';
    elseif isfinite(str2double(no{1}))
        parts{end + 1} = sprintf('notch at %s Hz', no{1});
    end
    s = strjoin(parts, ', ');
end
