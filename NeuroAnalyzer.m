function NeuroAnalyzer
% NeuroAnalyzer - Launch the Neuronal Data Analyzer toolbox (NMD Lab).
%
% Usage:
%   NeuroAnalyzer
%
% Adds the toolbox folders to the path and opens the main application window.
% You can add the NeuroAnalyzer folder to your MATLAB path permanently
% (e.g. via pathtool or addpath) and then run "NeuroAnalyzer" from the
% Command Window from any directory.
%
% Copyrights by Alejandro Suarez, Ph.D.
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
addpath(genpath(fullfile(rootDir, 'Utilities')));
% Project root for docs and resources (used by HelpApp, etc.)
setpref('NeuroAnalyzer', 'RootDir', rootDir);
% Launch main application
Main();
end
