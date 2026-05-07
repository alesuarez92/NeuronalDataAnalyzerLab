%% UITheme.m
% =========================================================================
% UI THEME - SINGLE SOURCE OF TRUTH FOR NEUROANALYZER WINDOW STYLING
% =========================================================================
% Use UITheme.* in all app buildUI() to keep windows consistent. When
% adding or changing windows, follow the pattern in .cursor/rules and
% UI_STYLE.md. Main window defines the reference look.
% =========================================================================

classdef UITheme
    properties(Constant)
        % Backgrounds
        bgGray      = [0.96 0.965 0.98]   % Main/content background
        headerBg    = [0.18 0.28 0.48]    % Header bar (dark blue)
        projectBarBg = [0.92 0.94 0.96]   % Project / secondary bar
        projectBarBorder = [0.78 0.80 0.84]
        cardBg      = [1 1 1]             % Panel/card background
        cardBorder  = [0.82 0.84 0.86]    % Panel border (HighlightColor)
        % Accent (primary actions, key buttons)
        accent      = [0.2 0.55 0.6]      % Teal
        accentDark  = [0.35 0.5 0.55]     % Darker teal for secondary emphasis
        % Text
        headerTitleColor = [1 1 1]
        headerSubtitleColor = [0.88 0.92 0.96]
        sectionTitleColor = [0.2 0.25 0.35]
        bodyColor   = [0.45 0.5 0.55]
        mutedColor  = [0.5 0.52 0.58]
        % Font sizes
        fontTitle   = 22
        fontSubtitle = 11
        fontSection = 14
        fontButton  = 12
        fontBody    = 11
        fontSmall   = 10
        fontTiny    = 9
        % Header dimensions (for sub-windows that add a header). Tall enough
        % to fit a 22pt bold title + 11pt subtitle on two rows without overlap.
        headerHeight = 80
        headerPaddingH = 20
        headerPaddingV = 14
        % Footer (copyright bar) – fixed height so content never overlaps
        footerHeight = 28
        % Padding inside graph/axes panels so titles and labels are not clipped.
        % Order is [L B R T] (matches uigridlayout 'Padding'). Generous on all
        % sides: left for ylabel + tick labels, bottom for xlabel, top for title.
        axesPanelPadding = [40 35 12 35]
    end
end
