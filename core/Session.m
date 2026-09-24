%% Session.m
% =========================================================================
% SESSION FILES - SAVE AND REOPEN A WINDOW'S INPUTS, SETTINGS AND RESULTS
% =========================================================================
% A session is a struct saved as '<name>.nasession.mat' (variable
% 'session') that records everything needed to reproduce an analysis:
%
%   format, formatVersion  'NeuroAnalyzer session', 1
%   app, appTitle          window class (e.g. 'LFPAnalysisApp') and title
%   toolboxVersion         UITheme.version
%   matlabVersion          version (and matlabRelease, e.g. '2021a')
%   os                     operating system and computer type
%   created                date/time of saving (ISO 8601, local time)
%   inputs                 struct array, one per input file or folder:
%                          role, path, name, isFolder, bytes, modified
%                          (ISO 8601), md5 (hex; folders: see md5 below)
%   settings               the window's settings (filter, ERP, sorting,
%                          ROI ... parameters); window specific
%   results                the window's result structs; leaves larger
%                          than Session.MaxLeafBytes are replaced by a
%                          text placeholder (they are re-computed on open)
%   summary                cellstr of key results, one line each (report)
%   notes                  free text entered when saving
%
% Each window provides two public methods:
%   st = app.sessionState()      struct with settings, results, inputs
%                                (built with Session.fileInfo) and summary
%   ok = app.restoreSession(s)   reload s.inputs (paths already resolved),
%                                re-apply s.settings, re-run the analysis
%                                (or restore stored results where re-running
%                                cannot reproduce them, e.g. manual edits)
%
% API
%   s    = Session.capture(app, notes)   new session from app.sessionState()
%   out  = Session.save(path, s)         write (-v7, or -v7.3 when large);
%                                        returns the path written (extension
%                                        '.nasession.mat' added if missing)
%   s    = Session.load(path)            read and validate
%   st   = Session.verifyInputs(s, sessionPath)
%          per-input status: 'ok' | 'changed' (MD5 differs) | 'missing' |
%          'moved' (not at the saved path, but a file with the same name and
%          MD5 sits next to the session file) | 'generated' (no file: made
%          in memory, e.g. a demo generator)
%   [s, st, msg] = Session.resolveInputs(s, sessionPath, interactive, fig)
%          verifyInputs + use moved files; when interactive, asks the user
%          to locate missing inputs (uigetfile / uigetdir)
%   h    = Session.md5(path, engine)     MD5 (hex) of a file or folder
%   info = Session.fileInfo(path, role)  provenance of one input
%   ok   = Session.saveApp(app, path, notes)          used by app.saveSessionTo
%   ok   = Session.openInApp(app, path, interactive)  used by app.openSession
%   lines = Session.describe(value, prefix)           text lines for reports
%
% MD5: java.security.MessageDigest, read in 4 MB chunks. Without a JVM
% it falls back to the system tool (md5sum / md5 / certutil) and then
% to a pure-MATLAB implementation of RFC 1321 (slow, small files). A
% folder's MD5 is the MD5 of the text "<md5>  <relative/path>\n" over
% all files in the folder (recursive, sorted by relative path, '/'
% separators), like the output of 'md5sum' run on each file.
%
% Base MATLAB only (R2021a). No toolboxes.
% =========================================================================

