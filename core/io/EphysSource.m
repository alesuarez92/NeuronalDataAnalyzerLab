%% EphysSource.m
% =========================================================================
% EPHYS SOURCE - ONE ADAPTER FOR THE ELECTROPHYSIOLOGY RECORDING FORMATS
% =========================================================================
% Every acquisition format is read into the struct shape Extract Ephys
% already uses for TDT tanks (TDTbin2mat), so the rest of the pipeline is
% format-agnostic:
%   rec.streams.xRAW.data  neural channels x samples (single, volts)
%   rec.streams.xRAW.fs    sample rate (Hz); .channel = 1:nChannels
%   rec.streams.Whis.data  candidate stimulus channels x samples (single)
%   rec.streams.Whis.fs    stimulus sample rate (Hz); .channel = 1:nStim
%   rec.info               source, format, file, blockname, duration (s),
%                          channelNames, stimNames, stimKinds, ... (plus
%                          whatever the underlying reader adds)
%
%   list = EphysSource.formats()        struct array: key, label, pick
%                                       ('folder' | 'file'), filter, prompt, hint
%   fmt  = EphysSource.detect(path)     a format key (by extension, folder
%                                       contents or the first bytes)
%   rec  = EphysSource.open(path, fmt)  read with the matching reader
%                                       (fmt 'auto' or omitted: detect)
%   rec  = EphysSource.makeRecording(raw, fs, stim, stimFs, info)
%   x    = EphysSource.eventsToSquare(onIdx, offIdx, n)  0/1 square wave
%   t    = EphysSource.risingEdges(x, fs, thr)           onset times (s)
%
% Readers: TDT tank folder (TDTbin2mat from the TDT MATLAB SDK, or the
% DemoData stand-in for demo tanks), Intan .rhd (readIntanRHD), Open
% Ephys binary folder (readOpenEphysBinary), NWB 2.x file (readNWB),
% SpikeGLX (readSpikeGLX), Blackrock NSx / NEV (readBlackrock), Neuralynx
% .ncs folder (readNeuralynx), Plexon .plx (readPlexon), Multi Channel
% Systems HDF5 (readMCS), Intan .rhs (readIntanRHS), Open Ephys legacy
% .continuous folder (readOpenEphysLegacy), Axon ABF 2 (readABF).
% Errors: NeuroAnalyzer:io:fileNotFound, NeuroAnalyzer:io:unknownFormat.
% Toolboxes: none (TDT tanks need the TDT MATLAB SDK).
% =========================================================================

