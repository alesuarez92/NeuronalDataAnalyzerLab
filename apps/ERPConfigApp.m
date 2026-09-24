%% ERPConfigApp.m
% =========================================================================
% ERP CONFIGURATION - DIALOG FOR ERP WINDOW AND STIMULUS DETECTION
% =========================================================================
% Modal dialog opened from LFPAnalysisApp when configuring ERP Analysis.
% User sets pre-stimulus time, post-stimulus time, stimulus threshold, and
% minimum ISI (inter-stimulus interval) for detecting events. On OK, Params
% struct is filled and dialog closes; LFPAnalysisApp uses it to cut trials
% and average.
% =========================================================================

classdef ERPConfigApp < handle
    %% PROPERTIES: UI edits and Params struct (preTime, postTime, threshold, minISI)
    properties
        UIFig
        PreEdit
        PostEdit
        ThresholdEdit
        ISIEdit
        ConfirmBtn

        Fs
        Params
    end

    methods
        %% Constructor - Store Fs (for validation if needed), build modal dialog
        function app = ERPConfigApp(Fs)
            app.Fs = Fs;
            app.buildUI();
        end

        %% buildUI - Modal figure with Pre/Post time, Threshold, Min ISI edits and OK button
        function buildUI(app)
            T = UITheme;
            app.UIFig = figure('Name', 'ERP Configuration', ...
                'Position', [500 500 320 260], 'Resize', 'off', 'WindowStyle', 'modal', ...
                'Color', T.bgGray);

            uicontrol(app.UIFig, 'Style','text', 'String','Pre-Stimulus Time (s):', ...
                'Position',[20 200 150 20], 'HorizontalAlignment','left');
            app.PreEdit = uicontrol(app.UIFig, 'Style','edit', 'String','0.1', ...
                'Position',[180 200 80 20]);

            uicontrol(app.UIFig, 'Style','text', 'String','Post-Stimulus Time (s):', ...
                'Position',[20 160 150 20], 'HorizontalAlignment','left');
            app.PostEdit = uicontrol(app.UIFig, 'Style','edit', 'String','0.3', ...
                'Position',[180 160 80 20]);

            uicontrol(app.UIFig, 'Style','text', 'String','Threshold (stim units):', ...
                'Position',[20 120 150 20], 'HorizontalAlignment','left');
            app.ThresholdEdit = uicontrol(app.UIFig, 'Style','edit', 'String','0.5', ...
                'Position',[180 120 80 20]);

            uicontrol(app.UIFig, 'Style','text', 'String','Min ISI (s):', ...
                'Position',[20 80 150 20], 'HorizontalAlignment','left');
            app.ISIEdit = uicontrol(app.UIFig, 'Style','edit', 'String','0.5', ...
                'Position',[180 80 80 20]);

            app.ConfirmBtn = uicontrol(app.UIFig, 'Style','pushbutton', 'String','OK', ...
                'Position',[100 30 100 30],                 'Callback', @(~,~)app.confirm());
            uicontrol(app.UIFig, 'Style', 'pushbutton', 'String', '© Copyrights by Alejandro Suarez, Ph.D.', ...
                'Position', [10 2 300 14], 'HorizontalAlignment', 'right', 'FontSize', 8, 'ForegroundColor', [0.1 0.4 0.7], ...
                'BackgroundColor', T.bgGray, 'Callback', @(~,~)web('https://github.com/alesuarez92', '-browser'));
        end

        %% confirm - Validate edits, fill Params struct and close dialog
        % On invalid input show errordlg and keep the dialog open (Params unset).
        function confirm(app)
            preTime   = str2double(app.PreEdit.String);
            postTime  = str2double(app.PostEdit.String);
            threshold = str2double(app.ThresholdEdit.String);
            minISI    = str2double(app.ISIEdit.String);

            if any(isnan([preTime postTime threshold minISI]))
                errordlg('All fields must be numeric.', 'Invalid ERP Settings'); return;
            end
            if preTime < 0
                errordlg('Pre-stimulus time must be >= 0.', 'Invalid ERP Settings'); return;
            end
            if postTime <= 0
                errordlg('Post-stimulus time must be > 0.', 'Invalid ERP Settings'); return;
            end
            if minISI < 0
                errordlg('Min ISI must be >= 0.', 'Invalid ERP Settings'); return;
            end

            app.Params = struct( ...
                'preTime', preTime, ...
                'postTime', postTime, ...
                'threshold', threshold, ...
                'minISI', minISI ...
            );
            close(app.UIFig);
        end
    end
end