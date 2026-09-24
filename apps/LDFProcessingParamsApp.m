%% LDFProcessingParamsApp.m
% =========================================================================
% LDF PROCESSING PARAMETERS - DIALOG FOR FILTER AND DOWNSAMPLE SETTINGS
% =========================================================================
% Modal dialog opened from ProcessingLDFApp when user clicks "Set Processing".
% Parent passes a callback and the current sampling rate. User selects:
% Downsample (1x, 2x, 5x, 10x), Filter Type (None, Low-pass, High-pass,
% Band-pass, Notch), Design Type (Butterworth, Chebyshev I, FIR), Cutoff
% Low/High (Hz), and Order. Cutoff fields are enabled/disabled and given
% default values based on filter type (updateCutoffFields). On Apply,
% parameters are validated and passed to ParentCallback(params); then the
% dialog closes. "? Filter help" button opens HelpApp on the Filtering tab.
% =========================================================================

classdef LDFProcessingParamsApp < handle
    %% PROPERTIES
    properties
        UIFig          % figure (legacy) for this dialog
        DSMenu         % popup: downsample factor (1x, 2x, 5x, 10x)
        FilterMenu     % (unused; kept for compatibility)
        CutoffLow      % edit: low cutoff (Hz); enabled for high-pass, band-pass, notch
        CutoffHigh     % edit: high cutoff (Hz); enabled for low-pass, band-pass, notch
        ParentCallback % function handle: called with params struct on Apply
        DesignMenu     % popup: Butterworth, Chebyshev I, FIR
        OrderEdit      % edit: filter order (positive integer)
        FilterTypeMenu % popup: None, Low-pass, High-pass, Band-pass, Notch
        SamplingRate   % scalar: used to suggest cutoff defaults (Nyquist = Fs/2)
    end

    methods
        %% Constructor - Store callback and Fs, then build UI
        function app = LDFProcessingParamsApp(parentCallback, samplingRate)
            app.ParentCallback = parentCallback;
            app.SamplingRate = samplingRate;
            app.buildUI();
        end

        %% buildUI - Create dialog with dropdowns and edit fields
        % -------------------------------------------------------------
        % Layout: Downsample, Filter Type, Design Type, Cutoff Low/High (Hz),
        % Order. Filter Type callback updates cutoff visibility and defaults.
        % Buttons: Apply (validates and calls ParentCallback), ? Filter help.
        % -------------------------------------------------------------
        function buildUI(app)
            T = UITheme;
            app.UIFig = figure('Name', 'Set Processing Parameters', ...
                'Position', [600 500 320 300], 'Resize', 'off', ...
                'Color', T.bgGray);

            uicontrol(app.UIFig,'Style','text','String','Downsample:',...
                'Position',[30 250 80 20]);
            app.DSMenu = uicontrol(app.UIFig,'Style','popupmenu',...
                'String',{'1x','2x','5x','10x'},...
                'Position',[120 250 100 25],...
                'Callback', @(~,~)app.updateCutoffFields(app.FilterTypeMenu.Value));

            uicontrol(app.UIFig,'Style','text','String','Filter Type:',...
                'Position',[30 210 80 20]);
            app.FilterTypeMenu = uicontrol(app.UIFig, 'Style','popupmenu', ...
                'String', {'None','Low-pass','High-pass','Band-pass','Notch'}, ...
                'Position',[120 210 100 25],...
                'Callback', @(src,~)app.updateCutoffFields(src.Value));

            uicontrol(app.UIFig, 'Style','text','String','Design Type:',...
                'Position',[30 170 100 20]);
            app.DesignMenu = uicontrol(app.UIFig, 'Style','popupmenu',...
                'String',{'Butterworth','Chebyshev I','FIR'},...
                'Position',[120 170 100 25]);

            uicontrol(app.UIFig,'Style','text','String','Cutoff Low (Hz):',...
                'Position',[30 130 100 20]);
            app.CutoffLow = uicontrol(app.UIFig,'Style','edit','String','0.5',...
                'Position',[140 130 60 25]);

            uicontrol(app.UIFig,'Style','text','String','Cutoff High (Hz):',...
                'Position',[30 90 100 20]);
            app.CutoffHigh = uicontrol(app.UIFig,'Style','edit','String','5',...
                'Position',[140 90 60 25]);

            uicontrol(app.UIFig, 'Style','text','String','Order:',...
                'Position',[30 50 100 20]);
            app.OrderEdit = uicontrol(app.UIFig, 'Style','edit','String','4',...
                'Position',[140 50 60 25]);

            uicontrol(app.UIFig,'Style','pushbutton','String','Apply',...
                'Position',[100 10 100 30],...
                'Callback', @(~,~)app.applySettings());
            uicontrol(app.UIFig,'Style','pushbutton','String','? Filter help',...
                'Position',[210 10 90 30],...
                'TooltipString','How low-pass, high-pass, and band-pass filters work',...
                'Callback', @(~,~)HelpApp('Filtering'));
            uicontrol(app.UIFig, 'Style', 'pushbutton', 'String', '© Copyrights by Alejandro Suarez, Ph.D.', ...
                'Position', [10 2 290 14], 'HorizontalAlignment', 'right', 'FontSize', 8, 'ForegroundColor', [0.1 0.4 0.7], ...
                'BackgroundColor', T.bgGray, 'Callback', @(~,~)web('https://github.com/alesuarez92', '-browser'));
        end

        %% applySettings - Read UI, validate, build params struct, call parent, close
        % -------------------------------------------------------------
        % params: downsample, filterType (menu index), designType (index),
        % filterOrder, cutoffLow, cutoffHigh (NaN when field disabled).
        % Validates order > 0 and cutoffs when enabled. On error shows errordlg
        % and returns; otherwise ParentCallback(params) and close(UIFig).
        % -------------------------------------------------------------
        function applySettings(app)
            dsOptions = [1, 2, 5, 10];
            params.downsample = dsOptions(app.DSMenu.Value);
            params.filterType = app.FilterTypeMenu.Value;
            params.designType = app.DesignMenu.Value;
            params.filterOrder = str2double(app.OrderEdit.String);

            if isnan(params.filterOrder) || params.filterOrder <= 0
                errordlg('Filter order must be a positive number.'); return;
            end

            if strcmp(app.CutoffLow.Enable, 'on')
                params.cutoffLow = str2double(app.CutoffLow.String);
                if isnan(params.cutoffLow) || params.cutoffLow <= 0
                    errordlg('Low cutoff frequency is invalid or missing.'); return;
                end
            else
                params.cutoffLow = NaN;
            end

            if strcmp(app.CutoffHigh.Enable, 'on')
                params.cutoffHigh = str2double(app.CutoffHigh.String);
                if isnan(params.cutoffHigh) || params.cutoffHigh <= 0
                    errordlg('High cutoff frequency is invalid or missing.'); return;
                end
            else
                params.cutoffHigh = NaN;
            end

            app.ParentCallback(params);
            close(app.UIFig);
        end

        %% updateCutoffFields - Enable/disable cutoff fields and set defaults by filter type
        % -------------------------------------------------------------
        % filterType: 1=None, 2=Low-pass, 3=High-pass, 4=Band-pass, 5=Notch.
        % Low-pass: only High cutoff; High-pass: only Low; Band/Notch: both.
        % Defaults use the effective Nyquist after downsampling
        % (Fs/factor/2), since filtering runs after downsampling: e.g.
        % low-pass high = 0.5*nyq. Also called when Downsample changes.
        % -------------------------------------------------------------
        function updateCutoffFields(app, filterType)
            dsOptions = [1, 2, 5, 10];
            Fs = app.SamplingRate / dsOptions(app.DSMenu.Value);
            nyq = Fs / 2;

            switch filterType
                case 2  % Low-pass
                    set(app.CutoffLow, 'Enable', 'off');
                    set(app.CutoffHigh, 'Enable', 'on');
                    app.CutoffHigh.String = num2str(round(0.5 * nyq, 2));

                case 3  % High-pass
                    set(app.CutoffLow, 'Enable', 'on');
                    set(app.CutoffHigh, 'Enable', 'off');
                    app.CutoffLow.String = num2str(round(0.01 * nyq, 2));

                case {4, 5}  % Band-pass or Notch
                    set(app.CutoffLow, 'Enable', 'on');
                    set(app.CutoffHigh, 'Enable', 'on');
                    app.CutoffLow.String  = num2str(round(0.01 * nyq, 2));
                    app.CutoffHigh.String = num2str(round(0.5 * nyq, 2));

                otherwise  % None or invalid
                    set(app.CutoffLow, 'Enable', 'off');
                    set(app.CutoffHigh, 'Enable', 'off');
                    app.CutoffLow.String = '';
                    app.CutoffHigh.String = '';
            end
        end
    end
end