classdef EphysSource
    methods(Static)

        %% formats - Supported sources, in dropdown order
        function list = formats()
            list = struct( ...
                'key',    {'tdt', 'intan', 'openephys', 'nwb', 'spikeglx', 'blackrock', 'neuralynx', ...
                           'plexon', 'mcs', 'intanrhs', 'openephyslegacy', 'abf'}, ...
                'label',  {'TDT tank', 'Intan .rhd', 'Open Ephys folder', 'NWB file', 'SpikeGLX', ...
                           'Blackrock NSx', 'Neuralynx folder', 'Plexon .plx', 'Multi Channel Systems HDF5', ...
                           'Intan .rhs', 'Open Ephys legacy folder', 'Axon ABF'}, ...
                'pick',   {'folder', 'file', 'folder', 'file', 'file', 'file', 'folder', 'file', 'file', ...
                           'file', 'folder', 'file'}, ...
                'filter', {{}, {'*.rhd', 'Intan RHD2000 data file (*.rhd)'}, {}, ...
                           {'*.nwb;*.h5;*.hdf5', 'NWB file (*.nwb, *.h5)'}, ...
                           {'*.bin;*.meta', 'SpikeGLX binary or metadata (*.bin, *.meta)'}, ...
                           {'*.ns1;*.ns2;*.ns3;*.ns4;*.ns5;*.ns6;*.nev', 'Blackrock NSx / NEV (*.ns1-*.ns6, *.nev)'}, {}, ...
                           {'*.plx', 'Plexon data file (*.plx)'}, ...
                           {'*.h5;*.hdf5', 'Multi Channel Systems HDF5 (*.h5)'}, ...
                           {'*.rhs', 'Intan RHS2000 data file (*.rhs)'}, {}, ...
                           {'*.abf', 'Axon Binary File (*.abf)'}}, ...
                'prompt', {'Select TDT Tank Folder', 'Select Intan .rhd file', ...
                           'Select Open Ephys recording folder (contains structure.oebin)', ...
                           'Select NWB file', 'Select SpikeGLX .bin or .meta file', ...
                           'Select Blackrock .ns1-.ns6 file', 'Select Neuralynx session folder (.ncs files)', ...
                           'Select Plexon .plx file', 'Select Multi Channel Systems HDF5 file', ...
                           'Select Intan .rhs file', 'Select Open Ephys legacy folder (.continuous files)', ...
                           'Select Axon .abf file'}, ...
                'hint',   {'Choose a TDT tank/block folder (needs Whis and xRAW streams)', ...
                           'Choose an Intan RHD2000 .rhd file (amplifier channels; stimulus from a digital or analog input)', ...
                           'Choose an Open Ephys binary recording folder, or a parent folder (stimulus from TTL lines or ADC channels)', ...
                           'Choose an NWB 2.x file (ElectricalSeries; stimulus from a stimulus TimeSeries or the trials table)', ...
                           'Choose a SpikeGLX imec (.ap / .lf) or nidq .bin with its .meta (stimulus from the sync or digital lines, or an analog input)', ...
                           'Choose a Blackrock .ns1-.ns6 file (electrodes; stimulus from analog inputs or the .nev digital input)', ...
                           'Choose a Neuralynx folder with .ncs channels (stimulus from the TTL bits in Events.nev)', ...
                           'Choose a Plexon .plx file (continuous channels; stimulus from AI channels or events)', ...
                           'Choose a Multi Channel Systems HDF5 file exported by Multi Channel DataManager (stimulus from auxiliary, digital or event streams)', ...
                           'Choose an Intan RHS2000 .rhs file (stimulus from a digital input, an analog input or the stimulation current)', ...
                           'Choose an Open Ephys folder of .continuous files (stimulus from ADC channels or TTL events)', ...
                           'Choose an Axon ABF 2 file (sweeps put one after the other; stimulus from a current or TTL channel)'});
        end

        %% label - Display label of a format key
        function s = label(fmt)
            list = EphysSource.formats();
            k = find(strcmpi({list.key}, fmt), 1);
            if isempty(k), s = fmt; else, s = list(k).label; end
        end

        %% detect - Guess the format of a file or folder
        function fmt = detect(p)
            if exist(p, 'dir') == 7
                if exist(fullfile(p, 'structure.oebin'), 'file') == 2
                    fmt = 'openephys';
                elseif EphysSource.isDemoTank(p) || ~isempty(dir(fullfile(p, '*.tsq'))) ...
                        || ~isempty(dir(fullfile(p, '*.tev'))) || ~isempty(dir(fullfile(p, '*.sev')))
                    fmt = 'tdt';
                elseif ~isempty(dir(fullfile(p, '*.continuous')))
                    fmt = 'openephyslegacy';
                elseif ~isempty(dir(fullfile(p, '*.ncs')))
                    fmt = 'neuralynx';
                elseif ~isempty(EphysSource.findFile(p, 'structure.oebin', 4))
                    fmt = 'openephys';
                else
                    fmt = 'tdt';
                end
                return;
            end
            if ~(exist(p, 'file') == 2)
                error('NeuroAnalyzer:io:fileNotFound', 'File or folder not found: %s', p);
            end
            [~, ~, ext] = fileparts(p);
            switch lower(ext)
                case '.rhd',                  fmt = 'intan'; return;
                case '.rhs',                  fmt = 'intanrhs'; return;
                case '.oebin',                fmt = 'openephys'; return;
                case '.continuous',           fmt = 'openephyslegacy'; return;
                case '.ncs',                  fmt = 'neuralynx'; return;
                case '.abf',                  fmt = 'abf'; return;
                case '.plx',                  fmt = 'plexon'; return;
                case {'.ns1', '.ns2', '.ns3', '.ns4', '.ns5', '.ns6'}, fmt = 'blackrock'; return;
                case {'.nwb', '.h5', '.hdf5'}, fmt = EphysSource.hdf5Kind(p); return;
                case '.meta',                 fmt = 'spikeglx'; return;
                case '.bin'
                    [d, b] = fileparts(p);
                    if exist(fullfile(d, [b '.meta']), 'file') == 2, fmt = 'spikeglx'; return; end
            end
            % Unknown extension (or .nev: Blackrock or Neuralynx): look at the first bytes
            fid = fopen(p, 'r', 'ieee-le');
            if fid < 0
                error('NeuroAnalyzer:io:fileNotFound', 'Cannot open %s', p);
            end
            b = fread(fid, 18, 'uint8=>double')';
            fclose(fid);
            head = char(b(1:min(8, end)));
            if numel(b) >= 4 && isequal(b(1:4), [2 39 145 198])        % 0xC6912702, little-endian
                fmt = 'intan';
            elseif numel(b) >= 4 && isequal(b(1:4), [172 39 145 214])  % 0xD69127AC: RHS2000
                fmt = 'intanrhs';
            elseif numel(b) >= 8 && isequal(b(1:8), [137 72 68 70 13 10 26 10])   % HDF5 signature
                fmt = EphysSource.hdf5Kind(p);
            elseif strncmp(head, 'ABF', 3)
                fmt = 'abf';
            elseif strncmp(head, 'PLEX', 4)
                fmt = 'plexon';
            elseif any(strcmp(head, {'NEURALCD', 'NEURALSG', 'BRSMPGRP', 'NEURALEV', 'BREVENTS'}))
                fmt = 'blackrock';
            elseif strncmp(char(b), '######## Neuralynx', 18)
                fmt = 'neuralynx';
            elseif strncmp(head, 'header.', 7)
                fmt = 'openephyslegacy';
            else
                error('NeuroAnalyzer:io:unknownFormat', ['Cannot tell the recording format of %s. ' ...
                    'Supported: TDT tank folder, Intan .rhd / .rhs, Open Ephys folder (binary or legacy), ' ...
                    'NWB, SpikeGLX, Blackrock, Neuralynx, Plexon .plx, Multi Channel Systems HDF5, Axon ABF.'], p);
            end
        end

        %% hdf5Kind - 'mcs' for a Multi Channel Systems HDF5 file, else 'nwb'
        function fmt = hdf5Kind(p)
            fmt = 'nwb';
            try
                I = h5info(p, '/');
                if any(strcmp({I.Attributes.Name}, 'McsHdf5ProtocolType')), fmt = 'mcs'; end
            catch
            end
        end

        %% open - Read a recording with the reader for its format
        function rec = open(p, fmt)
            if nargin < 2 || isempty(fmt) || strcmpi(fmt, 'auto')
                fmt = EphysSource.detect(p);
            end
            switch lower(fmt)
                case 'tdt',             rec = EphysSource.openTDT(p);
                case 'intan',           rec = readIntanRHD(p);
                case 'openephys',       rec = readOpenEphysBinary(p);
                case 'nwb',             rec = readNWB(p);
                case 'spikeglx',        rec = readSpikeGLX(p);
                case 'blackrock',       rec = readBlackrock(p);
                case 'neuralynx',       rec = readNeuralynx(p);
                case 'plexon',          rec = readPlexon(p);
                case 'mcs',             rec = readMCS(p);
                case 'intanrhs',        rec = readIntanRHS(p);
                case 'openephyslegacy', rec = readOpenEphysLegacy(p);
                case 'abf',             rec = readABF(p);
                otherwise
                    list = EphysSource.formats();
                    error('NeuroAnalyzer:io:unknownFormat', ...
                        'Unknown format ''%s'' (use %s).', fmt, strjoin({list.key}, ', '));
            end
        end

        %% openTDT - TDTbin2mat (or the DemoData stand-in for a demo tank)
        % The streams are returned exactly as TDTbin2mat gives them; only
        % info fields (source, format, file, channelNames, stimNames) are added.
        function data = openTDT(folder)
            if EphysSource.isDemoTank(folder)
                data = DemoData.loadTank(folder);   % TDTbin2mat stand-in
            else
                % Resolve the SDK relative to the toolbox root (core/io/../..), not pwd
                rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
                addpath(genpath(fullfile(rootDir, 'Utilities', 'TDTMatlabSDK')));
                data = TDTbin2mat(folder);
            end
            if ~isfield(data, 'info') || ~isstruct(data.info), data.info = struct(); end
            data.info.source = 'TDT';
            data.info.format = 'tdt';
            data.info.file = folder;
            if isfield(data, 'streams') && isfield(data.streams, 'xRAW')
                n = size(data.streams.xRAW.data, 1);
                data.info.channelNames = arrayfun(@(c) sprintf('Ch %d', c), 1:n, 'UniformOutput', false);
            end
            if isfield(data, 'streams') && isfield(data.streams, 'Whis')
                n = size(data.streams.Whis.data, 1);
                data.info.stimNames = arrayfun(@(c) sprintf('Whis Ch %d', c), 1:n, 'UniformOutput', false);
                data.info.stimKinds = repmat({'analog'}, 1, n);
            end
        end

        %% isDemoTank - DemoData demo tank folder (without needing DemoData on the path)
        function tf = isDemoTank(folder)
            tf = exist(fullfile(folder, 'demo_tank.mat'), 'file') == 2;
        end

        %% makeRecording - Assemble the common struct from arrays
        % raw: channels x samples (volts); stim: stimulus channels x samples
        % ([] = none: a zero row at the raw rate named '(no stimulus channel)').
        % info: fields to keep; missing standard fields get defaults.
        function rec = makeRecording(raw, fs, stim, stimFs, info)
            if nargin < 5 || isempty(info), info = struct(); end
            nCh = size(raw, 1);
            n = size(raw, 2);
            if isempty(stim)
                stim = zeros(1, n, 'single');
                stimFs = fs;
                info.stimNames = {'(no stimulus channel)'};
                info.stimKinds = {'none'};
            end
            nStim = size(stim, 1);
            defaults = struct('source', '', 'format', '', 'file', '', 'blockname', 'recording', ...
                'duration', n / fs, ...
                'channelNames', {arrayfun(@(c) sprintf('Ch %d', c), 1:nCh, 'UniformOutput', false)}, ...
                'stimNames', {arrayfun(@(c) sprintf('Stim %d', c), 1:nStim, 'UniformOutput', false)}, ...
                'stimKinds', {repmat({'analog'}, 1, nStim)}, 'units', 'V');
            f = fieldnames(defaults);
            for k = 1:numel(f)
                if ~isfield(info, f{k}) || isempty(info.(f{k}))
                    info.(f{k}) = defaults.(f{k});
                end
            end
            rec.info = info;
            rec.streams.xRAW = struct('data', single(raw), 'fs', fs, 'channel', 1:nCh);
            rec.streams.Whis = struct('data', single(stim), 'fs', stimFs, 'channel', 1:nStim);
        end

        %% eventsToSquare - 0/1 row of n samples, high from each on to the next off
        % onIdx / offIdx: 1-based sample indices of rising / falling edges.
        % An off before the first on means the line was high at the start;
        % an on without a later off stays high to the end.
        function x = eventsToSquare(onIdx, offIdx, n)
            x = zeros(1, n, 'single');
            on = sort(round(onIdx(:)'));
            off = sort(round(offIdx(:)'));
            if ~isempty(off) && (isempty(on) || off(1) < on(1))
                x(1:min(n, max(0, off(1) - 1))) = 1;
            end
            for k = 1:numel(on)
                nxt = off(find(off > on(k), 1));
                if isempty(nxt), nxt = n + 1; end
                i1 = max(1, on(k));
                i2 = min(n, nxt - 1);
                if i1 <= i2, x(i1:i2) = 1; end
            end
        end

        %% risingEdges - Times (s) where x crosses thr upwards (default: mid-range)
        function t = risingEdges(x, fs, thr)
            x = double(x(:)');
            if nargin < 3 || isempty(thr), thr = (min(x) + max(x)) / 2; end
            if isempty(x) || max(x) == min(x)
                t = zeros(1, 0);
                return;
            end
            idx = find(x(1:end-1) < thr & x(2:end) >= thr) + 1;
            t = (idx - 1) / fs;
        end

        %% findFile - First file called name under root (depth-limited, sorted)
        function p = findFile(root, name, maxDepth)
            p = '';
            if nargin < 3, maxDepth = 4; end
            if exist(fullfile(root, name), 'file') == 2
                p = fullfile(root, name);
                return;
            end
            if maxDepth <= 0, return; end
            d = dir(root);
            d = d([d.isdir] & ~ismember({d.name}, {'.', '..'}));
            names = sort({d.name});
            for k = 1:numel(names)
                p = EphysSource.findFile(fullfile(root, names{k}), name, maxDepth - 1);
                if ~isempty(p), return; end
            end
        end
    end
end
