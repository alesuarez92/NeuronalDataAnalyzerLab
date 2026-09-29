%% MainTest.m
% =========================================================================
% THE LAUNCHER: LAYOUT AT THREE WINDOW SIZES AND EVERY BUTTON
% =========================================================================
% Opens Main and checks the tiles against Techniques.list (order, family
% headings, cover), re-flows it to 2 columns (720 x 640 px, screenshot
% test-artifacts/screens/Main_small.png for review) and 1 column (560 px,
% cover hidden) and back. Then presses every button through its
% ButtonPushedFcn, as a click does: each step button opens its step's
% window, each ? and the header Help open Help on the right topic. The
% body has only the Analyses area (no Learn area).
% "Open a session..." asks for a file with a dialog, so its work is
% tested through openSessionFile(p): a session saved by Extract LDF opens
% in Extract LDF, a session of an unknown window is refused.
% AppSmokeTest keeps the default-size screenshot Main.png. Skipped when no
% display is available.
% =========================================================================

function tests = MainTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    addpath(fullfile(root, 'core', 'io'));
    addpath(fullfile(root, 'core', 'demo'));
    tests.TestData.outDir = fullfile(root, 'test-artifacts', 'screens');
    if ~exist(tests.TestData.outDir, 'dir'), mkdir(tests.TestData.outDir); end
    tests.TestData.work = tempname;
    mkdir(tests.TestData.work);
    % The launcher asks for project folders when none are set
    tests.TestData.hadImport = ispref('NeuroAnalyzer', 'ImportDir');
    if ~tests.TestData.hadImport
        ProjectManager.setBothDirs(tempdir);
    end
end

function teardownOnce(tests)
    if exist(tests.TestData.work, 'dir') == 7, rmdir(tests.TestData.work, 's'); end
    if ~tests.TestData.hadImport && ispref('NeuroAnalyzer', 'ImportDir')
        rmpref('NeuroAnalyzer', 'ImportDir');
        if ispref('NeuroAnalyzer', 'ExportDir'), rmpref('NeuroAnalyzer', 'ExportDir'); end
    end
end

function setup(tests)
    try
        f = uifigure('Visible', 'off'); delete(f); canDraw = true;
    catch
        canDraw = false;
    end
    tests.assumeTrue(canDraw, 'uifigure not available (no display)');
end

%% ------------------------------------------------------------- helpers

%% resizeTo - Set the launcher's size and re-flow it (as a drag of the window edge does)
function resizeTo(app, w, h)
    app.UIFig.Position(3:4) = [w h];
    drawnow;
    app.onResize();
    drawnow;
end

%% press - Click a button: run its ButtonPushedFcn
function press(b)
    fcn = b.ButtonPushedFcn;
    fcn(b, []);
    drawnow;
end

%% closeOpened - Close the window the launcher opened last
function closeOpened(app)
    w = app.LastOpened;
    if ~isempty(w) && isvalid(w) && isprop(w, 'UIFig') && ~isempty(w.UIFig) && isvalid(w.UIFig)
        delete(w.UIFig);
    end
end

%% headings - Family names shown over the tiles (upper case, as drawn)
function names = headings(app)
    F = Techniques.families();
    labels = findall(app.TileGrid, 'Type', 'uilabel');
    shown = {labels.Text};
    names = {};
    for i = 1:numel(F)
        if any(strcmp(shown, upper(F(i).name))), names{end+1} = F(i).name; end %#ok<AGROW>
    end
end

%% tilePlace - [row col] of the tile with id
function rc = tilePlace(app, id)
    p = app.Tiles(strcmp({app.Tiles.id}, id)).panel;
    rc = [p.Layout.Row, p.Layout.Column];
end

%% --------------------------------------------------------------- tests

function testLayoutFollowsTheWindowWidth(tests)
    app = Main(); c = onCleanup(@() delete(app.UIFig));
    T = Techniques.list();
    F = Techniques.families();
    tests.verifyEqual({app.Tiles.id}, {T.id}, 'one tile per row of Techniques.list, in order');

    % Default width: 3 columns, every family heading, the cover shown
    resizeTo(app, Main.DefaultSize(1), 900);
    tests.verifyEqual(app.Columns, 3);
    tests.verifyEqual(numel(app.TileGrid.ColumnWidth), 3);
    tests.verifyEqual(headings(app), {F.name}, 'five family headings');
    tests.verifyEqual(tilePlace(app, 'ldf'), [2 1], 'Blood flow first');
    tests.verifyEqual(tilePlace(app, 'lfp'), [2 2], 'Electrophysiology next to it');
    tests.verifyEqual(tilePlace(app, 'eeg'), [4 1], 'EEG on the next row');
    tests.verifyEqual(tilePlace(app, 'sessions'), [6 3], 'Across techniques last');
    if ~isempty(app.CoverImage)
        tests.verifyEqual(char(app.CoverImage.Visible), 'on', 'cover art shown at the default width');
    end

    % 720 x 640: 2 columns, EEG fills the gap next to Blood flow
    resizeTo(app, 720, 640);
    tests.verifyEqual(app.Columns, 2);
    tests.verifyEqual(tilePlace(app, 'ldf'), [2 1]);
    tests.verifyEqual(tilePlace(app, 'eeg'), [2 2]);
    tests.verifyEqual(tilePlace(app, 'lfp'), [4 1]);
    tests.verifyEqual(headings(app), {F.name}, 'every family keeps its heading');
    pause(0.5);
    try
        exportapp(app.UIFig, fullfile(tests.TestData.outDir, 'Main_small.png'));
    catch ME
        warning('MainTest:capture', 'Main_small: %s', ME.message);
    end

    % 560 wide: 1 column, no cover art (no room next to the title)
    resizeTo(app, 560, 640);
    tests.verifyEqual(app.Columns, 1);
    cols = arrayfun(@(t) t.panel.Layout.Column, app.Tiles);
    rows = arrayfun(@(t) t.panel.Layout.Row, app.Tiles);
    tests.verifyTrue(all(cols == 1), 'one column');
    tests.verifyTrue(issorted(rows) && numel(unique(rows)) == numel(rows), 'tiles one under the other, in order');
    if ~isempty(app.CoverImage)
        tests.verifyEqual(char(app.CoverImage.Visible), 'off', 'cover art hidden when narrow');
    end

    % Back to the default: 3 columns again
    resizeTo(app, Main.DefaultSize(1), 900);
    tests.verifyEqual(app.Columns, 3);
    tests.verifyEqual(tilePlace(app, 'eeg'), [4 1]);
    tests.verifyEqual(headings(app), {F.name});
