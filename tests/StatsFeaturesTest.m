%% StatsFeaturesTest.m
% =========================================================================
% UNIT TESTS FOR GroupStats, FigureExport AND THE GROUP DEMO DATA
% =========================================================================
% GroupStats is checked against published textbook results that are
% reproduced by every statistics package:
%   - Student's (1908) sleep data (R dataset "sleep"): paired and Welch
%     t-tests, Wilcoxon signed-rank with ties and a zero difference;
%   - Hollander & Wolfe examples (R wilcox.test help): exact signed-rank
%     and exact Mann-Whitney p-values (the latter also by enumeration);
%   - PlantGrowth (R dataset): one-way ANOVA, Tukey HSD, Kruskal-Wallis;
% and against identities (t quantiles, F = t^2 for two groups, the
% studentized range for 2 groups = sqrt(2) |t|, symmetry, zero effect).
% The group demo (core/demo/demoGroups) must give a significant paired
% effect in the simulated direction, with effect sizes close to the
% simulated truth. FigureExport must write non-empty PDF/SVG/EPS/PNG files
% without changing the source axes.
% =========================================================================

function tests = StatsFeaturesTest
    tests = functiontests(localfunctions);
end

function setupOnce(tests)
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    addpath(fullfile(root, 'core'));
    addpath(fullfile(root, 'core', 'demo'));
    addpath(fullfile(root, 'apps'));
    tests.TestData.tmp = tempname;
    mkdir(tests.TestData.tmp);
end

function teardownOnce(tests)
    if exist(tests.TestData.tmp, 'dir'), rmdir(tests.TestData.tmp, 's'); end
end

%% ---- Shared data ---------------------------------------------------------

% Student's sleep data: extra hours of sleep with drug 1 and drug 2, same 10 patients
function [g1, g2] = sleepData()
    g1 = [0.7 -1.6 -0.2 -1.2 -0.1 3.4 3.7 0.8 0.0 2.0];
    g2 = [1.9 0.8 1.1 0.1 -0.1 4.4 5.5 1.6 4.6 3.4];
end

% PlantGrowth: dried plant weight, control and two treatments (n = 10 each)
function [ctrl, trt1, trt2] = plantGrowth()
    ctrl = [4.17 5.58 5.18 6.11 4.50 4.61 5.17 4.53 5.33 5.14];
    trt1 = [4.81 4.17 4.41 3.59 5.87 3.83 6.03 4.89 4.32 4.69];
    trt2 = [6.31 5.12 5.54 5.50 5.37 5.29 4.92 6.15 5.80 5.26];
end

%% ---- Descriptives and distributions ---------------------------------------

function testDescribe_knownValues(tests)
    d = GroupStats.describe([1 2 3 4 5 NaN]);
    verifyEqual(tests, d.n, 5);
    verifyEqual(tests, d.nMissing, 1);
    verifyEqual(tests, d.mean, 3, 'AbsTol', 1e-12);
    verifyEqual(tests, d.sd, sqrt(2.5), 'AbsTol', 1e-12);
    verifyEqual(tests, d.sem, sqrt(0.5), 'AbsTol', 1e-12);
    verifyEqual(tests, [d.median d.q1 d.q3 d.iqr], [3 2 4 2], 'AbsTol', 1e-12);
    % t(0.975, 4) = 2.776445
    verifyEqual(tests, d.ci95, 3 + [-1 1] * 2.776445 * sqrt(0.5), 'AbsTol', 1e-5);
end

function testTDistribution_criticalValuesAndSymmetry(tests)
    verifyEqual(tests, GroupStats.tinv(0.975, 1), 12.706205, 'AbsTol', 1e-5);
    verifyEqual(tests, GroupStats.tinv(0.975, 9), 2.262157, 'AbsTol', 1e-6);
    verifyEqual(tests, GroupStats.tinv(0.975, 27), 2.051831, 'AbsTol', 1e-6);
    verifyEqual(tests, GroupStats.tinv(0.975, Inf), 1.959964, 'AbsTol', 1e-6);
    verifyEqual(tests, GroupStats.tinv(0.025, 9), -GroupStats.tinv(0.975, 9), 'AbsTol', 1e-12);
    t = [-3 -1 0 0.5 2.5];
    verifyEqual(tests, GroupStats.tcdf(-t, 7), 1 - GroupStats.tcdf(t, 7), 'AbsTol', 1e-12);
    verifyEqual(tests, GroupStats.tcdf(GroupStats.tinv(0.9, 5), 5), 0.9, 'AbsTol', 1e-10);
    verifyEqual(tests, GroupStats.pT2(0, 12), 1, 'AbsTol', 1e-12);
    % Two-sided p from t matches the CDF
    verifyEqual(tests, GroupStats.pT2(2.1, 11), 2 * (1 - GroupStats.tcdf(2.1, 11)), 'AbsTol', 1e-12);
    % Chi-square with 2 df: P(X > x) = exp(-x / 2)
    verifyEqual(tests, GroupStats.chi2Upper(5, 2), exp(-2.5), 'AbsTol', 1e-12);
