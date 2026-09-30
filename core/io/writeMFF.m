function writeMFF(folder, eeg, varargin)
% writeMFF - Write a continuous EEG recording as an EGI .mff folder (tests and demos).
%
% writeMFF(folder, eeg, Name, Value, ...)
%
% eeg      EEGSource struct (continuous): data channels x samples (uV),
%          fs (whole Hz), labels, chanlocs (x / y / z written as cm when
%          finite), events (type = code, latency, duration in s)
% Options: 'RecordTime' ('2026-09-30T12:00:00.000000+00:00'), 'BlockSize'
%          (samples per block, default 1000; blocks after the first of the
%          same size are written without a header, as Net Station does),
%          'Pause' [after pauseSamples]: the samples after 'after' form a
%          second piece starting pauseSamples later (epochs.xml), 'Gains'
%          (GCAL calibration per channel: the file holds data / gain),
%          'Reference' (index of the reference channel, sensor type 1)
% Writes info.xml, info1.xml, signal1.bin, epochs.xml, coordinates.xml,
% sensorLayout.xml and Events.xml. Layout as readMFF reads it (and as
% mffpy and MNE-Python read it). Base MATLAB only; also runs in GNU Octave.
%
o = struct('RecordTime', '2026-09-30T12:00:00.000000+00:00', 'BlockSize', 1000, 'Pause', [], ...
    'Gains', [], 'Reference', []);
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
[nCh, N] = size(eeg.data);
fs = eeg.fs;
if abs(fs - round(fs)) > 1e-9, error('NeuroAnalyzer:io:mff', 'MFF needs a whole-number sampling rate.'); end
if ~exist(folder, 'dir'), mkdir(folder); end
X = double(eeg.data);
if ~isempty(o.Gains), X = X ./ o.Gains(:); end
hdr = '<?xml version="1.0" encoding="UTF-8"?>';
writeText(fullfile(folder, 'info.xml'), sprintf(['%s\n<fileInfo xmlns="http://www.egi.com/info_mff">' ...
    '<mffVersion>3</mffVersion><recordTime>%s</recordTime></fileInfo>\n'], hdr, o.RecordTime));
cal = '';
if ~isempty(o.Gains)
    ch = sprintf('<ch n="%d">%.9g</ch>', [1:nCh; o.Gains(:)']);
    cal = sprintf('<calibration><beginTime>0</beginTime><type>GCAL</type><channels>%s</channels></calibration>', ch);
end
writeText(fullfile(folder, 'info1.xml'), sprintf(['%s\n<dataInfo xmlns="http://www.egi.com/info_n_mff">' ...
    '<generalInformation><fileDataType><EEG/></fileDataType></generalInformation><filters/>' ...
    '<calibrations>%s</calibrations></dataInfo>\n'], hdr, cal));
% Pieces and blocks
if isempty(o.Pause), pieces = {1:N}; begins = 0;
else, a = o.Pause(1); pieces = {1:a, a + 1:N}; begins = [0, (a + o.Pause(2)) / fs]; end
fid = fopen(fullfile(folder, 'signal1.bin'), 'w', 'ieee-le');
if fid < 0, error('NeuroAnalyzer:io:mff', 'Cannot write %s', folder); end
ep = zeros(numel(pieces), 4);
nb = 0; lastLen = -1;
for pc = 1:numel(pieces)
    idx = pieces{pc};
    first = nb + 1;
    for s = 1:o.BlockSize:numel(idx)
        i = idx(s:min(end, s + o.BlockSize - 1));
        n = numel(i);
        if n == lastLen
            fwrite(fid, 0, 'int32');
        else
            fwrite(fid, [1, 4 * (5 + 2 * nCh), 4 * n * nCh, nCh], 'int32');
            fwrite(fid, 4 * n * (0:nCh - 1), 'int32');
            fwrite(fid, repmat(round(fs) * 256 + 32, 1, nCh), 'int32');
            fwrite(fid, 0, 'int32');                        % no optional header
        end
        fwrite(fid, X(:, i)', 'float32');
        nb = nb + 1; lastLen = n;
    end
    ep(pc, :) = [round(begins(pc) * 1e6), round((begins(pc) + numel(idx) / fs) * 1e6), first, nb];
end
fclose(fid);
rows = sprintf('<epoch><beginTime>%d</beginTime><endTime>%d</endTime><firstBlock>%d</firstBlock><lastBlock>%d</lastBlock></epoch>', ep');
writeText(fullfile(folder, 'epochs.xml'), sprintf('%s\n<epochs xmlns="http://www.egi.com/epochs_mff">%s</epochs>\n', hdr, rows));
% Sensors
rows = cell(1, nCh);
for k = 1:nCh
    typ = 0; nm = '';
    if isequal(k, o.Reference), typ = 1; nm = eeg.labels{k}; end
    xyz = [NaN NaN NaN];
    if isfield(eeg, 'chanlocs') && numel(eeg.chanlocs) >= k, xyz = [eeg.chanlocs(k).x eeg.chanlocs(k).y eeg.chanlocs(k).z]; end
    pos = '';
    if all(isfinite(xyz)), pos = sprintf('<x>%.6g</x><y>%.6g</y><z>%.6g</z>', xyz); end
    rows{k} = sprintf('<sensor><name>%s</name><number>%d</number><type>%d</type>%s</sensor>', nm, k, typ, pos);
end
writeText(fullfile(folder, 'coordinates.xml'), sprintf(['%s\n<coordinates xmlns="http://www.egi.com/coordinates_mff">' ...
    '<sensorLayout><name>NDAL synthetic</name><sensors>%s</sensors></sensorLayout></coordinates>\n'], hdr, [rows{:}]));
writeText(fullfile(folder, 'sensorLayout.xml'), sprintf(['%s\n<sensorLayout xmlns="http://www.egi.com/sensorLayout_mff">' ...
    '<name>NDAL synthetic</name><sensors>%s</sensors></sensorLayout>\n'], hdr, [rows{:}]));
% Events
t0 = sscanf(o.RecordTime(12:end), '%d:%d:%f');
base = o.RecordTime(1:11);
tz = o.RecordTime(end-5:end);
rows = cell(1, numel(eeg.events));
for k = 1:numel(eeg.events)
    e = eeg.events(k);
    s = t0(1) * 3600 + t0(2) * 60 + t0(3) + e.latency;       % same day
    rows{k} = sprintf(['<event><beginTime>%s%02d:%02d:%09.6f%s</beginTime><duration>%d</duration>' ...
        '<code>%s</code><label>%s</label></event>'], base, floor(s / 3600), floor(mod(s, 3600) / 60), ...
        mod(s, 60), tz, round(e.duration * 1e9), e.type, e.type);
end
writeText(fullfile(folder, 'Events.xml'), sprintf(['%s\n<eventTrack xmlns="http://www.egi.com/event_mff">' ...
    '<name>Events</name><trackType>EVNT</trackType>%s</eventTrack>\n'], hdr, [rows{:}]));
end

function writeText(f, s)
fid = fopen(f, 'w');
if fid < 0, error('NeuroAnalyzer:io:mff', 'Cannot write %s', f); end
fwrite(fid, s, 'char');
fclose(fid);
end
