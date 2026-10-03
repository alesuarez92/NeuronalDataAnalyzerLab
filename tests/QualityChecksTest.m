%% QualityChecksTest.m
% =========================================================================
% UNIT TESTS: ONE FORMAT FOR THE QUALITY CHECKS OF EVERY WINDOW
% =========================================================================
% core/QualityChecks.m and where its rows go:
%   * rows (level, topic, found, why, action): add, count, summary, brief,
%     text, detail, table data; an unknown level is an error;
%   * the old formats: 'OK: / Check: / Warning: ...' lines and Histology's
%     K x 3 {level, topic, text} cells, both ways;
%   * Histology.checks and LaserSpeckle.checks give the same checks as rows
%     and in their old format (R.checks keeps its lines);
%   * a session holds the window's checks (plus a summary line), the
%     report lists them most serious first, the methods text names them.
% Base MATLAB only: also runs in GNU Octave (with a RandStream shim).
% =========================================================================

function tests = QualityChecksTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'imaging'));
    addpath(fullfile(root, 'core', 'io'));
    addpath(fullfile(root, 'core', 'demo'));
end

%% sample - Four rows, one of each level
function Q = sample()
    Q = QualityChecks.none();
    Q = QualityChecks.add(Q, 'ok', 'Pixel size', '0.5 um per pixel, read from the file.');
    Q = QualityChecks.add(Q, 'check', 'Alignment', 'The images are not aligned.', ...
        'Fine when you only need a count per whole image.', 'Align them in step 2.');
    Q = QualityChecks.add(Q, 'note', 'Flow index', 'Flow index = 1/K2.');
    Q = QualityChecks.add(Q, 'warning', 'Threshold', 'The threshold is below the noise floor.', ...
        'Background noise will be counted as cells.', 'Raise the threshold.');
end

function testRowsCountsAndSummary(tests)
    Q = QualityChecks.none();
    tests.verifySize(Q, [0 1]);
    tests.verifyEqual(QualityChecks.summary(Q), 'no checks');
    tests.verifyEqual(QualityChecks.brief(Q), '');
    Q = sample();
    tests.verifySize(Q, [4 1]);
    tests.verifyEqual(QualityChecks.count(Q, 'ok'), 1);
    tests.verifyEqual(QualityChecks.count(Q, 'warning'), 1);
    tests.verifyEqual(QualityChecks.count([], 'warning'), 0);
    tests.verifyEqual(QualityChecks.summary(Q), '1 OK, 1 to check, 1 warning, 1 note');
    tests.verifyEqual(QualityChecks.summary(Q(1:2)), '1 OK, 1 to check, no warnings');
    % brief: the warnings first, else the rows to check, else OK
    tests.verifyEqual(QualityChecks.brief(Q), '1 warning: Threshold: The threshold is below the noise floor.');
    tests.verifyEqual(QualityChecks.brief(Q(1:3)), '1 to check: Alignment: The images are not aligned.');
    tests.verifyEqual(QualityChecks.brief(Q([1 3])), 'OK');
    tests.verifyError(@() QualityChecks.add(Q, 'fine', 'x', 'y'), 'NeuroAnalyzer:QualityChecks:level');
end

