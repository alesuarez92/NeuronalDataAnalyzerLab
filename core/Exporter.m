%% Exporter.m
% =========================================================================
% EXPORTER - CENTRALIZED SAVE HELPERS FOR LDF AND CROPPED DATA
% =========================================================================
% Used by ExtractLDFApp (and can be used by other apps) to save cropped
% LDF data to .mat and to remember the last used directory via MATLAB
% preferences (NeuroAnalyzer.LastUsedPath). saveCropped() shows uiputfile,
% saves variables stim, LDF, t, Fs, and optionally uses defaultPath as
% initial folder. getLastUsedPath/setLastUsedPath read/write the pref.
% =========================================================================

classdef Exporter
    methods(Static)

        %% saveCropped - Save cropped stim, LDF, time vector, and Fs to .mat
        % -----------------------------------------------------------------
        % INPUT:  stim, LDF - vectors; t - time vector; Fs - sampling rate
        %         defaultPath - optional initial folder for uiputfile (or [])
        % OUTPUT: saved - true if save succeeded
        %         pathUsed - folder where file was saved (for setting last path)
        % If stim or LDF is empty, shows errordlg and returns. If user
        % cancels uiputfile, returns without saving. On save success shows
        % msgbox; on save error shows errordlg.
        % -----------------------------------------------------------------
        function [saved, pathUsed] = saveCropped(stim, LDF, t, Fs, defaultPath)
            saved = false;
            pathUsed = '';
            if isempty(stim) || isempty(LDF)
                errordlg('No cropped data to save. Crop first.', 'Save');
                return;
            end
            if nargin < 5
                defaultPath = '';
            end
            if isempty(defaultPath)
                [file, path] = uiputfile('*.mat', 'Save Cropped Data As');
            else
                [file, path] = uiputfile(fullfile(defaultPath, '*.mat'), 'Save Cropped Data As');
            end
            if isequal(file, 0)
                return;
            end
            filename = fullfile(path, file);
            try
                save(filename, 'stim', 'LDF', 't', 'Fs');
                saved = true;
                pathUsed = path;
                msgbox('Cropped data saved successfully.');
            catch ME
                errordlg(sprintf('Save failed: %s', ME.message), 'Save Error');
            end
        end

        %% getLastUsedPath - Return last used directory from preferences
        % -----------------------------------------------------------------
        % OUTPUT: pathUsed - char (folder path) or '' if not set
        % -----------------------------------------------------------------
        function pathUsed = getLastUsedPath()
            if ispref('NeuroAnalyzer', 'LastUsedPath')
                pathUsed = getpref('NeuroAnalyzer', 'LastUsedPath');
            else
                pathUsed = '';
            end
        end

        %% setLastUsedPath - Store directory for next save/open dialog
        % -----------------------------------------------------------------
        % INPUT: pathUsed - folder path; only stored if non-empty and exists as dir
        % -----------------------------------------------------------------
        function setLastUsedPath(pathUsed)
            if ~isempty(pathUsed) && exist(pathUsed, 'dir')
                setpref('NeuroAnalyzer', 'LastUsedPath', pathUsed);
            end
        end
    end
end
