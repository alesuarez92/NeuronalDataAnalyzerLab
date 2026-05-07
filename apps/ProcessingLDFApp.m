%% ProcessingLDFApp.m
% =========================================================================
% PROCESS LDF DATA - FILTER, DOWNSAMPLE, AND SEGMENT LDF BY STIMULUS ONSETS
% =========================================================================
% Launched from Main. Loads raw or cropped LDF + stimulus .mat, opens
% LDFProcessingParamsApp for filter/downsample settings, applies filter,
% optionally segments trials around stimulus onsets, plots average LDF or
% segments, and saves segmented data for LDFGrandAverageApp. Uses legacy
% figure/uicontrol. Key methods: loadData, receiveProcessingParams,
% segmentByOnsetsConfig, plotAverageSegment, saveData.
% =========================================================================

classdef ProcessingLDFApp < handle
    %% PROPERTIES: UI handles, processing params, signals and segmented data
    properties       
        UIFig
        LoadBtn
        SaveBtn
        AxStim
        AxLDF
        FilterBtn
        ApplyBtn           
        DSMenu
        FilterMenu
        ProcessingParams
        Stim
        LDF
        RawLDF
        t
        tRaw
        Fs
        FsLabel          % uicontrol handle for the sampling rate display
        SegmentedLDF     % ← store segmented LDF trials
        SegmentedTime    % ← time axis for each segment
    end

    methods
        %% Constructor - Build UI only; data loaded via Load File
        function app = ProcessingLDFApp()
            app.buildUI();
        end

        %% buildUI - Header | fixed controls | axes | fixed footer (consistent with Main)
        function buildUI(app)
            T = UITheme;
            app.UIFig = figure('Name', 'LDF Processing Window', ...
                'Position', [200 200 1200 680], 'Resize', 'on', ...
                'Color', T.bgGray, ...
                'MenuBar', 'none', 'ToolBar', 'none', 'NumberTitle', 'off');

            % --- Header: full-width, tall enough for title + subtitle ---
            headerH = 0.13;
            headerPanel = uipanel(app.UIFig, 'Units', 'normalized', ...
                'Position', [0 1-headerH 1 headerH], 'BorderType', 'none', ...
                'BackgroundColor', T.headerBg);
            uicontrol(headerPanel, 'Style', 'text', 'String', 'LDF Processing', ...
                'Units', 'normalized', 'Position', [0.02 0.45 0.4 0.45], ...
                'FontSize', T.fontTitle, 'FontWeight', 'bold', 'ForegroundColor', T.headerTitleColor, ...
                'BackgroundColor', T.headerBg, 'HorizontalAlignment', 'left');
            uicontrol(headerPanel, 'Style', 'text', 'String', 'Filter, downsample, segment by stimulus', ...
                'Units', 'normalized', 'Position', [0.02 0.10 0.45 0.30], ...
                'FontSize', T.fontSubtitle, 'ForegroundColor', T.headerSubtitleColor, ...
                'BackgroundColor', T.headerBg, 'HorizontalAlignment', 'left');

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

            % --- Fixed controls section (positioned just below the header) ---
            ctrlTop = 1 - headerH - 0.02;
            ctrlH = 0.08;
            ctrlPanel = uipanel(app.UIFig, 'Title', 'Controls', 'Units', 'normalized', ...
                'Position', [0.01 ctrlTop-ctrlH 0.98 ctrlH], 'BackgroundColor', T.cardBg, ...
                'HighlightColor', T.cardBorder, 'FontSize', T.fontSmall);
            app.LoadBtn = uicontrol(ctrlPanel, 'Style','pushbutton', 'String','Load File', ...
                'Units', 'normalized', 'Position', [0.01 0.15 0.08 0.7], 'Callback', @(~,~)app.loadData());
            uicontrol(ctrlPanel, 'Style','pushbutton','String','Set Processing', ...
                'Units', 'normalized', 'Position', [0.10 0.15 0.10 0.7], ...
                'Callback', @(~,~)openFilterSettings());
            function openFilterSettings()
                if isempty(app.Fs) || app.Fs <= 0
                    errordlg('Please load a dataset first.', 'Missing Sampling Rate');
                    return;
                end
                LDFProcessingParamsApp(@(params)app.receiveProcessingParams(params), app.Fs);
            end
            uicontrol(ctrlPanel, 'Style','pushbutton','String','Segment by Onsets', ...
                'Units', 'normalized', 'Position', [0.21 0.15 0.12 0.7], ...
                'Callback', @(~,~)openSegmentBySettings());
            function openSegmentBySettings()
                if isempty(app.Fs) || app.Fs <= 0
                    errordlg('Please load a dataset first.', 'Missing Sampling Rate');
                    return;
                end
                app.segmentByOnsetsConfig();
            end
            uicontrol(ctrlPanel, 'Style','pushbutton','String','Plot Average LDF', ...
                'Units', 'normalized', 'Position', [0.34 0.15 0.11 0.7], ...
                'Callback', @(~,~)openPlotAverageSegment());
            function openPlotAverageSegment()
                if isempty(app.Fs) || app.Fs <= 0
                    errordlg('Please load a dataset first.', 'Missing Sampling Rate');
                    return;
                end
                app.plotAverageSegment();
            end
            app.SaveBtn = uicontrol(ctrlPanel, 'Style','pushbutton', 'String','Save Result', ...
                'Units', 'normalized', 'Position', [0.46 0.15 0.09 0.7], 'Callback', @(~,~)opensaveData());
            function opensaveData()
                if isempty(app.Fs) || app.Fs <= 0
                    errordlg('Please load a dataset first.', 'Missing Sampling Rate');
                    return;
                end
                app.saveData();
            end
            uicontrol(ctrlPanel, 'Style','text', 'String','Sampling Rate (Hz):', ...
                'Units', 'normalized', 'Position', [0.57 0.15 0.13 0.5], 'HorizontalAlignment','left');
            app.FsLabel = uicontrol(ctrlPanel, 'Style','text', 'String','---', ...
                'Units', 'normalized', 'Position', [0.71 0.15 0.10 0.5], ...
                'BackgroundColor','white', 'HorizontalAlignment','left');

            % --- Axes (above footer, below controls); leave room above the
            % footer so the bottom-axis xlabel and tick labels never overlap
            % the copyright. Also reserve a top margin per axis for the title. ---
            graphBottom = footerH + 0.06;
            graphTop = ctrlTop - ctrlH - 0.04;
            graphH = graphTop - graphBottom;
            gap = 0.03;
            titleMargin = 0.04;
            axH = (graphH - gap - 2*titleMargin) / 2;
            app.AxStim = axes(app.UIFig, 'Units', 'normalized', ...
                'Position', [0.08, graphBottom + axH + titleMargin + gap, 0.84, axH]);
            app.AxLDF  = axes(app.UIFig, 'Units', 'normalized', ...
                'Position', [0.08, graphBottom, 0.84, axH]);
        end

        function loadData(app)
            uistack(app.UIFig, 'bottom');
            drawnow;
            [file, path] = uigetfile('*.mat', 'Load Saved Data');
            figure(app.UIFig);
            if isequal(file, 0), return; end
            data = load(fullfile(path, file));

            % Assume correct vars exist
            app.Stim = data.stim;
            app.LDF  = data.LDF;
            app.t    = data.t;
            app.Fs   = data.Fs;
            app.RawLDF = app.LDF;
            app.tRaw = data.t;
            app.updateSamplingRateLabel();

            % Plot
            axes(app.AxStim); cla(app.AxStim);
            plot(app.t, app.Stim);
            title('Loaded Stimulus'); xlabel('Time (s)');

            axes(app.AxLDF); cla(app.AxLDF);
            plot(app.t, app.LDF);
            title('Loaded LDF'); xlabel('Time (s)');          
        end
        
        function receiveProcessingParams(app, params)
            app.ProcessingParams = params;
            app.applyFilter();
        end
        
        function applyFilter(app)
            if isempty(app.LDF) || isempty(app.ProcessingParams)
                errordlg('Missing data or parameters.');
                return;
            end
        
            LDF = app.LDF;
            t = app.t;
            stim = app.Stim;
            Fs = app.Fs;
            p = app.ProcessingParams;
        
            % Downsample
            if p.downsample > 1
                LDF = downsample(LDF, p.downsample);
                stim = downsample(stim, p.downsample);
                t = downsample(t, p.downsample);
                Fs = Fs / p.downsample;
            end
        
            % Filter
            % Skip if no filtering
            if p.filterType == 1
                filteredLDF = LDF;
            else
                Wn = [];  % Normalized cutoff
                filterOrder = p.filterOrder;          
                switch p.filterType
                    case 2  % Low-pass
                        Wn = p.cutoffHigh / (Fs/2);
                    case 3  % High-pass
                        Wn = p.cutoffLow / (Fs/2);
                    case 4  % Band-pass
                        Wn = [p.cutoffLow p.cutoffHigh] / (Fs/2);
                    case 5  % Notch
                        Wn = [p.cutoffLow p.cutoffHigh] / (Fs/2);
                end

                if any([p.cutoffLow, p.cutoffHigh] >= Fs/2)
                    errordlg('Cutoff frequency must be below Nyquist (Fs/2).');
                    return;
                end
                
                if p.cutoffLow >= p.cutoffHigh && ismember(p.filterType, [4, 5])
                    errordlg('For band-pass and notch filters, Low cutoff must be < High cutoff.');
                    return;
                end
                
                if p.filterOrder <= 0 || isnan(p.filterOrder)
                    errordlg('Filter order must be a positive number.');
                    return;
                end
            
                % Design filter
                mode = app.getFilterMode(p.filterType);
                switch p.designType
                    case 1  % Butterworth
                        [b, a] = butter(filterOrder, Wn, mode);
                    case 2  % Chebyshev I
                        [b, a] = cheby1(filterOrder, 0.5, Wn, mode);
                    case 3  % FIR
                        b = fir1(filterOrder, Wn, mode);
                        a = 1;
                end
            
                % Apply filter
                filteredLDF = filtfilt(b, a, LDF);
            
                % Plot frequency response
                figure('Name','Filter Frequency Response');
                freqz(b, a, 1024, Fs);
            end

        
            % Update
            app.LDF = filteredLDF;
            app.Stim = stim;
            app.t = t;
            app.Fs = Fs;

            app.updateSamplingRateLabel();
        
            axes(app.AxLDF); cla(app.AxLDF);
            plot(t, filteredLDF); title('Processed LDF'); xlabel('Time (s)');

            figure('Name', 'LDF Filter Comparison');
            hold on;
            plot(app.tRaw(:), app.RawLDF(:), 'k--', 'DisplayName','Original LDF');  % original
            plot(t(:), filteredLDF(:), 'b-', 'LineWidth',1.5, 'DisplayName','Filtered LDF');
            xlabel('Time (s)'); ylabel('Amplitude');
            legend; grid on;
            title('Filtered vs. Original LDF');
        end
        
        function mode = getFilterMode(app,filterType)
            switch filterType
                case 2
                    mode = 'low';
                case 3
                    mode = 'high';
                case 4
                    mode = 'bandpass';
                case 5
                    mode = 'stop';
                otherwise
                    mode = 'low';
            end
        end

        function segmentByOnsetsConfig(app)
            d = dialog('Position',[600 500 300 250],'Name','Segment Around Stim Onsets');
        
            uicontrol(d,'Style','text','String','Stim Threshold:',...
                'Position',[20 190 100 20]);
            threshEdit = uicontrol(d,'Style','edit','String','0.5',...
                'Position',[150 190 80 25]);
        
            uicontrol(d,'Style','text','String','Pre (s):',...
                'Position',[20 150 100 20]);
            preEdit = uicontrol(d,'Style','edit','String','2',...
                'Position',[150 150 80 25]);
        
            uicontrol(d,'Style','text','String','Post (s):',...
                'Position',[20 110 100 20]);
            postEdit = uicontrol(d,'Style','edit','String','4',...
                'Position',[150 110 80 25]);
        
            uicontrol(d,'Style','text','String','Min ISI (s):',...
                 'Position',[20 70 100 20]);
            isiEdit = uicontrol(d,'Style','edit','String','1',...
                'Position',[150 70 80 25]);

             uicontrol(d,'Style','pushbutton','String','Apply',...
                'Position',[100 20 100 30],...
                'Callback', @(~,~)runSegmentation());
        
            function runSegmentation()
                threshold = str2double(threshEdit.String);
                preSec    = str2double(preEdit.String);
                postSec   = str2double(postEdit.String);
                minISI    = str2double(isiEdit.String);
            
                close(d);
                app.segmentLDFByOnsets(threshold, preSec, postSec, minISI);
            end
        end

        function segmentLDFByOnsets(app, threshold, preSec, postSec, minISI_sec)
            if isempty(app.Stim) || isempty(app.LDF)
                errordlg('Stimulus or LDF data missing.'); return;
            end
        
            stim = app.Stim;
            ldf = app.LDF;
            t = app.t;
            Fs = app.Fs;
        
            % 1. Threshold and detect rising edges
            stimLogic = app.Stim > threshold;
            stimLogic = stimLogic(:);  % ensure column vector
            rawOnsets = find(diff([0; stimLogic]) == 1);  % all rising edges
            
            % 2. Debounce: only keep one onset per pulse
            minISI_samp = round(minISI_sec * app.Fs);
            
            onsets = [];
            lastAccepted = -inf;
            
            for i = 1:length(rawOnsets)
                if rawOnsets(i) - lastAccepted >= minISI_samp
                    onsets(end+1) = rawOnsets(i); %#ok<AGROW>
                    lastAccepted = rawOnsets(i);
                end
            end
            
            fprintf('Debounced onsets found: %d\n', length(onsets));
            
            preSamp = round(preSec * Fs);
            postSamp = round(postSec * Fs);
            segLength = preSamp + postSamp + 1;
        
            validSegments = [];
            for i = 1:length(onsets)
                idx = onsets(i);
                startIdx = idx - preSamp;
                endIdx = idx + postSamp;
        
                if startIdx > 0 && endIdx <= length(ldf)
                    validSegments = [validSegments; startIdx endIdx];
                end
            end
        
            if isempty(validSegments)
                errordlg('No complete trials found.');
                return;
            end
        
            % 2. Create LDF segment matrix
            nTrials = size(validSegments,1);
            ldfSegments = zeros(nTrials, segLength);
        
            for i = 1:nTrials
                ldfSegments(i,:) = ldf(validSegments(i,1):validSegments(i,2));
            end
        
            % 3. Plot all segments over time
            t_seg = (-preSamp:postSamp) / Fs;
            figure('Name','LDF Segments Around Onsets');
            plot(t_seg, ldfSegments'); xlabel('Time (s)');
            title(sprintf('LDF Segments (n = %d)', nTrials));
        
            % 4. Optional: Store for further analysis
            app.SegmentedLDF = ldfSegments;
            app.SegmentedTime = t_seg;
        end

        function updateSamplingRateLabel(app)
            if ~isempty(app.Fs)
                app.FsLabel.String = sprintf('%.2f', app.Fs);
            else
                app.FsLabel.String = '---';
            end
        end

        function plotAverageSegment(app)
            if isempty(app.SegmentedLDF) || isempty(app.SegmentedTime)
                errordlg('No segmented LDF data available.'); return;
            end
        
            segments = app.SegmentedLDF;
            t_seg = app.SegmentedTime;
        
            avgLDF = mean(segments, 1);
            stdLDF = std(segments, 0, 1);
        
            figure('Name','Average LDF Trace');
            hold on;
        
            % Shaded area: mean ± std
            fill([t_seg, fliplr(t_seg)], ...
                 [avgLDF + stdLDF, fliplr(avgLDF - stdLDF)], ...
                 [0.8 0.8 1], 'EdgeColor', 'none', 'FaceAlpha', 0.4);
        
            plot(t_seg, avgLDF, 'b-', 'LineWidth', 2);
        
            xlabel('Time (s)');
            ylabel('LDF');
            title(sprintf('Average LDF (n = %d trials)', size(segments,1)));
            grid on;
        end

        function saveData(app)
            if isempty(app.SegmentedLDF)
                errordlg('No segmented data to save.');
                return;
            end
        
            [file, path] = uiputfile('*.mat', 'Save or Append Segmented Data As');
            if isequal(file, 0), return; end
        
            fullpath = fullfile(path, file);
            segmentedLDF = app.SegmentedLDF;
            segmentedTime = app.SegmentedTime;
            Fs = app.Fs;
        
            if isfile(fullpath)
                % Append to existing file
                existing = load(fullpath);
                if isfield(existing, 'segmentedLDF') && isfield(existing, 'segmentedTime')
                    if ~isequal(existing.segmentedTime, segmentedTime)
                        errordlg('Time axes do not match. Cannot append segments.');
                        return;
                    end
                    segmentedLDF = [existing.segmentedLDF; segmentedLDF];
                end
            end
        
            save(fullpath, 'segmentedLDF', 'segmentedTime', 'Fs');
            msgbox('Segmented LDF data saved!');
        end
        
    
    end
end