end

function testStudentizedRange(tests)
    % k = 2: Q = sqrt(2) |t|, so P(Q <= q) = 1 - p_two-sided(q / sqrt(2))
    for df = [1 3 10 27 1000 Inf]
        for q = [0.5 2 3.5 8]
            verifyEqual(tests, GroupStats.ptukey(q, 2, df), 1 - GroupStats.pT2(q / sqrt(2), df), ...
                'AbsTol', 1e-6, sprintf('k = 2, df = %g, q = %g', df, q));
        end
    end
    % Tabled upper 5% points of the studentized range
    verifyEqual(tests, GroupStats.qtukey(0.95, 3, Inf), 3.314, 'AbsTol', 1e-3);
    verifyEqual(tests, GroupStats.qtukey(0.95, 3, 10), 3.877, 'AbsTol', 1e-3);
    verifyEqual(tests, GroupStats.qtukey(0.95, 4, 20), 3.958, 'AbsTol', 1e-3);
end

%% ---- t-tests -------------------------------------------------------------

function testPairedT_sleepData(tests)
    [g1, g2] = sleepData();
    r = GroupStats.ttestPaired(g1, g2);
    verifyEqual(tests, r.stat, -4.062128, 'AbsTol', 1e-5);
    verifyEqual(tests, r.df, 9);
    verifyEqual(tests, r.p, 0.002833, 'AbsTol', 1e-6);
    verifyEqual(tests, r.meanDiff, -1.58, 'AbsTol', 1e-12);
    verifyEqual(tests, r.ci, [-2.4598858 -0.7001142], 'AbsTol', 1e-6);
    verifyEqual(tests, r.effect, -1.58 / std(g1 - g2), 'AbsTol', 1e-12);   % d_z
    verifyEqual(tests, GroupStats.dz(g1, g2), r.effect, 'AbsTol', 1e-12);
end

function testWelchT_sleepData(tests)
    [g1, g2] = sleepData();
    r = GroupStats.ttestWelch(g1, g2);
    verifyEqual(tests, r.stat, -1.860813, 'AbsTol', 1e-5);
    verifyEqual(tests, r.df, 17.77647, 'AbsTol', 1e-4);
    verifyEqual(tests, r.p, 0.07939, 'AbsTol', 1e-5);
    verifyEqual(tests, r.ci, [-3.3654832 0.2054832], 'AbsTol', 1e-6);
end

function testWelchT_handComputedAndSymmetric(tests)
    a = [1 2 3 4 5]; b = [3 4 5 6 7];
    r = GroupStats.ttestWelch(a, b);
    % Equal variances 2.5 and n = 5: se = 1, t = -2, df = 8
    verifyEqual(tests, r.stat, -2, 'AbsTol', 1e-12);
    verifyEqual(tests, r.df, 8, 'AbsTol', 1e-12);
    verifyEqual(tests, r.p, betainc(8 / 12, 4, 0.5), 'AbsTol', 1e-12);
    r2 = GroupStats.ttestWelch(b, a);
    verifyEqual(tests, r2.stat, 2, 'AbsTol', 1e-12);
    verifyEqual(tests, r2.p, r.p, 'AbsTol', 1e-12);
    % Cohen's d with the pooled SD, Hedges' g with the exact J(8) = 6 / (2 Gamma(3.5))
    d = -2 / sqrt(2.5);
    verifyEqual(tests, GroupStats.cohensD(a, b), d, 'AbsTol', 1e-12);
    J = 6 / (2 * gamma(3.5));
    verifyEqual(tests, GroupStats.hedgesG(a, b), d * J, 'AbsTol', 1e-12);
    verifyEqual(tests, J, 1 - 3 / (4 * 8 - 1), 'AbsTol', 1e-3);   % usual approximation
    verifyEqual(tests, r.effect, d * J, 'AbsTol', 1e-12);
