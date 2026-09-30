function f = unitScale(u, kind)
% unitScale - Micrometres in a length unit, or seconds in a time unit, from the text a file writes.
%
% f = unitScale('µm')          % 1 (ImageJ's escaped micro sign)
% f = unitScale('mm')               % 1000
% f = unitScale('ms', 'time')       % 0.001
%
% Accepts micron / microns / um / micrometre, the micro sign (U+00B5) and
% the Greek mu (U+03BC) as a character, as UTF-8 bytes or as a \uXXXX
% escape; nm, mm, cm, m, inch. Times: s / sec, ms, us, min, h.
% Returns NaN when the text is not a unit of that kind (e.g. 'pixel').
% Base MATLAB only; also runs in GNU Octave.
%
if nargin < 2, kind = 'length'; end
s = lower(strtrim(asciiUnit(u)));
s = regexprep(s, '[\s.]', '');
if strcmp(kind, 'time')
    switch s
        case {'s', 'sec', 'second', 'seconds'}, f = 1;
        case {'ms', 'msec', 'millisecond', 'milliseconds'}, f = 1e-3;
        case {'us', 'usec', 'microsecond', 'microseconds'}, f = 1e-6;
        case {'ns'}, f = 1e-9;
        case {'min', 'minute', 'minutes'}, f = 60;
        case {'h', 'hr', 'hour', 'hours'}, f = 3600;
        otherwise, f = NaN;
    end
    return;
end
switch s
    case {'um', 'micron', 'microns', 'micrometer', 'micrometers', 'micrometre', 'micrometres'}, f = 1;
    case {'nm', 'nanometer', 'nanometers', 'nanometre', 'nanometres'}, f = 1e-3;
    case {'mm', 'millimeter', 'millimeters', 'millimetre', 'millimetres'}, f = 1e3;
    case {'cm', 'centimeter', 'centimeters', 'centimetre', 'centimetres'}, f = 1e4;
    case {'m', 'meter', 'meters', 'metre', 'metres'}, f = 1e6;
    case {'in', 'inch', 'inches'}, f = 25400;
    otherwise, f = NaN;
end
end

%% asciiUnit - Text with the micro sign / Greek mu (any encoding, or \uXXXX) as 'u'
function out = asciiUnit(u)
if iscell(u), if isempty(u), u = ''; else, u = u{1}; end, end
u = char(u);
out = '';
i = 1;
hex = '0123456789abcdef';
while i <= numel(u)
    c = double(u(i));
    if u(i) == '\' && i + 5 <= numel(u) && lower(u(i+1)) == 'u' && all(ismember(lower(u(i+2:i+5)), hex))
        code = hex2dec(u(i+2:i+5));
        if code == 181 || code == 956
            out(end+1) = 'u'; %#ok<AGROW>
        elseif code < 128
            out(end+1) = char(code); %#ok<AGROW>
        end
        i = i + 6;
    elseif (c == 194 && i < numel(u) && double(u(i+1)) == 181) || (c == 206 && i < numel(u) && double(u(i+1)) == 188)
        out(end+1) = 'u'; %#ok<AGROW>                  % UTF-8 bytes of the micro sign / mu
        i = i + 2;
    elseif c == 181 || c == 956
        out(end+1) = 'u'; %#ok<AGROW>
        i = i + 1;
    else
        if c < 128, out(end+1) = u(i); end %#ok<AGROW>
        i = i + 1;
    end
end
end
