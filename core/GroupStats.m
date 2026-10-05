%% GroupStats.m
% =========================================================================
% GROUP STATISTICS - DESCRIPTIVES, T-TESTS, ANOVA, RANK TESTS, EFFECT SIZES
% =========================================================================
% Toolbox-free statistics (base MATLAB only) for comparing one response
% feature between groups or conditions, typically one value per animal.
% Used by the "Groups & statistics" tab of SignalCharacterizationApp.
%
%   d = GroupStats.describe(x)
%       n, mean, SD, SEM, median, quartiles/IQR, min/max and the t-based
%       95% CI of the mean. NaN/Inf values are ignored (counted in nMissing).
%   r = GroupStats.ttestPaired(a, b)       paired t-test on a - b; effect d_z
%   r = GroupStats.ttestWelch(a, b)        Welch t-test (unequal variances,
%                                          Welch-Satterthwaite df); Hedges' g
%   r = GroupStats.anova1way(values, groups[, postHoc])
%       One-way ANOVA (F, df, p, eta^2, omega^2) with pairwise post-hoc
%       comparisons: 'tukey' (Tukey-Kramer HSD, default) or 'holm'
%       (Welch t-tests with Holm-Bonferroni-adjusted p-values).
%   r = GroupStats.wilcoxonSignedRank(a, b[, method, correct])   paired
%   r = GroupStats.mannWhitney(a, b[, method, correct])          unpaired
%   r = GroupStats.kruskalWallis(values, groups)                 >= 2 groups
%       method: 'auto' (exact when there are no ties/zeros and n < 50,
%       else normal approximation), 'exact' or 'approx'. correct: continuity
%       correction of the normal approximation (default true). Effect size:
%       rank-biserial correlation (two groups) or eta^2_H (Kruskal-Wallis).
%   r = GroupStats.rmAnova(Y[, names])     repeated measures, one factor
%       Y: subjects x conditions (or a cell of equal-length vectors, one
%       per condition; the k-th values belong to the same subject).
%       Subjects with a non-finite value in any condition are excluded
%       (counted in nExcluded). F, df, p, partial eta^2 (effect) and
%       generalized eta^2 (effect2); r.sphericity: Mauchly's test (k >= 3),
%       Greenhouse-Geisser, Huynh-Feldt and lower-bound epsilons with the
%       corrected df and p. Rule for the reported p: Greenhouse-Geisser
%       corrected when Mauchly's test is significant (p < 0.05) or cannot
%       be computed (fewer subjects than conditions), else uncorrected;
%       both corrections are always listed. Post hoc: paired t-tests on
%       every pair, Holm-adjusted p, d_z with an exact 95% CI.
%   r = GroupStats.friedman(Y[, names])    rank-based repeated measures
%       Tie-corrected Friedman chi-square (k - 1 df), Kendall's W; post
%       hoc: Wilcoxon signed-rank tests on every pair, Holm-adjusted p.
%   s = GroupStats.sphericity(Y)   Mauchly's W, chi2, df, p and the epsilons
%   d = GroupStats.cohensD(a, b)   (mean(a) - mean(b)) / pooled SD
%   g = GroupStats.hedgesG(a, b)   Cohen's d x exact small-sample factor J
%   d = GroupStats.dz(a, b)        mean(a - b) / SD(a - b) (paired)
%   ci = GroupStats.dzCI(d, n)     exact 95% CI of d_z (noncentral t
%                                  inverted for t = d sqrt(n), df = n - 1)
%   res = GroupStats.compare(values, names, design, method)
%       One call for a whole comparison, as shown by the app. values: cell
%       of vectors (one per group); design: 'paired' | 'unpaired' | 'anova'
%       | 'rm' (repeated measures: the same subjects in every group,
%       matched by order; rmAnova / friedman); method: 'parametric' |
%       'nonparametric'. Runs the chosen test, the
%       other family as a robustness check, describes every group, lists
%       pairwise comparisons, and writes an assumptions note and a
%       one-line summary. Two-group differences are always B - A (second
%       group minus first), e.g. Stimulated - Control.
%
% Distributions (all exact up to floating point unless noted):
%   tcdf / tinv / pT2     Student t: betainc / betaincinv. pT2(t, df) is the
%                         two-sided p = I_{df/(df+t^2)}(df/2, 1/2).
%   fUpper(F, d1, d2)     P(F > f) = I_{d2/(d2+d1 f)}(d2/2, d1/2)
%   chi2Upper(x, k)       gammainc(x/2, k/2, 'upper')
%   normcdf / norminv     erfc / erfcinv
%   nctcdf(t, df, delta)  noncentral t: P(T <= t) = int_0^inf f_s(s)
%                         Phi(t s - delta) ds, s = sqrt(chi2_df / df)
%                         (Simpson, same grid as ptukey)
%   ptukey / qtukey      studentized range: numerical integration of
%                         P(Q <= q) = int_0^inf f_s(s) R_k(q s) ds, with
%                         R_k(w) = k int phi(z) [Phi(z) - Phi(z - w)]^(k-1) dz
%                         and s = sqrt(chi2_df / df) (Simpson in s, trapezoid in z;
%                         absolute error well below 1e-6). qtukey inverts
%                         it with fzero.
%   holm(p)               Holm step-down adjusted p-values
%   tiedRank(x)           average ranks and tie-group sizes
% Text helpers: formatP(p) ('p = 0.012', 'p < 0.0001'), stars(p),
%   statText(r) ('t(7) = 8.96', 'F(2, 21) = 11.8', 'F(1.62, 11.3) = 45.2'),
%   dfText(df) ('21', '11.3').
%
% Every test returns a struct with the same fields: test, statName, stat,
% df, p (two-sided), n, nExcluded, meanDiff, medianDiff, ci (95% CI of
% meanDiff), effectName, effect, effect2Name, effect2, method, note (and
% for ANOVA / Kruskal-Wallis / repeated measures: groupNames, means,
% table, posthoc; rmAnova also has sphericity).
%
% References:
%   Student (1908). The probable error of a mean. Biometrika, 6(1), 1-25.
%   Welch, B. L. (1947). The generalization of 'Student's' problem when
%     several different population variances are involved. Biometrika,
%     34(1-2), 28-35.
%   Satterthwaite, F. E. (1946). An approximate distribution of estimates
%     of variance components. Biometrics Bulletin, 2(6), 110-114.
%   Kramer, C. Y. (1956). Extension of multiple range tests to group means
%     with unequal numbers of replications. Biometrics, 12(3), 307-310.
%   Holm, S. (1979). A simple sequentially rejective multiple test
%     procedure. Scandinavian Journal of Statistics, 6(2), 65-70.
%   Wilcoxon, F. (1945). Individual comparisons by ranking methods.
%     Biometrics Bulletin, 1(6), 80-83.
%   Mann, H. B., & Whitney, D. R. (1947). On a test of whether one of two
%     random variables is stochastically larger than the other. Annals of
%     Mathematical Statistics, 18(1), 50-60.
%   Kruskal, W. H., & Wallis, W. A. (1952). Use of ranks in one-criterion
%     variance analysis. Journal of the American Statistical Association,
%     47(260), 583-621.
%   Cohen, J. (1988). Statistical Power Analysis for the Behavioral
%     Sciences (2nd ed.). Lawrence Erlbaum Associates.
%   Hedges, L. V. (1981). Distribution theory for Glass's estimator of
%     effect size and related estimators. Journal of Educational
%     Statistics, 6(2), 107-128.
%   Friedman, M. (1937). The use of ranks to avoid the assumption of
%     normality implicit in the analysis of variance. Journal of the
%     American Statistical Association, 32(200), 675-701.
%   Mauchly, J. W. (1940). Significance test for sphericity of a normal
%     n-variate distribution. Annals of Mathematical Statistics, 11(2),
%     204-209.
%   Greenhouse, S. W., & Geisser, S. (1959). On methods in the analysis of
%     profile data. Psychometrika, 24(2), 95-112.
%   Huynh, H., & Feldt, L. S. (1976). Estimation of the Box correction for
%     degrees of freedom from sample data in randomized block and
%     split-plot designs. Journal of Educational Statistics, 1(1), 69-82.
%   Olejnik, S., & Algina, J. (2003). Generalized eta and omega squared
%     statistics: measures of effect size for some common research
%     designs. Psychological Methods, 8(4), 434-447.
%   Bakeman, R. (2005). Recommended effect size statistics for repeated
%     measures designs. Behavior Research Methods, 37(3), 379-384.
% =========================================================================

