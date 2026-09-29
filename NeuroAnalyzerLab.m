function NeuroAnalyzerLab
% NeuroAnalyzerLab - Launch Neuronal Data Analyzer Lab.
%
% Usage:
%   NeuroAnalyzerLab
%
% Adds the toolbox folders to the path and opens the main application window.
% You can add the toolbox folder to your MATLAB path permanently
% (e.g. via pathtool or addpath) and then run "NeuroAnalyzerLab" from the
% Command Window from any directory.
%
% Copyright (C) 2026 Alejandro Suarez, Ph.D.
% Licensed under the PolyForm Noncommercial License 1.0.0 with a citation
% condition: free for noncommercial use; cite it when you publish work that
% used it (CITATION.cff). No warranty. See LICENSE.txt.
%
% See also Main.

rootDir = fileparts(mfilename('fullpath'));
if isempty(rootDir)
    rootDir = pwd;
end
% Ensure toolbox and subfolders are on the path
addpath(rootDir);
addpath(fullfile(rootDir, 'apps'));
addpath(fullfile(rootDir, 'core'));
addpath(fullfile(rootDir, 'core', 'imaging'));
addpath(fullfile(rootDir, 'core', 'io'));
addpath(fullfile(rootDir, 'core', 'demo'));
addpath(genpath(fullfile(rootDir, 'Utilities')));
% Project root for docs and resources (used by HelpApp, etc.)
setpref('NeuroAnalyzer', 'RootDir', rootDir);
% Launch main application
Main();
end