end

%% ---- ANOVA -----------------------------------------------------------------

function testAnova_plantGrowth(tests)
    [ctrl, trt1, trt2] = plantGrowth();
    r = GroupStats.anova1way({ctrl, trt1, trt2}, {'ctrl', 'trt1', 'trt2'});
    verifyEqual(tests, r.df, [2 27]);
    verifyEqual(tests, r.table.SSB, 3.76634, 'AbsTol', 1e-5);
    verifyEqual(tests, r.table.SSW, 10.49209, 'AbsTol', 1e-5);
    verifyEqual(tests, r.stat, 4.846088, 'AbsTol', 1e-5);
    verifyEqual(tests, r.p, 0.01591, 'AbsTol', 1e-5);
    verifyEqual(tests, r.effect, 3.76634 / (3.76634 + 10.49209), 'AbsTol', 1e-5);
    % Tukey HSD (as reported by R's TukeyHSD): trt1-ctrl, trt2-ctrl, trt2-trt1
    verifyEqual(tests, [r.posthoc.diff], [-0.371 0.494 0.865], 'AbsTol', 1e-10);
    verifyEqual(tests, [r.posthoc.p], [0.3908711 0.1979960 0.0120064], 'AbsTol', 2e-6);
    verifyEqual(tests, r.posthoc(3).ci, [0.1737839 1.5562161], 'AbsTol', 2e-6);
    % Same result from values + labels
    r2 = GroupStats.anova1way([ctrl trt1 trt2], [repmat({'ctrl'}, 1, 10), repmat({'trt1'}, 1, 10), repmat({'trt2'}, 1, 10)]);
    verifyEqual(tests, r2.stat, r.stat, 'AbsTol', 1e-12);
    verifyEqual(tests, r2.groupNames, {'ctrl', 'trt1', 'trt2'});
end

function testAnova_equalMeansGivesZeroF(tests)
    r = GroupStats.anova1way({[1 2 3], [1 2 3], [3 2 1]});
    verifyEqual(tests, r.stat, 0, 'AbsTol', 1e-12);
    verifyEqual(tests, r.p, 1, 'AbsTol', 1e-12);
    verifyEqual(tests, r.effect, 0, 'AbsTol', 1e-12);
end

function testAnova_twoGroupsIsStudentTSquared(tests)
    a = [3.1 4.2 5.0 4.4 3.9 4.8]; b = [5.2 5.9 4.9 6.3 5.5];
    na = numel(a); nb = numel(b);
    sp = sqrt(((na - 1) * var(a) + (nb - 1) * var(b)) / (na + nb - 2));
    t = (mean(a) - mean(b)) / (sp * sqrt(1 / na + 1 / nb));
    r = GroupStats.anova1way({a, b});
    verifyEqual(tests, r.stat, t^2, 'RelTol', 1e-10);
    verifyEqual(tests, r.p, GroupStats.pT2(t, na + nb - 2), 'AbsTol', 1e-12);
    % Holm post-hoc option: one comparison, unadjusted Welch p
    r = GroupStats.anova1way({a, b}, [], 'holm');
    verifyEqual(tests, r.posthoc(1).p, GroupStats.ttestWelch(b, a).p, 'AbsTol', 1e-12);
end

%% ---- Rank tests -----------------------------------------------------------

function testWilcoxon_exactHollanderWolfe(tests)
    % Hamilton depression scale, 9 patients, first vs second visit
    x = [1.83 0.50 1.62 2.48 1.68 1.88 1.55 3.06 1.30];
    y = [0.878 0.647 0.598 2.05 1.06 1.29 1.06 3.14 1.29];
    r = GroupStats.wilcoxonSignedRank(x, y);
    verifyEqual(tests, r.stat, 40);
    verifyEqual(tests, r.method, 'exact');
    % 10 of the 512 sign patterns give W- <= 5: one-sided 10/512, two-sided 20/512
    verifyEqual(tests, r.p, 20 / 512, 'AbsTol', 1e-12);
    % All 8 differences positive: two-sided exact p = 2 / 2^8
    r = GroupStats.wilcoxonSignedRank(2:9, zeros(1, 8));
    verifyEqual(tests, r.p, 2 / 256, 'AbsTol', 1e-12);
    verifyEqual(tests, r.effect, 1, 'AbsTol', 1e-12);
end

function testWilcoxon_normalApproxWithTiesAndZero(tests)
    [g1, g2] = sleepData();
    r = GroupStats.wilcoxonSignedRank(g1, g2);
    % One zero difference dropped (n = 9), one tie of 2: V = 0,
    % z = (0 - 22.5 + 0.5) / sqrt(9*10*19/24 - (2^3 - 2)/48)
    verifyEqual(tests, r.stat, 0);
    verifyEqual(tests, r.z, -22 / sqrt(71.125), 'AbsTol', 1e-12);
    verifyEqual(tests, r.p, 0.009091, 'AbsTol', 1e-6);
    verifySubstring(tests, r.method, 'normal approximation');
end

function testMannWhitney_exactMatchesEnumeration(tests)
    % Permeability constants, term (x) vs 12-26 weeks (y); no ties
    x = [0.80 0.83 1.89 1.04 1.45 1.38 1.91 1.64 0.73 1.46];
    y = [1.15 0.88 0.90 0.74 1.21];
    r = GroupStats.mannWhitney(x, y);
    verifyEqual(tests, r.stat, 35);
    verifyEqual(tests, r.method, 'exact');
    % Enumerate all C(15, 10) = 3003 splits of the pooled values
    v = [x y];
    C = nchoosek(1:15, 10);
    U = zeros(size(C, 1), 1);
    for i = 1:size(C, 1)
        xi = v(C(i, :)); yi = v(setdiff(1:15, C(i, :)));
        U(i) = sum(sum(xi(:) > yi(:)'));
    end
    pEnum = min(1, 2 * min(mean(U >= 35), mean(U <= 35)));
    verifyEqual(tests, r.p, pEnum, 'AbsTol', 1e-12);
    verifyEqual(tests, r.p / 2, 0.1272, 'AbsTol', 1e-4);   % R: one-sided p-value = 0.1272
    % Complete separation, 4 vs 4: two-sided p = 2 / C(8, 4)
    r = GroupStats.mannWhitney([5 6 7 8], [1 2 3 4]);
    verifyEqual(tests, r.p, 2 / 70, 'AbsTol', 1e-12);
    verifyEqual(tests, r.effect, 1, 'AbsTol', 1e-12);
end

function testMannWhitney_tiesSymmetry(tests)
    a = [1 2 2 3 4 4]; b = [2 3 5 6 6 7 4];
    r1 = GroupStats.mannWhitney(a, b);
    r2 = GroupStats.mannWhitney(b, a);
    verifySubstring(tests, r1.method, 'normal approximation');
    verifyEqual(tests, r1.stat + r2.stat, numel(a) * numel(b), 'AbsTol', 1e-12);
    verifyEqual(tests, r1.p, r2.p, 'AbsTol', 1e-12);
    verifyEqual(tests, r1.effect, -r2.effect, 'AbsTol', 1e-12);
    verifyLessThan(tests, r1.effect, 0);   % a tends to be smaller
end

function testKruskalWallis_plantGrowth(tests)
    [ctrl, trt1, trt2] = plantGrowth();
    r = GroupStats.kruskalWallis({ctrl, trt1, trt2}, {'ctrl', 'trt1', 'trt2'});
    verifyEqual(tests, r.stat, 7.988229, 'AbsTol', 1e-5);
    verifyEqual(tests, r.df, 2);
    verifyEqual(tests, r.p, 0.01842, 'AbsTol', 1e-5);
    verifyNumElements(tests, r.posthoc, 3);
end

function testHolm(tests)
    verifyEqual(tests, GroupStats.holm([0.01 0.04 0.03 0.005]), [0.03 0.06 0.06 0.02], 'AbsTol', 1e-12);
end

%% ---- compare (what the app shows) ------------------------------------------

function testCompare_pairedSummaryAndDirection(tests)
    [g1, g2] = sleepData();
    res = GroupStats.compare({g1, g2}, {'Drug 1', 'Drug 2'}, 'paired');
    verifyEqual(tests, res.main.test, 'Paired t-test');
    verifyEqual(tests, res.comparisons(1).diff, 1.58, 'AbsTol', 1e-12);   % B - A
    verifyEqual(tests, res.main.p, 0.002833, 'AbsTol', 1e-6);
    verifyEqual(tests, res.check.test, 'Wilcoxon signed-rank test');
    verifyTrue(tests, res.checkAgrees);
    verifySubstring(tests, res.summary, 't(9) = 4.06');
    verifyNotEmpty(tests, res.assumptions);
    res = GroupStats.compare({g1, g2}, {'Drug 1', 'Drug 2'}, 'unpaired', 'nonparametric');
    verifyEqual(tests, res.main.test, 'Mann-Whitney U test');
    verifyEqual(tests, res.check.test, 'Welch t-test');
end

function testCompare_errors(tests)
    verifyError(tests, @() GroupStats.compare({1:3, 1:4}, {'A', 'B'}, 'paired'), ...
        'NeuroAnalyzer:GroupStats:pairedLength');
    verifyError(tests, @() GroupStats.compare({1:3, 1:4, 2:5}, {'A', 'B', 'C'}, 'unpaired'), ...
        'NeuroAnalyzer:GroupStats:design');
end

function testCompare_pairedDropsIncompletePairs(tests)
    [g1, g2] = sleepData();
    g1(3) = NaN;
    res = GroupStats.compare({g1, g2}, {'A', 'B'}, 'paired');
    verifyEqual(tests, res.desc(1).n, 9);
    verifyEqual(tests, res.nExcluded, [1 1]);
    verifyEqual(tests, res.main.df, 8);
end

%% ---- Group demo: known effect recovered ------------------------------------

% Per-file peak amplitude of the trial-average trace, baseline = pre-stimulus mean
function vals = demoPeakAmplitudes(demo)
    vals = cell(1, numel(demo.conditions));
    for c = 1:numel(demo.conditions)
        v = zeros(numel(demo.paths{c}), 1);
        for k = 1:numel(demo.paths{c})
            s = load(demo.paths{c}{k});
            t = s.segmentedTime; y = mean(s.segmentedLDF, 1);
            v(k) = SignalFeatures.peakAmplitude(t, y, 0, 'max', mean(y(t < 0)));
        end
        vals{c} = v;
    end
end

function testDemoGroups_filesAndTruth(tests)
    demo = demoGroups(fullfile(tests.TestData.tmp, 'groups'));
    verifyEqual(tests, demo.conditions, {'Control', 'Stimulated', 'Drug'});
    verifyEqual(tests, cellfun(@numel, demo.paths), [8 8 8]);
    s = load(demo.paths{2}{1});
    verifyEqual(tests, size(s.segmentedLDF), [8 251]);
    verifyEqual(tests, s.segmentedTime([1 end]), [-5 20], 'AbsTol', 1e-9);
    verifyEqual(tests, s.Fs, 10);
    verifyEqual(tests, demo.truth.meanAmplitude, [18 30 24]);
    verifyEqual(tests, demo.truth.effect.meanDiff, 12);
    % Deterministic
    demo2 = demoGroups(fullfile(tests.TestData.tmp, 'groups2'));
    verifyEqual(tests, demo2.truth.amplitude, demo.truth.amplitude);
end

function testDemoGroups_pairedTestDetectsEffect(tests)
    demo = demoGroups(fullfile(tests.TestData.tmp, 'groups'));
    vals = demoPeakAmplitudes(demo);
    % Feature extraction recovers the simulated amplitude of every file
    verifyEqual(tests, [vals{:}], demo.truth.amplitude, 'AbsTol', 2.5);
    res = GroupStats.compare(vals(1:2), demo.conditions(1:2), 'paired');
    realizedDiff = mean(demo.truth.amplitude(:, 2) - demo.truth.amplitude(:, 1));
    verifyLessThan(tests, res.main.p, 0.05);
    verifyEqual(tests, res.comparisons(1).diff, realizedDiff, 'AbsTol', 1.5);
    verifyGreaterThan(tests, res.comparisons(1).ci(1), 0);
    % d_z close to the one of the simulated amplitudes, and large as simulated (2.75)
    verifyEqual(tests, res.main.effect, demo.truth.effect.sampleDz, 'RelTol', 0.3);
    verifyGreaterThan(tests, res.main.effect, 1);
    % Rank-based test agrees in direction
    verifyGreaterThan(tests, res.check.effect, 0);
    verifyLessThan(tests, res.check.p, 0.05);
    verifyTrue(tests, res.checkAgrees);
    np = GroupStats.compare(vals(1:2), demo.conditions(1:2), 'paired', 'nonparametric');
    verifyGreaterThan(tests, np.comparisons(1).diff, 0);
    % Unpaired analysis of the same data: same direction, Hedges' g near the simulated d
    up = GroupStats.compare(vals(1:2), demo.conditions(1:2), 'unpaired');
    verifyGreaterThan(tests, up.main.effect, 0);
    verifyEqual(tests, up.main.effect, demo.truth.effect.sampleD, 'RelTol', 0.35);
end

function testDemoGroups_anovaThreeGroups(tests)
    demo = demoGroups(fullfile(tests.TestData.tmp, 'groups'));
    vals = demoPeakAmplitudes(demo);
    res = GroupStats.compare(vals, demo.conditions, 'anova');
    verifyLessThan(tests, res.main.p, 0.05);
    verifyEqual(tests, res.main.df, [2 21]);
    verifyNumElements(tests, res.comparisons, 3);
    verifyEqual(tests, res.comparisons(1).label, ['Stimulated ' char(8722) ' Control']);
    verifyLessThan(tests, res.comparisons(1).p, 0.05);
    verifyEqual(tests, [res.desc.mean], mean(demo.truth.amplitude, 1), 'AbsTol', 1.5);
end

%% ---- FigureExport ------------------------------------------------------------

function f = exportTestFigure(tests)
    try
        f = figure('Visible', 'off');
    catch
        f = [];
    end
    tests.assumeNotEmpty(f, 'figures not available');
end

function testFigureExport_writesVectorAndPng(tests)
    f = exportTestFigure(tests); c = onCleanup(@() delete(f));
    ax = axes(f);
    plot(ax, 1:10, (1:10).^2, 'LineWidth', 0.5, 'DisplayName', 'data');
    hold(ax, 'on');
    patch(ax, [1 3 3 1], [0 0 50 50], [0 0.45 0.7], 'FaceAlpha', 0.2, 'EdgeColor', 'none', 'DisplayName', 'window');
    text(ax, 5, 60, 'label');
    title(ax, 'Test'); xlabel(ax, 'Time (s)'); ylabel(ax, 'Signal');
    legend(ax, 'show');
    ax.XGrid = 'on';
    nFigs = numel(findall(groot, 'Type', 'figure'));
    for fmt = {'pdf', 'svg', 'eps', 'png300'}
        out = FigureExport.export(ax, fullfile(tests.TestData.tmp, 'fig_test'), fmt{1});
        d = dir(out);
        verifyNotEmpty(tests, d, fmt{1});
        verifyGreaterThan(tests, d(1).bytes, 0, fmt{1});
    end
    [~, ~, ext] = fileparts(out);
    verifyEqual(tests, ext, '.png');
    info = imfinfo(out);
    verifyGreaterThan(tests, info.Width, 600);   % 8.5 cm at 300 dpi is ~1000 px
    % The source is unchanged and no temporary figure is left behind
    verifyEqual(tests, char(ax.XGrid), 'on');
    verifyEqual(tests, numel(findall(groot, 'Type', 'figure')), nFigs);
end

function testFigureExport_tiledLayout(tests)
    f = exportTestFigure(tests); c = onCleanup(@() delete(f));
    tl = tiledlayout(f, 1, 2);
    plot(nexttile(tl), 1:5, rand(1, 5));
    bar(nexttile(tl), [3 5 2]);
    out = FigureExport.export(tl, fullfile(tests.TestData.tmp, 'tiled.png'));
    d = dir(out);
    verifyGreaterThan(tests, d(1).bytes, 0);
end

function testFigureExport_uiaxes(tests)
    try
        uf = uifigure('Visible', 'off');
    catch
        uf = [];
    end
    tests.assumeNotEmpty(uf, 'uifigure not available (no display)');
    c = onCleanup(@() delete(uf));
    ax = uiaxes(uf);
    scatter(ax, 1:8, (1:8) + 0.5, 30, 'filled');
    hold(ax, 'on');
    errorbar(ax, 4, 5, 1);
    out = FigureExport.export(ax, fullfile(tests.TestData.tmp, 'ui_axes'), 'PDF (vector)');
    d = dir(out);
    verifyEqual(tests, out(end-3:end), '.pdf');
    verifyGreaterThan(tests, d(1).bytes, 0);
end

function testFigureExport_formatKeys(tests)
    verifyEqual(tests, FigureExport.formatKey('PNG 600 dpi'), 'png600');
    verifyEqual(tests, FigureExport.formatKey('svg'), 'svg');
    [fmt, ext, dpi, isVector] = FigureExport.parseFormat('TIFF 600 dpi');
    verifyEqual(tests, {fmt, ext, dpi, isVector}, {'tif', '.tif', 600, false});
    verifyError(tests, @() FigureExport.parseFormat('doc'), 'NeuroAnalyzer:FigureExport:format');
end
