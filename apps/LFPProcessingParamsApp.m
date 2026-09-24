%% LFPProcessingParamsApp.m
% =========================================================================
% LFP PROCESSING PARAMETERS - DIALOG FOR LFP FILTER AND DOWNSAMPLE
% =========================================================================
% Opened from ExtractEphysApp when processing LFP. User sets lowpass cutoff
% (Hz), optional 60 Hz notch, and optional downsample rate. Apply returns
% Params to caller; Cancel closes without applying.
% =========================================================================

classdef LFPProcessingParamsApp < handle
    %% PROPERTIES: UI controls and Params (filled on Apply)
    properties
        UIFig
        FreqLowEdit
        NotchCheckbox
        DownsampleCheckbox
        DownsampleRateEdit
        ApplyBtn
        CancelBtn
        Params
    end

    methods
        %% Constructor - Build dialog
        function app = LFPProcessingParamsApp()
            app.buildUI();
        end

        %% buildUI - Figure with FreqLow, Notch checkbox, Downsample checkbox/edit, Apply/Cancel
        function buildUI(app)
            T = UITheme;
            app.UIFig = figure('Name', 'LFP Processing Parameters', ...
                'Position', [500 500 320 240], 'Resize', 'off', ...
                'MenuBar', 'none', 'ToolBar', 'none', 'NumberTitle', 'off', ...
                'Color', T.bgGray);

            uicontrol(app.UIFig, 'Style','text', 'String','Lowpass Cutoff (Hz):', ...
                'Position',[20 170 130 20], 'HorizontalAlignment','left');
            app.FreqLowEdit = uicontrol(app.UIFig, 'Style','edit', ...
                'Position',[160 170 100 25]);

            app.NotchCheckbox = uicontrol(app.UIFig, 'Style','checkbox', ...
                'String','Apply 60 Hz Notch Filter', ...
                'Position',[20 130 200 25]);

            app.DownsampleCheckbox = uicontrol(app.UIFig, 'Style','checkbox', ...
                'String','Downsample to (Hz):', ...
                'Position',[20 90 140 25], ...
                'Callback', @(~,~)app.toggleDownsample());
            app.DownsampleRateEdit = uicontrol(app.UIFig, 'Style','edit', ...
                'Position',[170 90 90 25], 'Enable','off');

            app.ApplyBtn = uicontrol(app.UIFig, 'Style','pushbutton', ...
                'String','Apply', 'Position',[40 30 100 30], ...
                'Callback', @(~,~)app.applyParams());
            app.CancelBtn = uicontrol(app.UIFig, 'Style','pushbutton', ...
                'String','Cancel', 'Position',[160 30 100 30], ...
                'Callback', @(~,~)app.cancel());
            uicontrol(app.UIFig, 'Style', 'pushbutton', 'String', '© Copyrights by Alejandro Suarez, Ph.D.', ...
                'Position', [10 2 280 14], 'HorizontalAlignment', 'right', 'FontSize', 8, 'ForegroundColor', [0.1 0.4 0.7], ...
                'BackgroundColor', T.bgGray, 'Callback', @(~,~)web('https://github.com/alesuarez92', '-browser'));
        end

        function toggleDownsample(app)
            if app.DownsampleCheckbox.Value
                set(app.DownsampleRateEdit, 'Enable','on');
            else
                set(app.DownsampleRateEdit, 'Enable','off');
            end
        end

        %% applyParams - Validate inputs; on error show errordlg and keep dialog open
        function applyParams(app)
            lowCutoff = str2double(app.FreqLowEdit.String);
            doDownsample = app.DownsampleCheckbox.Value;
            downsampleRate = str2double(app.DownsampleRateEdit.String);

            % Lowpass is optional (empty = skip), but if given it must be valid
            if ~isempty(strtrim(app.FreqLowEdit.String)) && (isnan(lowCutoff) || lowCutoff <= 0)
                errordlg('Lowpass cutoff must be a positive number (or empty to skip).', 'Invalid Parameters');
                return;
            end
            if doDownsample && (isnan(downsampleRate) || downsampleRate <= 0)
                errordlg('Downsample rate must be a positive number (Hz).', 'Invalid Parameters');
                return;
            end

            app.Params.lowCutoff = lowCutoff;
            app.Params.notch60 = app.NotchCheckbox.Value;
            app.Params.downsample = doDownsample;
            app.Params.downsampleRate = downsampleRate;
            delete(app.UIFig);
        end

        function cancel(app)
            app.Params = [];
            delete(app.UIFig);
        end
    end
end