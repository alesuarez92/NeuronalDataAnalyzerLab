%% ERPAnalysis.m
% =========================================================================
% ERP ANALYSIS - HEADLESS ONSET DETECTION, EPOCH AVERAGING AND CSD
% =========================================================================
% The computations behind LFPAnalysisApp's ERP and CSD steps, without any
% UI, so scripts and batch processing get exactly the same numbers as the
% window. Toolbox-free (base MATLAB).
%
%   [onsetTimes, onsetIdx] = ERPAnalysis.detectOnsets(stim, fs, threshold, minISI)
%       Stimulus onsets: upward crossings of threshold by the
%       mean-subtracted stimulus. A crossing within minISI (s) of the last
%       kept onset is dropped (a pulse train gives one onset; same rule as
%       LDFPipeline.detectOnsets and SpikeTrains.stimulusOnsets). Sample k is at time
%       (k-1)/fs, so onsetTimes = (onsetIdx - 1) / fs (s).
%   [erpAvg, erpStd, t, nValid, epochs, valid] = ...
%           ERPAnalysis.average(lfp, fs, onsetTimes, pre, post)
%       Cuts one epoch per onset from onset - pre to onset + post (s) out
%       of lfp (channels x samples, sampled at fs, first sample at t = 0).
%       The onset sample is round(onsetTime * fs) + 1. Epochs that would
%       run past either end of the recording are left NaN and excluded
%       ('omitnan'); nValid counts the complete ones. erpAvg / erpStd are
%       channels x time (mean and SD over epochs), t = (-preN:postN) / fs,
%       epochs is channels x time x onsets and valid flags complete epochs.
%   csd = ERPAnalysis.csd(erp, spacingUm, order)
%       Current source density: the negative second spatial derivative of
%       the ERP across depth, -d2V/dz2, with z the channel position
%       (spacingUm micrometres apart; converted to metres, so the result
%       is in erp units / m^2). order (optional, default all rows) lists
%       the erp rows from top (superficial) to bottom (deep); at least 3.
%       The first and last rows (where the three-point difference is not
%       defined) are copied from their neighbours. Sinks are negative.
%       Constant conductivity is assumed (it is left out, so the units are
%       those of the potential's second derivative, not A/m^3).
%       This is the 'standard' method of core/CSDMethods, which adds
%       inverse CSD (delta / step / spline) and kernel CSD in A/m^3.
%
% Method reference (CSD):
%   Mitzdorf U (1985). Current source-density method and application in
%     cat cerebral cortex: investigation of evoked potentials and EEG
%     phenomena. Physiol Rev 65(1):37-100.
% =========================================================================

classdef ERPAnalysis
    methods(Static)

        %% detectOnsets - Upward threshold crossings of the mean-subtracted stimulus
        % stim: vector (row or column). fs: stimulus sampling rate (Hz).
        % threshold: in stimulus units, applied after subtracting the mean.
        % minISI: minimum interval (s) after the last kept onset.
        % OUTPUT: onsetTimes (s, row), onsetIdx (sample indices, row).
        function [onsetTimes, onsetIdx] = detectOnsets(stim, fs, threshold, minISI)
            if ~isvector(stim)
                error('NeuroAnalyzer:ERPAnalysis:stimNotVector', 'The stimulus must be a vector.');
            end
            stim = stim(:).';
            stim = stim - mean(stim);
            above = stim > threshold;
            onsetIdx = find(diff([0 above]) == 1);
            if isempty(onsetIdx)
                onsetIdx = zeros(1, 0);
                onsetTimes = zeros(1, 0);
                return;
            end
            % Keep a crossing only if it comes more than minISI after the last
            % KEPT onset (as LDF): a pulse train gives one onset per train
            keep = false(size(onsetIdx));
            last = -Inf;
            for i = 1:numel(onsetIdx)
                if (onsetIdx(i) - last) / fs > minISI
                    keep(i) = true;
                    last = onsetIdx(i);
                end
            end
            onsetIdx = onsetIdx(keep);
            onsetTimes = (onsetIdx - 1) / fs;   % sample k is at (k-1)/Fs
        end

        %% average - NaN-filled epochs around each onset; mean and SD of the complete ones
        function [erpAvg, erpStd, t, nValid, epochs, valid] = average(lfp, fs, onsetTimes, preS, postS)
            preSamples = round(preS * fs);
            postSamples = round(postS * fs);
            totalSamples = preSamples + postSamples + 1;
            nOn = numel(onsetTimes);
            % NaN-filled so skipped (edge) epochs are ignored by 'omitnan'
            epochs = nan(size(lfp, 1), totalSamples, nOn);
            valid = false(1, nOn);
            for k = 1:nOn
                centerIdx = round(onsetTimes(k) * fs) + 1;
                idxRange = centerIdx - preSamples : centerIdx + postSamples;
                if idxRange(1) < 1 || idxRange(end) > size(lfp, 2)
                    continue;
                end
                epochs(:, :, k) = lfp(:, idxRange);
                valid(k) = true;
            end
            nValid = sum(valid);
            erpAvg = mean(epochs, 3, 'omitnan');
            erpStd = std(epochs, 0, 3, 'omitnan');
            t = (-preSamples:postSamples) / fs;
        end

        %% csd - Negative second spatial derivative across ordered channels
        function c = csd(erp, spacingUm, order)
            if nargin < 3 || isempty(order), order = 1:size(erp, 1); end
            if ~(isscalar(spacingUm) && isfinite(spacingUm) && spacingUm > 0)
                error('NeuroAnalyzer:ERPAnalysis:badSpacing', ...
                    'Inter-electrode spacing must be a positive number (um).');
            end
            if numel(order) < 3
                error('NeuroAnalyzer:ERPAnalysis:tooFewChannels', 'CSD needs at least 3 channels.');
            end
            erp = erp(order, :);
            dz = spacingUm * 1e-6;                  % metres
            c = -diff(erp, 2, 1) / dz^2;
            c = [c(1,:); c; c(end,:)];              % replicate edge rows (no padarray dependency)
        end
    end
end
