%% ExtractEphysApp.m
% =========================================================================
% EXTRACT EPHYS DATA - LOAD TDT TANK, EXTRACT LFP AND MUA STREAMS
% =========================================================================
% Launched from Main. Loads TDT tank folder via TDTbin2mat, user selects
% stimulus (Whis) channel and raw (xRAW) channels. Can plot raw, then
% Process LFP (filter and downsample for LFP) or Process MUA (filter for
% multi-unit activity). Save LFP Data / Save MUA Data write .mat for
% LFPAnalysisApp and MUAAnalysisApp. Uses LFPProcessingParamsApp and
% MUAProcessingParamsApp for filter parameters.
% =========================================================================

classdef ExtractEphysApp < handle
    %% PROPERTIES: UI, TDT data struct, selected channels, last processed LFP/MUA and params
    properties
        UIFig
        LoadBtn
        RAWList
        PlotRAWBtn
        ProcessLFPBtn
        AxContainer
        WhisChannelMenu
        StatusLabel
        LastProcessedLFP
        LastLFPfs
        LastMUAFilterParams
        LastProcessedMUA
        LastMUAfs
        FsLabel  % Label to show current sampling rate

        Data  % Struct loaded from TDTbin2mat
        StimChannel  % Selected Whis channel
        RAWChannels  % Selected xRAW channels
    end

    methods
        %% Constructor - Build UI; data loaded via Load TDT Folder
        function app = ExtractEphysApp()
            app.buildUI();
        end

        %% buildUI - Header | fixed controls | graph area | fixed footer (consistent with Main)
        function buildUI(app)
            T = UITheme;
            app.UIFig = figure('Name', 'Extract Ephys Data', ...
                'Position', [100 100 1000 820], 'Resize', 'on', ...
                'Color', T.bgGray, ...
                'MenuBar', 'none', 'ToolBar', 'none', 'NumberTitle', 'off');

            % --- Header: full-width, tall enough for title + subtitle ---
            headerH = 0.11;
            headerPanel = uipanel(app.UIFig, 'Units', 'normalized', ...
                'Position', [0 1-headerH 1 headerH], 'BorderType', 'none', ...
                'BackgroundColor', T.headerBg);
            uicontrol(headerPanel, 'Style', 'text', 'String', 'Extract Ephys Data', ...
                'Units', 'normalized', 'Position', [0.02 0.45 0.5 0.45], ...
                'FontSize', T.fontTitle, 'FontWeight', 'bold', 'ForegroundColor', T.headerTitleColor, ...
                'BackgroundColor', T.headerBg, 'HorizontalAlignment', 'left');
            uicontrol(headerPanel, 'Style', 'text', 'String', 'Load TDT tank, extract LFP and MUA', ...
                'Units', 'normalized', 'Position', [0.02 0.10 0.5 0.30], ...
                'FontSize', T.fontSubtitle, 'ForegroundColor', T.headerSubtitleColor, ...
                'BackgroundColor', T.headerBg, 'HorizontalAlignment', 'left');

            % --- Fixed controls section (positioned just below the header) ---
            ctrlTop = 1 - headerH - 0.02;
            ctrlH = 0.22;
            ctrlPanel = uipanel(app.UIFig, 'Title', 'Controls', 'Units', 'normalized', ...
                'Position', [0.01 ctrlTop-ctrlH 0.98 ctrlH], 'BackgroundColor', T.cardBg, ...
                'HighlightColor', T.cardBorder, 'FontSize', T.fontSmall);
            app.LoadBtn = uicontrol(ctrlPanel, 'Style', 'pushbutton', ...
                'String', 'Load TDT Folder', 'Units', 'normalized', ...
                'Position', [0.01 0.72 0.12 0.24], 'Callback', @(~,~)app.loadTDT());
            app.StatusLabel = uicontrol(ctrlPanel, 'Style', 'text', 'String', '', ...
                'Units', 'normalized', 'Position', [0.01 0.48 0.28 0.22], ...
                'FontSize', T.fontSmall, 'HorizontalAlignment', 'left', 'ForegroundColor', 'green');
            uicontrol(ctrlPanel, 'Style', 'text', 'String', 'Select Stim Channel:', ...
                'Units', 'normalized', 'Position', [0.16 0.72 0.14 0.22], ...
                'HorizontalAlignment', 'left', 'FontWeight', 'bold');
            app.WhisChannelMenu = uicontrol(ctrlPanel, 'Style', 'popupmenu', ...
                'String', {'1','2','3','4','5','6','7','8'}, ...
                'Units', 'normalized', 'Position', [0.30 0.72 0.06 0.22]);
            uicontrol(ctrlPanel, 'Style', 'text', 'String', 'Channels:', ...
                'Units', 'normalized', 'Position', [0.16 0.48 0.08 0.22], 'HorizontalAlignment', 'left');
            app.RAWList = uicontrol(ctrlPanel, 'Style', 'listbox', ...
                'Units', 'normalized', 'Position', [0.16 0.08 0.10 0.38], ...
                'Max', 16, 'Min', 1, 'String', {'1','2','3','4','5','6','7','8','9','10','11','12','13','14','15','16'});
            app.PlotRAWBtn = uicontrol(ctrlPanel, 'Style', 'pushbutton', ...
                'String', 'Plot RAW', 'Units', 'normalized', 'Position', [0.01 0.08 0.12 0.38], ...
                'Callback', @(~,~)app.plotRAWData());
            app.ProcessLFPBtn = uicontrol(ctrlPanel, 'Style', 'pushbutton', ...
                'String', 'Process LFP', 'Units', 'normalized', 'Position', [0.38 0.72 0.10 0.24], ...
                'Callback', @(~,~)app.processLFPData());
            uicontrol(ctrlPanel, 'Style', 'pushbutton', 'String', 'Save LFP Data', ...
                'Units', 'normalized', 'Position', [0.38 0.40 0.10 0.28], ...
                'Callback', @(~,~)app.saveLFPData(app.LastProcessedLFP, app.LastLFPfs));
            uicontrol(ctrlPanel, 'Style', 'pushbutton', 'String', 'Process MUA', ...
                'Units', 'normalized', 'Position', [0.50 0.72 0.10 0.24], ...
                'Callback', @(~,~)app.processMUAData());
            uicontrol(ctrlPanel, 'Style', 'pushbutton', 'String', 'Save MUA Data', ...
                'Units', 'normalized', 'Position', [0.50 0.40 0.10 0.28], ...
                'Callback', @(~,~)app.saveMUAData(app.LastProcessedMUA, app.LastMUAfs, app.LastMUAFilterParams));
            app.FsLabel = uicontrol(ctrlPanel, 'Style', 'text', 'String', 'Fs: N/A', ...
                'Units', 'normalized', 'Position', [0.62 0.72 0.36 0.22], ...
                'HorizontalAlignment', 'left', 'FontWeight', 'bold');

            % --- Fixed footer (plain hyperlink-style text, no button border) ---
            footerH = 0.06;
            footerPanel = uipanel(app.UIFig, 'Units', 'normalized', ...
                'Position', [0 0 1 footerH], 'BorderType', 'none', 'BackgroundColor', T.bgGray);
            uicontrol(footerPanel, 'Style', 'text', ...
                'String', sprintf('© Copyrights by Alejandro Suarez, Ph.D.  ·  v%s', T.version), ...
                'Units', 'normalized', 'Position', [0.45 0.15 0.53 0.7], ...
                'HorizontalAlignment', 'right', 'FontSize', T.fontSmall, 'ForegroundColor', T.mutedColor, ...
                'BackgroundColor', T.bgGray, 'Enable', 'inactive', ...
                'ButtonDownFcn', @(~,~)web('https://github.com/alesuarez92', '-browser'));

            % --- Graph section (above footer, below controls); extra bottom
            % margin so the AxContainer never overlaps the copyright footer ---
            graphBottom = footerH + 0.04;
            graphTop = ctrlTop - ctrlH - 0.01;
            app.AxContainer = uipanel(app.UIFig, 'Title', 'Raw Data', ...
                'Units', 'normalized', 'Position', [0.01 graphBottom 0.98 graphTop - graphBottom], ...
                'BackgroundColor', T.cardBg, 'HighlightColor', T.cardBorder);
        end
