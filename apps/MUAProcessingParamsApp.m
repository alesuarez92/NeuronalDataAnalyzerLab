%% MUAProcessingParamsApp.m
% =========================================================================
% MUA PROCESSING PARAMETERS - DIALOG FOR MUA BANDPASS FILTER AND SMOOTHING
% =========================================================================
% Opened from ExtractEphysApp when processing MUA. Presets (e.g. Standard
% MUA 300–3000 Hz), filter type (Butterworth, Chebyshev), order, low/high
% cutoff, optional smoothing. Apply returns Params; Cancel closes.
% =========================================================================

classdef MUAProcessingParamsApp < handle
    %% PROPERTIES: UI menus/edits and Params (filled on Apply)
    properties
        UIFig
        PresetMenu
        FilterTypeMenu
        OrderEdit
        FreqLowEdit
        FreqHighEdit
        AutoSmoothCheckbox
        SmoothEdit
        OverlayCheckbox
        ApplyBtn
        CancelBtn
        Params
    end

    methods
        %% Constructor - Build dialog
        function app = MUAProcessingParamsApp()
            app.buildUI();
        end

        %% buildUI - Figure with Preset, Filter type, Order, Cutoffs, Smoothing, Overlay, Apply/Cancel
        function buildUI(app)
            T = UITheme;
            app.UIFig = figure('Name', 'MUA Processing Parameters', ...
                'Position', [500 400 380 380], 'Resize', 'off', ...
                'MenuBar', 'none', 'ToolBar', 'none', 'NumberTitle', 'off', ...
                'Color', T.bgGray);

            % === Presets ===
            uicontrol(app.UIFig, 'Style','text', 'String','Preset:', ...
                'Position',[20 310 80 20], 'HorizontalAlignment','left');
            app.PresetMenu = uicontrol(app.UIFig, 'Style','popupmenu', ...
                'String', {'Custom','Standard MUA (300–3000 Hz, Butter, 4)', ...
                           'Broadband MUA (500–5000 Hz)'}, ...
                'Position',[110 310 220 25], ...
                'Callback', @(~,~)app.applyPreset());

            % === Filter type ===
            uicontrol(app.UIFig, 'Style','text', 'String','Filter Type:', ...
                'Position',[20 270 100 20], 'HorizontalAlignment','left');
            app.FilterTypeMenu = uicontrol(app.UIFig, 'Style','popupmenu', ...
                'String', {'Butterworth','Chebyshev I'}, ...
                'Position',[130 270 200 25]);

            % === Order ===
            uicontrol(app.UIFig, 'Style','text', 'String','Filter Order:', ...
                'Position',[20 230 100 20], 'HorizontalAlignment','left');
            app.OrderEdit = uicontrol(app.UIFig, 'Style','edit', ...
                'Position',[130 230 200 25], 'String','4');

            % === Low cutoff ===
            uicontrol(app.UIFig, 'Style','text', 'String','Low Cutoff (Hz):', ...
                'Position',[20 190 100 20], 'HorizontalAlignment','left');
            app.FreqLowEdit = uicontrol(app.UIFig, 'Style','edit', ...
                'Position',[130 190 200 25], 'String','300');

            % === High cutoff ===
            uicontrol(app.UIFig, 'Style','text', 'String','High Cutoff (Hz):', ...
                'Position',[20 150 100 20], 'HorizontalAlignment','left');
            app.FreqHighEdit = uicontrol(app.UIFig, 'Style','edit', ...
                'Position',[130 150 200 25], 'String','3000');

            % === Smoothing ===
            app.AutoSmoothCheckbox = uicontrol(app.UIFig, 'Style','checkbox', ...
                'String','Auto-smooth (2 ms)', ...
                'Position',[20 110 150 25], ...
                'Value', 1, ...
                'Callback', @(~,~)app.toggleSmoothing());

            uicontrol(app.UIFig, 'Style','text', 'String','Smooth (ms):', ...
                'Position',[180 110 100 20], 'HorizontalAlignment','left');
            app.SmoothEdit = uicontrol(app.UIFig, 'Style','edit', ...
                'Position',[260 110 70 25], ...
                'String','2', ...
                'Enable','off');

            % === Overlay ===
            app.OverlayCheckbox = uicontrol(app.UIFig, 'Style','checkbox', ...
                'String','Overlay raw signal on plot', ...
                'Position',[20 70 200 25], 'Value', 0);

            % === Buttons ===
            app.ApplyBtn = uicontrol(app.UIFig, 'Style','pushbutton', ...
                'String','Apply', 'Position',[60 20 100 30], ...
                'Callback', @(~,~)app.applyParams());
            app.CancelBtn = uicontrol(app.UIFig, 'Style','pushbutton', ...
                'String','Cancel', 'Position',[190 20 100 30], ...
                'Callback', @(~,~)app.cancel());
            uicontrol(app.UIFig, 'Style', 'pushbutton', 'String', '© Copyrights by Alejandro Suarez, Ph.D.', ...
                'Position', [10 2 300 14], 'HorizontalAlignment', 'right', 'FontSize', 8, 'ForegroundColor', [0.1 0.4 0.7], ...
                'BackgroundColor', T.bgGray, 'Callback', @(~,~)web('https://github.com/alesuarez92', '-browser'));
        end

        function toggleSmoothing(app)
            if app.AutoSmoothCheckbox.Value
                app.SmoothEdit.Enable = 'off';
            else
                app.SmoothEdit.Enable = 'on';
            end
        end

        function applyPreset(app)
            switch app.PresetMenu.Value
                case 2 % Standard MUA
                    app.FilterTypeMenu.Value = 1;
                    app.OrderEdit.String = '4';
                    app.FreqLowEdit.String = '300';
                    app.FreqHighEdit.String = '3000';
                case 3 % Broadband
                    app.FilterTypeMenu.Value = 1;
                    app.OrderEdit.String = '4';
                    app.FreqLowEdit.String = '500';
                    app.FreqHighEdit.String = '5000';
            end
        end

        function applyParams(app)
            order = str2double(app.OrderEdit.String);
            lowCutoff = str2double(app.FreqLowEdit.String);
            highCutoff = str2double(app.FreqHighEdit.String);
            smoothMs = str2double(app.SmoothEdit.String);
            % Validate before closing; keep the dialog open on bad input
            if ~isfinite(order) || order < 1 || order ~= round(order)
                errordlg('Filter order must be a positive integer.', 'Invalid Parameters');
                return;
            end
            if ~isfinite(lowCutoff) || ~isfinite(highCutoff) || lowCutoff <= 0 || highCutoff <= lowCutoff
                errordlg('Cutoffs must satisfy 0 < Low < High (Hz).', 'Invalid Parameters');
                return;
            end
            if ~app.AutoSmoothCheckbox.Value && (~isfinite(smoothMs) || smoothMs <= 0)
                errordlg('Smoothing window must be a positive number of ms.', 'Invalid Parameters');
                return;
            end
            app.Params.filterType = app.FilterTypeMenu.String{app.FilterTypeMenu.Value};
            app.Params.order = order;
            app.Params.lowCutoff = lowCutoff;
            app.Params.highCutoff = highCutoff;
            app.Params.smoothMs = smoothMs;
            app.Params.autoSmooth = app.AutoSmoothCheckbox.Value;
            app.Params.overlayRaw = app.OverlayCheckbox.Value;
            delete(app.UIFig);
        end

        function cancel(app)
            app.Params = [];
            delete(app.UIFig);
        end
    end
end