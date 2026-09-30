function rec = readSignalText(p, opts)
% readSignalText - Read a physiology recording exported as delimited text.
%
% rec = readSignalText(file)
% rec = readSignalText(file, struct('Fs', 40))     % rate when the file has no time column
%
% Recognises three layouts, then returns the SignalSource structure (see
% SignalSource.m: channels, events, names, units, info):
%   LabChart text export (ADInstruments): header lines 'Interval=' (sample
%     interval with its unit), 'ChannelTitle=', 'Range=' (the unit follows
%     the number), optional 'UnitName=', 'ExcelDateTime=', 'TimeFormat=',
%     'DateFormat=', 'TopValue=', 'BottomValue='; then rows of time and one
%     column per channel; text after the numbers of a row is a comment at
%     that time. A new header starts a new block.
%   AcqKnowledge text export with header (BIOPAC): the .acq path, '<x>
%     msec/sample', '<n> channels', then a name line and a units line per
%     channel, then the rows (the first column is time when "Horizontal
%     scale values" was ticked; otherwise the rate comes from msec/sample).
%   Any delimited table (PeriSoft, moorVMS-PC, spreadsheets): optional
%     header rows (names, optionally 'Name (unit)' or 'Name [unit]', or a
%     second row of units), then numeric rows separated by tabs, commas or
%     semicolons. A column named time / t / sec / ms (or the first column
%     when it rises in equal steps) gives the rate; clock times
%     (hh:mm:ss.sss) are accepted in the first column. A decimal comma is
%     accepted when the separator is a tab or a semicolon.
% Sources: ADInstruments knowledge base (text import / export header
% items) and the parsing rules of phys2bids (Apache-2.0,
% https://github.com/physiopy/phys2bids) for LabChart and AcqKnowledge
% text, as summarised in the format survey; the other vendors do not
% document their text layout, so the generic rules apply.
%
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:text (no
% numbers, ragged rows), NeuroAnalyzer:io:noRate (no time column and no
% opts.Fs). Base MATLAB only; also runs in GNU Octave.
%
if nargin < 2 || isempty(opts), opts = struct(); end
if exist(p, 'file') ~= 2
    error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', p);
end
txt = readText(p);
if ~isempty(regexp(txt, '(?m)^\s*(Interval|ChannelTitle)=', 'once'))
    rec = labChartText(txt, p);
elseif ~isempty(regexp(txt, '(?im)^\s*[\d.]+\s*m?sec/sample', 'once'))
    rec = acqText(txt, p, opts);
else
    rec = genericText(txt, p, opts);
end
end

%% ------------------------------------------------------------------------
function txt = readText(p)
fid = fopen(p, 'r');
b = fread(fid, Inf, 'uint8=>uint8')';
fclose(fid);
if numel(b) >= 2 && isequal(b(1:2), [255 254])              % UTF-16 LE (Windows "Unicode")
    b = b(3:end);
    txt = char(double(typecast(b(1:2*floor(end/2)), 'uint16')));
elseif numel(b) >= 3 && isequal(b(1:3), [239 187 191])      % UTF-8 BOM
    txt = native2unicode(b(4:end), 'UTF-8');
else
    try
        txt = native2unicode(b, 'UTF-8');
    catch
        txt = char(b);
    end
end
txt = txt(:)';
txt = strrep(txt, char([13 10]), char(10));
txt = strrep(txt, char(13), char(10));
end

%% labChartText - Header blocks (key=value) then rows; each header starts a block
function rec = labChartText(txt, p)
starts = regexp(txt, '(?m)^\s*Interval=', 'start');
if isempty(starts), starts = regexp(txt, '(?m)^\s*ChannelTitle=', 'start'); end
starts(end+1) = numel(txt) + 1;
ch = SignalSource.emptyChannels();
ev = SignalSource.emptyEvents();
names = {}; units = {};
blockStart = {};
for b = 1:numel(starts) - 1
    seg = txt(starts(b):starts(b+1) - 1);
    d0 = regexp(seg, '(?m)^\s*[-+]?(\d|\.\d)', 'start', 'once');
    if isempty(d0), continue; end
    head = seg(1:d0-1);
    body = seg(d0:end);
    dt = headerInterval(head);
    titles = headerList(head, 'ChannelTitle');
    ranges = headerList(head, 'Range');
    unitNames = headerList(head, 'UnitName');
    [cols, comments] = numericTable(body, char(9));
    nCol = size(cols, 2);
    hasTime = nCol == numel(titles) + 1 || (isempty(titles) && nCol > 1);
    if hasTime
        t = cols(:, 1)';
        vals = cols(:, 2:end);
        if ~isfinite(dt) && numel(t) > 1, dt = median(diff(t)); end
    else
        vals = cols;
        t = (0:size(cols, 1) - 1) * dt;
    end
    if ~(isfinite(dt) && dt > 0)
        error('NeuroAnalyzer:io:noRate', 'The LabChart text export has no Interval= line and no time column.');
    end
    nCh = size(vals, 2);
    for c = 1:nCh
        nm = sprintf('Channel %d', c);
        if c <= numel(titles) && ~isempty(titles{c}), nm = titles{c}; end
        u = '';
        if c <= numel(unitNames) && ~isempty(unitNames{c}) && ~strcmp(unitNames{c}, '*')
            u = unitNames{c};
        elseif c <= numel(ranges)
            tok = regexp(ranges{c}, '^[-+\d.eE]+\s+(\S.*)$', 'tokens', 'once');
            if ~isempty(tok), u = strtrim(tok{1}); end
        end
        if b == 1 || c > numel(names), names{c} = nm; units{c} = u; end %#ok<AGROW>
        v = vals(:, c)';
        ch(end+1) = struct('chan', c, 'block', b, 'name', nm, 'units', u, 'fs', 1 / dt, ...
            'data', v, 't0', t(1)); %#ok<AGROW>
    end
    for k = find(~cellfun(@isempty, comments))'
        ev(end+1) = struct('time', t(k), 'block', b, 'channel', 0, 'type', 'comment', ...
            'text', cleanComment(comments{k})); %#ok<AGROW>
    end
    tok = regexp(head, 'ExcelDateTime=\s*\S+\s+([^\n]+)', 'tokens', 'once');
    if isempty(tok), blockStart{b} = ''; else, blockStart{b} = strtrim(tok{1}); end %#ok<AGROW>
end
rec = SignalSource.makeRec(ch, ev, names, units, 'text', p);
rec.info.label = 'LabChart text export';
rec.info.blockStart = blockStart;
rec.info.notes{end+1} = 'LabChart text export: rate from Interval=, names from ChannelTitle=, units from Range=.';
end

function dt = headerInterval(head)
dt = NaN;
tok = regexp(head, 'Interval=\s*([-+\d.eE]+)\s*([^\s\n]*)', 'tokens', 'once');
if isempty(tok), return; end
v = str2double(tok{1});
dt = v * timeFactor(tok{2});
if any(strcmpi(tok{2}, {'Hz', 'kHz', 'MHz'}))
    dt = 1 / (v * timeFactor(tok{2}));
end
end

function f = timeFactor(u)
switch lower(strtrim(u))
    case {'ms', 'msec'},              f = 1e-3;
    case {'us', 'µs', 'usec', 'µsec'}, f = 1e-6;
    case {'min', 'mins'},             f = 60;
    case {'h', 'hr', 'hour'},         f = 3600;
    case 'khz',                       f = 1e3;
    case 'mhz',                       f = 1e6;
    otherwise,                        f = 1;          % s, sec, Hz
end
end

function c = headerList(head, key)
c = {};
tok = regexp(head, ['(?m)^\s*' key '=([^\n]*)'], 'tokens', 'once');
if isempty(tok), return; end
c = strsplit(tok{1}, char(9));
c = cellfun(@(s) strtrim(strrep(s, '"', '')), c, 'UniformOutput', false);
if ~isempty(c) && isempty(c{1}), c(1) = []; end
end

function s = cleanComment(s)
s = strtrim(s);
s = regexprep(s, '^#\S*\s*', '');                     % LabChart writes '#<n> text' / '#* text'
end

%% acqText - AcqKnowledge text export with header lines
function rec = acqText(txt, p, opts) %#ok<INUSD>
lines = strsplit(txt(1:min(end, 20000)), char(10));
k = find(~cellfun(@isempty, regexpi(lines, '^\s*[\d.]+\s*m?sec/sample', 'once')), 1);
tok = regexpi(lines{k}, '^\s*([\d.]+)\s*(m?sec)/sample', 'tokens', 'once');
dt = str2double(tok{1}) * ifelse(strcmpi(tok{2}, 'msec'), 1e-3, 1);
nTok = regexp(lines{k + 1}, '^\s*(\d+)\s*channels', 'tokens', 'once');
nCh = str2double(nTok{1});
names = cell(1, nCh); units = cell(1, nCh);
for c = 1:nCh
    names{c} = strtrim(lines{k + 2 * c});
    units{c} = strtrim(lines{k + 2 * c + 1});
end
% The rows start at the first line made only of numbers, tabs and spaces
d0 = NaN;
pos = [1, find(txt == char(10)) + 1];                % start of every line
for j = k + 2 * nCh + 2:numel(lines)
    if ~isempty(regexp(lines{j}, '^\s*[-+]?(\d|\.\d)', 'once')) && ...
            numel(regexp(strtrim(lines{j}), '[\t ,;]+', 'split')) >= nCh
        d0 = pos(j); break;
    end
end
if isnan(d0)
    error('NeuroAnalyzer:io:text', 'No data rows found after the AcqKnowledge header.');
end
[cols, ~] = numericTable(txt(d0:end), char(9));
if size(cols, 2) == nCh + 1
    t = cols(:, 1)';
    tUnit = 1;
    if numel(t) > 1 && abs(median(diff(t)) - dt * 1000) < 1e-9 * max(1, dt * 1000)
        tUnit = 1e-3;                                  % time column in ms
    end
    t0 = t(1) * tUnit;
    vals = cols(:, 2:end);
else
    t0 = 0;
    vals = cols(:, 1:min(end, nCh));
end
ch = SignalSource.emptyChannels();
for c = 1:size(vals, 2)
    ch(end+1) = struct('chan', c, 'block', 1, 'name', names{c}, 'units', units{c}, 'fs', 1 / dt, ...
        'data', vals(:, c)', 't0', t0); %#ok<AGROW>
end
rec = SignalSource.makeRec(ch, SignalSource.emptyEvents(), names, units, 'text', p);
rec.info.label = 'AcqKnowledge text export';
rec.info.notes{end+1} = 'AcqKnowledge text export: event markers are not in text exports (use the .acq file).';
end

%% genericText - Header rows (names, units), then numeric rows
function rec = genericText(txt, p, opts)
d0 = regexp(txt, '(?m)^\s*[-+]?(\d|\.\d|[Nn]a[Nn])', 'start', 'once');
if isempty(d0)
    error('NeuroAnalyzer:io:text', 'No rows of numbers found in %s.', SignalSource.nameOf(p));
end
head = strtrim(txt(1:d0-1));
body = txt(d0:end);
firstLine = regexp(body, '^[^\n]*', 'match', 'once');
delim = pickDelimiter([head char(10) firstLine]);
% Decimal comma: '1,5' with a tab or semicolon separator
if ~strcmp(delim, ',') && ~isempty(regexp(firstLine, '\d,\d', 'once'))
    body = strrep(body, ',', '.');
end
% Clock time in the first column (hh:mm:ss[.sss]): converted to seconds
clock = ~isempty(regexp(firstLine, ['^\s*\d{1,2}:\d{2}:\d{2}(\.\d+)?\s*' regexptranslate('escape', delim)], 'once'));
if clock
    [tt, rest] = splitClock(body, delim);
    [cols, ~] = numericTable(rest, delim);
    cols = [tt(1:size(cols, 1)) cols];
else
    [cols, ~] = numericTable(body, delim);
end
nCol = size(cols, 2);
% Names and units from the header rows
hl = strsplit(head, char(10));
hl = hl(~cellfun(@isempty, strtrim(hl)));
names = repmat({''}, 1, nCol); units = repmat({''}, 1, nCol);
if ~isempty(hl)
    h1 = splitRow(hl{end}, delim);
    if numel(hl) >= 2 && numel(splitRow(hl{end-1}, delim)) == numel(h1) && allUnits(h1)
        units(1:min(nCol, numel(h1))) = h1(1:min(nCol, numel(h1)));
        h1 = splitRow(hl{end-1}, delim);
    end
    for c = 1:min(nCol, numel(h1))
        tok = regexp(h1{c}, '^(.*?)\s*[\(\[]([^\)\]]*)[\)\]]\s*$', 'tokens', 'once');
        if isempty(tok)
            names{c} = h1{c};
        else
            names{c} = strtrim(tok{1});
            if isempty(units{c}), units{c} = strtrim(tok{2}); end
        end
    end
end
% Time column: named, or the first column rising in equal steps
tc = find(~cellfun(@isempty, regexpi(names, '^(time|t|sec|seconds|s|ms|msec|zeit|temps|tiempo)([^a-z]|$)', 'once')), 1);
if isempty(tc) && (clock || isEqualSteps(cols(:, 1)))
    tc = 1;
end
fs = NaN; t0 = 0;
if ~isempty(tc)
    t = cols(:, tc)';
    f = 1;
    if clock
        f = 1;
    elseif any(strcmpi(units{tc}, {'ms', 'msec'})) || any(strcmpi(names{tc}, {'ms', 'msec'}))
        f = 1e-3;
    elseif any(strcmpi(units{tc}, {'min'}))
        f = 60;
    end
    t = t * f;
    if numel(t) > 1, fs = 1 / median(diff(t)); end
    t0 = t(1);
    keep = setdiff(1:nCol, tc);
else
    keep = 1:nCol;
end
if isfield(opts, 'Fs') && ~isempty(opts.Fs) && opts.Fs > 0 && isempty(tc)
    fs = opts.Fs;
end
if ~(isfinite(fs) && fs > 0)
    error('NeuroAnalyzer:io:noRate', ['%s has no time column: give the sampling rate (Hz) of its ' ...
        'rows, or add a first column named Time (s).'], SignalSource.nameOf(p));
end
ch = SignalSource.emptyChannels();
nm = {}; un = {};
for j = 1:numel(keep)
    c = keep(j);
    name = names{c};
    if isempty(name), name = sprintf('Column %d', c); end
    nm{end+1} = name; un{end+1} = units{c}; %#ok<AGROW>
    ch(end+1) = struct('chan', j, 'block', 1, 'name', name, 'units', units{c}, 'fs', fs, ...
        'data', cols(:, c)', 't0', t0); %#ok<AGROW>
end
rec = SignalSource.makeRec(ch, SignalSource.emptyEvents(), nm, un, 'text', p);
rec.info.label = 'Delimited text';
if ~isempty(tc)
    rec.info.notes{end+1} = sprintf('Rate %g Hz from the time column "%s".', fs, names{tc});
else
    rec.info.notes{end+1} = sprintf('No time column: rate %g Hz as given.', fs);
end
end

%% numericTable - Rows of numbers (NaN for empty cells); LabChart comments ('#...' after the numbers) kept
function [cols, comments] = numericTable(body, delim)
% Comments first: their text is removed so every row holds numbers only
comments = {};
[tok, st] = regexp(body, ['(?m)' regexptranslate('escape', delim) '\s*(#[^\n]*)$'], 'tokens', 'start');
if ~isempty(st)
    lineStart = [1, find(body == char(10)) + 1];
    rowOf = arrayfun(@(s) find(lineStart <= s, 1, 'last'), st);
    body = regexprep(body, ['(?m)' regexptranslate('escape', delim) '\s*#[^\n]*$'], '');
end
first = regexp(body, '^[^\n]*', 'match', 'once');
parts = splitRow(first, delim);
nNum = 0;
for k = 1:numel(parts)
    if isnan(str2double(parts{k})) && ~any(strcmpi(parts{k}, {'nan', ''})), break; end
    nNum = k;
end
if nNum == 0
    error('NeuroAnalyzer:io:text', 'The first data row has no numbers.');
end
if nNum > 1 && isempty(parts{nNum}), nNum = nNum - 1; end   % a trailing separator
fmt = repmat('%f', 1, nNum);
if strcmp(delim, ' ')
    C = textscan(body, fmt, 'Delimiter', ' ', 'MultipleDelimsAsOne', true, 'EmptyValue', NaN, ...
        'ReturnOnError', true, 'EndOfLine', '\n');
else
    C = textscan(body, fmt, 'Delimiter', delim, 'EmptyValue', NaN, 'ReturnOnError', true, 'EndOfLine', '\n');
end
n = min(cellfun(@numel, C));
cols = zeros(n, nNum);
for k = 1:nNum, cols(:, k) = C{k}(1:n); end
comments = repmat({''}, n, 1);
for k = 1:numel(st)
    if rowOf(k) <= n, comments{rowOf(k)} = tok{k}{1}; end
end
end

function c = splitRow(line, delim)
if strcmp(delim, ' ')
    c = regexp(strtrim(line), '\s+', 'split');
else
    c = strsplit(line, delim, 'CollapseDelimiters', false);
end
c = cellfun(@(s) strtrim(strrep(s, '"', '')), c, 'UniformOutput', false);
end

function d = pickDelimiter(s)
cand = {char(9), ';', ','};
n = cellfun(@(x) numel(strfind(s, x)), cand);
if max(n) == 0
    d = ' ';
else
    [~, i] = max(n);
    d = cand{i};
end
end

function tf = allUnits(c)
tf = all(cellfun(@(s) isempty(s) || numel(s) <= 8, c)) && ...
    all(cellfun(@(s) isempty(s) || any(strcmpi(s, {'s', 'ms', 'sec', 'min', 'v', 'mv', 'uv', 'µv', 'pu', ...
    'bpu', 'tpu', 'au', 'a.u.', '%', 'degc', '°c', 'mmhg', 'hz', 'ml/min', 'volts', 'flux'})), c));
end

function tf = isEqualSteps(x)
tf = false;
if numel(x) < 3, return; end
d = diff(x(1:min(end, 1000)));
tf = all(d > 0) && (max(d) - min(d)) <= 1e-6 * max(abs(d)) + 1e-9;
end

function [t, rest] = splitClock(body, delim)
tok = regexp(body, ['(?m)^\s*(\d{1,2}):(\d{2}):(\d{2}(?:\.\d+)?)\s*' regexptranslate('escape', delim) ...
    '([^\n]*)'], 'tokens');
n = numel(tok);
t = zeros(n, 1);
r = cell(n, 1);
for k = 1:n
    t(k) = 3600 * str2double(tok{k}{1}) + 60 * str2double(tok{k}{2}) + str2double(tok{k}{3});
    r{k} = tok{k}{4};
end
d = diff(t);
t(2:end) = t(1) + cumsum(d + 86400 * (d < -43200));   % past midnight
rest = strjoin(r', char(10));
end

function v = ifelse(c, a, b)
if c, v = a; else, v = b; end
end
