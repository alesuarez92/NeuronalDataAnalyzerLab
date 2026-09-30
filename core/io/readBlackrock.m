%% readBlackrock.m
% =========================================================================
% READ BLACKROCK - BLACKROCK NSx (+ NEV DIGITAL EVENTS) AS A TDT-LIKE STRUCT
% =========================================================================
% rec = readBlackrock(file)      file: .ns1 ... .ns6 (or the .nev: the
%                                highest-rate NSx with the same name is used)
%
% Blackrock Microsystems (Cerebus / NeuroPort; file specification
% documents 2.1-3.0), little-endian:
%   NSx 2.1  'NEURALSG', label char16, period uint32, channel count uint32,
%            electrode ids uint32 each; int16 samples interleaved (scale
%            unknown: 0.25 uV per bit assumed, as the NSP's default)
%   NSx 2.2+ 'NEURALCD', version (2 bytes), bytes in headers uint32, label
%            char16, comment char256, period uint32, time resolution
%            uint32, time origin (8 x uint16), channel count uint32 (314
%            bytes); 66-byte channel headers 'CC', electrode id uint16,
%            label char16, connector and pin (2 x uint8), min / max digital
%            int16, min / max analog int16, units char16, filters (20
%            bytes); data blocks: 0x01, timestamp (uint32; uint64 in 3.0),
%            number of samples uint32, then int16 samples interleaved.
%            value = (digital - minDigital) x (maxAnalog - minAnalog) /
%            (maxDigital - minDigital) + minAnalog, in units (uV / mV).
%   Sample rate = 30000 / period.
%   NEV      'NEURALEV' basic header (336 bytes: ... bytes in headers,
%            bytes per packet, time resolution ...), 32-byte extended
%            headers, then packets: timestamp (uint32; uint64 in 3.0),
%            packet id uint16; id 0 = digital / serial input: reason uint8
%            (bit 0 digital port, bit 7 serial), reserved uint8, value
%            uint16.
% Neural channels: electrode ids 1-128 not labelled ainp / analog;
% stimulus candidates: the analog inputs (electrode ids above 128 or
% labelled ainp), then each digital-input bit that changes in the NEV
% (0/1, held until the next event). Several data blocks (pauses) are put
% one after the other (info.nBlocks says how many).
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:blackrock.
% Toolboxes: none; also runs in GNU Octave.
% =========================================================================

function rec = readBlackrock(p)
[folder, base, ext] = fileparts(p);
if strcmpi(ext, '.nev')
    nsx = '';
    for k = 6:-1:1
        f = fullfile(folder, sprintf('%s.ns%d', base, k));
        if exist(f, 'file') == 2, nsx = f; break; end
    end
    if isempty(nsx)
        error('NeuroAnalyzer:io:blackrock', 'No .ns1-.ns6 file next to %s: the continuous signals are in them.', [base ext]);
    end
else
    nsx = p;
end
if exist(nsx, 'file') ~= 2
    error('NeuroAnalyzer:io:fileNotFound', 'File not found: %s', nsx);
end
fid = fopen(nsx, 'r', 'ieee-le');
c = onCleanup(@() fclose(fid));
fseek(fid, 0, 'eof'); nBytes = ftell(fid); fseek(fid, 0, 'bof');
id = fread(fid, [1 8], 'uint8=>char');
switch id
    case 'NEURALSG'
        spec = '2.1';
        fread(fid, 16, 'uint8');                               % label
        period = fread(fid, 1, 'uint32');
        nCh = fread(fid, 1, 'uint32');
        elec = fread(fid, [1 nCh], 'uint32');
        labels = arrayfun(@(e) sprintf('elec%d', e), elec, 'UniformOutput', false);
        scale = 0.25e-6 * ones(nCh, 1); offset = zeros(nCh, 1);
        dataStart = ftell(fid);
        n = floor((nBytes - dataStart) / (2 * nCh));
        x = fread(fid, [nCh n], '*int16');
        nBlocks = 1; ts0 = 0; tsRes = 30000;
        units = repmat({'uV'}, 1, nCh);
    case {'NEURALCD', 'BRSMPGRP'}
        ver = fread(fid, [1 2], 'uint8');
        spec = sprintf('%d.%d', ver);
        headerBytes = fread(fid, 1, 'uint32');
        fread(fid, 16 + 256, 'uint8');                         % label, comment
        period = fread(fid, 1, 'uint32');
        tsRes = fread(fid, 1, 'uint32');
        fread(fid, 8, 'uint16');                               % time origin
        nCh = fread(fid, 1, 'uint32');
        elec = zeros(1, nCh); labels = cell(1, nCh); units = cell(1, nCh);
        scale = zeros(nCh, 1); offset = zeros(nCh, 1);
        for k = 1:nCh
            fread(fid, 2, 'uint8');                            % 'CC'
            elec(k) = fread(fid, 1, 'uint16');
            labels{k} = cstr(fread(fid, [1 16], 'uint8=>char'));
            fread(fid, 2, 'uint8');
            dmin = fread(fid, 1, 'int16'); dmax = fread(fid, 1, 'int16');
            amin = fread(fid, 1, 'int16'); amax = fread(fid, 1, 'int16');
            units{k} = cstr(fread(fid, [1 16], 'uint8=>char'));
            fread(fid, 20, 'uint8');                           % filters (2 x corner, order, type)
            u = unitVolts(units{k});
            scale(k) = (amax - amin) / max(1, dmax - dmin) * u;
            offset(k) = (amin - dmin * (amax - amin) / max(1, dmax - dmin)) * u;
        end
        if tsRes == 1e9
            error('NeuroAnalyzer:io:blackrock', ['%s uses the precision-time-protocol layout of file ' ...
                'spec 3.0 (a timestamp in every sample), which this reader does not handle yet: ' ...
                'export it from Central as a standard NSx.'], [base ext]);
        end
        tsBytes = 4 + 4 * strcmp(spec, '3.0');
        fseek(fid, headerBytes, 'bof');
        parts = {}; ts0 = NaN; nBlocks = 0;
        while ftell(fid) < nBytes - (1 + tsBytes + 4)
            flag = fread(fid, 1, 'uint8');
            if isempty(flag) || flag ~= 1
                error('NeuroAnalyzer:io:blackrock', '%s: a data block does not start with 0x01.', [base ext]);
            end
            if tsBytes == 8, ts = fread(fid, 1, 'uint64'); else, ts = fread(fid, 1, 'uint32'); end
            m = fread(fid, 1, 'uint32');
            if isnan(ts0), ts0 = ts; end
            blk = fread(fid, [nCh m], '*int16');
            if size(blk, 2) < m
                error('NeuroAnalyzer:io:blackrock', '%s is cut short.', [base ext]);
            end
            if m > 0, parts{end+1} = blk; nBlocks = nBlocks + 1; end %#ok<AGROW>
        end
        if isempty(parts)
            error('NeuroAnalyzer:io:blackrock', '%s has no samples.', [base ext]);
        end
        x = [parts{:}];
    otherwise
        error('NeuroAnalyzer:io:blackrock', '%s is not a Blackrock NSx file (it starts with "%s").', [base ext], id);
end
fs = 30000 / period;
v = double(x) .* scale + offset;
isAnalog = elec > 128 | ~cellfun(@isempty, regexpi(labels, '^(ainp|analog)', 'once'));
neural = find(~isAnalog);
if isempty(neural), neural = 1:nCh; isAnalog(:) = false; end
raw = v(neural, :);
stim = v(isAnalog, :);
stimNames = labels(isAnalog);
stimKinds = repmat({'analog'}, 1, numel(stimNames));
% NEV digital input events on the NSx time base
nev = fullfile(folder, [base '.nev']);
events = [];
if exist(nev, 'file') == 2
    events = readNEVDigital(nev);
    if ~isempty(events)
        n = size(raw, 2);
        idx = round((double(events.timestamp) - ts0) / events.tsRes * fs) + 1;
        vals = double(events.value);
        for b = 0:15
            bit = bitget(vals, b + 1);
            if ~any(bit), continue; end                  % never high (the port starts at 0)
            s = zeros(1, n);
            for k = 1:numel(idx)
                if idx(k) > n, break; end
                s(max(1, idx(k)):n) = bit(k);
            end
            stim(end+1, :) = s; %#ok<AGROW>
            stimNames{end+1} = sprintf('Digital in bit %d', b); %#ok<AGROW>
            stimKinds{end+1} = 'digital'; %#ok<AGROW>
        end
    end
end
info = struct('source', sprintf('Blackrock NSx %s', spec), 'format', 'blackrock', 'file', nsx, ...
    'blockname', base, 'channelNames', {labels(neural)}, 'electrodeIds', elec(neural), ...
    'nBlocks', nBlocks, 'spec', spec);
if ~isempty(stimNames)
    info.stimNames = stimNames;
    info.stimKinds = stimKinds;
else
    stim = [];
end
info.digitalEvents = events;
rec = EphysSource.makeRecording(raw, fs, stim, fs, info);
end

%% readNEVDigital - Digital-input packets (id 0, reason bit 0 without bit 7) of a NEV
function ev = readNEVDigital(f)
ev = [];
fid = fopen(f, 'r', 'ieee-le');
if fid < 0, return; end
c = onCleanup(@() fclose(fid));
id = fread(fid, [1 8], 'uint8=>char');
if ~any(strcmp(id, {'NEURALEV', 'BREVENTS'})), return; end
ver = fread(fid, [1 2], 'uint8');
fread(fid, 1, 'uint16');
headerBytes = fread(fid, 1, 'uint32');
packetBytes = fread(fid, 1, 'uint32');
tsRes = fread(fid, 1, 'uint32');
fseek(fid, 0, 'eof'); nBytes = ftell(fid);
tsBytes = 4 + 4 * (ver(1) >= 3);
nPk = floor((nBytes - headerBytes) / packetBytes);
fseek(fid, headerBytes, 'bof');
raw = fread(fid, [packetBytes nPk], 'uint8=>uint8');
if isempty(raw), return; end
pid = double(raw(tsBytes + 1, :)) + 256 * double(raw(tsBytes + 2, :));
reason = raw(tsBytes + 3, :);
dig = pid == 0 & bitand(reason, 1) ~= 0 & bitand(reason, 128) == 0;
if ~any(dig), return; end
r = raw(:, dig);
ts = zeros(1, size(r, 2));
for b = tsBytes:-1:1, ts = ts * 256 + double(r(b, :)); end
ev.timestamp = ts;
ev.value = double(r(tsBytes + 5, :)) + 256 * double(r(tsBytes + 6, :));
ev.tsRes = tsRes;
end

function s = cstr(c)
k = find(c == char(0), 1);
if ~isempty(k), c = c(1:k-1); end
s = strtrim(c);
end

function f = unitVolts(u)
u = lower(strtrim(u));
f = 1e-6;                                               % Blackrock writes uV for amplifier channels
if numel(u) >= 1 && u(end) == 'v'
    switch u(1:end-1)
        case '', f = 1;
        case 'm', f = 1e-3;
        case 'n', f = 1e-9;
    end
end
end
