%% StatsChecksTest.m
% =========================================================================
% UNIT TESTS: STATISTICS QUALITY CHECKS (GROUPS & STATISTICS)
% =========================================================================
% GroupStats.shapiroWilk against SciPy (scipy.stats.shapiro, the same
% Royston algorithm) and GroupStats.checks on a comparison:
%   * sample size: Warning when every series is counted as a subject
%     (pseudoreplication) or a group has fewer than 3, a rank-based test
%     that cannot reach p < 0.05 with these n (Warning when it is the
%     result, Check otherwise), Check below 8 subjects;
%   * normality (Shapiro-Wilk on the paired differences, each group or the
%     repeated-measures residuals): Check, Warning when the rank-based test
%     disagrees, OK with a rank-based result; the outlying animal named;
%   * sphericity: Check when Mauchly's test rejects it, Warning when the
%     uncorrected p is reported but the correction changes the verdict, OK
%     with two conditions or the Friedman test;
%   * equal spread (ANOVA), robustness check, missing values;
%   * the group demo gives no warnings and no checks in any design; the
%     faults study (demoGroups Faults: 6 animals, animal 6 responds 3x,
%     the same Drug rise in every animal) fires sample size, normality and
%     sphericity;
%   * the texts for EEG Analysis: participants instead of animals, the
%     Measures tab instead of the Plot tab, its own missing-value advice.
% Base MATLAB only; also runs in GNU Octave.
% =========================================================================

function tests = StatsChecksTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'demo'));
end

%% row - The first row of a topic ([] when none)
function r = row(Q, topic)
    r = [];
    if isempty(Q), return; end
    k = find(strcmp({Q.topic}, topic), 1);
    if ~isempty(k), r = Q(k); end
end

%% expect - A row of this topic with this level whose finding has the text
function expect(tests, Q, topic, level, text)
    r = row(Q, topic);
    txt = strjoin(QualityChecks.lines(Q), newline);
    tests.verifyNotEmpty(r, sprintf('no %s row:\n%s', topic, txt));
    if isempty(r), return; end
    tests.verifyEqual(r.level, level, sprintf('%s: %s', topic, r.found));
    if nargin >= 5
        tests.verifyTrue(~isempty(strfind(r.found, text)), sprintf('%s: "%s" not in "%s"', topic, text, r.found)); %#ok<STREMP>
    end
end

%% faultsMatrix - The faults study's set amplitudes (6 animals x Control, Stimulated, Drug)
function A = faultsMatrix()
    c = [18 16 19 17 20 18]';
    A = [c, c + [12 11 13 12 12 40]', c + [6 7 5 6 7 6]'];
end

