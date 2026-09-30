%% demoLDFFormats.m
% =========================================================================
% DEMO LDF FORMATS - THE LDF DEMO AS OTHER ACQUISITION SYSTEMS SAVE IT
% =========================================================================
% files = demoLDFFormats()          cached copy in <DemoData.folder>/ldf_formats
% files = demoLDFFormats(folder)    (re)write the files into folder
%
% Writes the demo LDF recording (DemoData.ldfExport: 300 s, 5 s stimuli
% every 30 s from 30 s, +30 PU responses) as the other files Extract LDF
% reads, at 100 Hz (every 10th sample of the 1000 Hz demo), so each one
% can be opened in the window and checked against the same answer:
%   files.labchartText  demo_ldf_labchart.txt: LabChart text export
%                       (Interval=, ChannelTitle=, Range=; time column;
%                       channels Stimulus, Blood pressure, LDF; a comment
%                       "#* Stim" at every onset)
%   files.acq           demo_ldf.acq: AcqKnowledge 4.1 file (writeBiopacACQ),
%                       Trigger at 1000 Hz and LDF100C (BPU) at 100 Hz, a
%                       "Stimulus" event marker at every onset
%   files.table         demo_ldf_perisoft.csv: PeriSoft-style table,
%                       semicolons and decimal commas, "Time [s];Perfusion
%                       [PU];Stimulus [V]"
%   files.noTime        demo_ldf_notime.txt: tab-separated LDF and Stim
%                       columns without a time column (the rate, 100 Hz,
%                       must be given)
%   files.spike2        demo_ldf_spike2.mat: Spike2 MATLAB export, an LDF
%                       waveform channel and a "Stim" event channel
%   files.edf           demo_ldf.edf: EDF+C (writeEDF), LDF (PU) and
%                       Stimulus (V) in 10 ms records, a "Stim" annotation
%                       at every onset
%   files.truth         fs (100), onsets (s), t, ldf and stim at 100 Hz,
%                       and DemoData's ground truth (responses)
%   files.folder
% Deterministic (DemoData's fixed seed). Requires core/io on the path
% (writeBiopacACQ, writeEDF). Toolboxes: none; also runs in GNU Octave.
% =========================================================================

function files = demoLDFFormats(folder)
    cacheVersion = 2;
    cached = nargin < 1 || isempty(folder);
    if cached
        folder = fullfile(DemoData.folder(), 'ldf_formats');
        manifest = fullfile(folder, 'demo_ldf_formats.mat');
        if exist(manifest, 'file') == 2
            s = load(manifest);
            if isfield(s, 'version') && s.version == cacheVersion && allExist(s.files, folder)
                files = s.files;
                files.folder = folder;
                return;
            end
        end
    end
    if ~exist(folder, 'dir'), mkdir(folder); end
    if exist('writeBiopacACQ', 'file') ~= 2
        addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'io'));
    end

    d = DemoData.ldfExport();
    stim1k = d.data(d.datastart(6):d.dataend(6));
    ldf1k = d.data(d.datastart(8):d.dataend(8));
    ds = 10; fs = 1000 / ds;
    ldf = ldf1k(1:ds:end);
    stim = stim1k(1:ds:end);
    n = numel(ldf);
    t = (0:n-1) / fs;
    onsets = d.truth.onsets;
    bp = 95 + 8 * sin(2 * pi * 1.2 * t);                     % a third channel (mmHg)
    onIdx = round(onsets * fs) + 1;

    % LabChart text export (tab separated, comments after the row)
    rows = cell(1, n);
    for k = 1:n
        rows{k} = sprintf('%.2f\t%.4f\t%.3f\t%.4f', t(k), stim(k), bp(k), ldf(k));
    end
    for k = onIdx, rows{k} = [rows{k} sprintf('\t#* Stim')]; end
    head = sprintf(['Interval=\t0.01 s\nExcelDateTime=\t4.6295e+04\t9/30/2026 10:00:00.000\n' ...
        'TimeFormat=\tStartOfBlock\nDateFormat=\tM/d/yyyy\nChannelTitle=\tStimulus\tBlood pressure\tLDF\n' ...
        'Range=\t10.000 V\t200.00 mmHg\t1000.0 PU\n']);
    files.labchartText = fullfile(folder, 'demo_ldf_labchart.txt');
    writeText(files.labchartText, [head strjoin(rows, newline) newline]);

    % AcqKnowledge .acq: trigger at 1000 Hz, LDF at 100 Hz, markers at the onsets
    ch = struct('name', {'Trigger', 'LDF100C'}, 'units', {'V', 'BPU'}, ...
        'data', {stim1k, ldf}, 'divider', {1, ds}, 'type', {'int16', 'double'}, ...
        'scale', {[], []}, 'offset', {[], []});
    mk = struct('sample', num2cell(round(onsets * 1000)), 'channel', 0, 'type', 'stim', 'text', 'Stimulus');
    files.acq = fullfile(folder, 'demo_ldf.acq');
    writeBiopacACQ(files.acq, ch, 1, 'Markers', mk);

    % PeriSoft-style table: semicolons, decimal commas
    rows = cell(1, n);
    for k = 1:n
        rows{k} = strrep(sprintf('%.2f;%.4f;%.4f', t(k), ldf(k), stim(k)), '.', ',');
    end
    files.table = fullfile(folder, 'demo_ldf_perisoft.csv');
    writeText(files.table, [sprintf('Time [s];Perfusion [PU];Stimulus [V]\n') strjoin(rows, newline) newline]);

    % No time column (the rate must be given)
    rows = cell(1, n);
    for k = 1:n
        rows{k} = sprintf('%.4f\t%.4f', ldf(k), stim(k));
    end
    files.noTime = fullfile(folder, 'demo_ldf_notime.txt');
    writeText(files.noTime, [sprintf('LDF\tStim\n') strjoin(rows, newline) newline]);

    % Spike2 MATLAB export: a waveform channel and an event channel
    S.demo_Ch1 = struct('title', 'LDF', 'comment', 'No comment', 'interval', 1 / fs, 'scale', 1, ...
        'offset', 0, 'units', 'PU', 'start', 0, 'length', n, 'values', ldf(:));
    S.demo_Ch2 = struct('title', 'Stim', 'comment', 'No comment', 'resolution', 1e-6, ...
        'length', numel(onsets), 'times', onsets(:));
    files.spike2 = fullfile(folder, 'demo_ldf_spike2.mat');
    save(files.spike2, '-struct', 'S');

    % EDF+C: 10 ms records (one sample each), so the length is not padded
    sig = struct('label', {'LDF', 'Stimulus'}, 'units', {'PU', 'V'}, 'fs', fs, 'data', {ldf, stim});
    files.edf = fullfile(folder, 'demo_ldf.edf');
    writeEDF(files.edf, sig, 'Format', 'EDF+C', 'RecordDuration', 1 / fs, ...
        'Annotations', struct('onset', num2cell(onsets), 'duration', NaN, 'text', 'Stim'));

    files.truth = d.truth;
    files.truth.fs = fs;
    files.truth.onsets = onsets;
    files.truth.t = t;
    files.truth.ldf = ldf;
    files.truth.stim = stim;
    if cached
        s = struct('version', cacheVersion, 'files', files); %#ok<NASGU>
        save(fullfile(folder, 'demo_ldf_formats.mat'), '-struct', 's');
    end
    files.folder = folder;
end

function writeText(f, s)
    fid = fopen(f, 'w');
    if fid < 0, error('NeuroAnalyzer:io:write', 'Cannot write %s', f); end
    fwrite(fid, s, 'char');
    fclose(fid);
end

function tf = allExist(files, folder)
    tf = true;
    for k = {'labchartText', 'acq', 'table', 'noTime', 'spike2', 'edf'}
        if ~isfield(files, k{1}) || exist(fullfile(folder, fname(files.(k{1}))), 'file') ~= 2
            tf = false; return;
        end
    end
end

function n = fname(p)
    [~, a, b] = fileparts(p);
    n = [a b];
end
