%% TechniquesTest.m
% =========================================================================
% THE TABLE OF TECHNIQUES AND THE LAUNCHER LAYOUT RULES (NO DISPLAY)
% =========================================================================
% core/Techniques.m builds the launcher, Help's demo windows and website
% links, so every row must point to things that exist: window classes (with
% a loadDemo and, for analyses, openSession), Help topics and well-formed
% website page names (the website itself is not part of this repository).
% Also checks the launcher's tile packing (Main.pack), column
% rule (Main.columnsFor) and cover crop (Main.coverCrop), which need no
% window.
% =========================================================================

function tests = TechniquesTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'apps'));
    addpath(fullfile(root, 'core'));
    tests.TestData.root = root;
end

function testEveryWindowClassExists(tests)
    c = Techniques.windows();
    tests.verifyGreaterThanOrEqual(numel(c), 11);   % 11 windows since Course, Virtual lab and the Help card left the launcher
    for k = 1:numel(c)
        mc = meta.class.fromName(c{k});
        tests.verifyNotEmpty(mc, sprintf('window class %s does not exist', c{k}));
    end
end

function testRowsAreComplete(tests)
    T = Techniques.list();
    F = Techniques.families();
    tests.verifyEqual(numel(unique({T.id})), numel(T), 'tile ids are unique');
    tests.verifyEqual(numel(unique({F.id})), numel(F), 'family ids are unique');
    topics = {HelpApp.topicData().title};
    for i = 1:numel(T)
        t = T(i);
        tests.verifyTrue(any(strcmp({F.id}, t.family)), sprintf('%s: unknown family %s', t.id, t.family));
        tests.verifyNotEmpty(t.name); tests.verifyNotEmpty(t.short);
        tests.verifyNotEmpty(t.description); tests.verifyNotEmpty(t.io);
        tests.verifyTrue(any(strcmp(topics, t.help)), sprintf('%s: no Help topic "%s"', t.id, t.help));
        tests.verifyNotEmpty(t.steps, sprintf('%s: no steps', t.id));
        for k = 1:numel(t.steps)
            s = t.steps(k);
            where = sprintf('%s step %d', t.id, k);
            tests.verifyNotEmpty(s.label, where);
            tests.verifyNotEmpty(s.tooltip, where);
            tests.verifyTrue(any(strcmp(topics, s.help)), sprintf('%s: no Help topic "%s"', where, s.help));
            if isempty(s.window)
                tests.verifyEqual(s.action, 'session', [where ': no window and no action']);
            else
                m = methods(s.window);
                tests.verifyTrue(any(strcmp(m, 'loadDemo')), [where ': ' s.window ' has no loadDemo']);
            end
        end
    end
    % Families in the order of their first tile, every family used
    [~, first] = unique({T.family}, 'first');
    tests.verifyEqual({T(sort(first)).family}, {F.id}, 'tiles are listed family by family, in family order');
    L = Techniques.learn();
    tests.verifyEqual({L.id}, {'course', 'lab'});
    tests.verifyEqual([L.available], [false false], 'Course and Virtual lab: coming soon');
    for i = 1:numel(L)
        tests.verifyTrue(any(strcmp(topics, L(i).help)), sprintf('learn %s: no Help topic', L(i).id));
    end
end

function testSessionsOpenInEveryAnalysisWindow(tests)
    % Every window that saves sessions is in the table, so the launcher's
    % "Open a session..." can reopen any session
    root = tests.TestData.root;
    files = dir(fullfile(root, 'apps', '*App.m'));
    c = Techniques.windows();
    for k = 1:numel(files)
        cls = erase(files(k).name, '.m');
        if any(strcmp(methods(cls), 'openSession'))
            tests.verifyTrue(any(strcmp(c, cls)), sprintf('%s opens sessions but is not in Techniques', cls));
        end
    end
end

function testWebsitePageNamesAreWellFormed(tests)
    % 'page' or 'page#anchor', lower case, no .html: HelpApp.websitePage
    % builds the link to the online page from it
    T = Techniques.list();
    L = Techniques.learn();
    for w = [{T.web}, {L.web}]
        if isempty(w{1}), continue; end   % no website page
        tests.verifyNotEmpty(regexp(w{1}, '^[a-z0-9-]+(#[a-z0-9-]+)?$', 'once'), ...
            sprintf('website page name "%s" is not page or page#anchor', w{1}));
    end
end

