%% Processor.m
% =========================================================================
% PROCESSOR - STATIC SIGNAL PROCESSING HELPERS FOR LDF PIPELINE
% =========================================================================
% Currently provides only crop(): crops RawStim and RawLDF to a common
% sample range [startIdx, endIdx], fills ProcessedStim, ProcessedLDF,
% and TimeVector. If RawStim and RawLDF have different lengths, crops to
% the common length and issues a warning (ID: NeuroAnalyzer:Processor:lengthMismatch).
% =========================================================================

classdef Processor
    methods(Static)

        %% crop - Crop stimulus and LDF to a sample index range
        % -----------------------------------------------------------------
        % INPUT:  AppData - struct with RawStim, RawLDF, SamplingRate
        %         startIdx, endIdx - sample indices (1-based, inclusive)
        % OUTPUT: AppData - with ProcessedStim, ProcessedLDF, TimeVector updated
        % Logic: If RawStim and RawLDF lengths differ, N = min(lengths),
        %        clamp startIdx/endIdx to [1, N], then crop both to that range.
        %        TimeVector = (0 : numSamples-1) / Fs (seconds).
        % -----------------------------------------------------------------
        function AppData = crop(AppData, startIdx, endIdx)
            Nstim = length(AppData.RawStim);
            Nldf  = length(AppData.RawLDF);

            % --- Handle mismatched lengths: crop to common range and warn ---
            if Nstim ~= Nldf
                warning('NeuroAnalyzer:Processor:lengthMismatch', ...
                    'Processor.crop: RawStim length (%d) ~= RawLDF length (%d). Cropping to common range.', Nstim, Nldf);
                N = min(Nstim, Nldf);
                startIdx = max(1, min(startIdx, N));
                endIdx   = min(N, max(endIdx, startIdx));
            else
                N = Nstim;
                startIdx = max(1, startIdx);
                endIdx   = min(endIdx, N);
            end
            if startIdx > endIdx
                startIdx = 1;
                endIdx   = N;
            end

            % --- Copy cropped segments and build time vector ---
            AppData.ProcessedStim = AppData.RawStim(startIdx:endIdx);
            AppData.ProcessedLDF  = AppData.RawLDF(startIdx:endIdx);

            Fs = AppData.SamplingRate;
            AppData.TimeVector = (0:length(AppData.ProcessedStim)-1) / Fs;
        end
    end
end