function testTextDetailAndTable(tests)
    Q = sample();
    tests.verifyEqual(QualityChecks.text(Q(2)), ['The images are not aligned. Fine when you only need a ' ...
        'count per whole image. Align them in step 2.']);
    tests.verifyEqual(QualityChecks.text(Q(1)), '0.5 um per pixel, read from the file.');
    d = QualityChecks.detail(Q(2));
    tests.verifyEqual(d, {'Check: Alignment', 'The images are not aligned.', ...
        'Why it matters: Fine when you only need a count per whole image.', 'What to try: Align them in step 2.'});
    tests.verifyNumElements(QualityChecks.detail(Q(1)), 2, 'no empty parts');
    D = QualityChecks.tableData(Q);
    tests.verifyEqual(D(:, 1)', {'OK', 'Check', 'Note', 'Warning'});
    tests.verifyEqual(D{4, 2}, 'Threshold');
    tests.verifyEqual(D{4, 3}, 'The threshold is below the noise floor.');
    tests.verifySize(QualityChecks.tableData(QualityChecks.none()), [0 3]);
end

function testLinesAndReport(tests)
    Q = sample();
    L = QualityChecks.lines(Q);
    tests.verifyEqual(L{1}, 'OK: 0.5 um per pixel, read from the file.');
    tests.verifyTrue(strncmp(L{2}, 'Check: The images are not aligned. Fine', 39));
    tests.verifyEqual(L{3}, 'Flow index = 1/K2.', 'notes have no prefix');
    tests.verifyTrue(strncmp(L{4}, 'Warning: ', 9));
    R = QualityChecks.reportLines(Q);
    tests.verifyTrue(strncmp(R{1}, 'Warning - Threshold: ', 21), 'most serious first');
    tests.verifyTrue(strncmp(R{2}, 'Check - Alignment: ', 19));
    tests.verifyEqual(R{3}, 'Note - Flow index: Flow index = 1/K2.');
    tests.verifyEqual(R{4}, 'OK - Pixel size: 0.5 um per pixel, read from the file.');
    tests.verifyNotEmpty(strfind(R{1}, 'Raise the threshold.'), 'warnings in full');
end

function testOldFormats(tests)
    Q = sample();
    % Lines -> rows: the prefix gives the level, other lines are notes
    B = QualityChecks.fromLines(QualityChecks.lines(Q), 'Laser speckle');
    tests.verifyEqual({B.level}, {Q.level});
    tests.verifyEqual(unique({B.topic}), {'Laser speckle'});
    tests.verifyEqual(B(2).found, QualityChecks.text(Q(2)));
    B = QualityChecks.fromLines({'Warning: a', 'b'}, {'T1', 'T2'});
    tests.verifyEqual({B.level}, {'warning', 'note'});
    tests.verifyEqual({B.topic}, {'T1', 'T2'});
    % K x 3 cells -> rows and back
    C = QualityChecks.toCells(Q);
    tests.verifySize(C, [4 3]);
    tests.verifyEqual(C(:, 1)', {Q.level});
    tests.verifyEqual(C{2, 3}, QualityChecks.text(Q(2)));
    B = QualityChecks.fromCells(C);
    tests.verifyEqual(QualityChecks.toCells(B), C);
    % ensure: rows, cells, lines or []
    tests.verifyEqual(QualityChecks.ensure(Q), Q);
    tests.verifyEqual(QualityChecks.toCells(QualityChecks.ensure(C)), C);
    B = QualityChecks.ensure(QualityChecks.lines(Q));
    tests.verifyEqual({B.level}, {Q.level});
    tests.verifySize(QualityChecks.ensure([]), [0 1]);
end

function testHistologyChecksAsRows(tests)
    s = demoHistology();
    R = {Histology.countCells(double(s.images(:, :, 1, 1)), struct('MinAreaPx', 20))};
    ctx = struct('pixelSizeUm', 1, 'pixelSizeFromFile', false, 'nImages', 1, 'alignMethod', 'none', ...
        'shifts', zeros(1, 2), 'peak', 1, 'landmarkRms', NaN, 'channelShifts', [0 0; 2 1.5], 'hasRegions', false);
    [C, Q] = Histology.checks(R, {}, ctx);
    tests.verifyEqual(QualityChecks.toCells(Q), C, 'the K x 3 cells are the rows');
    tests.verifyEqual(Q(1).level, 'warning');
    tests.verifyEqual(Q(1).topic, 'Pixel size');
    tests.verifyNotEmpty(Q(1).why);
    tests.verifyNotEmpty(Q(1).action);
    k = find(strcmp({Q.topic}, 'Channels'));
    tests.verifyEqual({Q(k).level}, {'check'});
    tests.verifyTrue(any(strcmp({Q.topic}, 'Touching cells')));
end

function testLaserSpeckleChecksAsRows(tests)
    I = uint8(200 * ones(30, 30, 4));
    I(1:10, :, :) = 255;                                   % a third of the pixels saturated
    p = LaserSpeckle.defaults(); p.Fps = 10; p.Window = 3;
    R = LaserSpeckle.analyze(I, [], [], p);
    tests.verifyEqual(R.checks, QualityChecks.lines(R.checkRows), 'R.checks keeps its lines');
    Q = R.checkRows;
    tests.verifyEqual(Q(1).topic, 'Saturation');
    tests.verifyEqual(Q(1).level, 'warning');
    tests.verifyTrue(any(strcmp({Q.topic}, 'Contrast window')));
    tests.verifyEqual(Q(strcmp({Q.topic}, 'Dark level')).level, 'check');
    tests.verifyEqual(QualityChecks.count(Q, 'warning'), 2);
end

function testSessionReportAndMethods(tests)
    Q = sample();
    st = struct('settings', struct(), 'results', struct(), 'summary', {{'Result line'}}, 'checks', Q);
    app = struct('sessionState', @() st);
    s = Session.capture(app, 'notes');
    tests.verifyEqual(s.checks, Q);
    tests.verifyEqual(s.summary, {'Result line', 'Checks: 1 OK, 1 to check, 1 warning, 1 note'});
    % A window without checks: none in the session, no summary line
    st0 = rmfield(st, 'checks');
    s0 = Session.capture(struct('sessionState', @() st0), 'notes');
    tests.verifySize(s0.checks, [0 1]);
    tests.verifyEqual(s0.summary, {'Result line'});
    % Saved and loaded; an old session without checks loads with none
    f = [tempname Session.Extension];
    c = onCleanup(@() delete(f));
    Session.save(f, s);
    b = Session.load(f);
    tests.verifyEqual(b.checks, Q);
    session = rmfield(s, 'checks'); %#ok<NASGU>
    save(f, 'session');
    b = Session.load(f);
    tests.verifySize(b.checks, [0 1]);
    % Report: a CHECKS block, most serious first
    left = Report.lines(s);
    k = find(strncmp(left, 'CHECKS (', 8));
    tests.verifyNumElements(k, 1);
    tests.verifyEqual(left{k}, 'CHECKS (1 OK, 1 to check, 1 warning, 1 note)');
    tests.verifyTrue(strncmp(left{k + 1}, 'Warning - Threshold: ', 21));
    tests.verifyEmpty(find(strncmp(Report.lines(s0), 'CHECKS', 6), 1));
    % Methods text: what the checks reported, with the topics
    s.app = 'HistologyApp';
    tests.verifyEqual(MethodsWriter.checksSentence(s), ['The built-in quality checks reported 1 OK, ' ...
        '1 to check (Alignment) and 1 warning (Threshold).']);
    s.checks = Q([1 3]);
    tests.verifyEqual(MethodsWriter.checksSentence(s), ['The built-in quality checks reported 1 OK, ' ...
        'none to check and no warnings.']);
    tests.verifyEqual(MethodsWriter.checksSentence(s0), '');
end
