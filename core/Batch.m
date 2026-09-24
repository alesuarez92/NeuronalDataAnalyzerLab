%% Batch.m
% =========================================================================
% BATCH - RUN ONE PIPELINE WITH THE SAME SETTINGS ON MANY FILES
% =========================================================================
% Headless batch runner behind the Batch processing window (BatchApp).
% Every file of a folder (or list) goes through one pipeline with one set
% of settings; the results are collected in one summary table (CSV and
% MAT) plus a text log. A file that fails (unreadable, wrong variables,
% no trials, ...) is recorded in the table with Status 'error' and its
% message, and the batch carries on with the next file.
%
%   names = Batch.pipelines()          {'ldf', 'erp', 'mua', 'roi', 'features'}
%   d = Batch.describe(pipeline)       label, input, output, extensions
%   p = Batch.defaults(pipeline)       default settings (see below)
%   spec = Batch.paramSpec(pipeline)   the main settings as form fields
%                                      (name, label, kind, value, items,
%                                      limits, tooltip); used by BatchApp
%   p = Batch.completeParams(pipeline, p)  missing fields from defaults
%   files = Batch.listInputs(inputs, pipeline)
%       inputs: a folder (all files with the pipeline's extensions, sorted
%       by name), one file, or a cellstr of files and/or folders.
%   R = Batch.run(pipeline, inputs, params, outFolder, Name, Value, ...)
%       Runs the batch and writes to outFolder (created if needed; empty =
%       tempdir/NeuroAnalyzerBatch):
%         <Name>_summary.csv   summary table
%         <Name>_summary.mat   summary (table) and batch (struct: pipeline,
%                              params, files, fileStatus, messages, log)
%         <Name>_log.txt       settings + one line per file
%         trials/<file>_segments.mat   ('ldf' with saveTrials) the trials in
%                              the LDF Processing format (segmentedLDF,
%                              segmentedTime, Fs): LDF Average reads them
%       Options: 'Name' (file prefix; default batch_<pipeline>_<yyyymmdd_HHMMSS>),
%       'Progress' (function (k, n, fileName, status, message), called with
%       status 'running' before and 'ok' | 'warning' | 'error' after each
%       file), 'Cancel' (function returning true to stop before the next
%       file; the files left are recorded as 'skipped'), 'Echo' (true:
%       print the log lines to the command window; default false).
%       R: pipeline, params, files (cellstr), summary (table: File, Status,
%       Message, then the pipeline's columns), fileStatus (cellstr per file),
%       messages (cellstr per file), log (cellstr), paths (folder, csv,
%       mat, log, trials), nOK, nWarning, nError, nSkipped, cancelled,
%       elapsed (s).
%   [rows, info] = Batch.processFile(pipeline, file, params, outFolder)
%       One file: rows is a struct array (one element per summary row),
%       info a one-line description for the log. Throws on failure.
%   [vals, baseVal, dirn] = Batch.seriesFeatures(t, y, t0, bl, dirChoice)
%       The nine response features of one trace (Batch.FeatureNames
%       order), with Signal Characterization's rules: baseline = mean of y
%       in bl = [start end] (s; [] = first 0.05 s; empty window: pre-t0
%       mean), direction 'Auto' = larger deflection after t0.
%
% Pipelines, their input and one summary row (settings: Batch.defaults):
%   'ldf'       cropped LDF .mat (stim, LDF, t, Fs from Extract LDF) ->
%               LDFPipeline (decimate by downsample, filter, segment trials
%               around onsets: threshold, preSec, postSec, minISI) -> the
%               response features of the mean trial (t0 = 0, baseline =
%               the pre-onset window). Row per file: Fs_Hz, nOnsets,
%               nTrials, Baseline, features, TrialFile.
%   'erp'       LFP .mat (lfp_data, stim_data, lfp_fs, stim_fs from Extract
%               Ephys) -> ERPAnalysis (onsets: threshold on the mean-
%               subtracted stimulus, minISI; epochs preTime..postTime) and,
%               with computeCSD and >= 3 channels, ERPAnalysis.csd in the
%               given channel order (spacingUm). Row per channel: N1 =
%               minimum of the ERP in n1WindowMs, P2 = maximum in
%               p2WindowMs (latency in ms, amplitude relative to the
%               pre-onset mean, times amplitudeScale, unit amplitudeUnit),
%               CSD minimum in n1WindowMs (AmpUnit / mm^2) and the sink
%               channel of the file (most negative CSD).
%   'mua'       MUA .mat (mua_data, mua_fs; t_mua, mua_channels, stim_*
%               optional, from Extract Ephys) -> MUAPipeline.sort per
%               channel with the global random stream seeded (rng(seed,
%               'twister'), restored afterwards) so k-means is repeatable.
%               Row per channel: spikes, units (good / rejected by the QC:
%               SNR < 2 or > 2% ISIs < refractory), rates, mean SNR, max
%               ISI violations and, with a stimulus, the rate in
%               responseWindowMs vs baselineWindowMs around each onset
%               (SpikeTrains.stimulusOnsets: stimThreshold, stimMinISI).
%   'roi'       imaging .mat (stack or frames, timeVec or t, roiMask or
%               roiMasks) or multi-frame TIFF -> grayscale stack (optional
%               rigid motion correction) -> per ROI: mean brightness
%               (roiIntensityOverTime) and dF/F (deltaFOverF, baseline =
%               first baselineFrames frames); with a line [x1 y1 x2 y2]:
%               vessel diameter (vesselDiameterFromLine, FWHM, 'Robust'
%               option). Row per ROI (one row when only the diameter).
%   'features'  any file Signal Characterization reads (segmentedLDF +
%               segmentedTime, lfp_data + t_lfp, t + y, t + LDF) -> the
%               nine features of the mean of the series (seriesMode 'Mean
%               of series', one row per file) or of every series ('Each
%               series', one row per series).
%
% Requires: Signal Processing Toolbox for 'ldf' (decimate, butter,
% filtfilt) and 'mua' (findpeaks); Statistics and Machine Learning
% Toolbox for 'mua' (pca, kmeans). 'erp', 'roi' and 'features' use base
% MATLAB only (Image Processing Toolbox not needed).
% =========================================================================

classdef Batch
    properties(Constant)
        % Feature columns, in Signal Characterization's order
        FeatureNames = {'Peak latency', 'Onset delay (50%)', 'FWHM', 'AUC positive', ...
            'AUC negative', 'Rise time', 'Decay time', 'Peak amplitude', 'Stim-response integral'}
        FeatureColumns = {'PeakLatency_s', 'OnsetDelay_s', 'FWHM_s', 'AUCpos', 'AUCneg', ...
            'RiseTime_s', 'DecayTime_s', 'PeakAmp', 'Integral'}
        FilterTypes = {'None', 'Low-pass', 'High-pass', 'Band-pass', 'Notch'}
        FilterDesigns = {'Butterworth', 'Chebyshev I', 'FIR'}
    end

    methods(Static)

        %% pipelines - Pipeline keys, in menu order
        function names = pipelines()
            names = {'ldf', 'erp', 'mua', 'roi', 'features'};
        end

        %% describe - Label, input, output and file extensions of a pipeline
        function d = describe(pipeline)
            pipeline = Batch.checkPipeline(pipeline);
            switch pipeline
                case 'ldf'
                    d = struct('label', 'LDF: trials + response features', ...
                        'input', 'Cropped LDF .mat files (stim, LDF, t, Fs) from LDF Extract', ...
                        'output', 'One row per file: trials, peak latency / amplitude and the other response features of the mean trial; trial files for LDF Average', ...
                        'extensions', {{'.mat'}});
                case 'erp'
                    d = struct('label', 'LFP: ERP (+ CSD) per channel', ...
                        'input', 'LFP .mat files (lfp_data, stim_data, lfp_fs, stim_fs) from Extract Ephys', ...
                        'output', 'One row per channel: N1 / P2 latency and amplitude, CSD minimum, sink channel', ...
                        'extensions', {{'.mat'}});
                case 'mua'
                    d = struct('label', 'MUA: spike sorting per channel', ...
                        'input', 'MUA .mat files (mua_data, mua_fs; stim_data optional) from Extract Ephys', ...
                        'output', 'One row per channel: spikes, units, rates, SNR, ISI violations, evoked vs baseline rate', ...
                        'extensions', {{'.mat'}});
                case 'roi'
                    d = struct('label', 'Imaging: ROI dF/F and vessel diameter', ...
                        'input', 'Image stacks: .mat (stack, timeVec, roiMask) or multi-frame TIFF', ...
                        'output', 'One row per ROI: mean brightness, peak dF/F and its time; vessel diameter along a line', ...
                        'extensions', {{'.mat', '.tif', '.tiff'}});
                otherwise  % features
                    d = struct('label', 'Response features (any trace file)', ...
                        'input', 'Segmented LDF, LFP / ERP export or any t / y .mat (as Signal Characterization)', ...
                        'output', 'One row per file (mean of its series) or per series: the nine response features', ...
                        'extensions', {{'.mat'}});
            end
        end

        %% defaults - Default settings of a pipeline
        function p = defaults(pipeline)
            pipeline = Batch.checkPipeline(pipeline);
            switch pipeline
                case 'ldf'
                    p = struct('downsample', 10, 'filterType', 'Low-pass', 'designType', 'Butterworth', ...
                        'filterOrder', 4, 'cutoffLow', 0.05, 'cutoffHigh', 1, ...
                        'threshold', 2.5, 'preSec', 5, 'postSec', 20, 'minISI', 1, ...
                        'direction', 'Auto', 'saveTrials', true);
                case 'erp'
                    p = struct('preTime', 0.1, 'postTime', 0.3, 'threshold', 0.5, 'minISI', 0.5, ...
                        'channels', [], 'n1WindowMs', [5 50], 'p2WindowMs', [20 150], ...
                        'computeCSD', true, 'spacingUm', 100, ...
                        'amplitudeScale', 1e6, 'amplitudeUnit', 'uV');
                case 'mua'
                    p = struct('channels', [], 'detectMethod', 'MAD', 'threshold', 4, ...
                        'polarity', 'negative', 'featureMethod', 'PCA', 'clusterMethod', 'K-means', ...
                        'minSpikesPerCluster', 20, 'autoMerge', true, 'seed', 0, ...
                        'stimThreshold', 0.5, 'stimMinISI', 1, ...
                        'responseWindowMs', [5 55], 'baselineWindowMs', [-100 0]);
                case 'roi'
                    p = struct('measure', 'All', 'baselineFrames', 30, 'line', [], ...
                        'robust', true, 'motionCorrection', false, 'roiMask', []);
                otherwise  % features
                    p = struct('t0', 0, 'autoBaseline', true, 'baselineStart', 0, 'baselineEnd', 0.05, ...
                        'direction', 'Auto', 'seriesMode', 'Mean of series');
            end
        end

        %% paramSpec - Main settings of a pipeline as form fields (BatchApp)
        % kind: 'numeric' (limits) | 'vector' (numbers typed as text, may be
        % empty) | 'dropdown' (items) | 'checkbox' | 'text'.
        function spec = paramSpec(pipeline)
            pipeline = Batch.checkPipeline(pipeline);
            d = Batch.defaults(pipeline);
            switch pipeline
                case 'ldf'
                    rows = {
                        'downsample', 'Downsample (x)', 'numeric', {}, [1 1000], 'Integer decimation factor applied to the LDF (1 = none); e.g. 10 turns 1000 Hz into 100 Hz'
                        'filterType', 'Filter', 'dropdown', Batch.FilterTypes, [], 'Zero-phase filter applied after downsampling'
                        'designType', 'Design', 'dropdown', Batch.FilterDesigns, [], 'Filter design (Chebyshev I: 0.5 dB ripple)'
                        'filterOrder', 'Order', 'numeric', {}, [1 100], 'Filter order (2-4 is usually enough)'
                        'cutoffLow', 'Low cutoff (Hz)', 'numeric', {}, [0 Inf], 'High-pass, band-pass and notch: lower cutoff in Hz (below Nyquist after downsampling)'
                        'cutoffHigh', 'High cutoff (Hz)', 'numeric', {}, [0 Inf], 'Low-pass, band-pass and notch: upper cutoff in Hz (below Nyquist after downsampling)'
                        'threshold', 'Stim threshold', 'numeric', {}, [-Inf Inf], 'Stimulus level (stimulus units, e.g. V) whose rising crossing marks an onset'
                        'preSec', 'Pre-onset (s)', 'numeric', {}, [0 Inf], 'Seconds kept before each onset (baseline for the features)'
                        'postSec', 'Post-onset (s)', 'numeric', {}, [0 Inf], 'Seconds kept after each onset'
                        'minISI', 'Min interval (s)', 'numeric', {}, [0 Inf], 'Minimum time between two onsets; extra edges closer than this are ignored'
                        'direction', 'Direction', 'dropdown', {'Auto', 'Positive', 'Negative'}, [], 'Response polarity for the features (Auto: larger deflection)'
                        'saveTrials', 'Save trial files', 'checkbox', {}, [], 'Also save each file''s trials (segmentedLDF, segmentedTime, Fs) in <output>/trials for LDF Average'};
                case 'erp'
                    rows = {
                        'preTime', 'Pre-stimulus (s)', 'numeric', {}, [0 Inf], 'Epoch start before each onset, in seconds'
                        'postTime', 'Post-stimulus (s)', 'numeric', {}, [0 Inf], 'Epoch end after each onset, in seconds'
                        'threshold', 'Stim threshold', 'numeric', {}, [-Inf Inf], 'Onset threshold on the mean-subtracted stimulus (stimulus units)'
                        'minISI', 'Min ISI (s)', 'numeric', {}, [0 Inf], 'Crossings closer than this (s) to the previous one are ignored'
                        'channels', 'Channels', 'vector', {}, [], 'Channel numbers (lfp_channels, else rows), top to bottom; empty = all'
                        'n1WindowMs', 'N1 window (ms)', 'vector', {}, [], 'Search window for the N1 trough and the CSD sink, ms after onset, e.g. 5 50'
                        'p2WindowMs', 'P2 window (ms)', 'vector', {}, [], 'Search window for the P2 peak, ms after onset, e.g. 20 150'
                        'computeCSD', 'Compute CSD', 'checkbox', {}, [], 'Current source density across the channels (needs >= 3 channels)'
                        'spacingUm', 'Spacing (µm)', 'numeric', {}, [0 Inf], 'Distance between neighbouring electrodes in micrometres'
                        'amplitudeScale', 'Amplitude scale', 'numeric', {}, [0 Inf], 'Amplitudes are multiplied by this (1e6: volts to microvolts)'
                        'amplitudeUnit', 'Amplitude unit', 'text', {}, [], 'Unit label written to the AmpUnit column (after scaling)'};
                case 'mua'
                    rows = {
                        'channels', 'Channels', 'vector', {}, [], 'Channel numbers (mua_channels, else rows); empty = all'
                        'detectMethod', 'Detection', 'dropdown', {'Standard', 'MAD', 'NEO', 'Rolling MAD', 'Percentile'}, [], 'Threshold rule (MAD: median + k x robust SD)'
                        'threshold', 'Threshold (k)', 'numeric', {}, [0 Inf], 'Threshold multiplier k (SDs or robust SDs)'
                        'polarity', 'Polarity', 'dropdown', {'negative', 'positive', 'both'}, [], 'Sign of the spikes to detect'
                        'featureMethod', 'Features', 'dropdown', {'PCA', 'Waveform', 'Wavelet', 'ICA', 't-SNE'}, [], 'Waveform features used for clustering'
                        'clusterMethod', 'Clustering', 'dropdown', {'K-means', 'GMM', 'DBSCAN'}, [], 'Clustering method (K-means / GMM: 2-10 clusters by silhouette)'
                        'minSpikesPerCluster', 'Min spikes / cluster', 'numeric', {}, [1 Inf], 'Clusterings with a smaller cluster are rejected'
                        'autoMerge', 'Auto-merge', 'checkbox', {}, [], 'Merge over-split clusters (same shape r >= 0.95 and size ratio >= 0.85)'
                        'seed', 'Random seed', 'numeric', {}, [0 2^32-1], 'rng seed set before every channel so k-means gives the same clusters every run'
                        'stimThreshold', 'Stim threshold', 'numeric', {}, [-Inf Inf], 'Onset threshold on stim_data (stimulus units)'
                        'stimMinISI', 'Stim min ISI (s)', 'numeric', {}, [0 Inf], 'Minimum interval between onsets (s)'
                        'responseWindowMs', 'Response (ms)', 'vector', {}, [], 'Evoked-rate window after each onset, ms, e.g. 5 55'
                        'baselineWindowMs', 'Baseline (ms)', 'vector', {}, [], 'Baseline-rate window around each onset, ms, e.g. -100 0'};
                case 'roi'
                    rows = {
                        'measure', 'Measure', 'dropdown', {'All', 'dF/F', 'Brightness', 'Vessel diameter'}, [], 'All = brightness and dF/F per ROI, plus vessel diameter when a line is given'
                        'baselineFrames', 'dF/F baseline (frames)', 'numeric', {}, [1 Inf], 'F0 = mean of the first N frames of each ROI trace'
                        'line', 'Line x1 y1 x2 y2 (px)', 'vector', {}, [], 'Line across the vessel in pixels, e.g. 45 70 75 70; empty = no diameter'
                        'robust', 'Robust diameter', 'checkbox', {}, [], 'Edge baseline, percentile core and a Hampel filter over time (ignores red blood cells)'
                        'motionCorrection', 'Motion correction', 'checkbox', {}, [], 'Rigid registration of every frame onto the mean image first'};
                otherwise  % features
                    rows = {
                        't0', 'Onset t0 (s)', 'numeric', {}, [-Inf Inf], 'Stimulus onset in each trace; features are measured after t0'
                        'autoBaseline', 'Auto baseline', 'checkbox', {}, [], 'Baseline = pre-onset part of the trace (as Signal Characterization on load); off = window below'
                        'baselineStart', 'Baseline start (s)', 'numeric', {}, [-Inf Inf], 'Start of the baseline window (used when Auto baseline is off)'
                        'baselineEnd', 'Baseline end (s)', 'numeric', {}, [-Inf Inf], 'End of the baseline window (end <= start: first 0.05 s of the trace)'
                        'direction', 'Direction', 'dropdown', {'Auto', 'Positive', 'Negative'}, [], 'Response polarity (Auto: larger deflection after t0)'
                        'seriesMode', 'Series', 'dropdown', {'Mean of series', 'Each series'}, [], 'One row per file (features of the mean trace) or one row per series'};
            end
            spec = struct('name', rows(:, 1), 'label', rows(:, 2), 'kind', rows(:, 3), ...
                'items', rows(:, 4), 'limits', rows(:, 5), 'tooltip', rows(:, 6), 'value', []);
            for k = 1:numel(spec)
                spec(k).value = d.(spec(k).name);
            end
        end

        %% completeParams - Missing fields taken from Batch.defaults
        function p = completeParams(pipeline, p)
            d = Batch.defaults(pipeline);
            if nargin < 2 || isempty(p), p = d; return; end
            fn = fieldnames(d);
            for i = 1:numel(fn)
                if ~isfield(p, fn{i}), p.(fn{i}) = d.(fn{i}); end
            end
        end

        %% listInputs - Files to process from a folder, a file or a list
        function files = listInputs(inputs, pipeline)
            if nargin < 2 || isempty(pipeline), pipeline = 'features'; end
            d = Batch.describe(pipeline);
            ext = d.extensions;
            if ischar(inputs), inputs = {inputs}; end
            files = {};
            for i = 1:numel(inputs)
                item = char(inputs{i});
                if isempty(item), continue; end
                if exist(item, 'dir') == 7
                    listing = dir(item);
                    listing = listing(~[listing.isdir]);
                    names = sort({listing.name});
                    for k = 1:numel(names)
                        [~, ~, e] = fileparts(names{k});
                        if any(strcmpi(e, ext))
                            files{end+1} = fullfile(item, names{k}); %#ok<AGROW>
                        end
                    end
                else
                    files{end+1} = item; %#ok<AGROW>
                end
            end
            files = files(:)';
        end

        %% run - Process every file, collect the summary, write CSV / MAT / log
        function R = run(pipeline, inputs, params, outFolder, varargin)
            pipeline = Batch.checkPipeline(pipeline);
            if nargin < 3, params = []; end
            if nargin < 4 || isempty(outFolder), outFolder = fullfile(tempdir, 'NeuroAnalyzerBatch'); end
            opt = struct('Name', '', 'Progress', [], 'Cancel', [], 'Echo', false);
            for i = 1:2:numel(varargin)
                opt.(Batch.optionName(varargin{i}, fieldnames(opt))) = varargin{i + 1};
            end
            params = Batch.completeParams(pipeline, params);
            files = Batch.listInputs(inputs, pipeline);
            if isempty(files)
                d = Batch.describe(pipeline);
                error('NeuroAnalyzer:Batch:noInputs', 'No input files to process (folder empty or no %s files).', ...
                    strjoin(d.extensions, ' / '));
            end
            if isempty(opt.Name)
                opt.Name = sprintf('batch_%s_%s', pipeline, datestr(now, 'yyyymmdd_HHMMSS')); %#ok<TNOW1,DATST>
            end
            if exist(outFolder, 'dir') ~= 7, mkdir(outFolder); end

            n = numel(files);
            tStart = tic;
            logLines = Batch.logHeader(pipeline, params, files, outFolder);
            if opt.Echo, fprintf('%s\n', logLines{:}); end
            allRows = cell(n, 1);
            fileStatus = repmat({'skipped'}, 1, n);
            messages = repmat({''}, 1, n);
            cancelled = false;
            for k = 1:n
                [~, nm, ex] = fileparts(files{k});
                fname = [nm ex];
                if ~isempty(opt.Cancel) && opt.Cancel()
                    cancelled = true;
                end
                if cancelled
                    messages{k} = 'Cancelled before this file';
                    allRows{k} = struct('File', fname, 'Status', 'skipped', 'Message', messages{k});
                    line = sprintf('[%d/%d] %s: skipped (cancelled)', k, n, fname);
                    logLines{end+1} = line; %#ok<AGROW>
                    if opt.Echo, fprintf('%s\n', line); end
                    continue;
                end
                if ~isempty(opt.Progress), opt.Progress(k, n, fname, 'running', ''); end
                t1 = tic;
                try
                    [rows, info] = Batch.processFile(pipeline, files{k}, params, outFolder);
                    rowStatus = {rows.Status};
                    if all(strcmp(rowStatus, 'error'))
                        fileStatus{k} = 'error';
                        messages{k} = rows(1).Message;
                    elseif any(~strcmp(rowStatus, 'ok'))
                        fileStatus{k} = 'warning';
                        bad = find(~strcmp(rowStatus, 'ok'), 1);
                        messages{k} = sprintf('%d of %d rows failed (first: %s)', ...
                            sum(~strcmp(rowStatus, 'ok')), numel(rows), rows(bad).Message);
                    else
                        fileStatus{k} = 'ok';
                        messages{k} = '';
                    end
                    for r = 1:numel(rows), rows(r).File = fname; end
                    allRows{k} = rows;
                    line = sprintf('[%d/%d] %s: %s, %s (%.1f s)', k, n, fname, upper(fileStatus{k}), ...
                        info, toc(t1));
                    if ~isempty(messages{k}), line = [line ' - ' messages{k}]; end %#ok<AGROW>
                catch ME
                    fileStatus{k} = 'error';
                    messages{k} = Batch.oneLine(ME.message);
                    allRows{k} = struct('File', fname, 'Status', 'error', 'Message', messages{k});
                    line = sprintf('[%d/%d] %s: ERROR (%.1f s) - %s', k, n, fname, toc(t1), messages{k});
                end
                logLines{end+1} = line; %#ok<AGROW>
                if opt.Echo, fprintf('%s\n', line); end
                if ~isempty(opt.Progress), opt.Progress(k, n, fname, fileStatus{k}, messages{k}); end
            end

            summary = Batch.rowsToTable(pipeline, allRows);
            nOK = sum(strcmp(fileStatus, 'ok'));
            nWarn = sum(strcmp(fileStatus, 'warning'));
            nErr = sum(strcmp(fileStatus, 'error'));
            nSkip = sum(strcmp(fileStatus, 'skipped'));
            elapsed = toc(tStart);
            logLines{end+1} = sprintf(['Done in %.1f s: %d file(s) OK, %d with warnings, %d failed, ' ...
                '%d skipped%s.'], elapsed, nOK, nWarn, nErr, nSkip, Batch.ifelse(cancelled, ' (cancelled)', ''));
            if opt.Echo, fprintf('%s\n', logLines{end}); end

            paths = struct('folder', outFolder, ...
                'csv', fullfile(outFolder, [opt.Name '_summary.csv']), ...
                'mat', fullfile(outFolder, [opt.Name '_summary.mat']), ...
                'log', fullfile(outFolder, [opt.Name '_log.txt']), ...
                'trials', '');
            if strcmp(pipeline, 'ldf') && params.saveTrials
                paths.trials = fullfile(outFolder, 'trials');
            end
            batch = struct('pipeline', pipeline, 'params', params, 'files', {files}, ...
                'fileStatus', {fileStatus}, 'messages', {messages}, 'log', {logLines(:)}, ...
                'created', datestr(now, 'yyyy-mm-dd HH:MM:SS')); %#ok<TNOW1,DATST>
            writetable(summary, paths.csv);
            save(paths.mat, 'summary', 'batch');
            Batch.writeLog(paths.log, logLines);

            R = struct('pipeline', pipeline, 'params', params, 'files', {files}, ...
                'summary', summary, 'fileStatus', {fileStatus}, 'messages', {messages}, ...
                'log', {logLines(:)}, 'paths', paths, 'nOK', nOK, 'nWarning', nWarn, ...
                'nError', nErr, 'nSkipped', nSkip, 'cancelled', cancelled, 'elapsed', elapsed);
        end

        %% processFile - Run one file through a pipeline; rows of the summary
        function [rows, info] = processFile(pipeline, file, params, outFolder)
            pipeline = Batch.checkPipeline(pipeline);
            if nargin < 3, params = []; end
            if nargin < 4, outFolder = ''; end
            params = Batch.completeParams(pipeline, params);
            if exist(file, 'file') ~= 2
                error('NeuroAnalyzer:Batch:fileNotFound', 'File not found: %s', file);
            end
            switch pipeline
                case 'ldf',      [rows, info] = Batch.fileLDF(file, params, outFolder);
                case 'erp',      [rows, info] = Batch.fileERP(file, params);
                case 'mua',      [rows, info] = Batch.fileMUA(file, params);
                case 'roi',      [rows, info] = Batch.fileROI(file, params);
                otherwise,       [rows, info] = Batch.fileFeatures(file, params);
            end
        end

        %% seriesFeatures - Nine response features of one trace (Signal Characterization rules)
        function [vals, baseVal, dirn] = seriesFeatures(t, y, t0, bl, dirChoice)
            t = t(:); y = y(:);
            vals = NaN(1, numel(Batch.FeatureNames));
            baseVal = NaN; dirn = 'max';
            if isempty(t) || numel(t) ~= numel(y), return; end
            % Baseline: mean in the window, else the pre-onset mean, else y(1)
            if isempty(bl)
                baseVal = mean(y(t >= t(1) & t < min(t(1) + 0.05, t(end))));
            else
                baseVal = mean(y(t >= bl(1) & t <= bl(2)));
            end
            if ~isfinite(baseVal)
                pre = y(t < t0);
                baseVal = mean(pre(isfinite(pre)));
                if ~isfinite(baseVal), baseVal = y(1); end
            end
            % Direction: 'Auto' = larger deflection after t0
            switch dirChoice
                case 'Positive', dirn = 'max';
                case 'Negative', dirn = 'min';
                otherwise
                    post = y(t >= t0);
                    if ~isempty(post) && (baseVal - min(post)) > (max(post) - baseVal)
                        dirn = 'min';
                    else
                        dirn = 'max';
                    end
            end
            vals(1) = SignalFeatures.peakLatency(t, y, t0, dirn);
            vals(2) = SignalFeatures.onsetDelay(t, y, t0, 0.5, dirn, baseVal);
            vals(3) = SignalFeatures.fwhm(t, y, t0, dirn, baseVal);
            vals(4) = SignalFeatures.aucPositive(t, y, baseVal);
            vals(5) = SignalFeatures.aucNegative(t, y, baseVal);
            vals(6) = SignalFeatures.riseTime(t, y, t0, dirn, baseVal);
            vals(7) = SignalFeatures.decayTime(t, y, t0, dirn, baseVal);
            vals(8) = SignalFeatures.peakAmplitude(t, y, t0, dirn, baseVal);
            stim = zeros(size(y)); stim(t >= t0) = 1;
            vals(9) = SignalFeatures.stimResponseIntegration(t, stim, y, t0);
        end

        %% columns - Summary columns of a pipeline: {name, 'double' | 'char'}
        function cols = columns(pipeline)
            pipeline = Batch.checkPipeline(pipeline);
            feat = [Batch.FeatureColumns(:), repmat({'double'}, numel(Batch.FeatureColumns), 1)];
            switch pipeline
                case 'ldf'
                    cols = [{'Fs_Hz', 'double'; 'nOnsets', 'double'; 'nTrials', 'double'; ...
                        'Baseline', 'double'}; feat; {'TrialFile', 'char'}];
                case 'erp'
                    cols = {'Channel', 'double'; 'nOnsets', 'double'; 'nEpochs', 'double'; ...
                        'N1Latency_ms', 'double'; 'N1Amp', 'double'; 'P2Latency_ms', 'double'; ...
                        'P2Amp', 'double'; 'PeakToPeak', 'double'; 'AmpUnit', 'char'; ...
                        'CSDMin', 'double'; 'CSDMinLatency_ms', 'double'; 'SinkChannel', 'double'};
                case 'mua'
                    cols = {'Channel', 'double'; 'Duration_s', 'double'; 'nDetected', 'double'; ...
                        'nSpikes', 'double'; 'nUnits', 'double'; 'nGoodUnits', 'double'; ...
                        'nRejected', 'double'; 'MeanRate_Hz', 'double'; 'UnitRates_Hz', 'char'; ...
                        'MeanSNR', 'double'; 'MaxISIViol_pct', 'double'; 'nOnsets', 'double'; ...
                        'BaselineRate_Hz', 'double'; 'EvokedRate_Hz', 'double'};
                case 'roi'
                    cols = {'ROI', 'char'; 'nFrames', 'double'; 'FrameRate_Hz', 'double'; ...
                        'MeanBrightness', 'double'; 'PeakDFF', 'double'; 'PeakDFFTime_s', 'double'; ...
                        'MeanDiameter_px', 'double'; 'MinDiameter_px', 'double'; ...
                        'MaxDiameter_px', 'double'; 'nDiameterOutliers', 'double'};
                otherwise
                    cols = [{'Series', 'char'; 'nSeries', 'double'; 'DataType', 'char'; ...
                        'Baseline', 'double'}; feat];
            end
        end

        %% rowsToTable - Struct rows -> summary table (File, Status, Message, columns)
        % rows: struct array, or a cell array of struct arrays whose fields
        % may differ (e.g. error rows only have File, Status, Message).
        % Missing numeric values become NaN and missing text ''.
        function T = rowsToTable(pipeline, rows)
            cols = [{'File', 'char'; 'Status', 'char'; 'Message', 'char'}; Batch.columns(pipeline)];
            if isstruct(rows), rows = {rows}; end
            list = {};
            for i = 1:numel(rows)
                for j = 1:numel(rows{i})
                    list{end+1} = rows{i}(j); %#ok<AGROW>
                end
            end
            rows = list;
            n = numel(rows);
            data = cell(1, size(cols, 1));
            for c = 1:size(cols, 1)
                name = cols{c, 1};
                if strcmp(cols{c, 2}, 'char')
                    v = repmat({''}, n, 1);
                    for r = 1:n
                        if isfield(rows{r}, name) && ~isempty(rows{r}.(name)), v{r} = char(rows{r}.(name)); end
                    end
                else
                    v = NaN(n, 1);
                    for r = 1:n
                        if isfield(rows{r}, name) && ~isempty(rows{r}.(name)), v(r) = double(rows{r}.(name)); end
                    end
                end
                data{c} = v;
            end
            T = table(data{:}, 'VariableNames', cols(:, 1)');
        end
    end

    methods(Static, Access = private)

        %% fileLDF - Cropped LDF -> trials -> features of the mean trial
        function [rows, info] = fileLDF(file, p, outFolder)
            s = LDFPipeline.loadCropped(file);
            pp = Batch.ldfProcessingParams(p);
            r = LDFPipeline.run(s.LDF, s.stim, s.t, s.Fs, pp);
            tSeg = r.segmentedTime;
            meanTrial = mean(r.segmentedLDF, 1);
            [vals, baseVal] = Batch.seriesFeatures(tSeg, meanTrial, 0, [tSeg(1) 0], p.direction);
            row = struct('Status', 'ok', 'Message', '', 'Fs_Hz', r.Fs, 'nOnsets', r.nOnsets, ...
                'nTrials', r.nTrials, 'Baseline', baseVal, 'TrialFile', '');
            row = Batch.addFeatures(row, vals);
            if p.saveTrials && ~isempty(outFolder)
                trialDir = fullfile(outFolder, 'trials');
                if exist(trialDir, 'dir') ~= 7, mkdir(trialDir); end
                [~, nm] = fileparts(file);
                segmentedLDF = r.segmentedLDF; segmentedTime = r.segmentedTime; Fs = r.Fs; %#ok<NASGU>
                trialFile = fullfile(trialDir, [nm '_segments.mat']);
                save(trialFile, 'segmentedLDF', 'segmentedTime', 'Fs');
                row.TrialFile = fullfile('trials', [nm '_segments.mat']);
            end
            rows = row;
            info = sprintf('%d trials of %d onsets, peak %.2f s, amplitude %.3g', r.nTrials, r.nOnsets, ...
                vals(1), vals(8));
        end

        %% ldfProcessingParams - Batch settings -> LDFPipeline params
        function pp = ldfProcessingParams(p)
            ft = Batch.menuIndex(p.filterType, Batch.FilterTypes, 'filter type');
            dt = Batch.menuIndex(p.designType, Batch.FilterDesigns, 'filter design');
            low = NaN; high = NaN;
            if ismember(ft, [3 4 5]), low = p.cutoffLow; end
            if ismember(ft, [2 4 5]), high = p.cutoffHigh; end
            pp = struct('downsample', round(p.downsample), 'filterType', ft, 'designType', dt, ...
                'filterOrder', p.filterOrder, 'cutoffLow', low, 'cutoffHigh', high, ...
                'threshold', p.threshold, 'preSec', p.preSec, 'postSec', p.postSec, 'minISI', p.minISI);
        end

        %% fileERP - LFP -> ERP per channel (+ CSD): N1 / P2 / sink
        function [rows, info] = fileERP(file, p)
            s = load(file);
            required = {'lfp_data', 'stim_data', 'lfp_fs', 'stim_fs'};
            Batch.requireVars(s, required, 'LFP', 'Extract Ephys (Save LFP)');
            [idx, ids] = Batch.channelRows(size(s.lfp_data, 1), Batch.fieldOr(s, 'lfp_channels', []), p.channels);
            fs = double(s.lfp_fs);
            onsetTimes = ERPAnalysis.detectOnsets(s.stim_data, double(s.stim_fs), p.threshold, p.minISI);
            if isempty(onsetTimes)
                error('NeuroAnalyzer:Batch:noOnsets', 'No stimulus onsets above threshold %g.', p.threshold);
            end
            [erpAvg, ~, t, nValid] = ERPAnalysis.average(double(s.lfp_data(idx, :)), fs, onsetTimes, ...
                p.preTime, p.postTime);
            if nValid == 0
                error('NeuroAnalyzer:Batch:noEpochs', 'No complete epochs: all onsets are too close to the recording edges.');
            end
            n1w = Batch.window2(p.n1WindowMs, 'N1 window') / 1000;
            p2w = Batch.window2(p.p2WindowMs, 'P2 window') / 1000;
            csd = [];
            if p.computeCSD && numel(idx) >= 3
                csd = ERPAnalysis.csd(erpAvg, p.spacingUm);
            end
            scale = p.amplitudeScale;
            inN1 = t >= n1w(1) & t <= n1w(2);
            inP2 = t >= p2w(1) & t <= p2w(2);
            if ~any(inN1) || ~any(inP2)
                error('NeuroAnalyzer:Batch:window', 'The N1 / P2 windows lie outside the epoch (post-stimulus %g s).', p.postTime);
            end
            tN1 = t(inN1); tP2 = t(inP2);
            rowList = cell(1, numel(idx));
            csdMin = NaN(1, numel(idx));
            for c = 1:numel(idx)
                y = erpAvg(c, :);
                base = mean(y(t < 0), 'omitnan');
                if ~isfinite(base), base = 0; end
                [v1, i1] = min(y(inN1));
                [v2, i2] = max(y(inP2));
                row = struct('Status', 'ok', 'Message', '', 'Channel', ids(c), ...
                    'nOnsets', numel(onsetTimes), 'nEpochs', nValid, ...
                    'N1Latency_ms', 1000 * tN1(i1), 'N1Amp', scale * (v1 - base), ...
                    'P2Latency_ms', 1000 * tP2(i2), 'P2Amp', scale * (v2 - base), ...
                    'PeakToPeak', scale * (v2 - v1), 'AmpUnit', p.amplitudeUnit, ...
                    'CSDMin', NaN, 'CSDMinLatency_ms', NaN, 'SinkChannel', NaN);
                if ~isempty(csd)
                    [cm, ic] = min(csd(c, inN1));
                    csdMin(c) = cm;
                    row.CSDMin = scale * cm * 1e-6;      % per m^2 -> per mm^2
                    row.CSDMinLatency_ms = 1000 * tN1(ic);
                end
                rowList{c} = row;
            end
            rows = [rowList{:}];
            sink = NaN;
            if ~isempty(csd)
                [~, is] = min(csdMin);
                sink = ids(is);
                for c = 1:numel(rows), rows(c).SinkChannel = sink; end
            end
            [~, iBig] = min([rows.N1Amp]);
            info = sprintf('%d channels, %d epochs, largest N1 on ch %g at %.1f ms', numel(idx), nValid, ...
                rows(iBig).Channel, rows(iBig).N1Latency_ms);
            if isfinite(sink), info = sprintf('%s, CSD sink ch %g', info, sink); end
        end

        %% fileMUA - MUA -> spike sorting per channel (seeded) -> units, rates, QC
        function [rows, info] = fileMUA(file, p)
            s = load(file);
            Batch.requireVars(s, {'mua_data', 'mua_fs'}, 'MUA', 'Extract Ephys (Save MUA)');
            fs = double(s.mua_fs);
            nS = size(s.mua_data, 2);
            tm = Batch.fieldOr(s, 't_mua', []);
            if numel(tm) ~= nS, tm = (0:nS - 1) / fs; end
            tm = double(tm(:)');
            [idx, ids] = Batch.channelRows(size(s.mua_data, 1), Batch.fieldOr(s, 'mua_channels', []), p.channels);
            dur = tm(end) - tm(1) + 1 / fs;
            onsets = [];
            if isfield(s, 'stim_data') && isfield(s, 't_stim') && ~isempty(s.stim_data)
                onsets = SpikeTrains.stimulusOnsets(double(s.stim_data), double(s.t_stim), p.stimThreshold, p.stimMinISI);
            end
            rw = Batch.window2(p.responseWindowMs, 'Response window') / 1000;
            bw = Batch.window2(p.baselineWindowMs, 'Baseline window') / 1000;
            sp = MUAPipeline.completeParams(struct('detectMethod', p.detectMethod, ...
                'threshold', p.threshold, 'polarity', p.polarity, 'featureMethod', p.featureMethod, ...
                'clusterMethod', p.clusterMethod, 'minSpikesPerCluster', p.minSpikesPerCluster, ...
                'autoMerge', double(logical(p.autoMerge))));
            rowList = cell(1, numel(idx));
            nUnitsAll = 0;
            for c = 1:numel(idx)
                row = struct('Status', 'ok', 'Message', '', 'Channel', ids(c), 'Duration_s', dur, ...
                    'nDetected', NaN, 'nSpikes', NaN, 'nUnits', NaN, 'nRejected', NaN, 'nGoodUnits', NaN, ...
                    'MeanRate_Hz', NaN, 'UnitRates_Hz', '', 'MeanSNR', NaN, 'MaxISIViol_pct', NaN, ...
                    'nOnsets', numel(onsets), 'BaselineRate_Hz', NaN, 'EvokedRate_Hz', NaN);
                try
                    x = double(s.mua_data(idx(c), :));
                    [res, qcInfo] = Batch.seededSort(x, tm, fs, sp, p.seed);
                    lab = res.clusterIdx(:);
                    qc = qcInfo.qc;
                    units = [qc([qc.id] > 0)];
                    unitSpikes = res.spikeTimes(lab > 0);
                    row.nDetected = numel(lab);
                    row.nSpikes = numel(unitSpikes);
                    row.nUnits = numel(units);
                    row.nRejected = sum([units.rejected]);
                    row.nGoodUnits = row.nUnits - row.nRejected;
                    row.MeanRate_Hz = row.nSpikes / dur;
                    row.UnitRates_Hz = strjoin(arrayfun(@(u) sprintf('%.2f', u.n / dur), units, ...
                        'UniformOutput', false), ' ');
                    if isempty(units)
                        row.MeanSNR = NaN; row.MaxISIViol_pct = NaN;
                    else
                        row.MeanSNR = mean([units.snr]);
                        row.MaxISIViol_pct = max([units.isiPct]);
                    end
                    row.nOnsets = numel(onsets);
                    [row.BaselineRate_Hz, row.EvokedRate_Hz] = Batch.windowRates(unitSpikes, onsets, ...
                        bw, rw, tm([1 end]));
                    nUnitsAll = nUnitsAll + row.nUnits;
                catch ME
                    row.Status = 'error';
                    row.Message = sprintf('Ch %g: %s', ids(c), Batch.oneLine(ME.message));
                end
                rowList{c} = row;
            end
            rows = [rowList{:}];
            nFail = sum(strcmp({rows.Status}, 'error'));
            info = sprintf('%d channel(s) sorted, %d unit(s) in total', numel(idx) - nFail, nUnitsAll);
            if nFail > 0, info = sprintf('%s, %d channel(s) failed', info, nFail); end
        end

        %% seededSort - MUAPipeline.sort with rng(seed) set and restored, console quiet
        function [res, qcInfo] = seededSort(x, t, fs, sp, seed)
            prevRng = rng;
            restore = onCleanup(@() rng(prevRng));
            rng(seed, 'twister');
            res = []; qcInfo = []; %#ok<NASGU>
            evalc('[res, qcInfo] = MUAPipeline.sort(x, t, fs, sp);');
            clear restore
        end

        %% windowRates - Mean rate (spikes/s) in a baseline and a response window per onset
        function [baseRate, evokedRate] = windowRates(spikes, onsets, bw, rw, span)
            baseRate = NaN; evokedRate = NaN;
            if isempty(onsets), return; end
            onsets = onsets(:);
            lo = min(bw(1), rw(1)); hi = max(bw(2), rw(2));
            onsets = onsets(onsets + lo >= span(1) & onsets + hi <= span(2));
            if isempty(onsets), return; end
            nb = 0; nr = 0;
            for k = 1:numel(onsets)
                d = spikes - onsets(k);
                nb = nb + sum(d >= bw(1) & d < bw(2));
                nr = nr + sum(d >= rw(1) & d < rw(2));
            end
            baseRate = nb / (numel(onsets) * (bw(2) - bw(1)));
            evokedRate = nr / (numel(onsets) * (rw(2) - rw(1)));
        end

        %% fileROI - Stack -> per-ROI brightness / dF/F, vessel diameter on a line
        function [rows, info] = fileROI(file, p)
            [stack, timeVec, masks, names] = Batch.loadStack(file);
            N = size(stack, 3);
            if p.motionCorrection
                stack = registerStackRigid(stack, 'mean');
            end
            t = 1:N;
            fromFile = numel(timeVec) == N;
            if fromFile, t = double(timeVec(:)'); end
            if ~isempty(p.roiMask)
                masks = logical(p.roiMask); names = {};
            end
            if ~isempty(masks) && (size(masks, 1) ~= size(stack, 1) || size(masks, 2) ~= size(stack, 2))
                error('NeuroAnalyzer:Batch:maskSize', 'The ROI mask (%d x %d) does not match the frames (%d x %d).', ...
                    size(masks, 1), size(masks, 2), size(stack, 1), size(stack, 2));
            end
            K = size(masks, 3);
            if isempty(masks), K = 0; end
            measure = p.measure;
            wantROI = any(strcmp(measure, {'All', 'dF/F', 'Brightness'}));
            wantLine = any(strcmp(measure, {'All', 'Vessel diameter'})) && ~isempty(p.line);
            if strcmp(measure, 'Vessel diameter') && isempty(p.line)
                error('NeuroAnalyzer:Batch:noLine', 'Vessel diameter needs a line: set Line x1 y1 x2 y2 (px).');
            end
            if wantROI && K == 0 && ~wantLine
                error('NeuroAnalyzer:Batch:noROI', 'No ROI: the file has no roiMask / roiMasks variable.');
            end
            fr = NaN;
            if fromFile && N > 1, fr = 1 / median(diff(t)); end

            diam = struct('mean', NaN, 'min', NaN, 'max', NaN, 'nOut', NaN);
            if wantLine
                ln = double(p.line(:)');
                if numel(ln) ~= 4
                    error('NeuroAnalyzer:Batch:line', 'The line must be 4 numbers: x1 y1 x2 y2 (px).');
                end
                [d, ~, ~, isOut] = vesselDiameterFromLine(stack, ln(1:2), ln(3:4), t, 'fwhm', ...
                    'Robust', logical(p.robust));
                diam = struct('mean', mean(d, 'omitnan'), 'min', min(d), 'max', max(d), 'nOut', nnz(isOut));
            end

            rowList = {};
            base = struct('Status', 'ok', 'Message', '', 'ROI', '', 'nFrames', N, 'FrameRate_Hz', fr, ...
                'MeanBrightness', NaN, 'PeakDFF', NaN, 'PeakDFFTime_s', NaN, ...
                'MeanDiameter_px', diam.mean, 'MinDiameter_px', diam.min, ...
                'MaxDiameter_px', diam.max, 'nDiameterOutliers', diam.nOut);
            if wantROI
                for k = 1:K
                    row = base;
                    if numel(names) >= k && ~isempty(names{k}), row.ROI = names{k}; else, row.ROI = sprintf('ROI %d', k); end
                    m = masks(:, :, k);
                    if any(strcmp(measure, {'All', 'Brightness'}))
                        row.MeanBrightness = mean(roiIntensityOverTime(stack, m, t));
                    end
                    if any(strcmp(measure, {'All', 'dF/F'}))
                        dff = deltaFOverF(stack, m, t, 'first', p.baselineFrames);
                        [row.PeakDFF, ip] = max(dff);
                        row.PeakDFFTime_s = t(ip);
                    end
                    rowList{end+1} = row; %#ok<AGROW>
                end
            end
            if isempty(rowList), rowList = {base}; end
            rows = [rowList{:}];
            info = sprintf('%d frames, %d ROI(s)', N, K * wantROI);
            if wantROI && K > 0 && isfinite(rows(1).PeakDFF)
                info = sprintf('%s, peak dF/F %.2f', info, rows(1).PeakDFF);
            end
            if wantLine, info = sprintf('%s, diameter %.1f px (mean)', info, diam.mean); end
        end

        %% loadStack - Grayscale H x W x N stack, time vector, ROI masks and names
        function [stack, timeVec, masks, names] = loadStack(file)
            [~, ~, ext] = fileparts(file);
            masks = []; names = {}; timeVec = [];
            if strcmpi(ext, '.mat')
                s = load(file);
                fn = fieldnames(s);
                if isempty(fn), error('NeuroAnalyzer:Batch:empty', 'The file contains no variables.'); end
                if isfield(s, 'stack')
                    stack = s.stack;
                elseif isfield(s, 'frames')
                    stack = s.frames;
                else
                    stack = s.(fn{1});
                end
                if ~(isnumeric(stack) || islogical(stack)) || ndims(stack) < 3
                    error('NeuroAnalyzer:Batch:noStack', ['No image stack found: save the frames as a ' ...
                        'numeric variable named ''stack'' (H x W x N or H x W x 3 x N).']);
                end
                if isfield(s, 'timeVec'), timeVec = s.timeVec; elseif isfield(s, 't'), timeVec = s.t; end
                if isfield(s, 'roiMasks') && ~isempty(s.roiMasks)
                    masks = logical(s.roiMasks);
                    if isfield(s, 'roiNames'), names = cellstr(s.roiNames); end
                elseif isfield(s, 'roiMask') && ~isempty(s.roiMask)
                    masks = logical(s.roiMask);
                end
            else
                finfo = imfinfo(file);
                first = imread(file, 1);
                stack = zeros(size(first, 1), size(first, 2), numel(finfo));
                for k = 1:numel(finfo)
                    fr = double(imread(file, k));
                    if ndims(fr) == 3, fr = mean(fr(:, :, 1:min(3, size(fr, 3))), 3); end
                    stack(:, :, k) = fr;
                end
            end
            stack = double(stack);
            if ndims(stack) == 4   % H x W x 3 x N -> grayscale mean of the colour channels
                stack = reshape(mean(stack, 3), size(stack, 1), size(stack, 2), size(stack, 4));
            end
        end

        %% fileFeatures - Any Signal Characterization file -> features
        function [rows, info] = fileFeatures(file, p)
            s = load(file);
            [dt, tCell, yCell] = Batch.parseSeries(s);
            if isempty(dt)
                error('NeuroAnalyzer:Batch:unsupported', ['No supported variables (expected segmentedLDF + ' ...
                    'segmentedTime, lfp_data + t_lfp, t + y or t + LDF). Found: %s.'], strjoin(fieldnames(s), ', '));
            end
            if isempty(tCell)
                error('NeuroAnalyzer:Batch:noSeries', 'The file has no series to measure.');
            end
            t0 = p.t0;
            if strcmp(p.seriesMode, 'Each series')
                rowList = cell(1, numel(tCell));
                for k = 1:numel(tCell)
                    rowList{k} = Batch.featureRow(tCell{k}, yCell{k}, t0, p, sprintf('Trial %d', k), numel(tCell), dt);
                end
                rows = [rowList{:}];
            else
                [tm, ym, same] = Batch.meanTrace(tCell, yCell);
                if ~same
                    error('NeuroAnalyzer:Batch:timeBase', 'The series do not share one time base; use Series = Each series.');
                end
                rows = Batch.featureRow(tm, ym, t0, p, sprintf('Mean of %d', numel(tCell)), numel(tCell), dt);
            end
            info = sprintf('%s, %d series, peak latency %.3g s, peak amplitude %.3g', dt, numel(tCell), ...
                rows(1).PeakLatency_s, rows(1).PeakAmp);
        end

        %% featureRow - Summary row with the nine features of one trace
        function row = featureRow(t, y, t0, p, name, nSeries, dt)
            t = t(:)'; y = y(:)';
            if p.autoBaseline
                if ~isempty(t) && t(1) < t0, bl = [t(1) t0]; else, bl = []; end
            else
                bl = [p.baselineStart p.baselineEnd];
                if bl(2) <= bl(1), bl = []; end
            end
            [vals, baseVal] = Batch.seriesFeatures(t, y, t0, bl, p.direction);
            row = struct('Status', 'ok', 'Message', '', 'Series', name, 'nSeries', nSeries, ...
                'DataType', dt, 'Baseline', baseVal);
            row = Batch.addFeatures(row, vals);
            if all(isnan(vals))
                row.Status = 'warning';
                row.Message = sprintf('%s: empty or malformed series', name);
            end
        end

        %% parseSeries - Data type and series, as Signal Characterization reads them
        function [dt, tCell, yCell] = parseSeries(s)
            tCell = {}; yCell = {};
            if isfield(s, 'segmentedLDF') && isfield(s, 'segmentedTime')
                dt = 'LDF segments';
                t = s.segmentedTime(1, :);
                for i = 1:size(s.segmentedLDF, 1)
                    tCell{end+1} = t; %#ok<AGROW>
                    yCell{end+1} = s.segmentedLDF(i, :); %#ok<AGROW>
                end
            elseif (isfield(s, 'lfp_data') && (isfield(s, 't') || isfield(s, 't_lfp'))) || ...
                    (isfield(s, 'erp_avg') && isfield(s, 't') && isfield(s, 'y'))
                dt = 'ERP / average';
                if isfield(s, 't'), tv = s.t; elseif isfield(s, 't_lfp'), tv = s.t_lfp; else, tv = []; end
                if ~isempty(tv) && isfield(s, 'lfp_data')
                    y = mean(s.lfp_data, 1);
                    tCell = {tv(:)'}; yCell = {y(:)'};
                elseif isfield(s, 't') && isfield(s, 'y')
                    tCell = {s.t(:)'}; yCell = {s.y(:)'};
                end
            elseif isfield(s, 't') && isfield(s, 'y')
                dt = 'Time series';
                tCell = {s.t(:)'}; yCell = {s.y(:)'};
            elseif isfield(s, 't') && isfield(s, 'LDF')
                dt = 'Time series';
                tCell = {s.t(:)'}; yCell = {s.LDF(:)'};
            else
                dt = '';
            end
        end

        %% meanTrace - Mean of series sharing one time base (same = false otherwise)
        function [t, y, same] = meanTrace(T, Y)
            t = T{1}(:)';
            y = [];
            same = ~isempty(t);
            tol = 1e-9 * max(1, max(abs(t)));
            for i = 1:numel(T)
                if numel(T{i}) ~= numel(t) || numel(Y{i}) ~= numel(t) || any(abs(T{i}(:)' - t) > tol)
                    same = false;
                    return;
                end
            end
            rows = cellfun(@(v) v(:)', Y(:), 'UniformOutput', false);
            y = mean(vertcat(rows{:}), 1, 'omitnan');
        end

        %% addFeatures - Copy the nine feature values into a row
        function row = addFeatures(row, vals)
            for f = 1:numel(Batch.FeatureColumns)
                row.(Batch.FeatureColumns{f}) = vals(f);
            end
        end

        %% channelRows - Rows of the requested channels (IDs from the file, else row numbers)
        function [idx, ids] = channelRows(nRows, fileIDs, wanted)
            fileIDs = double(fileIDs(:)');
            if numel(fileIDs) ~= nRows, fileIDs = 1:nRows; end
            if isempty(wanted)
                idx = 1:nRows;
            else
                [ok, idx] = ismember(double(wanted(:)'), fileIDs);
                if ~all(ok)
                    error('NeuroAnalyzer:Batch:channels', 'Channel(s) %s not in the file (it has %s).', ...
                        strtrim(sprintf('%g ', wanted(~ok))), strtrim(sprintf('%g ', fileIDs)));
                end
            end
            ids = fileIDs(idx);
        end

        %% requireVars - Error listing the missing variables of a file
        function requireVars(s, required, what, source)
            missing = required(~isfield(s, required));
            if ~isempty(missing)
                error('NeuroAnalyzer:Batch:missingVars', 'Invalid %s file. Missing variable(s): %s. Use a file saved by %s.', ...
                    what, strjoin(missing, ', '), source);
            end
        end

        %% window2 - Validate a [from to] window
        function w = window2(w, what)
            w = double(w(:)');
            if numel(w) ~= 2 || ~all(isfinite(w)) || w(2) <= w(1)
                error('NeuroAnalyzer:Batch:window', '%s must be two numbers "from to" with to > from.', what);
            end
        end

        %% menuIndex - Position of a menu value (text) or a valid index
        function k = menuIndex(v, items, what)
            if isnumeric(v) && isscalar(v) && v >= 1 && v <= numel(items)
                k = round(v);
                return;
            end
            k = find(strcmpi(char(v), items), 1);
            if isempty(k)
                error('NeuroAnalyzer:Batch:badValue', 'Unknown %s ''%s''. Use one of: %s.', what, char(v), ...
                    strjoin(items, ', '));
            end
        end

        %% checkPipeline - Validated lower-case pipeline key
        function pipeline = checkPipeline(pipeline)
            pipeline = lower(char(pipeline));
            if ~any(strcmp(pipeline, Batch.pipelines()))
                error('NeuroAnalyzer:Batch:unknownPipeline', 'Unknown pipeline ''%s''. Use one of: %s.', ...
                    pipeline, strjoin(Batch.pipelines(), ', '));
            end
        end

        %% optionName - Case-insensitive match of a Name-Value option
        function name = optionName(name, valid)
            k = find(strcmpi(char(name), valid), 1);
            if isempty(k)
                error('NeuroAnalyzer:Batch:option', 'Unknown option ''%s''. Use one of: %s.', char(name), ...
                    strjoin(valid, ', '));
            end
            name = valid{k};
        end

        %% fieldOr - Struct field or a default
        function v = fieldOr(s, name, default)
            if isfield(s, name), v = s.(name); else, v = default; end
        end

        %% logHeader - First lines of the log: date, pipeline, settings, files
        function lines = logHeader(pipeline, params, files, outFolder)
            d = Batch.describe(pipeline);
            lines = {sprintf('NeuroAnalyzer batch - %s', d.label); ...
                sprintf('Started %s', datestr(now, 'yyyy-mm-dd HH:MM:SS')); ... %#ok<TNOW1,DATST>
                sprintf('Output folder: %s', outFolder); ...
                sprintf('%d file(s)', numel(files)); 'Settings:'};
            fn = fieldnames(params);
            for i = 1:numel(fn)
                lines{end+1, 1} = sprintf('  %s = %s', fn{i}, Batch.valueText(params.(fn{i}))); %#ok<AGROW>
            end
            lines{end+1, 1} = 'Files:';
        end

        %% valueText - Short text for a setting value
        function s = valueText(v)
            if ischar(v)
                s = v;
            elseif islogical(v) && isscalar(v)
                s = Batch.ifelse(v, 'true', 'false');
            elseif isnumeric(v) && isempty(v)
                s = '[]';
            elseif isnumeric(v) && numel(v) <= 8
                s = mat2str(v);
            else
                s = sprintf('<%s %s>', class(v), mat2str(size(v)));
            end
        end

        %% writeLog - Log lines to a UTF-8 text file
        function writeLog(path, lines)
            fid = fopen(path, 'w', 'n', 'UTF-8');
            if fid < 0
                error('NeuroAnalyzer:Batch:log', 'Could not write the log file %s.', path);
            end
            closer = onCleanup(@() fclose(fid));
            fprintf(fid, '%s\n', lines{:});
            clear closer
        end

        %% oneLine - Message without line breaks
        function s = oneLine(s)
            s = strtrim(regexprep(char(s), '\s*[\r\n]+\s*', ' '));
        end

        %% ifelse - One of two values
        function v = ifelse(cond, a, b)
            if cond, v = a; else, v = b; end
        end
    end
end
