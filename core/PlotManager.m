%% PlotManager.m
% =========================================================================
% PLOTMANAGER - STATIC HELPERS FOR PLOTTING LDF AND STIMULUS SIGNALS
% =========================================================================
% plotStimLDF(AppData, axStim, axLDF): clears the two axes and plots
% AppData.RawStim and AppData.RawLDF vs time (derived from length and
% SamplingRate). Uses plot(ax, t, y) so it works with both legacy axes
% and uiaxes (e.g. in ExtractLDFApp). Titles and axis labels are set
% for "Stimulus (Channel 6)" and "LDF (Channel 8)".
% =========================================================================

classdef PlotManager
    methods(Static)

        %% plotStimLDF - Plot raw stimulus and LDF in two axes
        % -----------------------------------------------------------------
        % INPUT:  AppData - struct with RawStim, RawLDF, SamplingRate
        %         axStim  - axes handle (e.g. uiaxes) for stimulus
        %         axLDF   - axes handle for LDF
        % Builds time vector t = (0 : length(RawStim)-1) / SamplingRate,
        % then plots RawStim and RawLDF with titles and axis labels.
        % -----------------------------------------------------------------
        function plotStimLDF(AppData, axStim, axLDF)
            t = (0:length(AppData.RawStim)-1) / AppData.SamplingRate;

            cla(axStim);
            plot(axStim, t, AppData.RawStim);
            title(axStim, 'Stimulus (Channel 6)');
            xlabel(axStim, 'Time (s)');
            ylabel(axStim, 'Amplitude');

            cla(axLDF);
            plot(axLDF, t, AppData.RawLDF);
            title(axLDF, 'LDF (Channel 8)');
            xlabel(axLDF, 'Time (s)');
            ylabel(axLDF, 'Amplitude');
        end
    end
end