%% ------------------------------------------------------------------------------------------
        function loadTDT(app)
            folder = uigetdir('', 'Select TDT Tank Folder');
            if folder == 0
                app.StatusLabel.String = 'Load canceled.';
                app.StatusLabel.ForegroundColor = 'red';
                return;
            end
        
            % Show loading message
            app.StatusLabel.String = 'Loading data... please wait';
            app.StatusLabel.ForegroundColor = 'blue';
            drawnow;  % Force UI update
        
            try
                addpath(genpath(fullfile(pwd, 'Utilities', 'TDTMatlabSDK')));
                app.Data = TDTbin2mat(folder);
        
                app.StatusLabel.String = 'TDT data loaded successfully.';
                app.StatusLabel.ForegroundColor = 'green';
            catch ME
                app.StatusLabel.String = sprintf('Error loading data: %s', ME.message);
                app.StatusLabel.ForegroundColor = 'red';
            end
        
        end

%% ------------------------------------------------------------------------------------------
        function plotRAWData(app)
            if isempty(app.Data)
                errordlg('No data loaded.');
                return;
            end
        
            app.StimChannel = app.WhisChannelMenu.Value;
            app.RAWChannels = app.RAWList.Value;
        
            stim = app.Data.streams.Whis.data(app.StimChannel, :);
            stim_fs = app.Data.streams.Whis.fs;
            t_stim = (0:length(stim)-1)/stim_fs;
        
            raw = double(app.Data.streams.xRAW.data(app.RAWChannels, :));
            raw_fs = app.Data.streams.xRAW.fs;
            app.FsLabel.String = sprintf('Fs: %.1f Hz', raw_fs);
            t_raw = (0:size(raw,2)-1)/raw_fs;

            % Case 1: 4 or fewer channels -> plot in AxContainer
            if length(app.RAWChannels) <= 4
                delete(findall(app.AxContainer, 'Type', 'tiledlayout'));  % Clear old layout
        
                ax = tiledlayout(app.AxContainer, length(app.RAWChannels)+1, 1, ...
                    'TileSpacing','compact', 'Padding','compact');
        
                % Plot stimulus
                nexttile(ax)
                plot(t_stim, stim);
                ylabel(sprintf('Whis Ch %d', app.StimChannel));
                title('Stimulation Signal');
        
                % Plot RAW channels
                for i = 1:length(app.RAWChannels)
                    nexttile(ax)
                    plot(t_raw, raw(i,:));
                    ylabel(sprintf('RAW Ch %d', app.RAWChannels(i)));
                    if i == length(app.RAWChannels)
                        xlabel('Time (s)');
                    else
                        set(gca, 'XTickLabel', []);
                    end
                end
        
            % Case 2: > 4 channels -> create multiple windows
            else
                ch = app.RAWChannels;
                nGroups = ceil(length(ch)/4);
                for g = 1:nGroups
                    chIdx = ch((g-1)*4 + 1 : min(g*4, length(ch)));
                    rawGroup = double(app.Data.streams.xRAW.data(chIdx, :));
        
                    fig = figure('Name', sprintf('Group %d: RAW Channels', g), ...
                                 'Position', [200+100*g, 200-50*g, 1000, 700]);
        
                    ax = tiledlayout(fig, length(chIdx)+1, 1, ...
                        'TileSpacing','compact', 'Padding','compact');
        
                    % Plot stimulus
                    nexttile(ax)
                    plot(t_stim, stim);
                    ylabel(sprintf('Whis Ch %d', app.StimChannel));
                    title('Stimulation Signal');
        
                    % Plot group of 4 RAW channels
                    for i = 1:length(chIdx)
                        nexttile(ax)
                        plot(t_raw, rawGroup(i,:));
                        ylabel(sprintf('RAW Ch %d', chIdx(i)));
                        if i == length(chIdx)
                            xlabel('Time (s)');
                        else
                            set(gca, 'XTickLabel', []);
                        end
                    end
                end
            end
        end

