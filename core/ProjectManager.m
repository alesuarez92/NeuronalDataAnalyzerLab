%% ProjectManager.m
% =========================================================================
% PROJECT MANAGER - IMPORT/EXPORT DIRECTORIES FOR THE CURRENT SESSION
% =========================================================================
% Stores and retrieves Import and Export directories via MATLAB preferences
% (NeuroAnalyzer.ImportDir, NeuroAnalyzer.ExportDir). Used by Main to show
% current project dirs and by DataLoader/Exporter as default paths. User can
% set both to the same "working directory" or use separate Import/Export.
% promptIfEmpty: if true and dirs not set, opens uigetdir to set them.
% =========================================================================

classdef ProjectManager
    methods(Static)
        %% getImportDir - Return current Import directory ('' if not set)
        function p = getImportDir()
            if ispref('NeuroAnalyzer', 'ImportDir')
                p = getpref('NeuroAnalyzer', 'ImportDir');
            else
                p = '';
            end
        end

        %% getExportDir - Return current Export directory ('' if not set)
        function p = getExportDir()
            if ispref('NeuroAnalyzer', 'ExportDir')
                p = getpref('NeuroAnalyzer', 'ExportDir');
            else
                p = '';
            end
        end

        %% setImportDir - Store Import directory; only if path exists
        function setImportDir(p)
            if ~isempty(p) && exist(p, 'dir')
                setpref('NeuroAnalyzer', 'ImportDir', p);
            end
        end

        %% setExportDir - Store Export directory; only if path exists
        function setExportDir(p)
            if ~isempty(p) && exist(p, 'dir')
                setpref('NeuroAnalyzer', 'ExportDir', p);
            end
        end

        %% setBothDirs - Set both Import and Export to the same folder (working dir)
        function setBothDirs(p)
            if ~isempty(p) && exist(p, 'dir')
                setpref('NeuroAnalyzer', 'ImportDir', p);
                setpref('NeuroAnalyzer', 'ExportDir', p);
            end
        end

        %% hasProject - True if at least Import or Export is set
        function ok = hasProject()
            ok = ~isempty(ProjectManager.getImportDir()) || ...
                 ~isempty(ProjectManager.getExportDir());
        end

        %% promptForProjectDirs - Dialog to set Import and/or Export; returns true if user set at least one
        % Optional: startIn - initial folder for uigetdir
        function ok = promptForProjectDirs(startIn)
            if nargin < 1, startIn = ''; end
            if isempty(startIn)
                startIn = ProjectManager.getImportDir();
                if isempty(startIn), startIn = ProjectManager.getExportDir(); end
                if isempty(startIn), startIn = pwd; end
            end
            msg = 'Set project directories. You can choose the same folder for both (working directory) or set them separately.';
            choice = questdlg(msg, 'Project Directories', ...
                'Set Import & Export (same folder)', 'Set Import or Export separately', 'Cancel', ...
                'Set Import & Export (same folder)');
            ok = false;
            switch choice
                case 'Set Import & Export (same folder)'
                    p = uigetdir(startIn, 'Select working directory (Import & Export)');
                    if p ~= 0
                        ProjectManager.setBothDirs(p);
                        ok = true;
                    end
                case 'Set Import or Export separately'
                    choice2 = questdlg('Which directory do you want to set?', 'Project Directories', ...
                        'Set Import only', 'Set Export only', 'Cancel', 'Set Import only');
                    switch choice2
                        case 'Set Import only'
                            p = uigetdir(startIn, 'Select Import directory');
                            if p ~= 0
                                ProjectManager.setImportDir(p);
                                ok = true;
                            end
                        case 'Set Export only'
                            p = uigetdir(startIn, 'Select Export directory');
                            if p ~= 0
                                ProjectManager.setExportDir(p);
                                ok = true;
                            end
                    end
            end
        end
    end
end
