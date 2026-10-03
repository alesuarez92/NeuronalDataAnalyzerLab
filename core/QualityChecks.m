%% QualityChecks.m
% =========================================================================
% QUALITY CHECKS - ONE FORMAT FOR THE CHECKS OF EVERY WINDOW
% =========================================================================
% A window's checks say, in plain language, what was found in the data and
% the settings, why it matters and what to try, before the numbers are
% used. Every window keeps them in the same format, so the Checks tab
% (UIKit.checksTab), sessions, the PDF report, the methods text and batch
% summaries show them the same way.
%
% Checks are a struct array Q (K x 1), one element per row:
%   level   'ok'      nothing to do
%           'check'   look at it: it may be fine, or not
%           'warning' the numbers are probably wrong until it is fixed
%           'note'    information, no judgement (e.g. which model was used)
%   topic   short name of what was checked ('Pixel size', 'Trials', ...)
%   found   what was found, with the values
%   why     why it matters ('' when obvious)
%   action  what to try ('' when nothing)
%
%   Q = QualityChecks.none()                     no rows (0 x 1)
%   Q = QualityChecks.add(Q, level, topic, found, why, action)
%                                                 one row more (why and
%                                                 action optional)
%   n = QualityChecks.count(Q, level)             rows of a level
%   s = QualityChecks.summary(Q)                  '6 OK, 1 to check, no warnings'
%   s = QualityChecks.brief(Q)                    number of warnings and the
%                                                 first one, for a table cell
%   t = QualityChecks.text(row)                   found, why and action as one
%                                                 paragraph
%   d = QualityChecks.detail(row)                 the whole row, one part per
%                                                 line (the Checks tab text box)
%   L = QualityChecks.lines(Q)                    'OK: ...', 'Check: ...',
%                                                 'Warning: ...' (notes without
%                                                 a prefix), one per row
%   L = QualityChecks.reportLines(Q)              'Warning - Topic: ...', most
%                                                 serious first (report, logs);
%                                                 OK rows and notes: what was
%                                                 found only
%   D = QualityChecks.tableData(Q)                K x 3 {Result, Topic, Finding}
%   C = QualityChecks.toCells(Q)                  K x 3 {level, topic, text}
%   Q = QualityChecks.fromCells(C)                the reverse (text -> found)
%   Q = QualityChecks.fromLines(L, topic)         rows from 'OK: / Check: /
%                                                 Warning: ...' lines (other
%                                                 lines are notes); topic: one
%                                                 text or one per line
%   s = QualityChecks.label(level)                'OK' | 'Check' | 'Warning' | 'Note'
%   Q = QualityChecks.ensure(Q)                   any of the above inputs, or
%                                                 [] -> rows (sessions, scripts)
%
% Errors: NeuroAnalyzer:QualityChecks:level. Base MATLAB only; also runs in
% GNU Octave.
% =========================================================================