%% ------------------------------------------------------------------------------------------
        function processLFPData(app)
            if isempty(app.Data)
                errordlg('No data loaded.');
                return;
            end
            % Ensure channels are updated from UI
            app.StimChannel = app.WhisChannelMenu.Value;
            app.RAWChannels = app.RAWList.Value;
        
            % Launch parameter window
            paramsApp = LFPProcessingParamsApp();
            uiwait(paramsApp.UIFig);  % Wait for user input
        
            params = paramsApp.Params;
            if isempty(params)
                return;  % User cancelled
            end
        
            % Extract selected channels
            stim = app.Data.streams.Whis.data(app.StimChannel, :);
            stim_fs = app.Data.streams.Whis.fs;
            t_stim = (0:length(stim)-1)/stim_fs;
        
            raw = double(app.Data.streams.xRAW.data(app.RAWChannels,:));
            raw_fs = app.Data.streams.xRAW.fs;
        
            % Preallocate
            processed = cell(1, length(app.RAWChannels));
            fs = raw_fs;
        
            % === 1. Anti-aliasing + Downsample if requested ===
            if params.downsample
                target_fs = params.downsampleRate;
                aa_cutoff = 0.8 * target_fs / 2;  % anti-alias cutoff
        
                [b_aa, a_aa] = butter(4, aa_cutoff / (fs / 2), 'low');
                for i = 1:length(app.RAWChannels)
                    filtered = filtfilt(b_aa, a_aa, raw(i,:));
                    processed{i} = downsample(filtered, round(fs / target_fs));
                end
                fs = target_fs;  % update sampling rate
                % Update UI
            else
                for i = 1:length(app.RAWChannels)
                    processed{i} = raw(i,:);
                end
            end
            app.FsLabel.String = sprintf('Raw Fs: %.1f Hz  LFP Fs: %.1f Hz', raw_fs, fs);
        
            % === 2. Apply lowpass filter ===
            if ~isnan(params.lowCutoff) && params.lowCutoff > 0 && params.lowCutoff < fs/2
                [b_lp, a_lp] = butter(4, params.lowCutoff / (fs/2), 'low');
                for i = 1:length(processed)
                    processed{i} = filtfilt(b_lp, a_lp, processed{i});
                end
            end
        
            % === 3. Apply 60 Hz Notch filter if requested ===
            if params.notch60
                wo = 60/(fs/2);
                bw = wo/35;
                [b_notch, a_notch] = iirnotch(wo, bw);
                for i = 1:length(processed)
                    processed{i} = filtfilt(b_notch, a_notch, processed{i});
                end
            end
        
            % === 4. Plot LFP data ===
            ch = app.RAWChannels;
            t = @(n) (0:length(processed{n})-1)/fs;
        
            if length(ch) <= 4
                % Plot in app panel
                delete(findall(app.AxContainer, 'Type', 'tiledlayout'));  % Clear panel
        
                ax = tiledlayout(app.AxContainer, length(ch)+1, 1, ...
                    'TileSpacing','compact', 'Padding','compact');
        
                % Stim
                nexttile(ax)
                plot(t_stim, stim);
                ylabel(sprintf('Whis Ch %d', app.StimChannel));
                title('Stimulation Signal');
        
                for i = 1:length(ch)
                    nexttile(ax)
                    plot(t(i), processed{i});
                    ylabel(sprintf('RAW Ch %d', ch(i)));
                    if i == length(ch)
                        xlabel('Time (s)');
                    else
                        set(gca, 'XTickLabel', []);
                    end
                end
            else
                % Plot in external figures in groups of 4
                nGroups = ceil(length(ch)/4);
                for g = 1:nGroups
                    chIdx = ch((g-1)*4 + 1 : min(g*4, length(ch)));
                    fig = figure('Name', sprintf('LFP Processed - Group %d', g), ...
                                 'Position', [200+100*g, 200-50*g, 1000, 700]);
                    ax = tiledlayout(fig, length(chIdx)+1, 1, ...
                                     'TileSpacing','compact', 'Padding','compact');
        
                    % Stim
                    nexttile(ax)
                    plot(t_stim, stim);
                    ylabel(sprintf('Whis Ch %d', app.StimChannel));
                    title('Stimulation Signal');
        
                    for i = 1:length(chIdx)
                        nexttile(ax)
                        plot(t(i), processed{(g-1)*4 + i});
                        ylabel(sprintf('RAW Ch %d', chIdx(i)));
                        if i == length(chIdx)
                            xlabel('Time (s)');
                        else
                            set(gca, 'XTickLabel', []);
                        end
                    end
                end
            end
            app.LastProcessedLFP = processed;
            app.LastLFPfs = fs;

        end