classdef Session
    properties(Constant)
        Extension = '.nasession.mat'
        Format = 'NeuroAnalyzer session'
        FormatVersion = 1
        ChunkBytes = 4 * 1024 * 1024     % MD5 read size
        MaxLeafBytes = 100e6             % larger result arrays are not stored
        V73Bytes = 1.9e9                 % -v7 cannot hold variables > 2 GB
    end

    methods(Static)

        %% new - Empty session with the environment filled in
        function s = new(appName)
            if nargin < 1, appName = ''; end
            s = struct();
            s.format = Session.Format;
            s.formatVersion = Session.FormatVersion;
            s.app = char(appName);
            s.appTitle = '';
            s.toolboxVersion = UITheme.version;
            s.matlabVersion = version;
            s.matlabRelease = '';
            try, s.matlabRelease = version('-release'); catch, end
            s.os = Session.osText();
            s.created = Session.isoNow();
            s.inputs = Session.emptyInputs();
            s.settings = struct();
            s.results = struct();
            s.summary = {};
            s.notes = '';
        end

        %% capture - Session of a window: environment + app.sessionState()
        % notes: free text (default: the notes of the session last saved or
        % opened in this window).
        function s = capture(app, notes)
            if nargin < 2 || isempty(notes)
                notes = Session.lastNotes(app);
            end
            s = Session.new(class(app));
            try, s.appTitle = char(app.UIFig.Name); catch, end
            st = app.sessionState();
            if isfield(st, 'settings'), s.settings = st.settings; end
            if isfield(st, 'results'), s.results = Session.limitSize(st.results, Session.MaxLeafBytes); end
            if isfield(st, 'inputs') && ~isempty(st.inputs), s.inputs = st.inputs(:)'; end
            if isfield(st, 'summary'), s.summary = cellstr(st.summary); end
            s.notes = Session.notesText(notes);
        end

        %% save - Write the session to path ('.nasession.mat' added if missing)
        function out = save(p, s)
            Session.validate(s, 'the session to save');
            out = Session.withExtension(p);
            session = s; %#ok<NASGU> saved below
            w = whos('session');
            if w.bytes > Session.V73Bytes
                save(out, 'session', '-v7.3');
            else
                save(out, 'session', '-v7');
            end
        end

        %% load - Read a session file and check that it is one
        function s = load(p)
            if ~exist(p, 'file')
                error('NeuroAnalyzer:Session:notFound', 'Session file not found: %s', p);
            end
            try
                d = load(p, 'session');
            catch ME
                error('NeuroAnalyzer:Session:unreadable', 'Could not read %s: %s', p, ME.message);
            end
            if ~isfield(d, 'session')
                error('NeuroAnalyzer:Session:invalid', ...
                    'This is not a NeuroAnalyzer session file (no variable ''session''): %s', p);
            end
            s = d.session;
            Session.validate(s, p);
            if isempty(s.inputs), s.inputs = Session.emptyInputs(); end
            if ~isfield(s, 'summary'), s.summary = {}; end
            if ~isfield(s, 'notes'), s.notes = ''; end
            if ~isfield(s, 'appTitle'), s.appTitle = ''; end
        end

        %% validate - Error unless s has the session fields
        function validate(s, where)
            need = {'format', 'app', 'toolboxVersion', 'matlabVersion', 'created', ...
                'inputs', 'settings', 'results'};
            if ~isstruct(s) || ~isscalar(s)
                error('NeuroAnalyzer:Session:invalid', 'Not a session struct: %s', where);
            end
            missing = need(~isfield(s, need));
            if ~isempty(missing)
                error('NeuroAnalyzer:Session:invalid', 'Session fields missing (%s): %s', ...
                    strjoin(missing, ', '), where);
            end
            if ~strcmp(s.format, Session.Format)
                error('NeuroAnalyzer:Session:invalid', 'Not a NeuroAnalyzer session: %s', where);
            end
        end

        %% withExtension - path ending in '.nasession.mat'
        function p = withExtension(p)
            p = char(p);
            if numel(p) >= 14 && strcmpi(p(end-13:end), Session.Extension)
                return;
            end
            if numel(p) >= 4 && strcmpi(p(end-3:end), '.mat')
                p = p(1:end-4);
            end
            p = [p Session.Extension];
        end

        %% fileInfo - Provenance of one input: role, path, size, date, MD5
        % path '' (or a struct with field generator) = generated in memory.
        function info = fileInfo(p, role)
            if nargin < 2, role = 'input'; end
            p = char(p);
            info = struct('role', char(role), 'path', p, 'name', '', 'isFolder', false, ...
                'bytes', 0, 'modified', '', 'md5', '');
            if isempty(p)
                info.name = '(generated in memory)';
                return;
            end
            [~, n, e] = fileparts(regexprep(p, '[\\/]+$', ''));
            info.name = [n e];
            info.isFolder = isfolder(p);
            if info.isFolder
                files = Session.listFiles(p);
                info.bytes = 0;
                last = 0;
                for k = 1:numel(files)
                    d = dir(fullfile(p, files{k}));
                    info.bytes = info.bytes + d.bytes;
                    last = max(last, d.datenum);
                end
                if last > 0, info.modified = datestr(last, 'yyyy-mm-ddTHH:MM:SS'); end
            elseif exist(p, 'file')
                d = dir(p);
                info.bytes = d.bytes;
                info.modified = datestr(d.datenum, 'yyyy-mm-ddTHH:MM:SS');
            else
                return;
            end
            try
                info.md5 = Session.md5(p);
            catch
                info.md5 = '';
            end
        end

        %% verifyInputs - Check every input against its saved size / MD5
        % Returns a struct array (one per input): role, name, path (saved),
        % resolvedPath (where it is now, '' when missing), status, md5
        % (saved), md5Now, message. status: 'ok' | 'changed' | 'missing' |
        % 'moved' | 'generated'. sessionPath (optional): moved inputs are
        % looked for next to the session file.
        function st = verifyInputs(s, sessionPath)
            if nargin < 2, sessionPath = ''; end
            ins = s.inputs;
            st = struct('role', {}, 'name', {}, 'path', {}, 'resolvedPath', {}, 'status', {}, ...
                'md5', {}, 'md5Now', {}, 'message', {});
            for k = 1:numel(ins)
                r = struct('role', ins(k).role, 'name', ins(k).name, 'path', ins(k).path, ...
                    'resolvedPath', '', 'status', '', 'md5', ins(k).md5, 'md5Now', '', 'message', '');
                if isempty(ins(k).path)
                    r.status = 'generated';
                    r.message = sprintf('%s: generated in memory (no file to check)', ins(k).role);
                    st(end+1) = r; %#ok<AGROW>
                    continue;
                end
                if Session.exists(ins(k).path)
                    r.resolvedPath = ins(k).path;
                    r.md5Now = Session.safeMD5(ins(k).path);
                    if isempty(ins(k).md5) || strcmpi(r.md5Now, ins(k).md5)
                        r.status = 'ok';
                        r.message = sprintf('%s: %s (unchanged)', ins(k).role, ins(k).name);
                    else
                        r.status = 'changed';
                        r.message = sprintf('%s: %s has CHANGED since the session was saved (MD5 differs)', ...
                            ins(k).role, ins(k).name);
                    end
                else
                    cand = '';
                    if ~isempty(sessionPath)
                        cand = fullfile(fileparts(char(sessionPath)), ins(k).name);
                        if ~Session.exists(cand), cand = ''; end
                    end
                    if ~isempty(cand) && strcmpi(Session.safeMD5(cand), ins(k).md5)
                        r.resolvedPath = cand;
                        r.md5Now = ins(k).md5;
                        r.status = 'moved';
                        r.message = sprintf('%s: %s found next to the session file (moved, unchanged)', ...
                            ins(k).role, ins(k).name);
                    else
                        r.status = 'missing';
                        r.message = sprintf('%s: %s not found at %s', ins(k).role, ins(k).name, ins(k).path);
                    end
                end
                st(end+1) = r; %#ok<AGROW>
            end
        end

        %% resolveInputs - verifyInputs, then relocate missing inputs
        % interactive: ask the user to locate each missing input (file or
        % folder picker); the new location is checked against the saved
        % MD5. s.inputs(k).path is set to the location found. msg: cellstr
        % of warnings (changed / moved / relocated / missing inputs).
        function [s, st, msg] = resolveInputs(s, sessionPath, interactive, fig)
            if nargin < 2, sessionPath = ''; end
            if nargin < 3, interactive = false; end
            if nargin < 4, fig = []; end
            st = Session.verifyInputs(s, sessionPath);
            msg = {};
            for k = 1:numel(st)
                if strcmp(st(k).status, 'missing') && interactive
                    p = Session.askLocation(s.inputs(k), fig);
                    if ~isempty(p)
                        st(k).resolvedPath = p;
                        st(k).md5Now = Session.safeMD5(p);
                        if isempty(s.inputs(k).md5) || strcmpi(st(k).md5Now, s.inputs(k).md5)
                            st(k).status = 'moved';
                            st(k).message = sprintf('%s: %s relocated by the user (unchanged)', ...
                                st(k).role, st(k).name);
                        else
                            st(k).status = 'changed';
                            st(k).message = sprintf(['%s: the file chosen for %s differs from the one ' ...
                                'used when the session was saved (MD5 differs)'], st(k).role, st(k).name);
                        end
                    end
                end
                if ~isempty(st(k).resolvedPath)
                    s.inputs(k).path = st(k).resolvedPath;
                end
                if ~any(strcmp(st(k).status, {'ok', 'generated'}))
                    msg{end+1} = st(k).message; %#ok<AGROW>
                end
            end
        end

        %% saveApp - Capture the window's session and write it (status + alert)
        % Used by every window's saveSessionTo(path, notes). Returns true on
        % success; the path written is stored with the notes in the window.
        function ok = saveApp(app, p, notes)
            if nargin < 3, notes = []; end
            ok = false;
            lbl = Session.statusLabel(app);
            try
                s = Session.capture(app, notes);
                out = Session.save(p, s);
            catch ME
                UIKit.setStatus(lbl, sprintf('Session not saved: %s', ME.message), 'error');
                UIKit.alert(app.UIFig, sprintf('The session could not be saved:\n%s', ME.message), ...
                    'Save session', 'error');
                return;
            end
            Session.remember(app, out, s.notes);
            [~, n, e] = fileparts(out);
            UIKit.setStatus(lbl, sprintf('Session saved to %s%s (%d input file(s) with MD5, settings and results).', ...
                n, e, numel(s.inputs)), 'success');
            ok = true;
        end

        %% openInApp - Read a session, check its inputs and restore it in app
        % interactive: ask for missing inputs and show warnings as alerts.
        % Without it (scripts / CI) missing inputs make ok false and all
        % messages go to the status bar. Changed inputs are used, with a
        % warning.
        function [ok, msg] = openInApp(app, p, interactive)
            if nargin < 3, interactive = false; end
            ok = false; msg = {};
            lbl = Session.statusLabel(app);
            try
                s = Session.load(p);
            catch ME
                Session.fail(app, lbl, sprintf('Could not open the session: %s', ME.message), interactive);
                return;
            end
            if ~strcmp(s.app, class(app))
                Session.fail(app, lbl, sprintf(['This session was saved by %s, not by this window. ' ...
                    'Open it in that window.'], s.app), interactive);
                return;
            end
            UIKit.setStatus(lbl, 'Checking the session''s input files (MD5)...', 'busy');
            [s, st, msg] = Session.resolveInputs(s, p, interactive, app.UIFig);
            missing = strcmp({st.status}, 'missing');
            if any(missing)
                Session.fail(app, lbl, sprintf('Session not opened: %s', strjoin({st(missing).message}, '; ')), ...
                    interactive);
                return;
            end
            try
                ok = logical(app.restoreSession(s));
            catch ME
                ok = false;
                Session.fail(app, lbl, sprintf('The session could not be restored: %s', ME.message), interactive);
                return;
            end
            if ~ok
                Session.fail(app, lbl, 'The session could not be restored (see the previous message).', interactive);
                return;
            end
            Session.remember(app, p, s.notes);
            [~, n, e] = fileparts(p);
            txt = sprintf('Session %s%s opened (saved %s with NeuroAnalyzer v%s).', n, e, s.created, s.toolboxVersion);
            if ~isempty(s.notes)
                txt = sprintf('%s Notes: %s', txt, strrep(s.notes, newline, ' / '));
            end
            if isempty(msg)
                UIKit.setStatus(lbl, txt, 'success');
            else
                UIKit.setStatus(lbl, sprintf('%s Warning: %s', txt, strjoin(msg, '; ')), 'warning');
                if interactive
                    UIKit.alert(app.UIFig, sprintf('The session was opened, but:\n%s', strjoin(msg, newline)), ...
                        'Open session', 'warning');
                end
            end
        end

        %% md5 - MD5 (lower-case hex) of a file or folder
        % engine: 'auto' (default: Java, else system tool, else MATLAB),
        % 'java', 'system' or 'matlab' (pure MATLAB, for tests / no JVM).
        function h = md5(p, engine)
            if nargin < 2 || isempty(engine), engine = 'auto'; end
            p = char(p);
            if isfolder(p)
                files = Session.listFiles(p);
                lines = cell(1, numel(files));
                for k = 1:numel(files)
                    lines{k} = sprintf('%s  %s\n', Session.md5(fullfile(p, files{k}), engine), ...
                        strrep(files{k}, '\', '/'));
                end
                h = Session.md5Bytes(unicode2native([lines{:}], 'UTF-8'), engine);
                return;
            end
            if ~exist(p, 'file')
                error('NeuroAnalyzer:Session:md5', 'File not found: %s', p);
            end
            switch lower(engine)
                case 'java',   h = Session.md5Java(p);
                case 'system', h = Session.md5System(p);
                case 'matlab', h = Session.md5Matlab(p);
                otherwise
                    h = '';
                    if usejava('jvm')
                        try, h = Session.md5Java(p); catch, h = ''; end
                    end
                    if isempty(h)
                        try, h = Session.md5System(p); catch, h = ''; end
                    end
                    if isempty(h), h = Session.md5Matlab(p); end
            end
        end

        %% md5Bytes - MD5 (hex) of a uint8 vector
        function h = md5Bytes(bytes, engine)
            if nargin < 2 || isempty(engine), engine = 'auto'; end
            bytes = uint8(bytes(:));
            if ~strcmpi(engine, 'matlab') && usejava('jvm')
                try
                    md = java.security.MessageDigest.getInstance('MD5');
                    if ~isempty(bytes), md.update(typecast(bytes, 'int8')); end
                    h = Session.hexDigest(md.digest());
                    return;
                catch
                end
            end
            st = Session.md5Init();
            st = Session.md5Update(st, bytes);
            h = Session.md5Final(st);
        end

        %% describe - "name = value" text lines of a (nested) value, for reports
        % Scalars, short vectors, text and short cellstrs are written out;
        % larger arrays as "[rows x cols class]".
        function lines = describe(v, prefix, depth)
            if nargin < 2, prefix = ''; end
            if nargin < 3, depth = 0; end
            lines = {};
            if isstruct(v) && depth < 4 && numel(v) <= 6
                if numel(v) == 1
                    f = fieldnames(v);
                    if isempty(f)
                        if isempty(prefix), lines = {'(none)'}; else, lines = {sprintf('%s = (none)', prefix)}; end
                    end
                    for k = 1:numel(f)
                        lines = [lines, Session.describe(v.(f{k}), Session.join(prefix, f{k}), depth + 1)]; %#ok<AGROW>
                    end
                else
                    for i = 1:numel(v)
                        lines = [lines, Session.describe(v(i), sprintf('%s(%d)', prefix, i), depth + 1)]; %#ok<AGROW>
                    end
                end
                return;
            end
            lines = {sprintf('%s = %s', prefix, Session.valueText(v))};
        end

        %% valueText - Short text for one value
        function t = valueText(v)
            if isstring(v), v = char(v); end
            if ischar(v)
                if isempty(v)
                    t = '''''';
                elseif size(v, 1) == 1
                    t = v;
                    if numel(t) > 160, t = [t(1:157) '...']; end
                else
                    t = sprintf('[%s char]', Session.sizeText(v));
                end
            elseif (isnumeric(v) || islogical(v)) && numel(v) <= 12 && ismatrix(v)
                if isempty(v)
                    t = '[]';
                elseif islogical(v)
                    t = mat2str(v);
                else
                    t = mat2str(double(v), 6);
                end
            elseif iscell(v) && numel(v) <= 12 && all(cellfun(@(c) ischar(c) || (isstring(c) && isscalar(c)), v))
                t = ['{' strjoin(cellfun(@char, v(:)', 'UniformOutput', false), ', ') '}'];
            elseif isa(v, 'function_handle')
                t = func2str(v);
            else
                t = sprintf('[%s %s]', Session.sizeText(v), class(v));
            end
        end

        %% limitSize - Replace leaves larger than maxBytes by a text placeholder
        function v = limitSize(v, maxBytes)
            w = whos('v');
            if w.bytes <= maxBytes, return; end
            if isstruct(v)
                f = fieldnames(v);
                for i = 1:numel(v)
                    for k = 1:numel(f)
                        v(i).(f{k}) = Session.limitSize(v(i).(f{k}), maxBytes);
                    end
                end
            elseif iscell(v)
                for i = 1:numel(v)
                    v{i} = Session.limitSize(v{i}, maxBytes);
                end
            else
                v = sprintf('[not stored: %s %s, %.0f MB; re-computed when the session is opened]', ...
                    Session.sizeText(v), class(v), w.bytes / 1e6);
            end
        end

        %% lastNotes - Notes of the session last saved / opened in this window
        function n = lastNotes(app)
            n = '';
            try
                if isappdata(app.UIFig, 'NeuroAnalyzerSession')
                    d = getappdata(app.UIFig, 'NeuroAnalyzerSession');
                    n = d.notes;
                end
            catch
            end
        end

        %% lastPath - Session file last saved / opened in this window ('' if none)
        function p = lastPath(app)
            p = '';
            try
                if isappdata(app.UIFig, 'NeuroAnalyzerSession')
                    d = getappdata(app.UIFig, 'NeuroAnalyzerSession');
                    p = d.path;
                end
            catch
            end
        end

        %% statusLabel - The window's status bar label (StatusLabel or W.Status)
        function lbl = statusLabel(app)
            lbl = [];
            try
                if isprop(app, 'StatusLabel') && ~isempty(app.StatusLabel)
                    lbl = app.StatusLabel;
                elseif isprop(app, 'W') && isstruct(app.W) && isfield(app.W, 'Status')
                    lbl = app.W.Status;
                end
            catch
            end
        end

        %% isoNow - Current local date/time as ISO 8601 (with UTC offset when known)
        function t = isoNow()
            try
                d = datetime('now', 'TimeZone', 'local', 'Format', 'yyyy-MM-dd''T''HH:mm:ssxxx');
                t = char(d);
            catch
                t = datestr(now, 'yyyy-mm-ddTHH:MM:SS');
            end
        end
    end

    methods(Static, Access = private)

        %% emptyInputs - 0x0 input struct with the provenance fields
        function s = emptyInputs()
            s = struct('role', {}, 'path', {}, 'name', {}, 'isFolder', {}, 'bytes', {}, ...
                'modified', {}, 'md5', {});
        end

        %% exists - File or folder exists
        function tf = exists(p)
            tf = ~isempty(p) && (isfolder(p) || exist(p, 'file') == 2);
        end

        %% safeMD5 - MD5 or '' when it cannot be computed
        function h = safeMD5(p)
            try
                h = Session.md5(p);
            catch
                h = '';
            end
        end

        %% notesText - Notes as one char row (lines joined with newline)
        function n = notesText(notes)
            if isempty(notes)
                n = '';
            elseif iscell(notes) || isstring(notes)
                n = strjoin(cellstr(notes), newline);
            else
                n = char(notes);
                if size(n, 1) > 1, n = strjoin(cellstr(n), newline); end
            end
            n = strtrim(n);
        end

        %% remember - Store the last session path and notes in the window
        function remember(app, p, notes)
            try
                setappdata(app.UIFig, 'NeuroAnalyzerSession', struct('path', char(p), 'notes', notes));
            catch
            end
        end

        %% fail - Error status, plus an alert when interactive
        function fail(app, lbl, msg, interactive)
            UIKit.setStatus(lbl, msg, 'error');
            if interactive
                UIKit.alert(app.UIFig, msg, 'Open session', 'error');
            end
        end

        %% askLocation - Ask the user where a missing input is now ('' if cancelled)
        function p = askLocation(in, fig)
            p = '';
            prompt = sprintf('Locate %s (%s)', in.name, in.role);
            try
                if in.isFolder
                    q = uigetdir(pwd, prompt);
                    if ~isequal(q, 0), p = q; end
                else
                    [~, ~, e] = fileparts(in.name);
                    if isempty(e), e = '.*'; end
                    [f, d] = uigetfile({['*' e], sprintf('%s (*%s)', in.name, e); '*.*', 'All files'}, prompt);
                    if ~isequal(f, 0), p = fullfile(d, f); end
                end
            catch
            end
            if ~isempty(fig)
                try, figure(fig); catch, end
            end
        end

        %% listFiles - Relative paths of every file under folder (sorted)
        function files = listFiles(folder)
            files = Session.listFilesRel(folder, '');
            files = sort(files);
        end

        function files = listFilesRel(folder, rel)
            files = {};
            d = dir(fullfile(folder, rel));
            for k = 1:numel(d)
                if any(strcmp(d(k).name, {'.', '..'})), continue; end
                r = d(k).name;
                if ~isempty(rel), r = [rel '/' d(k).name]; end
                if d(k).isdir
                    files = [files, Session.listFilesRel(folder, r)]; %#ok<AGROW>
                else
                    files{end+1} = r; %#ok<AGROW>
                end
            end
        end

        %% md5Java - java.security.MessageDigest over ChunkBytes chunks
        function h = md5Java(p)
            md = java.security.MessageDigest.getInstance('MD5');
            fid = fopen(p, 'r');
            if fid < 0
                error('NeuroAnalyzer:Session:md5', 'Cannot open %s', p);
            end
            c = onCleanup(@() fclose(fid));
            while true
                buf = fread(fid, Session.ChunkBytes, '*uint8');
                if isempty(buf), break; end
                md.update(typecast(buf, 'int8'));
            end
            h = Session.hexDigest(md.digest());
        end

        %% md5System - md5sum (Linux), md5 -q (macOS) or certutil (Windows)
        function h = md5System(p)
            h = '';
            q = ['"' p '"'];
            if ispc
                [st, out] = system(['certutil -hashfile ' q ' MD5']);
            elseif ismac
                [st, out] = system(['md5 -q ' q]);
            else
                [st, out] = system(['md5sum ' q]);
            end
            if st == 0
                tok = regexp(out, '(?<![0-9a-fA-F])[0-9a-fA-F]{32}(?![0-9a-fA-F])', 'match', 'once');
                if isempty(tok)
                    % certutil may print the hash as spaced byte pairs
                    tok = regexprep(regexp(out, '([0-9a-fA-F]{2} ){15}[0-9a-fA-F]{2}', 'match', 'once'), ' ', '');
                end
                h = lower(tok);
            end
            if isempty(h)
                error('NeuroAnalyzer:Session:md5', 'No system MD5 tool available.');
            end
        end

        %% md5Matlab - Pure-MATLAB MD5 of a file, streamed in chunks
        function h = md5Matlab(p)
            fid = fopen(p, 'r');
            if fid < 0
                error('NeuroAnalyzer:Session:md5', 'Cannot open %s', p);
            end
            c = onCleanup(@() fclose(fid));
            st = Session.md5Init();
            while true
                buf = fread(fid, Session.ChunkBytes, '*uint8');
                if isempty(buf), break; end
                st = Session.md5Update(st, buf);
            end
            h = Session.md5Final(st);
        end

        %% hexDigest - int8 Java digest -> lower-case hex text
        function h = hexDigest(d)
            b = typecast(int8(d(:)), 'uint8');
            h = lower(reshape(dec2hex(b, 2)', 1, []));
        end

        % ---- Pure-MATLAB MD5 (RFC 1321) on doubles holding 32-bit words ----
        function st = md5Init()
            st.abcd = [1732584193, 4023233417, 2562383102, 271733878];
            st.buf = zeros(0, 1, 'uint8');
            st.len = 0;
        end

        function st = md5Update(st, bytes)
            bytes = uint8(bytes(:));
            st.len = st.len + numel(bytes);
            data = [st.buf; bytes];
            nBlocks = floor(numel(data) / 64);
            for b = 1:nBlocks
                st.abcd = Session.md5Block(st.abcd, data((b - 1) * 64 + (1:64)));
            end
            st.buf = data(nBlocks * 64 + 1:end);
        end

        function h = md5Final(st)
            bitLen = st.len * 8;
            nPad = mod(55 - numel(st.buf), 64);
            lenBytes = zeros(8, 1);
            for i = 1:8
                lenBytes(i) = mod(floor(bitLen / 256^(i - 1)), 256);
            end
            tail = [st.buf; uint8(128); zeros(nPad, 1, 'uint8'); uint8(lenBytes)];
            abcd = st.abcd;
            for b = 1:numel(tail) / 64
                abcd = Session.md5Block(abcd, tail((b - 1) * 64 + (1:64)));
            end
            out = zeros(1, 16);
            for w = 1:4
                for i = 1:4
                    out((w - 1) * 4 + i) = mod(floor(abcd(w) / 256^(i - 1)), 256);
                end
            end
            h = lower(reshape(dec2hex(out, 2)', 1, []));
        end

        function abcd = md5Block(abcd, block)
            persistent K S
            if isempty(K)
                K = floor(abs(sin(1:64)) * 2^32);
                S = [repmat([7 12 17 22], 1, 4), repmat([5 9 14 20], 1, 4), ...
                     repmat([4 11 16 23], 1, 4), repmat([6 10 15 21], 1, 4)];
            end
            x = double(block(:));
            M = x(1:4:end) + x(2:4:end) * 256 + x(3:4:end) * 65536 + x(4:4:end) * 16777216;
            full = 4294967295;
            A = abcd(1); B = abcd(2); C = abcd(3); D = abcd(4);
            for i = 0:63
                if i < 16
                    F = bitor(bitand(B, C), bitand(full - B, D)); g = i;
                elseif i < 32
                    F = bitor(bitand(D, B), bitand(full - D, C)); g = mod(5 * i + 1, 16);
                elseif i < 48
                    F = bitxor(bitxor(B, C), D); g = mod(3 * i + 5, 16);
                else
                    F = bitxor(C, bitor(B, full - D)); g = mod(7 * i, 16);
                end
                F = mod(F + A + K(i + 1) + M(g + 1), 4294967296);
                A = D; D = C; C = B;
                s = S(i + 1);
                B = mod(B + mod(F, 2^(32 - s)) * 2^s + floor(F / 2^(32 - s)), 4294967296);
            end
            abcd = mod(abcd + [A B C D], 4294967296);
        end

        %% osText - Operating system description
        function t = osText()
            if ispc
                t = 'Windows';
            elseif ismac
                t = 'macOS';
            else
                t = 'Linux/Unix';
            end
            try
                t = sprintf('%s %s', char(java.lang.System.getProperty('os.name')), ...
                    char(java.lang.System.getProperty('os.version')));
            catch
            end
            t = sprintf('%s (%s)', t, computer);
        end

        function s = sizeText(v)
            s = strjoin(arrayfun(@num2str, size(v), 'UniformOutput', false), 'x');
        end

        function p = join(prefix, name)
            if isempty(prefix), p = name; else, p = [prefix '.' name]; end
        end
    end
end
