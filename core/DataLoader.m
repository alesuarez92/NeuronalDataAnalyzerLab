%% DataLoader.m
% =========================================================================
% DATALOADER - LOAD LDF EXPORT .MAT FILES WITH VALIDATION
% =========================================================================
% Static class. load(AppData, varargin) loads a .mat file that contains
% LDF export format: a single 'data' vector plus 'datastart' and 'dataend'
% index arrays per channel. Fills AppData.RawStim, AppData.RawLDF,
% AppData.SamplingRate, AppData.FilePath, and optional AppData.Metadata.
% Optional name-value args: 'StimChannel', 6, 'LDFChannel', 8.
% For unit tests: 'FromStruct', d uses struct d instead of opening a file
% (no uigetfile). On error or user cancel, returns without changing AppData
% (or returns early so caller keeps previous state).
% =========================================================================

classdef DataLoader
    methods(Static)

        %% load - Load LDF data from file or from struct (testing)
        % -----------------------------------------------------------------
        % INPUT:  AppData - struct with at least RawStim, RawLDF, FilePath,
        %                   SamplingRate, Metadata (can be empty)
        %         varargin - optional 'StimChannel', k, 'LDFChannel', j,
        %                    'FromStruct', d (d = pre-loaded struct, skip file)
        % OUTPUT: AppData - updated with RawStim, RawLDF, SamplingRate,
        %                  FilePath, Metadata. If user cancels or error, returns
        %                  input AppData unchanged (early return).
        % Flow: (1) Parse options; (2) get d from file or FromStruct;
        %       (3) validate with Validation.isValidLDFStruct(d);
        %       (4) check channel indices in range; (5) extract channel slices;
        %       (6) set sampling rate from d.samplerate or default 1000;
        %       (7) copy optional metadata fields if present.
        % -----------------------------------------------------------------
        function AppData = load(AppData, varargin)
            % --- Parse optional arguments (channel indices and test-mode struct) ---
            p = inputParser;
            addParameter(p, 'StimChannel', 6);
            addParameter(p, 'LDFChannel', 8);
            addParameter(p, 'FromStruct', []);
            parse(p, varargin{:});
            stim_idx = p.Results.StimChannel;
            ldf_idx  = p.Results.LDFChannel;
            d = p.Results.FromStruct;

            % --- Get data: either from file dialog or from passed struct ---
            if isempty(d)
                initPath = ProjectManager.getImportDir();
                if isempty(initPath), initPath = pwd; end
                [file, path] = uigetfile(fullfile(initPath, '*.mat'));
                if isequal(file, 0)
                    return;  % User cancelled; AppData unchanged
                end
                fullPath = fullfile(path, file);
                try
                    d = load(fullPath);
                catch ME
                    errordlg(sprintf('Could not load file: %s', ME.message), 'Load Error');
                    return;
                end
                AppData.FilePath = fullPath;
            else
                AppData.FilePath = '';
            end

            % --- Validate file structure before indexing ---
            if ~Validation.isValidLDFStruct(d)
                errordlg('Not a valid LDF export: file must contain data, datastart, and dataend.', 'Invalid File');
                return;
            end

            % --- Ensure channel indices are within datastart/dataend length ---
            maxIdx = max(numel(d.datastart), numel(d.dataend));
            if stim_idx < 1 || stim_idx > maxIdx || ldf_idx < 1 || ldf_idx > maxIdx
                errordlg(sprintf('Channel indices out of range (1-%d).', maxIdx), 'Invalid Channels');
                return;
            end

            % --- Extract stimulus and LDF channel time series ---
            try
                AppData.RawStim = d.data(d.datastart(stim_idx):d.dataend(stim_idx));
                AppData.RawLDF  = d.data(d.datastart(ldf_idx):d.dataend(ldf_idx));
            catch ME
                errordlg(sprintf('Error reading channels: %s', ME.message), 'Load Error');
                return;
            end

            % --- Sampling rate: from file or default 1000 Hz ---
            if isfield(d, 'samplerate') && numel(d.samplerate) >= max(stim_idx, ldf_idx)
                fs_stim = d.samplerate(stim_idx);
                fs_ldf  = d.samplerate(ldf_idx);
                if fs_stim ~= fs_ldf
                    warning('Sampling rate mismatch: Stim = %d Hz, LDF = %d Hz', fs_stim, fs_ldf);
                end
                AppData.SamplingRate = fs_ldf;
            else
                AppData.SamplingRate = 1000;
                warning('Sampling rate not found or invalid, defaulting to 1000 Hz');
            end

            % --- Metadata: copy optional fields only if present (avoid errors) ---
            AppData.Metadata = struct();
            if isfield(d, 'titles'),        AppData.Metadata.ChannelTitles = d.titles; end
            if isfield(d, 'unittext'),      AppData.Metadata.Units = d.unittext; end
            if isfield(d, 'samplerate'),    AppData.Metadata.SampleRateRaw = d.samplerate; end
            if isfield(d, 'rangemin'),      AppData.Metadata.RangeMin = d.rangemin; end
            if isfield(d, 'rangemax'),      AppData.Metadata.RangeMax = d.rangemax; end
            if isfield(d, 'blocktimes'),    AppData.Metadata.BlockTimes = d.blocktimes; end
            if isfield(d, 'com'),           AppData.Metadata.Comments = d.com; end
            if isfield(d, 'comtext'),       AppData.Metadata.CommentText = d.comtext; end
            if isfield(d, 'firstsampleoffset'), AppData.Metadata.FirstSampleOffset = d.firstsampleoffset; end
        end
    end
end