%% ------------------------------------------------------------------------------------------
        function saveLFPData(app, processedLFP, fsLFP)
            % processedLFP: cell array of processed data (1 x Nch)
            % fsLFP: sampling rate after filtering/downsampling
        
            if isempty(processedLFP)
                errordlg('No processed LFP data available.');
                return;
            end
        
            chLabels = arrayfun(@(c) sprintf('Ch %d', app.RAWChannels(c)), ...
                                1:length(app.RAWChannels), 'UniformOutput', false);
        
            [selection, ok] = listdlg('PromptString','Select LFP channels to save:', ...
                                      'SelectionMode','multiple', ...
                                      'ListString', chLabels);
        
            if ~ok || isempty(selection)
                return;  % User cancelled
            end
        
            lfp_data = cell2mat(processedLFP(selection)');
            lfp_channels = app.RAWChannels(selection);
            lfp_fs = fsLFP;
            t_lfp = (0:size(lfp_data,2)-1)/lfp_fs;

            stim_data = app.Data.streams.Whis.data(app.StimChannel, :);
            stim_fs = app.Data.streams.Whis.fs;
            t_stim = (0:length(stim_data)-1)/stim_fs;
        
            % Save dialog
            [file, path] = uiputfile('*.mat', 'Save LFP Data As');
            if isequal(file, 0)
                return;
            end
        
            % Save .mat file
            save(fullfile(path, file), ...
                'lfp_data', 'lfp_channels', 'lfp_fs', 't_lfp', ...
                'stim_data', 'stim_fs', 't_stim');
        
            msgbox('LFP data saved successfully.', 'Success');
        end

%% ------------------------------------------------------------------------------------------
        function processMUAData(app)
            if isempty(app.Data)
                errordlg('No data loaded.');
                return;
            end
        
            app.StimChannel = app.WhisChannelMenu.Value;
            app.RAWChannels = app.RAWList.Value;
        
            paramApp = MUAProcessingParamsApp();
            uiwait(paramApp.UIFig);
            params = paramApp.Params;
            if isempty(params), return; end
        
            stim = app.Data.streams.Whis.data(app.StimChannel, :);
            stim_fs = app.Data.streams.Whis.fs;
            fs = app.Data.streams.xRAW.fs;
        
            Wn = [params.lowCutoff params.highCutoff] / (fs/2);
            switch params.filterType
                case 'Butterworth'
                    [b, a] = butter(params.order, Wn, 'bandpass');
                case 'Chebyshev I'
                    Rp = 0.5;
                    [b, a] = cheby1(params.order, Rp, Wn, 'bandpass');
                otherwise
                    errordlg('Unsupported filter type'); return;
            end
        
            smooth_ms = params.smoothMs;
            if params.autoSmooth
                smooth_ms = 2;
            end
            window = max(1, round((smooth_ms / 1000) * fs));
            kernel = ones(1, window) / window;
        
            processed = cell(1, length(app.RAWChannels));
            rawAll = cell(1, length(app.RAWChannels));
        
            for i = 1:length(app.RAWChannels)
                raw = double(app.Data.streams.xRAW.data(app.RAWChannels(i), :));
                rawAll{i} = raw;
                bandpassed = filtfilt(b, a, raw);
                % ⛔ No rectification
                smoothed = conv(bandpassed, kernel, 'same');
                processed{i} = smoothed;
            end
        
            t_stim = (0:length(stim)-1)/stim_fs;
            t = @(n) (0:length(processed{n})-1)/fs;
            ch = app.RAWChannels;
        
            if length(ch) <= 4
                delete(findall(app.AxContainer, 'Type', 'tiledlayout'));
                ax = tiledlayout(app.AxContainer, length(ch)+1, 1, ...
                                 'TileSpacing','compact', 'Padding','compact');
        
                nexttile(ax);
                plot(t_stim, stim);
                ylabel(sprintf('Whis Ch %d', app.StimChannel));
                title('Stimulation Signal');
        
                for i = 1:length(ch)
                    nexttile(ax); hold on;
                    if params.overlayRaw
                        plot(t(i), rawAll{i}, 'Color', [0.6 0.6 0.6]);
                    end
                    plot(t(i), processed{i}, 'k', 'LineWidth', 1);
                    ylabel(sprintf('MUA Ch %d', ch(i)));
                    if i == length(ch), xlabel('Time (s)'); else, set(gca, 'XTickLabel', []); end
                end
            else
                nGroups = ceil(length(ch)/4);
                for g = 1:nGroups
                    chIdx = ch((g-1)*4 + 1 : min(g*4, length(ch)));
                    fig = figure('Name', sprintf('MUA Processed - Group %d', g), ...
                                 'Position', [200+100*g, 200-50*g, 1000, 700]);
                    ax = tiledlayout(fig, length(chIdx)+1, 1, ...
                                     'TileSpacing','compact', 'Padding','compact');
        
                    nexttile(ax);
                    plot(t_stim, stim);
                    ylabel(sprintf('Whis Ch %d', app.StimChannel));
                    title('Stimulation Signal');
        
                    for i = 1:length(chIdx)
                        chInd = (g-1)*4 + i;
                        nexttile(ax); hold on;
                        if params.overlayRaw
                            plot(t(chInd), rawAll{chInd}, 'Color', [0.6 0.6 0.6]);
                        end
                        plot(t(chInd), processed{chInd}, 'k', 'LineWidth', 1);
                        ylabel(sprintf('MUA Ch %d', chIdx(i)));
                        if i == length(chIdx), xlabel('Time (s)'); else, set(gca, 'XTickLabel', []); end
                    end
                end
            end
        
            app.LastProcessedMUA = processed;
            app.LastMUAfs = fs;
            app.LastMUAFilterParams = params;
        end
        
%% ------------------------------------------------------------------------------------------
        function saveMUAData(app, processedMUA, fsMUA, filterParams)
            if isempty(processedMUA)
                errordlg('No processed MUA data available.');
                return;
            end
        
            chLabels = arrayfun(@(c) sprintf('Ch %d', app.RAWChannels(c)), ...
                                1:length(app.RAWChannels), 'UniformOutput', false);
        
            [selection, ok] = listdlg('PromptString','Select MUA channels to save:', ...
                                      'SelectionMode','multiple', ...
                                      'ListString', chLabels);
        
            if ~ok || isempty(selection)
                return;
            end
        
            mua_data = cell2mat(processedMUA(selection)');
            mua_channels = app.RAWChannels(selection);
            mua_fs = fsMUA;
            t_mua = (0:size(mua_data,2)-1)/mua_fs;
            
            stim_data = app.Data.streams.Whis.data(app.StimChannel, :);
            stim_fs = app.Data.streams.Whis.fs;
            t_stim = (0:length(stim_data)-1)/stim_fs;
        
            [file, path] = uiputfile('*.mat', 'Save MUA Data As');
            if isequal(file, 0)
                return;
            end
        
            save(fullfile(path, file), ...
            'mua_data', 'mua_channels', 'mua_fs', 't_mua', ...
            'stim_data', 'stim_fs', 't_stim', 'filterParams');
        
            msgbox('MUA data and parameters saved successfully.', 'Success');
        end

    end
end