end

function testEveryStepButtonOpensItsWindow(tests)
    app = Main(); c = onCleanup(@() delete(app.UIFig));
    T = Techniques.list();
    for i = 1:numel(T)
        tile = app.Tiles(strcmp({app.Tiles.id}, T(i).id));
        tests.verifyEqual(numel(tile.steps), numel(T(i).steps), T(i).id);
        for k = 1:numel(T(i).steps)
            s = T(i).steps(k);
            where = sprintf('%s step %d (%s)', T(i).id, k, s.label);
            tests.verifyTrue(contains(tile.steps(k).Text, s.label), [where ': button text']);
            tests.verifyEqual(char(tile.steps(k).Tooltip), s.tooltip, [where ': tooltip']);
            if strcmp(s.action, 'session')
                continue;   % asks for a file with a dialog: see testOpenSessionFile
            end
            press(tile.steps(k));
            tests.verifyTrue(isa(app.LastOpened, s.window), sprintf('%s: opened %s', where, class(app.LastOpened)));
            tests.verifyTrue(startsWith(app.StatusLabel.Text, char(10003)), [where ': ' app.StatusLabel.Text]);
            closeOpened(app);
        end
    end
end

function testEveryHelpButtonOpensItsTopic(tests)
    app = Main(); c = onCleanup(@() delete(app.UIFig));
    T = Techniques.list();
    for i = 1:numel(T)
        tile = app.Tiles(strcmp({app.Tiles.id}, T(i).id));
        press(tile.help);
        tests.verifyTrue(isa(app.LastOpened, 'HelpApp'), [T(i).id ': ? opens Help']);
        if isa(app.LastOpened, 'HelpApp')
            tests.verifyEqual(app.LastOpened.TopicList.Value, T(i).help, [T(i).id ': Help topic']);
        end
        closeOpened(app);
    end
    press(app.HelpBtn);
    tests.verifyTrue(isa(app.LastOpened, 'HelpApp'), 'header ? Help');
    if isa(app.LastOpened, 'HelpApp')
        tests.verifyEqual(app.LastOpened.TopicList.Value, 'Welcome');
    end
    closeOpened(app);
end

function testOnlyTheAnalysesArea(tests)
    % No Learn area: Help and demo data are reached through ? Help
    app = Main(); c = onCleanup(@() delete(app.UIFig));
    tests.verifyFalse(isprop(app, 'LearnButtons'), 'no Learn buttons');
    tests.verifyEqual(numel(app.BodyGrid.RowHeight), 2, 'body: Analyses heading and tiles');
    labels = findall(app.BodyGrid, 'Type', 'uilabel');
    texts = {labels.Text};
    tests.verifyFalse(any(strcmp(texts, 'LEARN')), 'no LEARN heading');
    tests.verifyTrue(any(strcmp(texts, 'ANALYSES')), 'ANALYSES heading');
    tests.verifyTrue(any(contains(texts, 'Try it with demo data')), 'the heading points to demo data in ? Help');
end

function testOpenSessionFile(tests)
    % A session saved by Extract LDF opens in Extract LDF
    a = ExtractLDFApp(); ca = onCleanup(@() delete(a.UIFig));
    a.loadDemo();
    a.processData();
    p = fullfile(tests.TestData.work, ['launcher' Session.Extension]);
    tests.verifyTrue(logical(a.saveSessionTo(p)));

    app = Main(); c = onCleanup(@() delete(app.UIFig));
    win = app.openSessionFile(p);
    tests.verifyTrue(isa(win, 'ExtractLDFApp'), 'opened in the window that saved it');
    if isa(win, 'ExtractLDFApp')
        tests.verifyEqual(win.CropRange, a.CropRange, 'with its crop');
        delete(win.UIFig);
    end
    tests.verifyTrue(contains(app.StatusLabel.Text, 'Opened the session'), app.StatusLabel.Text);

    % A session of a window this version does not have is refused
    s = Session.load(p);
    s.app = 'NoSuchApp';
    q = Session.save(fullfile(tests.TestData.work, ['unknown' Session.Extension]), s);
    win = app.openSessionFile(q);
    tests.verifyEmpty(win);
    tests.verifyEmpty(app.LastOpened);
    tests.verifyTrue(contains(app.StatusLabel.Text, 'No window opens sessions of NoSuchApp'), app.StatusLabel.Text);
end
