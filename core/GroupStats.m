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
%   d = GroupStats.cohensD(a, b)   (mean(a) - mean(b)) / pooled SD
%   g = GroupStats.hedgesG(a, b)   Cohen's d x exact small-sample factor J
%   d = GroupStats.dz(a, b)        mean(a - b) / SD(a - b) (paired)
%   res = GroupStats.compare(values, names, design, method)
%       One call for a whole comparison, as shown by the app. values: cell
%       of vectors (one per group); design: 'paired' | 'unpaired' | 'anova';
%       method: 'parametric' | 'nonparametric'. Runs the chosen test, the
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
%   ptukey / qtukey       studentized range: numerical integration of
%                         P(Q <= q) = int_0^inf f_s(s) R_k(q s) ds, with
%                         R_k(w) = k int phi(z) [Phi(z) - Phi(z - w)]^(k-1) dz
%                         and s = sqrt(chi2_df / df) (Simpson in s, trapezoid in z;
%                         absolute error well below 1e-6). qtukey inverts
%                         it with fzero.
%   holm(p)               Holm step-down adjusted p-values
%   tiedRank(x)           average ranks and tie-group sizes
% Text helpers: formatP(p) ('p = 0.012', 'p < 0.0001'), stars(p),
%   statText(r) ('t(7) = 8.96', 'F(2, 21) = 11.8').
%
% Every test returns a struct with the same fields: test, statName, stat,
% df, p (two-sided), n, nExcluded, meanDiff, medianDiff, ci (95% CI of
% meanDiff), effectName, effect, effect2Name, effect2, method, note (and
% for ANOVA / Kruskal-Wallis: groupNames, means, table, posthoc).
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
% =========================================================================

classdef GroupStats
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

        %% compare - Test for a design, robustness check, descriptives and summary
        % values: cell of vectors (one per group, same order as names).
        % design: 'paired' (2 groups; the k-th values of A and B belong to
        % the same subject), 'unpaired' (2 independent groups) or 'anova'
        % (2+ independent groups). method: 'parametric' (default) or
        % 'nonparametric'. Two-group differences are B - A.
        % Output fields: design, method, groupNames, values (as analysed),
        % nExcluded (non-finite values per group; pairs for 'paired'), desc
        % (describe per group), main, check (the other family), checkAgrees,
        % comparisons (struct array: a, b, label, diff, ci, stat, p, method),
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
                otherwise
                    error('NeuroAnalyzer:GroupStats:design', ...
                        'Unknown design ''%s'' (use paired, unpaired or anova).', design);
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
            if strcmp(design, 'anova')
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

        %% statText - Statistic with its df, e.g. 't(7) = 8.96', 'F(2, 21) = 11.8', 'U = 12'
        function s = statText(r)
            if numel(r.df) == 2
                dfTxt = sprintf('%g, %g', r.df(1), r.df(2));
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
            elseif ~strcmp(design, 'paired') && any(res.nExcluded > 0)
                parts{end + 1} = sprintf(['%d value(s) excluded because the feature could not be ' ...
                    'computed (NaN).'], sum(res.nExcluded));
            end
            s = strjoin(parts, ' ');
        end

        %% summaryLine - One-line, report-ready result
        function s = summaryLine(res)
            m = res.main;
            statTxt = GroupStats.statText(m);
            nTxt = strjoin(arrayfun(@(d) sprintf('%d', d.n), res.desc, 'UniformOutput', false), ', ');
            s = sprintf('%s: %s, %s; %s = %.2f', m.test, statTxt, GroupStats.formatP(m.p), ...
                m.effectName, m.effect);
            if ~strcmp(res.design, 'anova')
                c = res.comparisons(1);
                if all(isfinite(c.ci))
                    s = sprintf('%s; %s = %.3g [95%% CI %.3g, %.3g]', s, c.label, c.diff, c.ci(1), c.ci(2));
                else
                    s = sprintf('%s; median difference %s = %.3g', s, c.label, c.diff);
                end
            end
            if strcmp(res.design, 'paired')
                s = sprintf('%s; n = %d pairs.', s, res.desc(1).n);
            else
                s = sprintf('%s; n = %s.', s, nTxt);
            end
        end
    end
end