classdef GroupStats
    properties(Constant)
        SmallN = 8          % checks: fewer subjects per group than this is a Check
    end

    methods(Static)

        %% describe - Descriptive statistics of one sample (non-finite values ignored)
        % Quartiles use linear interpolation between order statistics
        % (h = (n-1)p + 1; the default of R, NumPy and Excel QUARTILE.INC).
        function d = describe(x)
            x = double(x(:));
            nAll = numel(x);
            x = x(isfinite(x));
            n = numel(x);
            d = struct('n', n, 'nMissing', nAll - n, 'mean', NaN, 'sd', NaN, 'sem', NaN, ...
                'median', NaN, 'q1', NaN, 'q3', NaN, 'iqr', NaN, 'min', NaN, 'max', NaN, ...
                'ci95', [NaN NaN]);
            if n == 0, return; end
            d.mean = mean(x);
            d.median = median(x);
            d.min = min(x);
            d.max = max(x);
            q = GroupStats.quantile(x, [0.25 0.75]);
            d.q1 = q(1); d.q3 = q(2); d.iqr = q(2) - q(1);
            if n >= 2
                d.sd = std(x);
                d.sem = d.sd / sqrt(n);
                d.ci95 = d.mean + [-1 1] * GroupStats.tinv(0.975, n - 1) * d.sem;
            end
        end

        %% quantile - Sample quantiles, linear interpolation (h = (n-1)p + 1)
        function q = quantile(x, p)
            x = sort(double(x(isfinite(x(:)))));
            n = numel(x);
            q = NaN(size(p));
            if n == 0, return; end
            for i = 1:numel(p)
                h = (n - 1) * p(i) + 1;
                lo = floor(h);
                hi = min(lo + 1, n);
                q(i) = x(lo) + (h - lo) * (x(hi) - x(lo));
            end
        end

        %% ttestPaired - Paired t-test of a against b (differences a - b)
        % Pairs with a non-finite value in a or b are dropped. Effect size:
        % d_z = mean(a - b) / SD(a - b). ci: 95% CI of the mean difference.
        function r = ttestPaired(a, b)
            a = double(a(:)); b = double(b(:));
            if numel(a) ~= numel(b)
                error('NeuroAnalyzer:GroupStats:pairedLength', ...
                    'A paired test needs the same number of values in both conditions (%d vs %d).', ...
                    numel(a), numel(b));
            end
            keep = isfinite(a) & isfinite(b);
            d = a(keep) - b(keep);
            n = numel(d);
            if n < 2
                error('NeuroAnalyzer:GroupStats:tooFew', 'A paired t-test needs at least 2 complete pairs.');
            end
            r = GroupStats.emptyResult('Paired t-test', 't');
            r.n = [n n];
            r.nExcluded = [sum(~keep) sum(~keep)];
            md = mean(d);
            sd = std(d);
            se = sd / sqrt(n);
            df = n - 1;
            [t, p] = GroupStats.tFromDiff(md, se, df);
            r.stat = t; r.df = df; r.p = p;
            r.meanDiff = md;
            r.medianDiff = median(d);
            r.ci = md + [-1 1] * GroupStats.tinv(0.975, df) * se;
            r.effectName = 'd_z';
            r.effect = GroupStats.safeDivide(md, sd);
            r.method = 'exact t distribution';
            r.note = 'Two-sided; mean of the paired differences a - b.';
        end

        %% ttestWelch - Two-sample t-test without assuming equal variances
        % df from the Welch-Satterthwaite equation. Effect: Hedges' g
        % (effect2: Cohen's d with the pooled SD). Difference = mean(a) - mean(b).
        function r = ttestWelch(a, b)
            a = double(a(:)); b = double(b(:));
            nExc = [sum(~isfinite(a)) sum(~isfinite(b))];
            a = a(isfinite(a)); b = b(isfinite(b));
            na = numel(a); nb = numel(b);
            if na < 2 || nb < 2
                error('NeuroAnalyzer:GroupStats:tooFew', ...
                    'A Welch t-test needs at least 2 values in each group (%d and %d).', na, nb);
            end
            r = GroupStats.emptyResult('Welch t-test', 't');
            r.n = [na nb];
            r.nExcluded = nExc;
            sa = var(a) / na;
            sb = var(b) / nb;
            se = sqrt(sa + sb);
            md = mean(a) - mean(b);
            if sa + sb > 0
                df = (sa + sb)^2 / (sa^2 / (na - 1) + sb^2 / (nb - 1));
            else
                df = na + nb - 2;
            end
            [t, p] = GroupStats.tFromDiff(md, se, df);
            r.stat = t; r.df = df; r.p = p;
            r.meanDiff = md;
            r.medianDiff = median(a) - median(b);
            r.ci = md + [-1 1] * GroupStats.tinv(0.975, df) * se;
            r.effectName = 'Hedges'' g';
            r.effect = GroupStats.hedgesG(a, b);
            r.effect2Name = 'Cohen''s d';
            r.effect2 = GroupStats.cohensD(a, b);
            r.method = 'Welch-Satterthwaite df';
            r.note = 'Two-sided; mean(a) - mean(b); variances not assumed equal.';
        end

        %% anova1way - One-way (between-subjects) ANOVA with post-hoc comparisons
        % values: numeric vector with group labels in groups (cellstr,
        % string, categorical or numeric), or a cell array of vectors (one
        % per group) with optional names in groups. postHoc: 'tukey'
        % (Tukey-Kramer HSD, default) or 'holm' (pairwise Welch t-tests,
        % Holm-Bonferroni-adjusted). Pairwise differences are B - A for
        % every pair (A listed before B).
        function r = anova1way(values, groups, postHoc)
            if nargin < 2, groups = []; end
            if nargin < 3 || isempty(postHoc), postHoc = 'tukey'; end
            [vals, names, nExc] = GroupStats.toGroups(values, groups);
            k = numel(vals);
            n = cellfun(@numel, vals);
            if k < 2
                error('NeuroAnalyzer:GroupStats:tooFewGroups', 'ANOVA needs at least 2 groups.');
            end
            if any(n < 2)
                error('NeuroAnalyzer:GroupStats:tooFew', ...
                    'ANOVA needs at least 2 values in every group (%s).', GroupStats.nList(names, n));
            end
            N = sum(n);
            allv = vertcat(vals{:});
            means = cellfun(@mean, vals);
            SSB = sum(n .* (means - mean(allv)).^2);
            SSW = sum(cellfun(@(v) sum((v - mean(v)).^2), vals));
            dfB = k - 1; dfW = N - k;
            MSB = SSB / dfB; MSW = SSW / dfW;
            if MSW > 0
                F = MSB / MSW;
                p = GroupStats.fUpper(F, dfB, dfW);
            elseif MSB > 0
                F = Inf; p = 0;
            else
                F = NaN; p = 1;
            end
            r = GroupStats.emptyResult('One-way ANOVA', 'F');
            r.stat = F; r.df = [dfB dfW]; r.p = p;
            r.n = n; r.nExcluded = nExc;
            r.effectName = 'η²';
            r.effect = GroupStats.safeDivide(SSB, SSB + SSW);
            r.effect2Name = 'ω²';
            r.effect2 = GroupStats.safeDivide(SSB - dfB * MSW, SSB + SSW + MSW);
            r.method = 'F distribution';
            r.groupNames = names;
            r.means = means;
            r.table = struct('SSB', SSB, 'SSW', SSW, 'dfB', dfB, 'dfW', dfW, 'MSB', MSB, 'MSW', MSW);
            switch lower(postHoc)
                case 'holm'
                    r.posthoc = GroupStats.pairwise(vals, names, 'welch');
                    r.note = 'Post-hoc: pairwise Welch t-tests, Holm-Bonferroni-adjusted p (CIs unadjusted).';
                otherwise
                    r.posthoc = GroupStats.tukeyKramer(vals, names, MSW, dfW);
                    r.note = 'Post-hoc: Tukey-Kramer HSD (family-wise 95% CIs).';
            end
        end

        %% wilcoxonSignedRank - Wilcoxon signed-rank test of a against b (paired)
        % Zero differences are dropped (Wilcoxon's method). stat = W+ (sum of
        % the ranks of positive differences a - b). method: 'auto' | 'exact'
        % | 'approx'; the exact null distribution is used by 'auto' when
        % there are no ties or zeros and n < 50. correct: continuity
        % correction for the normal approximation (default true). Effect:
        % matched-pairs rank-biserial r = (W+ - W-) / (W+ + W-).
        function r = wilcoxonSignedRank(a, b, method, correct)
            if nargin < 3 || isempty(method), method = 'auto'; end
            if nargin < 4 || isempty(correct), correct = true; end
            a = double(a(:)); b = double(b(:));
            if numel(a) ~= numel(b)
                error('NeuroAnalyzer:GroupStats:pairedLength', ...
                    'A paired test needs the same number of values in both conditions (%d vs %d).', ...
                    numel(a), numel(b));
            end
            keep = isfinite(a) & isfinite(b);
            dAll = a(keep) - b(keep);
            d = dAll(dAll ~= 0);
            n = numel(d);
            nZero = numel(dAll) - n;
            r = GroupStats.emptyResult('Wilcoxon signed-rank test', 'W+');
            r.n = [numel(dAll) numel(dAll)];
            r.nExcluded = [sum(~keep) sum(~keep)];
            r.medianDiff = median(dAll);
            if isempty(dAll)
                error('NeuroAnalyzer:GroupStats:tooFew', 'The signed-rank test needs at least 1 complete pair.');
            end
            [rk, ties] = GroupStats.tiedRank(abs(d));
            Wp = sum(rk(d > 0));
            Wm = sum(rk(d < 0));
            r.stat = Wp;
            r.effectName = 'rank-biserial r';
            r.effect = GroupStats.safeDivide(Wp - Wm, Wp + Wm);
            useExact = strcmpi(method, 'exact') || ...
                (strcmpi(method, 'auto') && isempty(ties) && nZero == 0 && n < 50);
            if n == 0
                r.p = 1; r.method = 'all differences are zero';
            elseif useExact && isempty(ties)
                c = GroupStats.signedRankCounts(n);
                tot = sum(c);
                w = round(Wp);
                r.p = min(1, 2 * min(sum(c(1:w + 1)), sum(c(w + 1:end))) / tot);
                r.method = 'exact';
            else
                mu = n * (n + 1) / 4;
                sigma = sqrt(n * (n + 1) * (2 * n + 1) / 24 - sum(ties.^3 - ties) / 48);
                z = Wp - mu;
                cc = 0.5 * sign(z) * logical(correct);
                z = (z - cc) / sigma;
                r.p = min(1, erfc(abs(z) / sqrt(2)));
                r.method = sprintf('normal approximation (%stie correction)', ...
                    GroupStats.ifElse(correct, 'continuity and ', ''));
                r.z = z;
            end
            r.note = sprintf('Two-sided; differences a - b; %d zero difference(s) dropped.', nZero);
        end

        %% mannWhitney - Mann-Whitney U (Wilcoxon rank-sum) test of a against b
        % stat = U of a (number of pairs with a > b, ties count 1/2).
        % method / correct as in wilcoxonSignedRank; 'auto' is exact when
        % there are no ties and both groups have fewer than 50 values.
        % Effect: rank-biserial r = 2 U / (na nb) - 1 (positive: a larger).
        function r = mannWhitney(a, b, method, correct)
            if nargin < 3 || isempty(method), method = 'auto'; end
            if nargin < 4 || isempty(correct), correct = true; end
            a = double(a(:)); b = double(b(:));
            nExc = [sum(~isfinite(a)) sum(~isfinite(b))];
            a = a(isfinite(a)); b = b(isfinite(b));
            na = numel(a); nb = numel(b);
            if na < 1 || nb < 1
                error('NeuroAnalyzer:GroupStats:tooFew', ...
                    'The Mann-Whitney test needs at least 1 value in each group (%d and %d).', na, nb);
            end
            r = GroupStats.emptyResult('Mann-Whitney U test', 'U');
            r.n = [na nb];
            r.nExcluded = nExc;
            r.medianDiff = median(a) - median(b);
            N = na + nb;
            [rk, ties] = GroupStats.tiedRank([a; b]);
            U = sum(rk(1:na)) - na * (na + 1) / 2;
            r.stat = U;
            r.effectName = 'rank-biserial r';
            r.effect = 2 * U / (na * nb) - 1;
            useExact = strcmpi(method, 'exact') || ...
                (strcmpi(method, 'auto') && isempty(ties) && na < 50 && nb < 50);
            if useExact && isempty(ties)
                pmf = GroupStats.mannWhitneyPmf(na, nb);
                u = round(U);
                r.p = min(1, 2 * min(sum(pmf(1:u + 1)), sum(pmf(u + 1:end))));
                r.method = 'exact';
            else
                sigma = sqrt(na * nb / 12 * ((N + 1) - sum(ties.^3 - ties) / (N * (N - 1))));
                z = U - na * nb / 2;
                cc = 0.5 * sign(z) * logical(correct);
                z = (z - cc) / sigma;
                r.p = min(1, erfc(abs(z) / sqrt(2)));
                r.method = sprintf('normal approximation (%stie correction)', ...
                    GroupStats.ifElse(correct, 'continuity and ', ''));
                r.z = z;
            end
            r.note = 'Two-sided; U counts pairs with a > b.';
        end

        %% kruskalWallis - Kruskal-Wallis H test (rank-based one-way ANOVA)
        % Tie-corrected H, chi-square approximation with k - 1 df. Effect:
        % eta^2_H = (H - k + 1) / (N - k). Post-hoc: pairwise Mann-Whitney
        % tests, Holm-Bonferroni-adjusted (differences of medians, B - A).
        function r = kruskalWallis(values, groups)
            if nargin < 2, groups = []; end
            [vals, names, nExc] = GroupStats.toGroups(values, groups);
            k = numel(vals);
            n = cellfun(@numel, vals);
            if k < 2 || any(n < 1)
                error('NeuroAnalyzer:GroupStats:tooFew', ...
                    'Kruskal-Wallis needs at least 2 groups with values (%s).', GroupStats.nList(names, n));
            end
            N = sum(n);
            [rk, ties] = GroupStats.tiedRank(vertcat(vals{:}));
            edges = [0 cumsum(n)];
            Rsum = zeros(1, k);
            for i = 1:k
                Rsum(i) = sum(rk(edges(i) + 1:edges(i + 1)));
            end
            H = 12 / (N * (N + 1)) * sum(Rsum.^2 ./ n) - 3 * (N + 1);
            C = 1 - sum(ties.^3 - ties) / (N^3 - N);
            if C > 0, H = H / C; else, H = 0; end
            r = GroupStats.emptyResult('Kruskal-Wallis test', 'H');
            r.stat = H; r.df = k - 1;
            r.p = GroupStats.chi2Upper(H, k - 1);
            r.n = n; r.nExcluded = nExc;
            r.effectName = 'η²_H';
            r.effect = GroupStats.safeDivide(H - k + 1, N - k);
            r.method = 'chi-square approximation (tie correction)';
            r.groupNames = names;
            r.means = cellfun(@mean, vals);
            r.posthoc = GroupStats.pairwise(vals, names, 'mannwhitney');
            r.note = 'Post-hoc: pairwise Mann-Whitney tests, Holm-Bonferroni-adjusted p.';
        end

        %% rmAnova - One-way repeated-measures ANOVA (subjects x conditions)
        % Y: n x k matrix (row = subject, column = condition) or a cell of k
        % equal-length vectors (the i-th values belong to subject i). names:
        % condition names (default 'Group 1', ...). Subjects with a
        % non-finite value in any condition are excluded (nExcluded).
        % Sums of squares: conditions SSc = n sum_j (mean_j - M)^2, subjects
        % SSs = k sum_i (mean_i - M)^2, error SSe = residual of the additive
        % model; F = (SSc / (k-1)) / (SSe / ((n-1)(k-1))). Effects: partial
        % eta^2 = SSc / (SSc + SSe) and generalized eta^2 = SSc / (SSc + SSs
        % + SSe) (Olejnik & Algina 2003; Bakeman 2005). r.sphericity (see
        % sphericity) adds the Greenhouse-Geisser / Huynh-Feldt corrected df
        % and p; r.stat, r.df and r.p are the Greenhouse-Geisser corrected
        % values when Mauchly's p < 0.05 (or Mauchly's test cannot be
        % computed because n < k), otherwise the uncorrected ones. r.table:
        % SS, df, MS, F and the uncorrected p. Post hoc: paired t-tests on
        % every pair (differences B - A), Holm-adjusted p, unadjusted 95% CI
        % of the mean difference, d_z with its exact 95% CI.
        function r = rmAnova(Y, names)
            if nargin < 2, names = []; end
            [Y, names, nExc] = GroupStats.toMatrix(Y, names);
            [n, k] = size(Y);
            if k < 2
                error('NeuroAnalyzer:GroupStats:tooFewGroups', 'Repeated-measures ANOVA needs at least 2 conditions.');
            end
            if n < 2
                error('NeuroAnalyzer:GroupStats:tooFew', ...
                    'Repeated-measures ANOVA needs at least 2 subjects with a value in every condition (got %d).', n);
            end
            gm = mean(Y(:));
            cm = mean(Y, 1);
            sm = mean(Y, 2);
            SSc = n * sum((cm - gm).^2);
            SSs = k * sum((sm - gm).^2);
            E = Y - repmat(sm, 1, k) - repmat(cm, n, 1) + gm;
            SSe = sum(E(:).^2);
            df1 = k - 1; df2 = (n - 1) * (k - 1);
            MSc = SSc / df1; MSe = SSe / df2;
            if MSe > 1e-12 * max(1, MSc)
                F = MSc / MSe;
                p = GroupStats.fUpper(F, df1, df2);
            elseif MSc > 0
                F = Inf; p = 0;
            else
                F = NaN; p = 1;
            end
            sph = GroupStats.sphericity(Y);
            sph.dfGG = [df1 df2] * sph.epsGG;
            sph.dfHF = [df1 df2] * sph.epsHF;
            sph.pUncorrected = p;
            sph.pGG = GroupStats.fUpperSafe(F, sph.dfGG(1), sph.dfGG(2), p);
            sph.pHF = GroupStats.fUpperSafe(F, sph.dfHF(1), sph.dfHF(2), p);
            if k >= 3 && (~sph.testable || sph.p < 0.05)
                sph.correction = 'Greenhouse-Geisser';
            else
                sph.correction = 'none';
            end
            r = GroupStats.emptyResult('Repeated-measures ANOVA', 'F');
            r.stat = F;
            if strcmp(sph.correction, 'none')
                r.df = [df1 df2]; r.p = p;
                r.method = 'F distribution, sphericity assumed';
            else
                r.df = sph.dfGG; r.p = sph.pGG;
                r.method = sprintf('F distribution, Greenhouse-Geisser corrected (ε = %.3f)', sph.epsGG);
            end
            r.n = repmat(n, 1, k); r.nExcluded = repmat(nExc, 1, k);
            r.effectName = 'partial η²';
            r.effect = GroupStats.safeDivide(SSc, SSc + SSe);
            r.effect2Name = 'generalized η²';
            r.effect2 = GroupStats.safeDivide(SSc, SSc + SSs + SSe);
            r.groupNames = names;
            r.means = cm;
            r.table = struct('SSc', SSc, 'SSs', SSs, 'SSe', SSe, 'SSt', SSc + SSs + SSe, ...
                'dfc', df1, 'dfs', n - 1, 'dfe', df2, 'MSc', MSc, 'MSe', MSe, 'F', F, 'p', p);
            r.sphericity = sph;
            r.posthoc = GroupStats.pairwisePaired(Y, names, 'ttest');
            r.note = ['Post hoc: paired t-tests on every pair, Holm-adjusted p (95% CIs of the ' ...
                'differences unadjusted); d_z with an exact 95% CI.'];
        end

        %% friedman - Friedman test (rank-based one-way repeated measures)
        % Y / names as in rmAnova. Values are ranked within each subject
        % (ties: average ranks); chi2 = 12 / (n k (k+1)) sum_j R_j^2 -
        % 3 n (k+1), divided by the tie correction 1 - sum(t^3 - t) /
        % (n (k^3 - k)); p from the chi-square distribution with k - 1 df.
        % Effect: Kendall's W = chi2 / (n (k - 1)). Post hoc: Wilcoxon
        % signed-rank tests on every pair (median of the differences B - A),
        % Holm-adjusted p.
        function r = friedman(Y, names)
            if nargin < 2, names = []; end
            [Y, names, nExc] = GroupStats.toMatrix(Y, names);
            [n, k] = size(Y);
            if k < 2 || n < 2
                error('NeuroAnalyzer:GroupStats:tooFew', ...
                    'The Friedman test needs at least 2 conditions and 2 complete subjects (got %d subjects).', n);
            end
            R = zeros(n, k);
            tieSum = 0;
            for i = 1:n
                [rk, ties] = GroupStats.tiedRank(Y(i, :));
                R(i, :) = rk';
                tieSum = tieSum + sum(ties.^3 - ties);
            end
            Rj = sum(R, 1);
            chi2 = 12 / (n * k * (k + 1)) * sum(Rj.^2) - 3 * n * (k + 1);
            C = 1 - tieSum / (n * (k^3 - k));
            if C > 0, chi2 = max(chi2, 0) / C; else, chi2 = 0; end
            r = GroupStats.emptyResult('Friedman test', 'χ²');
            r.stat = chi2; r.df = k - 1;
            r.p = GroupStats.chi2Upper(chi2, k - 1);
            r.n = repmat(n, 1, k); r.nExcluded = repmat(nExc, 1, k);
            r.effectName = 'Kendall''s W';
            r.effect = chi2 / (n * (k - 1));
            r.method = 'chi-square approximation (tie correction)';
            r.groupNames = names;
            r.means = mean(Y, 1);
            r.table = struct('rankSums', Rj, 'meanRanks', Rj / n, 'tieCorrection', C);
            r.posthoc = GroupStats.pairwisePaired(Y, names, 'wilcoxon');
            r.note = 'Post hoc: Wilcoxon signed-rank tests on every pair, Holm-adjusted p.';
        end

        %% sphericity - Mauchly's test and the epsilon estimates for Y (n x k)
        % With C a k x (k-1) orthonormal contrast matrix (normalized
        % Helmert) and S the covariance of the columns of Y, M = C' S C
        % (p = k - 1): Mauchly's W = det(M) / (tr(M) / p)^p, chi2 = -(n - 1 -
        % (2p^2 + p + 2) / (6p)) ln W with p(p+1)/2 - 1 df (Mauchly 1940);
        % epsGG = tr(M)^2 / (p tr(M^2)) (Greenhouse & Geisser 1959); epsHF =
        % (n p epsGG - 2) / (p (n - 1 - p epsGG)) (Huynh & Feldt 1976),
        % limited to [1/p, 1]; epsLB = 1/p (lower bound). Mauchly's test
        % needs k >= 3 and n > k - 1 (testable = false otherwise; W, chi2, p
        % NaN). With k = 2 every epsilon is 1 (sphericity always holds).
        % The p-value is the first-order chi-square approximation; some
        % packages add a second-order term, which changes p slightly for
        % k >= 4 (the term is zero for k = 3).
        function s = sphericity(Y)
            [n, k] = size(Y);
            p = k - 1;
            s = struct('W', NaN, 'chi2', NaN, 'df', NaN, 'p', NaN, 'testable', false, ...
                'epsGG', 1, 'epsHF', 1, 'epsLB', 1 / max(p, 1), 'note', '');
            if p < 1, return; end
            if p == 1
                s.note = 'Two conditions: sphericity holds by definition.';
                return;
            end
            C = zeros(k, p);
            for j = 1:p
                C(1:j, j) = 1;
                C(j + 1, j) = -j;
                C(:, j) = C(:, j) / sqrt(j * (j + 1));
            end
            M = C' * cov(Y) * C;
            M = (M + M') / 2;
            trM = trace(M);
            trM2 = trace(M * M);
            if trM2 > 0
                s.epsGG = min(1, max(1 / p, trM^2 / (p * trM2)));
                den = p * (n - 1 - p * s.epsGG);
                if den > 0
                    s.epsHF = min(1, max(1 / p, (n * p * s.epsGG - 2) / den));
                else
                    s.epsHF = 1;
                end
            end
            s.df = p * (p + 1) / 2 - 1;
            if n - 1 < p || ~(trM > 0)
                s.note = sprintf(['Mauchly''s test needs more subjects than conditions minus one ' ...
                    '(n = %d, k = %d) and some variation in the differences.'], n, k);
                return;
            end
            s.testable = true;
            s.W = max(0, det(M) / (trM / p)^p);
            f = (n - 1) - (2 * p^2 + p + 2) / (6 * p);
            if s.W > 0
                s.chi2 = max(0, -f * log(s.W));
                s.p = GroupStats.chi2Upper(s.chi2, s.df);
            else
                s.chi2 = Inf; s.p = 0;
            end
        end

        %% shapiroWilk - Shapiro-Wilk test of normality (Royston 1992/1995, AS R94)
        % x: values (non-finite ignored), 3 to 5000 of them. Coefficients
        % from Royston's approximation of the expected normal order
        % statistics; p from his normalising transformations (exact for
        % n = 3). r: W, p, n (p NaN and W NaN when n < 3 or all values are
        % equal).
        function r = shapiroWilk(x)
            x = double(x(:));
            x = sort(x(isfinite(x)));
            n = numel(x);
            r = struct('W', NaN, 'p', NaN, 'n', n);
            if n < 3 || n > 5000 || x(end) - x(1) <= 1e-12 * max(1, abs(x(end))), return; end
            if n == 3
                a = [-sqrt(0.5); 0; sqrt(0.5)];
            else
                m = GroupStats.norminv(((1:n)' - 0.375) / (n + 0.25));
                mm = sum(m.^2);
                u = 1 / sqrt(n);
                c = m / sqrt(mm);
                an = c(n) + polyval([-2.706056 4.434685 -2.071190 -0.147981 0.221157 0], u);
                a = zeros(n, 1);
                if n > 5
                    an1 = c(n - 1) + polyval([-3.582633 5.682633 -1.752461 -0.293762 0.042981 0], u);
                    phi = (mm - 2 * m(n)^2 - 2 * m(n - 1)^2) / (1 - 2 * an^2 - 2 * an1^2);
                    a(3:n - 2) = m(3:n - 2) / sqrt(phi);
                    a([1 2 n - 1 n]) = [-an; -an1; an1; an];
                else
                    phi = (mm - 2 * m(n)^2) / (1 - 2 * an^2);
                    a(2:n - 1) = m(2:n - 1) / sqrt(phi);
                    a([1 n]) = [-an; an];
                end
            end
            ss = sum((x - mean(x)).^2);
            W = min(1, (a' * x)^2 / ss);
            r.W = W;
            if n == 3
                p = 6 / pi * (asin(sqrt(W)) - asin(sqrt(0.75)));
            elseif n <= 11
                g = -2.273 + 0.459 * n;
                mu = 0.5440 - 0.39978 * n + 0.025054 * n^2 - 0.0006714 * n^3;
                sg = exp(1.3822 - 0.77857 * n + 0.062767 * n^2 - 0.0020322 * n^3);
                z = (-log(g - log(1 - W)) - mu) / sg;
                p = 1 - GroupStats.normcdf(z);
            else
                L = log(n);
                mu = -1.5861 - 0.31082 * L - 0.083751 * L^2 + 0.0038915 * L^3;
                sg = exp(-0.4803 - 0.082676 * L + 0.0030302 * L^2);
                z = (log(1 - W) - mu) / sg;
                p = 1 - GroupStats.normcdf(z);
            end
            if W >= 1, p = 1; end
            r.p = min(1, max(0, p));
        end

        %% cohensD - Standardized mean difference with the pooled SD
        function d = cohensD(a, b)
            a = double(a(isfinite(a(:)))); b = double(b(isfinite(b(:))));
            na = numel(a); nb = numel(b);
            sp = sqrt(((na - 1) * var(a) + (nb - 1) * var(b)) / (na + nb - 2));
            d = GroupStats.safeDivide(mean(a) - mean(b), sp);
        end

        %% hedgesG - Cohen's d times the exact small-sample correction J(df)
        % J(m) = Gamma(m/2) / (sqrt(m/2) Gamma((m-1)/2)), m = na + nb - 2
        % (approximately 1 - 3 / (4m - 1)).
        function g = hedgesG(a, b)
            a = a(isfinite(a(:))); b = b(isfinite(b(:)));
            m = numel(a) + numel(b) - 2;
            g = GroupStats.cohensD(a, b) * GroupStats.hedgesJ(m);
        end

        %% hedgesJ - Exact small-sample bias correction factor for d
        function J = hedgesJ(m)
            J = exp(gammaln(m / 2) - gammaln((m - 1) / 2)) ./ sqrt(m / 2);
        end

        %% dz - Paired standardized difference mean(a - b) / SD(a - b)
        function d = dz(a, b)
            a = double(a(:)); b = double(b(:));
            keep = isfinite(a) & isfinite(b);
            x = a(keep) - b(keep);
            d = GroupStats.safeDivide(mean(x), std(x));
        end

        %% dzCI - Exact 95% CI of d_z for n pairs (noncentral t inversion)
        % t = d sqrt(n) follows a noncentral t with n - 1 df and
        % noncentrality delta sqrt(n); the limits are the deltas for which
        % the observed t is the 97.5th and the 2.5th percentile.
        function ci = dzCI(d, n)
            ci = [NaN NaN];
            if ~isfinite(d) || n < 2, return; end
            df = n - 1;
            t = d * sqrt(n);
            ci = [GroupStats.nctDelta(t, df, 0.975), GroupStats.nctDelta(t, df, 0.025)] / sqrt(n);
        end

        %% compare - Test for a design, robustness check, descriptives and summary
        % values: cell of vectors (one per group, same order as names).
        % design: 'paired' (2 groups; the k-th values of A and B belong to
        % the same subject), 'unpaired' (2 independent groups) or 'anova'
        % (2+ independent groups) or 'rm' (repeated measures: 2+ groups
        % holding the same subjects, the k-th value of every group from
        % subject k; also 'repeated'; subjects with a non-finite value in
        % any group are excluded). method: 'parametric' (default) or
        % 'nonparametric'. Two-group differences are B - A.
        % Output fields: design, method, groupNames, values (as analysed),
        % nExcluded (non-finite values per group; pairs for 'paired'), desc
        % (describe per group), main, check (the other family), checkAgrees,
        % (for 'rm' the parametric result has main/check.sphericity),
        % comparisons (struct array: a, b, label, diff, ci, stat, p, method;
        % for 'rm' also pRaw (unadjusted p), effectName, effect, effectCI),
        % assumptions, summary.
        function res = compare(values, names, design, method)
            if nargin < 4 || isempty(method), method = 'parametric'; end
            if ~iscell(values), error('NeuroAnalyzer:GroupStats:input', 'values must be a cell array (one vector per group).'); end
            k = numel(values);
            if nargin < 2 || isempty(names)
                names = arrayfun(@(i) sprintf('Group %d', i), 1:k, 'UniformOutput', false);
            end
            names = cellstr(names);
            names = names(:)';
            design = lower(char(design));
            if any(strcmp(design, {'repeated', 'repeated measures', 'repeated-measures', 'rmanova'}))
                design = 'rm';
            end
            method = lower(char(method));
            isNonPar = strncmp(method, 'non', 3);
            vals = cellfun(@(v) double(v(:)), values, 'UniformOutput', false);
            res = struct('design', design, 'method', method, 'groupNames', {names}, ...
                'values', {vals}, 'nExcluded', zeros(1, k), 'desc', [], 'main', [], 'check', [], ...
                'checkAgrees', true, 'comparisons', [], 'assumptions', '', 'summary', '');
            switch design
                case 'paired'
                    if k ~= 2
                        error('NeuroAnalyzer:GroupStats:design', ...
                            'The paired design compares exactly 2 groups (got %d).', k);
                    end
                    if numel(vals{1}) ~= numel(vals{2})
                        error('NeuroAnalyzer:GroupStats:pairedLength', ...
                            ['The paired design needs the same number of subjects in both groups ' ...
                             '(%s: %d, %s: %d). Subjects are matched by order: the 1st of %s with ' ...
                             'the 1st of %s, and so on.'], names{1}, numel(vals{1}), names{2}, ...
                            numel(vals{2}), names{1}, names{2});
                    end
                    keep = isfinite(vals{1}) & isfinite(vals{2});
                    vals = {vals{1}(keep), vals{2}(keep)};
                    res.values = vals;
                    res.nExcluded = [sum(~keep) sum(~keep)];
                    par = GroupStats.ttestPaired(vals{2}, vals{1});
                    npar = GroupStats.wilcoxonSignedRank(vals{2}, vals{1});
                case 'unpaired'
                    if k ~= 2
                        error('NeuroAnalyzer:GroupStats:design', ...
                            'The unpaired design compares exactly 2 groups (got %d); use ANOVA for more.', k);
                    end
                    res.nExcluded = cellfun(@(v) sum(~isfinite(v)), vals);
                    vals = cellfun(@(v) v(isfinite(v)), vals, 'UniformOutput', false);
                    res.values = vals;
                    par = GroupStats.ttestWelch(vals{2}, vals{1});
                    npar = GroupStats.mannWhitney(vals{2}, vals{1});
                case 'anova'
                    if k < 2
                        error('NeuroAnalyzer:GroupStats:design', 'ANOVA needs at least 2 groups.');
                    end
                    res.nExcluded = cellfun(@(v) sum(~isfinite(v)), vals);
                    vals = cellfun(@(v) v(isfinite(v)), vals, 'UniformOutput', false);
                    res.values = vals;
                    par = GroupStats.anova1way(vals, names);
                    npar = GroupStats.kruskalWallis(vals, names);
                case 'rm'
                    if k < 2
                        error('NeuroAnalyzer:GroupStats:design', ...
                            'Repeated measures need at least 2 groups (conditions).');
                    end
                    [Y, ~, nExc] = GroupStats.toMatrix(vals, names);
                    vals = num2cell(Y, 1);
                    res.values = vals;
                    res.nExcluded = repmat(nExc, 1, k);
                    par = GroupStats.rmAnova(Y, names);
                    npar = GroupStats.friedman(Y, names);
                otherwise
                    error('NeuroAnalyzer:GroupStats:design', ...
                        'Unknown design ''%s'' (use paired, unpaired, anova or rm).', design);
            end
            if isNonPar
                res.main = npar; res.check = par;
            else
                res.main = par; res.check = npar;
            end
            desc = cellfun(@GroupStats.describe, vals, 'UniformOutput', false);
            res.desc = [desc{:}];
            % Robustness check agrees: same verdict at 5%, and (two groups,
            % both significant) the same direction
            sigMain = res.main.p < 0.05;
            sigCheck = res.check.p < 0.05;
            res.checkAgrees = sigMain == sigCheck;
            % Pairwise comparisons: the post-hoc list, or the single B - A
            if any(strcmp(design, {'anova', 'rm'}))
                res.comparisons = res.main.posthoc;
            else
                if isNonPar
                    diffVal = res.main.medianDiff; ci = [NaN NaN];
                else
                    diffVal = res.main.meanDiff; ci = res.main.ci;
                end
                res.comparisons = struct('a', names{1}, 'b', names{2}, ...
                    'label', sprintf('%s − %s', names{2}, names{1}), 'diff', diffVal, ...
                    'ci', ci, 'stat', res.main.stat, 'p', res.main.p, 'method', res.main.test);
                if sigMain && sigCheck
                    res.checkAgrees = sign(res.main.effect) == sign(res.check.effect);
                end
            end
            res.assumptions = GroupStats.assumptionNote(design, isNonPar, res);
            res.summary = GroupStats.summaryLine(res);
        end

        %% checkOptions - Settings of GroupStats.checks
        % subjectMode  'meantrace' | 'meanvalues' (one value per file) |
        %              'series' (every series counted as a subject)
        % nFiles       files behind each group (1 x k; [] = not known)
        % labels       {} | one cellstr of subject names per group (as in
        %              res.labels: the subjects analysed)
        function o = checkOptions()
            o = struct('subjectMode', 'meantrace', 'nFiles', [], 'labels', {{}});
        end

        %% checks - Quality checks of a comparison (QualityChecks rows)
        % res: GroupStats.compare output. Rows:
        %   Sample size   Warning: every series counted as a subject
        %                 (series of one animal are not independent), fewer
        %                 than 3 subjects in a group, or a rank-based test
        %                 that cannot reach p < 0.05 with these n (exact
        %                 Wilcoxon: 2 / 2^n; Mann-Whitney: 2 / C(m+n, m));
        %                 Check: fewer than SmallN (8) in a group.
        %   Normality     Shapiro-Wilk on what the parametric test assumes
        %                 normal: the paired differences, each group, or the
        %                 residuals of subjects x conditions (repeated
        %                 measures). Check at p < 0.05 with a parametric
        %                 result, Warning when the rank-based test also
        %                 disagrees; OK for a rank-based result. Names the
        %                 most extreme subject (> 3.5 robust SDs).
        %   Sphericity    repeated measures, parametric, 3+ conditions:
        %                 Check when Mauchly's test rejects it (the
        %                 Greenhouse-Geisser p is reported) or cannot be
        %                 computed; Warning when the uncorrected p is reported but the
        %                 corrected one changes the verdict at 5%.
        %   Equal spread  ANOVA, parametric: Check when the largest SD is
        %                 more than twice the smallest, Warning when the
        %                 group sizes also differ by more than 1.5 times.
        %   Robustness check  Check when the parametric and the rank-based
        %                 tests disagree at 5%.
        %   Missing values    Check when subjects were left out (NaN).
        function Q = checks(res, o)
            if nargin < 2 || isempty(o), o = GroupStats.checkOptions(); end
            d = GroupStats.checkOptions();
            f = fieldnames(d);
            for i = 1:numel(f)
                if ~isfield(o, f{i}), o.(f{i}) = d.(f{i}); end
            end
            if isempty(o.labels) && isfield(res, 'labels'), o.labels = res.labels; end
            Q = QualityChecks.none();
            if ~isstruct(res) || ~isfield(res, 'main') || isempty(res.main), return; end
            Q = GroupStats.checkN(Q, res, o);
            Q = GroupStats.checkNormality(Q, res, o);
            Q = GroupStats.checkSphericity(Q, res);
            Q = GroupStats.checkSpread(Q, res);
            isNonPar = strncmp(res.method, 'non', 3);
            if res.checkAgrees
                Q = QualityChecks.add(Q, 'ok', 'Robustness check', sprintf(['The %s and the %s agree ' ...
                    '(%s and %s).'], GroupStats.familyName(~isNonPar), GroupStats.familyName(isNonPar), ...
                    GroupStats.formatP(res.main.p), GroupStats.formatP(res.check.p)));
            else
                Q = QualityChecks.add(Q, 'check', 'Robustness check', sprintf(['%s gives %s but %s gives ' ...
                    '%s: the verdict depends on the test.'], res.main.test, GroupStats.formatP(res.main.p), ...
                    res.check.test, GroupStats.formatP(res.check.p)), ...
                    ['A result that only one family of tests supports usually rests on one or two ' ...
                    'subjects or on the shape of the values.'], ...
                    'Look at the Plot tab for an outlying animal; report both tests, or the rank-based one.');
            end
            nExc = max(res.nExcluded);
            if any(res.nExcluded > 0)
                if any(strcmp(res.design, {'paired', 'rm'}))
                    txt = sprintf('%s left out: the feature could not be computed in at least one condition.', ...
                        GroupStats.plural(nExc, 'subject'));
                else
                    txt = sprintf('%s left out: the feature could not be computed (NaN).', ...
                        GroupStats.plural(sum(res.nExcluded), 'value'));
                end
                Q = QualityChecks.add(Q, 'check', 'Missing values', txt, ...
                    'Subjects left out lower n; when the feature fails for a reason (no response), leaving them out biases the result.', ...
                    'Open those files in the Single file tab and look at why the feature is missing.');
            end
        end

        %% ----- Distributions ---------------------------------------------

        %% normcdf - Standard normal CDF
        function P = normcdf(z)
            P = 0.5 * erfc(-z / sqrt(2));
        end

        %% norminv - Standard normal quantile
        function z = norminv(P)
            z = -sqrt(2) * erfcinv(2 * P);
        end

        %% tcdf - Student t CDF, P(T <= t) (df may be Inf)
        function P = tcdf(t, df)
            if isinf(df), P = GroupStats.normcdf(t); return; end
            tail = 0.5 * betainc(df ./ (df + t.^2), df / 2, 0.5);   % P(T > |t|)
            P = tail;
            P(t > 0) = 1 - tail(t > 0);
        end

        %% pT2 - Two-sided p-value P(|T| >= |t|) for a t statistic
        function p = pT2(t, df)
            if isinf(df)
                p = erfc(abs(t) / sqrt(2));
            else
                p = betainc(df ./ (df + t.^2), df / 2, 0.5);
            end
        end

        %% tinv - Student t quantile (df may be Inf)
        function t = tinv(P, df)
            t = NaN(size(P));
            for i = 1:numel(P)
                p = P(i);
                if isinf(df)
                    t(i) = GroupStats.norminv(p);
                elseif p <= 0
                    t(i) = -Inf;
                elseif p >= 1
                    t(i) = Inf;
                elseif p == 0.5
                    t(i) = 0;
                else
                    x = betaincinv(2 * min(p, 1 - p), df / 2, 0.5);   % x = df / (df + t^2)
                    t(i) = sign(p - 0.5) * sqrt(df * (1 - x) / x);
                end
            end
        end

        %% fUpper - Upper tail P(F > f) of the F(d1, d2) distribution
        function p = fUpper(F, d1, d2)
            p = ones(size(F));
            pos = F > 0;
            p(pos) = betainc(d2 ./ (d2 + d1 .* F(pos)), d2 / 2, d1 / 2);
            p(isinf(F)) = 0;
            p(isnan(F)) = NaN;
        end

        %% chi2Upper - Upper tail P(X > x) of the chi-square distribution
        function p = chi2Upper(x, k)
            p = ones(size(x));
            pos = x > 0;
            p(pos) = gammainc(x(pos) / 2, k / 2, 'upper');
        end

        %% nctcdf - Noncentral t CDF P(T <= t) for df and noncentrality delta
        % T = (Z + delta) / s, s = sqrt(chi2_df / df): P = int f_s(s)
        % Phi(t s - delta) ds (Simpson on the grid of ptukey); df may be Inf.
        function P = nctcdf(t, df, delta)
            P = zeros(size(t));
            if isinf(df) || df > 2e5
                P = GroupStats.normcdf(t - delta);
                return;
            end
            [s, wts] = GroupStats.chiGrid(df);
            for i = 1:numel(t)
                P(i) = sum(wts .* GroupStats.normcdf(t(i) * s - delta));
            end
            P = min(max(P, 0), 1);
        end

        %% ptukey - CDF of the studentized range Q for k means and df error df
        % P(Q <= q); df may be Inf. See the header for the integral.
        function P = ptukey(q, k, df)
            P = zeros(size(q));
            for i = 1:numel(q)
                P(i) = GroupStats.ptukey1(q(i), k, df);
            end
        end

        %% qtukey - Quantile of the studentized range: ptukey(q, k, df) = p
        function q = qtukey(p, k, df)
            f = @(x) GroupStats.ptukey1(x, k, df) - p;
            hi = 4;
            while f(hi) < 0 && hi < 1e4, hi = 2 * hi; end
            q = fzero(f, [0 hi], optimset('TolX', 1e-10));
        end

        %% holm - Holm-Bonferroni step-down adjusted p-values (same shape as p)
        function pAdj = holm(p)
            sz = size(p);
            p = p(:);
            m = numel(p);
            [ps, idx] = sort(p);
            adj = min(1, cummax((m - (1:m)' + 1) .* ps));
            pAdj = zeros(m, 1);
            pAdj(idx) = adj;
            pAdj = reshape(pAdj, sz);
        end

        %% tiedRank - Ranks 1..n with ties given their average rank
        % ties: sizes of the tie groups (only groups of 2 or more).
        function [r, ties] = tiedRank(x)
            x = x(:);
            n = numel(x);
            [xs, idx] = sort(x);
            r = zeros(n, 1);
            ties = zeros(0, 1);
            i = 1;
            while i <= n
                j = i;
                while j < n && xs(j + 1) == xs(i), j = j + 1; end
                r(idx(i:j)) = (i + j) / 2;
                if j > i, ties(end + 1, 1) = j - i + 1; end %#ok<AGROW>
                i = j + 1;
            end
        end

        %% formatP - p-value as text: 'p = 0.012', 'p = 0.0004', 'p < 0.0001'
        function s = formatP(p)
            if isnan(p)
                s = 'p = n/a';
            elseif p < 1e-4
                s = 'p < 0.0001';
            elseif p < 0.001
                s = sprintf('p = %.4f', p);
            else
                s = sprintf('p = %.3f', p);
            end
        end

        %% dfText - df for display: integer as '%d', otherwise 3 significant digits
        function s = dfText(df)
            if abs(df - round(df)) < 1e-9
                s = sprintf('%d', round(df));
            else
                s = sprintf('%.3g', df);
            end
        end

        %% statText - Statistic with its df, e.g. 't(7) = 8.96', 'F(2, 21) = 11.8', 'U = 12'
        % Non-integer ANOVA df (Greenhouse-Geisser) as 3 significant digits: 'F(1.62, 11.3) = 45.2'.
        function s = statText(r)
            if numel(r.df) == 2
                dfTxt = sprintf('%s, %s', GroupStats.dfText(r.df(1)), GroupStats.dfText(r.df(2)));
            elseif isempty(r.df) || isnan(r.df)
                dfTxt = '';
            elseif abs(r.df - round(r.df)) < 1e-9
                dfTxt = sprintf('%d', round(r.df));
            else
                dfTxt = sprintf('%.1f', r.df);
            end
            if isempty(dfTxt)
                s = sprintf('%s = %.4g', r.statName, r.stat);
            else
                s = sprintf('%s(%s) = %.3g', r.statName, dfTxt, r.stat);
            end
        end

        %% stars - Significance stars: *** p<0.001, ** p<0.01, * p<0.05, else 'n.s.'
        function s = stars(p)
            if p < 0.001, s = '***';
            elseif p < 0.01, s = '**';
            elseif p < 0.05, s = '*';
            else, s = 'n.s.';
            end
        end
    end

    methods(Static, Access = private)

        %% emptyResult - Result struct with every field present
        function r = emptyResult(testName, statName)
            r = struct('test', testName, 'statName', statName, 'stat', NaN, 'df', NaN, ...
                'p', NaN, 'n', [], 'nExcluded', [], 'meanDiff', NaN, 'medianDiff', NaN, ...
                'ci', [NaN NaN], 'effectName', '', 'effect', NaN, 'effect2Name', '', ...
                'effect2', NaN, 'method', '', 'note', '', 'z', NaN, 'groupNames', {{}}, ...
                'means', [], 'table', [], 'posthoc', []);
        end

        %% tFromDiff - t statistic and two-sided p (handles a zero standard error)
        function [t, p] = tFromDiff(md, se, df)
            if se > 0
                t = md / se;
                p = GroupStats.pT2(t, df);
            elseif md == 0
                t = 0; p = 1;
            else
                t = sign(md) * Inf; p = 0;
            end
        end

        %% safeDivide - a / b, NaN when both are zero
        function q = safeDivide(a, b)
            if b == 0 && a == 0
                q = NaN;
            else
                q = a / b;
            end
        end

        %% ifElse - Inline conditional for strings
        function out = ifElse(cond, a, b)
            if cond, out = a; else, out = b; end
        end

        %% toGroups - Cell of finite column vectors + names from either input style
        function [vals, names, nExc] = toGroups(values, groups)
            if iscell(values)
                vals = cellfun(@(v) double(v(:)), values(:)', 'UniformOutput', false);
                if isempty(groups)
                    names = arrayfun(@(i) sprintf('Group %d', i), 1:numel(vals), 'UniformOutput', false);
                else
                    names = cellstr(groups);
                    names = names(:)';
                end
            else
                values = double(values(:));
                if isnumeric(groups) || islogical(groups)
                    labels = arrayfun(@(g) sprintf('%g', g), groups(:), 'UniformOutput', false);
                else
                    labels = cellstr(groups);
                    labels = labels(:);
                end
                if numel(labels) ~= numel(values)
                    error('NeuroAnalyzer:GroupStats:input', 'values and groups must have the same length.');
                end
                % Groups in order of first appearance
                names = {};
                idx = zeros(numel(labels), 1);
                for i = 1:numel(labels)
                    j = find(strcmp(names, labels{i}), 1);
                    if isempty(j), names{end + 1} = labels{i}; j = numel(names); end %#ok<AGROW>
                    idx(i) = j;
                end
                vals = arrayfun(@(j) values(idx == j), 1:numel(names), 'UniformOutput', false);
            end
            nExc = cellfun(@(v) sum(~isfinite(v)), vals);
            vals = cellfun(@(v) v(isfinite(v)), vals, 'UniformOutput', false);
        end

        %% toMatrix - Complete-case subjects x conditions matrix from Y or a cell
        % nExc: number of subjects dropped for a non-finite value.
        function [Y, names, nExc] = toMatrix(Y, names)
            if iscell(Y)
                vals = cellfun(@(v) double(v(:)), Y(:)', 'UniformOutput', false);
                lens = cellfun(@numel, vals);
                if isempty(names)
                    names = arrayfun(@(i) sprintf('Group %d', i), 1:numel(vals), 'UniformOutput', false);
                end
                names = cellstr(names); names = names(:)';
                if any(lens ~= lens(1))
                    error('NeuroAnalyzer:GroupStats:rmLength', ...
                        ['Repeated measures need the same number of subjects in every condition ' ...
                         '(%s). Subjects are matched by order: the 1st value of every condition ' ...
                         'belongs to the same subject, and so on.'], GroupStats.nList(names, lens));
                end
                Y = [vals{:}];
            else
                Y = double(Y);
                if isempty(names)
                    names = arrayfun(@(i) sprintf('Group %d', i), 1:size(Y, 2), 'UniformOutput', false);
                end
                names = cellstr(names); names = names(:)';
            end
            if numel(names) ~= size(Y, 2)
                error('NeuroAnalyzer:GroupStats:input', 'Give one name per condition (column of Y).');
            end
            keep = all(isfinite(Y), 2);
            nExc = sum(~keep);
            Y = Y(keep, :);
        end

        %% pairwisePaired - Paired t or Wilcoxon on every pair of columns, Holm (B - A)
        function ph = pairwisePaired(Y, names, kind)
            k = size(Y, 2);
            ph = struct('a', {}, 'b', {}, 'label', {}, 'diff', {}, 'ci', {}, 'stat', {}, ...
                'p', {}, 'method', {}, 'pRaw', {}, 'effectName', {}, 'effect', {}, 'effectCI', {});
            for i = 1:k - 1
                for j = i + 1:k
                    if strcmp(kind, 'ttest')
                        t = GroupStats.ttestPaired(Y(:, j), Y(:, i));
                        d = t.meanDiff; ci = t.ci; m = 'paired t, Holm';
                        eName = 'd_z'; eci = GroupStats.dzCI(t.effect, size(Y, 1));
                    else
                        t = GroupStats.wilcoxonSignedRank(Y(:, j), Y(:, i));
                        d = t.medianDiff; ci = [NaN NaN]; m = 'Wilcoxon signed-rank, Holm';
                        eName = 'rank-biserial r'; eci = [NaN NaN];
                    end
                    ph(end + 1) = struct('a', names{i}, 'b', names{j}, ...
                        'label', sprintf('%s − %s', names{j}, names{i}), 'diff', d, ...
                        'ci', ci, 'stat', t.stat, 'p', t.p, 'method', m, 'pRaw', t.p, ...
                        'effectName', eName, 'effect', t.effect, 'effectCI', eci); %#ok<AGROW>
                end
            end
            if ~isempty(ph)
                pAdj = GroupStats.holm([ph.p]);
                for i = 1:numel(ph), ph(i).p = pAdj(i); end
            end
        end

        %% fUpperSafe - fUpper that returns pDefault when F is not finite
        function p = fUpperSafe(F, d1, d2, pDefault)
            if isfinite(F) && d1 > 0 && d2 > 0
                p = GroupStats.fUpper(F, d1, d2);
            else
                p = pDefault;
            end
        end

        %% chiGrid - Nodes s and Simpson weights (times the density of s =
        % sqrt(chi2_df / df)) so that int f_s(s) g(s) ds = sum(wts .* g(s))
        function [s, wts] = chiGrid(df)
            w = 15 * sqrt(2 * df);
            s = linspace(sqrt(max(df - w, 0) / df), sqrt((df + w + 30) / df), 2001);
            logf = log(2) + (df / 2) * log(df / 2) - gammaln(df / 2) + (df - 1) * log(s) - df * s.^2 / 2;
            f = exp(logf);
            if s(1) == 0
                if df == 1, f(1) = sqrt(2 / pi); else, f(1) = 0; end
            end
            wts = 2 * ones(size(s));
            wts(2:2:end - 1) = 4;
            wts([1 end]) = 1;
            wts = (s(2) - s(1)) / 3 * wts .* f;
        end

        %% nctDelta - Noncentrality delta with nctcdf(t, df, delta) = P
        % nctcdf decreases in delta: bracket around t, then fzero.
        function delta = nctDelta(t, df, P)
            f = @(dl) GroupStats.nctcdf(t, df, dl) - P;
            lo = t - 4; hi = t + 4;
            step = 4;
            while f(lo) < 0 && step < 1e4, step = 2 * step; lo = t - step; end
            step = 4;
            while f(hi) > 0 && step < 1e4, step = 2 * step; hi = t + step; end
            delta = fzero(f, [lo hi], optimset('TolX', 1e-10));
        end

        %% nList - 'A: 3, B: 4' for error messages
        function s = nList(names, n)
            parts = arrayfun(@(i) sprintf('%s: %d', names{i}, n(i)), 1:numel(n), 'UniformOutput', false);
            s = strjoin(parts, ', ');
        end

        %% tukeyKramer - All pairwise Tukey-Kramer comparisons (B - A)
        function ph = tukeyKramer(vals, names, MSW, dfW)
            k = numel(vals);
            qc = GroupStats.qtukey(0.95, k, dfW);
            ph = struct('a', {}, 'b', {}, 'label', {}, 'diff', {}, 'ci', {}, 'stat', {}, ...
                'p', {}, 'method', {});
            for i = 1:k - 1
                for j = i + 1:k
                    d = mean(vals{j}) - mean(vals{i});
                    se = sqrt(MSW / 2 * (1 / numel(vals{i}) + 1 / numel(vals{j})));
                    if se > 0
                        q = abs(d) / se;
                        p = min(1, max(0, 1 - GroupStats.ptukey1(q, k, dfW)));
                    elseif d ~= 0
                        q = Inf; p = 0;
                    else
                        q = 0; p = 1;
                    end
                    ph(end + 1) = struct('a', names{i}, 'b', names{j}, ...
                        'label', sprintf('%s − %s', names{j}, names{i}), 'diff', d, ...
                        'ci', d + [-1 1] * qc * se, 'stat', q, 'p', p, ...
                        'method', 'Tukey-Kramer'); %#ok<AGROW>
                end
            end
        end

        %% pairwise - All pairwise Welch or Mann-Whitney tests, Holm-adjusted (B - A)
        function ph = pairwise(vals, names, kind)
            k = numel(vals);
            ph = struct('a', {}, 'b', {}, 'label', {}, 'diff', {}, 'ci', {}, 'stat', {}, ...
                'p', {}, 'method', {});
            for i = 1:k - 1
                for j = i + 1:k
                    if strcmp(kind, 'welch')
                        t = GroupStats.ttestWelch(vals{j}, vals{i});
                        d = t.meanDiff; ci = t.ci; m = 'Welch t, Holm';
                    else
                        t = GroupStats.mannWhitney(vals{j}, vals{i});
                        d = t.medianDiff; ci = [NaN NaN]; m = 'Mann-Whitney, Holm';
                    end
                    ph(end + 1) = struct('a', names{i}, 'b', names{j}, ...
                        'label', sprintf('%s − %s', names{j}, names{i}), 'diff', d, ...
                        'ci', ci, 'stat', t.stat, 'p', t.p, 'method', m); %#ok<AGROW>
                end
            end
            if ~isempty(ph)
                pAdj = GroupStats.holm([ph.p]);
                for i = 1:numel(ph), ph(i).p = pAdj(i); end
            end
        end

        %% signedRankCounts - Number of sign patterns giving W+ = 0..n(n+1)/2
        function c = signedRankCounts(n)
            c = 1;
            for i = 1:n
                c = [c, zeros(1, i)] + [zeros(1, i), c];
            end
        end

        %% mannWhitneyPmf - Exact null distribution P(U = 0..m n) without ties
        % Recursion on the largest observation: it belongs to the first
        % sample with probability i/(i+j) (adding j to U), else to the second.
        function pmf = mannWhitneyPmf(m, n)
            prev = repmat({1}, 1, n + 1);
            for i = 1:m
                cur = cell(1, n + 1);
                cur{1} = 1;
                for j = 1:n
                    v = zeros(1, i * j + 1);
                    a = prev{j + 1};
                    v(j + (1:numel(a))) = (i / (i + j)) * a;
                    b = cur{j};
                    v(1:numel(b)) = v(1:numel(b)) + (j / (i + j)) * b;
                    cur{j + 1} = v;
                end
                prev = cur;
            end
            pmf = prev{n + 1};
        end

        %% ptukey1 - Studentized range CDF for one q
        function P = ptukey1(q, k, df)
            if isnan(q), P = NaN; return; end
            if q <= 0, P = 0; return; end
            if isinf(q), P = 1; return; end
            if isinf(df) || df > 2e5
                P = GroupStats.rangeCdf(q, k);
                return;
            end
            % Density of s = sqrt(chi2_df / df) on the range holding its mass
            w = 15 * sqrt(2 * df);
            s = linspace(sqrt(max(df - w, 0) / df), sqrt((df + w + 30) / df), 1201);
            logf = log(2) + (df / 2) * log(df / 2) - gammaln(df / 2) + (df - 1) * log(s) - df * s.^2 / 2;
            f = exp(logf);
            if s(1) == 0
                if df == 1, f(1) = sqrt(2 / pi); else, f(1) = 0; end
            end
            % Simpson's rule (odd number of points): the integrand has a
            % non-zero slope at s = 0 for df = 1, where trapz is only O(h^2)
            wts = 2 * ones(size(s));
            wts(2:2:end - 1) = 4;
            wts([1 end]) = 1;
            P = (s(2) - s(1)) / 3 * sum(wts .* f .* GroupStats.rangeCdf(q * s, k));
            P = min(max(P, 0), 1);
        end

        %% rangeCdf - P(range of k iid standard normals <= w), vector w
        function R = rangeCdf(w, k)
            w = w(:);
            z = -8.5:0.025:8.5;
            phi = exp(-z.^2 / 2) / sqrt(2 * pi);
            D = GroupStats.normcdf(z) - GroupStats.normcdf(z - w);
            D(D < 0) = 0;
            R = k * trapz(z, phi .* D.^(k - 1), 2);
            R(w <= 0) = 0;
            R = min(R, 1);
            R = R(:)';
        end

        %% assumptionNote - Plain-language assumptions for the chosen test
        function s = assumptionNote(design, isNonPar, res)
            n = arrayfun(@(d) d.n, res.desc);
            sds = arrayfun(@(d) d.sd, res.desc);
            sdRatio = max(sds) / min(sds);
            parts = {};
            switch design
                case 'paired'
                    parts{end + 1} = sprintf(['Paired design: the k-th value of %s and of %s come from ' ...
                        'the same subject (matched by order); %d complete pair(s).'], ...
                        res.groupNames{1}, res.groupNames{2}, n(1));
                    if isNonPar
                        parts{end + 1} = ['Wilcoxon signed-rank: no normality assumption; assumes the ' ...
                            'differences are symmetric around their median.'];
                    else
                        parts{end + 1} = ['Paired t-test: assumes the paired differences are roughly ' ...
                            'normal (outliers matter most with few pairs).'];
                    end
                case 'unpaired'
                    parts{end + 1} = sprintf('Unpaired design: independent subjects in %s and %s.', ...
                        res.groupNames{1}, res.groupNames{2});
                    if isNonPar
                        parts{end + 1} = ['Mann-Whitney U: no normality assumption; tests whether values ' ...
                            'in one group tend to be larger (not specifically the means).'];
                    else
                        parts{end + 1} = sprintf(['Welch t-test: does not assume equal variances ' ...
                            '(SD ratio %.2g); assumes roughly normal values in each group.'], sdRatio);
                    end
                case 'rm'
                    parts{end + 1} = sprintf(['Repeated-measures design: the k-th value of every group ' ...
                        'comes from the same subject (matched by order); %d complete subject(s) in %d ' ...
                        'conditions.'], n(1), numel(n));
                    if isNonPar
                        parts{end + 1} = ['Friedman test: ranks within each subject, no normality or ' ...
                            'sphericity assumption; pairwise Wilcoxon signed-rank tests with Holm-Bonferroni ' ...
                            'correction.'];
                        rmPar = res.check;
                    else
                        parts{end + 1} = ['Repeated-measures ANOVA: assumes roughly normal residuals and ' ...
                            'sphericity (equal variances of all pairwise differences); pairwise paired ' ...
                            't-tests with Holm-Bonferroni correction.'];
                        rmPar = res.main;
                    end
                    parts{end + 1} = GroupStats.sphericityText(rmPar.sphericity, numel(n));
                otherwise
                    if isNonPar
                        parts{end + 1} = ['Kruskal-Wallis: independent groups, no normality assumption; ' ...
                            'pairwise Mann-Whitney tests with Holm-Bonferroni correction.'];
                    else
                        parts{end + 1} = sprintf(['One-way ANOVA: independent groups, roughly normal values ' ...
                            'and similar SDs (largest/smallest SD = %.2g%s); pairwise Tukey-Kramer ' ...
                            'comparisons (family-wise 95%%).'], sdRatio, ...
                            GroupStats.ifElse(sdRatio > 2, ', above 2: prefer the Kruskal-Wallis result', ''));
                    end
                    parts{end + 1} = ['If the same animals appear in every group, the groups are not ' ...
                        'independent: a repeated-measures analysis would be more appropriate.'];
            end
            if any(n < 10)
                parts{end + 1} = sprintf(['Small samples (n = %s): normality cannot be checked ' ...
                    'reliably; compare with the robustness check (%s, %s).'], ...
                    strjoin(arrayfun(@(x) sprintf('%d', x), n, 'UniformOutput', false), ', '), ...
                    res.check.test, GroupStats.formatP(res.check.p));
            end
            if ~res.checkAgrees
                parts{end + 1} = 'Note: the parametric and rank-based tests disagree; interpret with care.';
            end
            if strcmp(design, 'paired') && res.nExcluded(1) > 0
                parts{end + 1} = sprintf(['%d pair(s) excluded because the feature could not be ' ...
                    'computed (NaN) for one of the conditions.'], res.nExcluded(1));
            elseif strcmp(design, 'rm') && res.nExcluded(1) > 0
                parts{end + 1} = sprintf(['%d subject(s) excluded because the feature could not be ' ...
                    'computed (NaN) for at least one condition.'], res.nExcluded(1));
            elseif ~any(strcmp(design, {'paired', 'rm'})) && any(res.nExcluded > 0)
                parts{end + 1} = sprintf(['%d value(s) excluded because the feature could not be ' ...
                    'computed (NaN).'], sum(res.nExcluded));
            end
            s = strjoin(parts, ' ');
        end

        %% sphericityText - Mauchly's test and the corrections in plain language
        function s = sphericityText(sph, k)
            if k < 3
                s = 'Sphericity: holds by definition with two conditions (no correction needed).';
                return;
            end
            corr = sprintf(['Greenhouse-Geisser ε = %.3f (%s), Huynh-Feldt ε = %.3f (%s), ' ...
                'uncorrected %s.'], sph.epsGG, GroupStats.formatP(sph.pGG), sph.epsHF, ...
                GroupStats.formatP(sph.pHF), GroupStats.formatP(sph.pUncorrected));
            if ~sph.testable
                s = ['Sphericity: Mauchly''s test cannot be computed (fewer subjects than ' ...
                    'conditions); the Greenhouse-Geisser corrected p is reported. ' corr];
            elseif sph.p < 0.05
                s = sprintf(['Sphericity: violated (Mauchly''s W = %.3f, χ²(%d) = %.3g, %s); the ' ...
                    'Greenhouse-Geisser corrected p is reported. %s'], sph.W, round(sph.df), ...
                    sph.chi2, GroupStats.formatP(sph.p), corr);
            else
                s = sprintf(['Sphericity: not rejected (Mauchly''s W = %.3f, χ²(%d) = %.3g, %s); the ' ...
                    'uncorrected p is reported. Mauchly''s test has little power with few subjects: ' ...
                    'if the corrected p differs in verdict, report it. %s'], sph.W, round(sph.df), ...
                    sph.chi2, GroupStats.formatP(sph.p), corr);
            end
        end

        %% summaryLine - One-line, report-ready result
        function s = summaryLine(res)
            m = res.main;
            statTxt = GroupStats.statText(m);
            nTxt = strjoin(arrayfun(@(d) sprintf('%d', d.n), res.desc, 'UniformOutput', false), ', ');
            pTxt = GroupStats.formatP(m.p);
            if isfield(m, 'sphericity') && ~strcmp(m.sphericity.correction, 'none')
                pTxt = sprintf('%s (%s, ε = %.2f)', pTxt, m.sphericity.correction, m.sphericity.epsGG);
            end
            s = sprintf('%s: %s, %s; %s = %.2f', m.test, statTxt, pTxt, m.effectName, m.effect);
            if ~any(strcmp(res.design, {'anova', 'rm'}))
                c = res.comparisons(1);
                if all(isfinite(c.ci))
                    s = sprintf('%s; %s = %.3g [95%% CI %.3g, %.3g]', s, c.label, c.diff, c.ci(1), c.ci(2));
                else
                    s = sprintf('%s; median difference %s = %.3g', s, c.label, c.diff);
                end
            end
            if strcmp(res.design, 'paired')
                s = sprintf('%s; n = %d pairs.', s, res.desc(1).n);
            elseif strcmp(res.design, 'rm')
                s = sprintf('%s; n = %d subjects x %d conditions.', s, res.desc(1).n, numel(res.desc));
            else
                s = sprintf('%s; n = %s.', s, nTxt);
            end
        end

        %% checkN - Sample size: what a subject is, how many, what the tests can reach
        function Q = checkN(Q, res, o)
            n = arrayfun(@(x) x.n, res.desc);
            nTxt = strjoin(arrayfun(@(i) sprintf('%s %d', res.groupNames{i}, n(i)), 1:numel(n), ...
                'UniformOutput', false), ', ');
            if any(strcmp(res.design, {'paired', 'rm'}))
                nTxt = sprintf('%d subjects with a value in every condition', n(1));
            end
            if strcmp(o.subjectMode, 'series')
                files = '';
                if ~isempty(o.nFiles)
                    files = sprintf(' from %s', GroupStats.plural(sum(o.nFiles), 'file'));
                end
                Q = QualityChecks.add(Q, 'warning', 'Sample size', sprintf(['Every series is counted as a ' ...
                    'subject: n = %s%s.'], nTxt, files), ...
                    ['Trials or channels of one animal are not independent: counting them as subjects ' ...
                    'makes n far too large and p far too small (pseudoreplication). n is the number of ' ...
                    'animals.'], 'Set Subject to File (mean trace): one value per animal.');
                return;
            end
            nMin = min(n);
            pMin = GroupStats.smallestRankP(res, n);
            isNonPar = strncmp(res.method, 'non', 3);
            if nMin < 3
                Q = QualityChecks.add(Q, 'warning', 'Sample size', sprintf('n = %s.', nTxt), ...
                    'With fewer than 3 subjects in a group no test can tell an effect from chance.', ...
                    'Add animals before testing.');
            elseif isfinite(pMin) && pMin >= 0.05
                lvl = 'check';
                if isNonPar, lvl = 'warning'; end
                Q = QualityChecks.add(Q, lvl, 'Sample size', sprintf(['n = %s: the %s cannot give ' ...
                    'p below %.3g with these n, whatever the data.'], nTxt, res.(GroupStats.ifElse(isNonPar, ...
                    'main', 'check')).test, pMin), ...
                    'A rank-based test has a smallest possible p that depends only on n.', ...
                    'Add animals, or report the parametric result with its normality check.');
            elseif nMin < GroupStats.SmallN
                Q = QualityChecks.add(Q, 'check', 'Sample size', sprintf('n = %s (fewer than %d).', ...
                    nTxt, GroupStats.SmallN), ...
                    ['With few subjects one animal can change the verdict, and normality cannot be judged ' ...
                    'reliably.'], 'Look at every animal in the Plot tab; report n and the individual values.');
            else
                Q = QualityChecks.add(Q, 'ok', 'Sample size', sprintf('n = %s (one value per file).', nTxt));
            end
        end

        %% smallestRankP - Smallest two-sided p the exact rank test can give (NaN: not exact)
        function p = smallestRankP(res, n)
            p = NaN;
            switch res.design
                case 'paired'
                    if n(1) < 50, p = 2 / 2^n(1); end
                case 'unpaired'
                    if sum(n) < 50, p = 2 / nchoosek(sum(n), n(1)); end
            end
        end

        %% checkNormality - Shapiro-Wilk on what the parametric test assumes normal
        function Q = checkNormality(Q, res, o)
            isNonPar = strncmp(res.method, 'non', 3);
            names = res.groupNames;
            labels = o.labels;
            lab = @(j, i) GroupStats.subjectLabel(labels, j, i);
            switch res.design
                case 'paired'
                    sets = {res.values{2} - res.values{1}};
                    setNames = {sprintf('the differences %s − %s', names{2}, names{1})};
                    setLabels = {arrayfun(@(i) lab(2, i), 1:numel(sets{1}), 'UniformOutput', false)};
                    what = 'the paired differences';
                case 'rm'
                    Y = [res.values{:}];
                    E = Y - repmat(mean(Y, 2), 1, size(Y, 2)) - repmat(mean(Y, 1), size(Y, 1), 1) + mean(Y(:));
                    sets = {E(:)};
                    setNames = {'the residuals (each value minus its animal''s and its condition''s mean)'};
                    L = cell(size(E));
                    for j = 1:size(E, 2)
                        for i = 1:size(E, 1)
                            L{i, j} = sprintf('%s in %s', lab(j, i), names{j});
                        end
                    end
                    setLabels = {L(:)'};
                    what = 'the residuals';
                otherwise
                    sets = res.values;
                    setNames = names;
                    setLabels = arrayfun(@(j) arrayfun(@(i) lab(j, i), 1:numel(res.values{j}), ...
                        'UniformOutput', false), 1:numel(names), 'UniformOutput', false);
                    what = 'the values of each group';
            end
            worstP = Inf; parts = {}; tested = 0;
            out = '';
            for s = 1:numel(sets)
                r = GroupStats.shapiroWilk(sets{s});
                if ~isfinite(r.p), continue; end
                tested = tested + 1;
                if r.p < worstP
                    worstP = r.p;
                    out = GroupStats.outlierText(sets{s}, setLabels{s});
                end
                if r.p < 0.05
                    parts{end + 1} = sprintf('%s (W = %.3f, %s)', setNames{s}, r.W, GroupStats.formatP(r.p)); %#ok<AGROW>
                end
            end
            if tested == 0
                Q = QualityChecks.add(Q, 'note', 'Normality', sprintf(['Too few values to test %s for ' ...
                    'normality (Shapiro-Wilk needs 3).'], what));
                return;
            end
            nSmall = min(cellfun(@numel, sets)) < GroupStats.SmallN;
            if isempty(parts)
                txt = sprintf('Shapiro-Wilk does not reject normality of %s (%s%s)%s.', what, ...
                    GroupStats.ifElse(tested > 1, 'smallest ', ''), GroupStats.formatP(worstP), out);
                if nSmall
                    txt = [txt ' With few values it can miss a departure: look at the Plot tab.'];
                end
                if isNonPar
                    txt = [txt ' The rank-based test does not need it.'];
                end
                Q = QualityChecks.add(Q, 'ok', 'Normality', txt);
                return;
            end
            found = sprintf('Not normal: %s%s.', strjoin(parts, '; '), out);
            why = sprintf(['The %s assumes %s are roughly normal; one outlying animal or skewed values ' ...
                'can make its p too small or too large.'], GroupStats.familyName(true), what);
            if isNonPar
                Q = QualityChecks.add(Q, 'ok', 'Normality', [found ' The rank-based test reported does not ' ...
                    'need normality.']);
            elseif ~res.checkAgrees
                Q = QualityChecks.add(Q, 'warning', 'Normality', found, [why ' Here the rank-based ' ...
                    'test gives a different verdict.'], sprintf(['Report the rank-based result (%s, %s): ' ...
                    'set Method to Nonparametric.'], res.check.test, GroupStats.formatP(res.check.p)));
            else
                Q = QualityChecks.add(Q, 'check', 'Normality', found, why, sprintf(['The rank-based test ' ...
                    'agrees (%s, %s); report it alongside, or set Method to Nonparametric.'], ...
                    res.check.test, GroupStats.formatP(res.check.p)));
            end
        end

        %% outlierText - ' Most extreme: animal 6 (5.2 robust SDs from the median)' or ''
        function s = outlierText(x, labels)
            s = '';
            x = x(:);
            if numel(x) < 4, return; end
            med = median(x);
            mad = 1.4826 * median(abs(x - med));
            if ~(mad > 0), return; end
            [z, i] = max(abs(x - med) / mad);
            if z > 3.5
                nm = sprintf('value %d', i);
                if i <= numel(labels) && ~isempty(labels{i}), nm = labels{i}; end
                if z > 10
                    s = sprintf('; most extreme: %s, more than 10 robust SDs from the median', nm);
                else
                    s = sprintf('; most extreme: %s, %.1f robust SDs from the median', nm, z);
                end
            end
        end

        %% subjectLabel - Name of subject i of group j ('animal 3' when there are no labels)
        function s = subjectLabel(labels, j, i)
            s = sprintf('subject %d', i);
            if j <= numel(labels) && i <= numel(labels{j}) && ~isempty(labels{j}{i})
                s = char(labels{j}{i});
            end
        end

        %% checkSphericity - Repeated measures: Mauchly's test and the corrections
        function Q = checkSphericity(Q, res)
            if ~strcmp(res.design, 'rm'), return; end
            k = numel(res.groupNames);
            isNonPar = strncmp(res.method, 'non', 3);
            if k < 3
                Q = QualityChecks.add(Q, 'ok', 'Sphericity', 'Two conditions: sphericity holds by definition.');
                return;
            end
            if isNonPar
                Q = QualityChecks.add(Q, 'ok', 'Sphericity', sprintf(['The %s does not assume sphericity ' ...
                    '(it ranks within each animal).'], res.main.test));
                return;
            end
            s = res.main.sphericity;
            why = ['Repeated-measures ANOVA assumes that every pair of conditions differs by about ' ...
                'equally variable amounts across animals (sphericity); when not, its uncorrected p is ' ...
                'too small.'];
            corrTxt = sprintf('Greenhouse-Geisser ε = %.2f: corrected %s, uncorrected %s', s.epsGG, ...
                GroupStats.formatP(s.pGG), GroupStats.formatP(s.pUncorrected));
            sigU = s.pUncorrected < 0.05; sigGG = s.pGG < 0.05;
            if ~s.testable
                Q = QualityChecks.add(Q, 'check', 'Sphericity', sprintf(['Mauchly''s test cannot be computed ' ...
                    '(%d animals for %d conditions); the corrected p is reported (%s).'], res.desc(1).n, k, corrTxt), ...
                    why, 'Add animals: Mauchly''s test needs at least as many animals as conditions.');
            elseif s.p < 0.05
                Q = QualityChecks.add(Q, 'check', 'Sphericity', sprintf(['Violated (Mauchly''s W = %.3f, %s); ' ...
                    'the Greenhouse-Geisser corrected p is reported (%s).'], s.W, GroupStats.formatP(s.p), corrTxt), ...
                    why, ['Report the corrected p and ε; look at the Plot tab for a condition in which animals ' ...
                    'respond very differently (responders and non-responders).']);
            elseif sigU ~= sigGG
                Q = QualityChecks.add(Q, 'warning', 'Sphericity', sprintf(['Not rejected (Mauchly''s W = %.3f, ' ...
                    '%s), so the uncorrected p is reported, but the correction changes the verdict (%s).'], ...
                    s.W, GroupStats.formatP(s.p), corrTxt), [why ' With few animals Mauchly''s test ' ...
                    'rarely rejects.'], 'Report the corrected p.');
            else
                Q = QualityChecks.add(Q, 'ok', 'Sphericity', sprintf('Not rejected (Mauchly''s W = %.3f, %s; %s).', ...
                    s.W, GroupStats.formatP(s.p), corrTxt));
            end
        end

        %% checkSpread - ANOVA: similar SDs in every group
        function Q = checkSpread(Q, res)
            if strncmp(res.method, 'non', 3), return; end
            sds = arrayfun(@(x) x.sd, res.desc);
            n = arrayfun(@(x) x.n, res.desc);
            ratio = max(sds) / min(sds);
            if strcmp(res.design, 'unpaired')
                Q = QualityChecks.add(Q, 'ok', 'Equal spread', sprintf(['SD ratio %.2g: the Welch t-test ' ...
                    'does not assume equal SDs.'], ratio));
                return;
            end
            if ~strcmp(res.design, 'anova') || ~isfinite(ratio), return; end
            [~, iMax] = max(sds); [~, iMin] = min(sds);
            txt = sprintf('Largest / smallest SD = %.2g (%s %.3g, %s %.3g).', ratio, res.groupNames{iMax}, ...
                sds(iMax), res.groupNames{iMin}, sds(iMin));
            if ratio > 2
                lvl = 'check';
                if max(n) > 1.5 * min(n), lvl = 'warning'; txt = [txt ' The group sizes differ too.']; end
                Q = QualityChecks.add(Q, lvl, 'Equal spread', txt, ['One-way ANOVA and Tukey''s comparisons ' ...
                    'assume similar SDs; with unequal SDs (worse with unequal group sizes) their p-values ' ...
                    'are wrong.'], sprintf('Use the rank-based result (%s, %s), or compare pairs with Welch t-tests.', ...
                    res.check.test, GroupStats.formatP(res.check.p)));
            else
                Q = QualityChecks.add(Q, 'ok', 'Equal spread', txt);
            end
        end

        %% familyName - 'parametric test' | 'rank-based test'
        function s = familyName(isParametric)
            if isParametric
                s = 'parametric test';
            else
                s = 'rank-based test';
            end
        end

        %% plural - '1 subject', '3 subjects'
        function s = plural(n, word)
            if n == 1
                s = sprintf('1 %s', word);
            else
                s = sprintf('%d %ss', n, word);
            end
        end
    end
end