classdef QualityChecks
    properties(Constant)
        Levels = {'warning', 'check', 'note', 'ok'}    % most serious first
        Labels = {'Warning', 'Check', 'Note', 'OK'}
        Prefixes = {'Warning: ', 'Check: ', '', 'OK: '}
    end

    methods(Static)

        %% none - No rows
        function Q = none()
            Q = repmat(struct('level', '', 'topic', '', 'found', '', 'why', '', 'action', ''), 0, 1);
        end

        %% add - Append one row
        function Q = add(Q, level, topic, found, why, action)
            if nargin < 5, why = ''; end
            if nargin < 6, action = ''; end
            level = lower(char(level));
            if ~any(strcmp(level, QualityChecks.Levels))
                error('NeuroAnalyzer:QualityChecks:level', ...
                    'A check level must be ok, check, warning or note (got "%s").', level);
            end
            if isempty(Q), Q = QualityChecks.none(); end
            Q(end + 1, 1) = struct('level', level, 'topic', char(topic), 'found', char(found), ...
                'why', char(why), 'action', char(action));
        end

        %% count - Number of rows of a level
        function n = count(Q, level)
            Q = QualityChecks.ensure(Q);
            if isempty(Q), n = 0; return; end
            n = nnz(strcmp({Q.level}, level));
        end

        %% summary - '6 OK, 1 to check, no warnings' ('no checks' when there are none)
        function s = summary(Q)
            Q = QualityChecks.ensure(Q);
            if isempty(Q), s = 'no checks'; return; end
            s = sprintf('%d OK, %d to check, %s', QualityChecks.count(Q, 'ok'), ...
                QualityChecks.count(Q, 'check'), QualityChecks.plural(QualityChecks.count(Q, 'warning'), 'warning'));
            nn = QualityChecks.count(Q, 'note');
            if nn > 0, s = sprintf('%s, %s', s, QualityChecks.plural(nn, 'note')); end
        end

        %% brief - One cell of a table: the warnings (or checks) and the first one
        % '' when there are no rows; 'OK' when nothing is to check.
        function s = brief(Q)
            Q = QualityChecks.ensure(Q);
            s = '';
            if isempty(Q), return; end
            k = find(strcmp({Q.level}, 'warning'));
            head = QualityChecks.plural(numel(k), 'warning');
            if isempty(k)
                k = find(strcmp({Q.level}, 'check'));
                head = sprintf('%d to check', numel(k));
            end
            if isempty(k)
                s = 'OK';
            else
                s = sprintf('%s: %s: %s', head, Q(k(1)).topic, Q(k(1)).found);
            end
        end

        %% text - Found, why and action as one paragraph
        function t = text(row)
            parts = {row.found, row.why, row.action};
            parts = parts(~cellfun(@isempty, parts));
            t = strjoin(parts, ' ');
        end

        %% detail - The whole row, one part per line (cellstr)
        function d = detail(row)
            d = {sprintf('%s: %s', QualityChecks.label(row.level), row.topic), row.found};
            if ~isempty(row.why), d{end+1} = ['Why it matters: ' row.why]; end
            if ~isempty(row.action), d{end+1} = ['What to try: ' row.action]; end
        end

        %% lines - One 'OK: / Check: / Warning: ...' line per row (notes: no prefix)
        function L = lines(Q)
            Q = QualityChecks.ensure(Q);
            L = cell(1, numel(Q));
            for k = 1:numel(Q)
                L{k} = [QualityChecks.Prefixes{QualityChecks.levelIndex(Q(k).level)} QualityChecks.text(Q(k))];
            end
        end

        %% reportLines - 'Warning - Topic: ...', most serious first
        function L = reportLines(Q)
            Q = QualityChecks.ensure(Q);
            L = {};
            for i = 1:numel(QualityChecks.Levels)
                for k = find(strcmp({Q.level}, QualityChecks.Levels{i}))
                    if any(strcmp(Q(k).level, {'warning', 'check'}))
                        t = QualityChecks.text(Q(k));
                    else
                        t = Q(k).found;
                    end
                    L{end+1} = sprintf('%s - %s: %s', QualityChecks.Labels{i}, Q(k).topic, t); %#ok<AGROW>
                end
            end
        end

        %% tableData - K x 3 {Result, Topic, Finding} for a uitable
        function D = tableData(Q)
            Q = QualityChecks.ensure(Q);
            D = cell(numel(Q), 3);
            for k = 1:numel(Q)
                D(k, :) = {QualityChecks.label(Q(k).level), Q(k).topic, Q(k).found};
            end
        end

        %% toCells - K x 3 {level, topic, text}
        function C = toCells(Q)
            Q = QualityChecks.ensure(Q);
            C = cell(numel(Q), 3);
            for k = 1:numel(Q)
                C(k, :) = {Q(k).level, Q(k).topic, QualityChecks.text(Q(k))};
            end
        end

        %% fromCells - Rows from K x 3 {level, topic, text}
        function Q = fromCells(C)
            Q = QualityChecks.none();
            for k = 1:size(C, 1)
                Q = QualityChecks.add(Q, C{k, 1}, C{k, 2}, C{k, 3});
            end
        end

        %% fromLines - Rows from 'OK: / Check: / Warning: ...' lines
        function Q = fromLines(L, topic)
            if nargin < 2 || isempty(topic), topic = 'General'; end
            L = cellstr(L);
            if ischar(topic), topic = repmat({topic}, size(L)); end
            Q = QualityChecks.none();
            for k = 1:numel(L)
                t = char(L{k});
                level = 'note';
                for i = [1 2 4]
                    pre = QualityChecks.Prefixes{i};
                    if strncmpi(t, pre, numel(pre))
                        level = QualityChecks.Levels{i};
                        t = t(numel(pre) + 1:end);
                        break;
                    end
                end
                Q = QualityChecks.add(Q, level, topic{k}, strtrim(t));
            end
        end

        %% label - 'OK' | 'Check' | 'Warning' | 'Note'
        function s = label(level)
            s = QualityChecks.Labels{QualityChecks.levelIndex(level)};
        end

        %% ensure - Rows from rows, K x 3 cells, lines or []
        function Q = ensure(Q)
            if isempty(Q)
                Q = QualityChecks.none();
            elseif isstruct(Q)
                Q = Q(:);
            elseif iscell(Q) && size(Q, 2) == 3 && iscellstr(Q) && ...
                    all(ismember(lower(Q(:, 1)), QualityChecks.Levels))
                Q = QualityChecks.fromCells(Q);
            else
                Q = QualityChecks.fromLines(Q);
            end
        end
    end

    methods(Static, Hidden)

        function i = levelIndex(level)
            i = find(strcmp(lower(char(level)), QualityChecks.Levels), 1);
            if isempty(i)
                error('NeuroAnalyzer:QualityChecks:level', ...
                    'A check level must be ok, check, warning or note (got "%s").', char(level));
            end
        end

        %% plural - '1 warning', '2 warnings', 'no warnings'
        function s = plural(n, word)
            if n == 0
                s = sprintf('no %ss', word);
            elseif n == 1
                s = sprintf('1 %s', word);
            else
                s = sprintf('%d %ss', n, word);
            end
        end
    end
end