function testShapiroWilkMatchesScipy(tests)
    % x, W, p from scipy.stats.shapiro 1.x
    ref = {[1 2 4], 0.964286, 0.636887
           [3.1 1 7 2], 0.895638, 0.409717
           [1 2 3 4 10], 0.835788, 0.153613
           [148 154 158 160 161 162 166 170 182 195 236], 0.788815, 0.00670381
           [11 13 12 10 12 45], 0.569100, 0.00019091
           [2.1 2.2 2.2 5 5 5.3 5.1], 0.720712, 0.00621189
           0.1 * (1:30).^2, 0.901421, 0.00909979};
    for i = 1:size(ref, 1)
        r = GroupStats.shapiroWilk(ref{i, 1});
        tests.verifyEqual(r.W, ref{i, 2}, 'AbsTol', 1e-5, sprintf('W of set %d', i));
        tests.verifyEqual(r.p, ref{i, 3}, 'RelTol', 1e-4, sprintf('p of set %d', i));
        tests.verifyEqual(r.n, numel(ref{i, 1}));
    end
    r = GroupStats.shapiroWilk([1 NaN 2 Inf 4]);
    tests.verifyEqual(r.W, 0.964286, 'AbsTol', 1e-5, 'non-finite values ignored');
    tests.verifyTrue(isnan(GroupStats.shapiroWilk([1 2]).p), 'fewer than 3 values');
    tests.verifyTrue(isnan(GroupStats.shapiroWilk([5 5 5 5]).p), 'all values equal');
    tests.verifyEqual(GroupStats.shapiroWilk(5:5:50).W, GroupStats.shapiroWilk((5:5:50)').W, ...
        'AbsTol', 1e-12, 'rows and columns alike');
end

function testSampleSizeRules(tests)
    a = [10 12 11 13 9 12 11 10]'; b = a + [3 4 2 5 3 4 3 2]';
    Q = GroupStats.checks(GroupStats.compare({a, b}, {'A', 'B'}, 'paired'));
    expect(tests, Q, 'Sample size', 'ok', '8 subjects');
    Q = GroupStats.checks(GroupStats.compare({a(1:6), b(1:6)}, {'A', 'B'}, 'paired'));
    expect(tests, Q, 'Sample size', 'check', 'fewer than 8');
    % 5 pairs: the exact Wilcoxon test cannot go below p = 2/32
    Q = GroupStats.checks(GroupStats.compare({a(1:5), b(1:5)}, {'A', 'B'}, 'paired', 'nonparametric'));
    expect(tests, Q, 'Sample size', 'warning', '0.0625');
    Q = GroupStats.checks(GroupStats.compare({a(1:5), b(1:5)}, {'A', 'B'}, 'paired', 'parametric'));
    expect(tests, Q, 'Sample size', 'check', 'Wilcoxon');
    % 3 vs 3 unpaired: Mann-Whitney cannot go below 0.1
    Q = GroupStats.checks(GroupStats.compare({a(1:3), b(1:3)}, {'A', 'B'}, 'unpaired', 'nonparametric'));
    expect(tests, Q, 'Sample size', 'warning', '0.1');
    Q = GroupStats.checks(GroupStats.compare({a(1:2), b(1:4)}, {'A', 'B'}, 'unpaired'));
    expect(tests, Q, 'Sample size', 'warning', 'A 2');
    % Every series counted as a subject: pseudoreplication
    o = GroupStats.checkOptions(); o.subjectMode = 'series'; o.nFiles = [2 2];
    Q = GroupStats.checks(GroupStats.compare({a, b}, {'A', 'B'}, 'unpaired'), o);
    expect(tests, Q, 'Sample size', 'warning', 'from 4 files');
    tests.verifyTrue(~isempty(strfind(row(Q, 'Sample size').why, 'pseudoreplication'))); %#ok<STREMP>
end

function testNormalityRules(tests)
    a = [10 12 11 13 9 12 11 10 12 11]';
    d = [3 4 2 5 3 4 3 2 4 3]';
    Q = GroupStats.checks(GroupStats.compare({a, a + d}, {'A', 'B'}, 'paired'));
    expect(tests, Q, 'Normality', 'ok', 'does not reject');
    d(10) = 14;                                   % one animal responds far more
    res = GroupStats.compare({a, a + d}, {'A', 'B'}, 'paired');
    o = GroupStats.checkOptions(); o.labels = {arrayfun(@(i) sprintf('rat %d', i), 1:10, 'UniformOutput', false), ...
        arrayfun(@(i) sprintf('rat %d', i), 1:10, 'UniformOutput', false)};
    Q = GroupStats.checks(res, o);
    expect(tests, Q, 'Normality', 'check', 'rat 10');
    res.checkAgrees = false;                      % the rank-based test disagrees
    expect(tests, GroupStats.checks(res, o), 'Normality', 'warning', 'Not normal');
    res = GroupStats.compare({a, a + d}, {'A', 'B'}, 'paired', 'nonparametric');
    expect(tests, GroupStats.checks(res), 'Normality', 'ok', 'does not need normality');
    % Unpaired / ANOVA: each group
    Q = GroupStats.checks(GroupStats.compare({a, [a(1:9); 60]}, {'A', 'B'}, 'unpaired'));
    expect(tests, Q, 'Normality', 'check', 'B (W =');
    Q = GroupStats.checks(GroupStats.compare({[1 2]', [3 4]'}, {'A', 'B'}, 'unpaired'));
    expect(tests, Q, 'Normality', 'note', 'Too few');
end

function testSphericityRules(tests)
    A = faultsMatrix();
    res = GroupStats.compare(num2cell(A, 1), {'Control', 'Stimulated', 'Drug'}, 'rm');
    expect(tests, GroupStats.checks(res), 'Sphericity', 'check', 'Violated');
    sph = res.main.sphericity;
    tests.verifyLessThan(sph.p, 0.01, 'Mauchly rejects sphericity');
    % Mauchly not rejected but the correction changes the verdict
    res.main.sphericity.p = 0.3; res.main.sphericity.pUncorrected = 0.03; res.main.sphericity.pGG = 0.07;
    expect(tests, GroupStats.checks(res), 'Sphericity', 'warning', 'changes the verdict');
    res.main.sphericity.pGG = 0.04;
    expect(tests, GroupStats.checks(res), 'Sphericity', 'ok', 'Not rejected');
    % Fewer animals than conditions
    res = GroupStats.compare(num2cell(A(1:2, :), 1), {'C', 'S', 'D'}, 'rm');
    expect(tests, GroupStats.checks(res), 'Sphericity', 'check', 'cannot be computed');
    % Two conditions; Friedman
    res = GroupStats.compare(num2cell(A(:, 1:2), 1), {'C', 'S'}, 'rm');
    expect(tests, GroupStats.checks(res), 'Sphericity', 'ok', 'by definition');
    res = GroupStats.compare(num2cell(A, 1), {'C', 'S', 'D'}, 'rm', 'nonparametric');
    expect(tests, GroupStats.checks(res), 'Sphericity', 'ok', 'Friedman');
    % Not a repeated-measures design: no row
    tests.verifyEmpty(row(GroupStats.checks(GroupStats.compare({A(:, 1), A(:, 2)}, {'C', 'S'}, 'paired')), 'Sphericity'));
end

function testSpreadRobustnessAndMissing(tests)
    g1 = [10 11 12 10 11 12 11 10]'; g2 = [20 30 10 25 15 35 5 28]'; g3 = [15 16 14 15 16 14 15 16]';
    Q = GroupStats.checks(GroupStats.compare({g1, g2, g3}, {'A', 'B', 'C'}, 'anova'));
    expect(tests, Q, 'Equal spread', 'check', 'Largest / smallest SD');
    Q = GroupStats.checks(GroupStats.compare({g1(1:4), g2, g3}, {'A', 'B', 'C'}, 'anova'));
    expect(tests, Q, 'Equal spread', 'warning', 'group sizes differ');
    Q = GroupStats.checks(GroupStats.compare({g1, g3}, {'A', 'C'}, 'unpaired'));
    expect(tests, Q, 'Equal spread', 'ok', 'Welch');
    tests.verifyEmpty(row(GroupStats.checks(GroupStats.compare({g1, g2, g3}, {'A', 'B', 'C'}, 'anova', ...
        'nonparametric')), 'Equal spread'), 'no spread row for a rank-based result');
    res = GroupStats.compare({g1, g3}, {'A', 'C'}, 'unpaired');
    expect(tests, GroupStats.checks(res), 'Robustness check', 'ok', 'agree');
    res.checkAgrees = false;
    expect(tests, GroupStats.checks(res), 'Robustness check', 'check', 'depends on the test');
    tests.verifyEmpty(row(GroupStats.checks(res), 'Missing values'));
    Q = GroupStats.checks(GroupStats.compare({[g1; NaN], [g3; 15]}, {'A', 'C'}, 'paired'));
    expect(tests, Q, 'Missing values', 'check', '1 subject left out');
end

function testGroupDemoHasNoWarnings(tests)
    demo = demoGroups(fullfile(tempdir, 'StatsChecksTest_groups'));
    A = demo.truth.amplitude;
    designs = {'paired', 'unpaired', 'anova', 'rm'};
    for d = 1:numel(designs)
        for m = {'parametric', 'nonparametric'}
            if d <= 2
                v = {A(:, 1), A(:, 2)}; nm = demo.conditions(1:2);
            else
                v = num2cell(A, 1); nm = demo.conditions;
            end
            Q = GroupStats.checks(GroupStats.compare(v, nm, designs{d}, m{1}));
            txt = sprintf('%s %s:\n%s', designs{d}, m{1}, strjoin(QualityChecks.lines(Q), newline));
            tests.verifyEqual(QualityChecks.count(Q, 'warning'), 0, txt);
            expect(tests, Q, 'Sample size', 'ok');
        end
    end
end

function testFaultsStudy(tests)
    demo = demoGroups(fullfile(tempdir, 'StatsChecksTest_faults'), struct('Faults', true));
    tests.verifyEqual(demo.truth.nAnimals, 6);
    tests.verifyEqual(demo.truth.amplitude, faultsMatrix(), 'AbsTol', 1.5, 'trial means near the set amplitudes');
    tests.verifyEqual(numel(demo.paths{1}), 6);
    A = demo.truth.amplitude;
    Q = GroupStats.checks(GroupStats.compare(num2cell(A, 1), demo.conditions, 'rm'));
    expect(tests, Q, 'Sample size', 'check', 'fewer than 8');
    tests.verifyTrue(any(strcmp(row(Q, 'Normality').level, {'check', 'warning'})), row(Q, 'Normality').found);
    expect(tests, Q, 'Sphericity', 'check', 'Violated');
    Q = GroupStats.checks(GroupStats.compare({A(:, 1), A(:, 2)}, demo.conditions(1:2), 'paired'));
    expect(tests, Q, 'Normality', 'check', 'subject 6');
end

%% testParticipantWording - EEG Analysis: participants, the Measures tab and its own missing-value advice
function testParticipantWording(tests)
    A = faultsMatrix();
    A(2, 3) = NaN;                                % one participant without a value in one condition
    res = GroupStats.compare(num2cell(A, 1), {'Standard', 'Target', 'Novel'}, 'rm');
    Q = GroupStats.checks(res);
    all1 = strjoin([{Q.found}, {Q.why}, {Q.action}], ' ');
    tests.verifyTrue(~isempty(strfind(all1, 'animal')), 'animals by default'); %#ok<STREMP>
    tests.verifyTrue(~isempty(strfind(all1, 'the Plot tab')), 'the Plot tab by default'); %#ok<STREMP>
    o = GroupStats.checkOptions();
    o.subject = 'participant';
    o.valuesTab = 'the Measures tab';
    o.missingAction = 'See Trials per condition.';
    names = arrayfun(@(i) sprintf('sub-%02d', i), [1 3 4 5 6], 'UniformOutput', false);
    o.labels = {names, names, names};
    Q = GroupStats.checks(res, o);
    all2 = strjoin([{Q.found}, {Q.why}, {Q.action}], ' ');
    tests.verifyEmpty(strfind(all2, 'animal'), all2);
    tests.verifyEmpty(strfind(all2, 'Plot tab'), all2);
    tests.verifyTrue(~isempty(strfind(all2, 'participant')), all2); %#ok<STREMP>
    tests.verifyTrue(~isempty(strfind(all2, 'the Measures tab')), all2); %#ok<STREMP>
    expect(tests, Q, 'Missing values', 'check', '1 subject left out');
    tests.verifyEqual(row(Q, 'Missing values').action, 'See Trials per condition.');
    expect(tests, Q, 'Sample size', 'check', 'fewer than 8');
    tests.verifyEqual({Q.topic}, {GroupStats.checks(res).topic}, 'the same rows, other words');
end
