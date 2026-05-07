%% FileDialog.m
% =========================================================================
% FILE DIALOG WRAPPERS (PASS-THROUGH)
% =========================================================================
% Previously tried hiding or minimizing the figure so dialogs would appear
% on top on macOS; that caused the dialog to be stuck (not movable, not
% raisable) or the figure to flicker. Reverted to built-in uigetfile/
% uiputfile/uigetdir. If the dialog opens behind the app, drag the main
% window aside to use it. No-op wrappers kept only for API compatibility.
% =========================================================================

classdef FileDialog
    methods (Static)
        function varargout = uigetfile(varargin)
            [varargout{1:nargout}] = uigetfile(varargin{:});
        end
        function varargout = uiputfile(varargin)
            [varargout{1:nargout}] = uiputfile(varargin{:});
        end
        function pathname = uigetdir(varargin)
            pathname = uigetdir(varargin{:});
        end
    end
end