function testHelpMapsComeFromTheTable(tests)
    T = Techniques.list();
    for i = 1:numel(T)
        for k = 1:numel(T(i).steps)
            s = T(i).steps(k);
            if isempty(s.window), continue; end
            tests.verifyEqual(HelpApp.demoWindow(s.help), Techniques.windowForTopic(s.help));
            tests.verifyTrue(endsWith(HelpApp.websitePage(s.help), ['/' T(i).web]) || ...
                ~isempty(Techniques.pageForTopic(s.help)), s.help);
        end
    end
    tests.verifyEqual(HelpApp.demoWindow('LDF Extract'), 'ExtractLDFApp');
    tests.verifyEqual(HelpApp.demoWindow('Ephys Extract'), 'ExtractEphysApp');
    tests.verifyEqual(HelpApp.demoWindow('EEG Analysis'), 'EEGAnalysisApp');
    tests.verifyEqual(HelpApp.demoWindow('Filtering'), 'ProcessingLDFApp');
    tests.verifyEqual(HelpApp.demoWindow('Welcome'), '');
    tests.verifyEqual(HelpApp.demoWindow('Sessions and reports'), '');
    tests.verifyEqual(HelpApp.websitePage('Welcome'), [HelpApp.WebsiteURL '/']);
    tests.verifyEqual(HelpApp.websitePage('EEG Analysis'), [HelpApp.WebsiteURL '/eeg']);
    tests.verifyEqual(HelpApp.websitePage('Histology'), [HelpApp.WebsiteURL '/imaging#histology']);
    tests.verifyEqual(HelpApp.websitePage('Filtering'), [HelpApp.WebsiteURL '/ldf']);
    tests.verifyEqual(HelpApp.websitePage('Sessions and reports'), [HelpApp.WebsiteURL '/sessions']);
end

function testDemoChoices(tests)
    [labels, classes] = Techniques.demoChoices();
    tests.verifyEqual(numel(unique(classes)), numel(classes), 'one entry per window');
    tests.verifyEqual(numel(labels), numel(classes));
    tests.verifyEqual(labels(1:4), {'Extract LDF', 'Process LDF', 'Average LDF', 'Extract LFP / MUA'});
    tests.verifyTrue(any(strcmp(labels, 'EEG analysis')));
    tests.verifyEqual(Techniques.windowName('HistologyApp'), 'Histology / culture');
    tests.verifyEqual(Techniques.windowName('NoSuchApp'), 'NoSuchApp');
end

function testPackKeepsFamiliesTogether(tests)
    F = Techniques.families();
    T = Techniques.list();
    counts = cellfun(@(f) sum(strcmp({T.family}, f)), {F.id});
    for n = 1:3
        B = Main.pack(counts, n);
        % Every tile once, inside n columns, no two blocks on the same cells
        tests.verifyEqual(sum([B.count]), numel(T), sprintf('n = %d: every tile placed once', n));
        tests.verifyTrue(all([B.col] >= 1 & [B.col] + [B.count] - 1 <= n), sprintf('n = %d: inside the grid', n));
        cells = zeros(max([B.row]), n);
        for b = B
            cells(b.row, b.col:b.col + b.count - 1) = cells(b.row, b.col:b.col + b.count - 1) + 1;
        end
        tests.verifyLessThanOrEqual(max(cells(:)), 1, sprintf('n = %d: no overlap', n));
        % The chunks of a family come in order, the first one has the heading
        for f = 1:numel(counts)
            Bf = B([B.family] == f);
            tests.verifyEqual([Bf.first], sort([Bf.first]));
            tests.verifyTrue(issorted([Bf.row]));
            tests.verifyEqual([Bf.head], [Bf.first] == 1);
        end
    end
    % Default width: Blood flow + Electrophysiology | EEG + Imaging | Across techniques
    B = Main.pack(counts, 3);
    tests.verifyEqual([B.row], [1 1 2 2 3]);
    tests.verifyEqual([B.col], [1 2 1 2 1]);
    % Two columns: EEG fills the gap next to Blood flow
    B = Main.pack(counts, 2);
    tests.verifyEqual(B([B.family] == 3).row, 1);
end

function testColumnsForWidth(tests)
    tests.verifyEqual(Main.columnsFor(Main.DefaultSize(1)), 3);
    tests.verifyEqual(Main.columnsFor(1000), 3);
    tests.verifyEqual(Main.columnsFor(720), 2);
    tests.verifyEqual(Main.columnsFor(560), 1);
end

function testCoverCrop(tests)
    art = uint8(randi(255, 300, 2400, 3));
    bg = UITheme.headerBg;
    img = Main.coverCrop(art, 500, 116, bg);
    tests.verifyEqual(size(img), [300 round(500 * 300 / 116) 3]);
    tests.verifyEqual(img(:, 1:100, :), art(:, 1:100, :), 'the left part is the art');
    tests.verifyEqual(double(squeeze(img(1, end, :)))', round(255 * bg), 'AbsTol', 1, 'the right edge meets the header');
    wide = Main.coverCrop(art, 1500, 116, bg);
    tests.verifyEqual(size(wide, 2), round(1500 * 300 / 116), 'wider than the art: padded');
    root = tests.TestData.root;
    tests.verifyTrue(exist(fullfile(root, 'core', 'icons', 'cover.png'), 'file') == 2, 'core/icons/cover.png');
end
