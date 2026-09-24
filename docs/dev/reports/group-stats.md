# Report: Signal Characterization, group statistics and publication figures

Classification: NEW STRAND, delegated sub-task. Area: Signal Characterization → group statistics and publication-ready figures.

Nothing here has been run in real MATLAB yet:
- **Numeric core in Octave 8.** GroupStats, demoGroups and all their tests ran in Octave 8 through a small test shim (149 checks pass).
- **App logic in Octave, with stand-in widgets.** Every group-workflow method ran headless on mock widgets; the single-file workflow ran as a regression check.
- **FigureExport.** Only parse-checked, because Octave graphics handles are not objects.
- **UI layout.** Parse-checked only; the layout has not been seen on screen.

## Files

Changed
- `apps/SignalCharacterizationApp.m` (+1281 / −95).
  - The window now has two tabs that act as a mode switch: **Single file** (the existing workflow, unchanged) and **Groups & statistics** (new).
  - The Single file plot gains **Export figure…** with a format dropdown.

New
- `core/GroupStats.m`: toolbox-free statistics (descriptives, t-tests, ANOVA with Tukey–Kramer, rank tests, effect sizes, one-call `compare`).
- `core/FigureExport.m`: publication export of any axes, uiaxes or tiled layout. It works on a styled temporary copy.
- `core/demo/demoGroups.m`: 3 conditions × 8 animals of LDF trial files, with known effects.
- `tests/StatsFeaturesTest.m`: 25 unit tests.
- `tests/StatsWalkthroughTest.m`: 2 UI tests, frames `SignalCharacterizationApp_x01..x10_*.png`.
- `docs/dev/reports/group-stats.md`: this report.

`git diff --stat` (my tracked file): `apps/SignalCharacterizationApp.m | 1376 +++++++++++++++++++++++++++++++++++---` (1281 insertions, 95 deletions).

New file sizes:

| File | Lines |
|---|---|
| `core/GroupStats.m` | 958 |
| `core/FigureExport.m` | 382 |
| `core/demo/demoGroups.m` | 114 |
| `tests/StatsFeaturesTest.m` | 428 |
| `tests/StatsWalkthroughTest.m` | 143 |

The launcher and `run_tests` already add `core/demo`, from commit 95c4b69. The app also adds it itself, in `ensureDemoPath`, before calling `demoGroups`.

## Single file tab: what changed

- The existing controls and public methods are unchanged: `openFile`, `loadDemo`, `extract`, `extractFeatures`, `exportResults`, `getTimeSeriesFromData`, `plotSelected` and the rest.
- Two internal refactors give identical results:
  - The per-feature loop in `extractFeatures` now calls a local `computeFeature(name, …)`, which makes the same `SignalFeatures` calls and fills the table columns in the same order.
  - Series parsing moved to a local `parseSeriesStruct(s, dt)`, which the group loader also uses. `getTimeSeriesFromData(app, dt)` delegates to it.
- The window is now 1240×900 (was 1200×860) to make room for the tab strip.

## Groups & statistics tab

Left side: four step cards.

1. **Files and groups**
   - **Group** field: an editable dropdown with Control and Stimulated, or type a new name.
   - **Add files…** (multi-select). Files are sorted alphabetically, so the subject numbers follow the file names.
   - **Try group demo**.
   - An info line, e.g. "24 file(s) in 3 group(s): Control 8, Stimulated 8, Drug 8".
2. **Feature (one value per subject)**
   - **Feature**: the same 9 features as the Single file tab.
   - **Value per**, one of:
     - File (mean trace): the feature of the average of the file's trials. This is the default.
     - File (mean of series): the mean of the per-trial features.
     - Each series: every trial or channel is a subject.
   - **Onset t0 (s)**.
   - **Baseline (s)** start/end. It is set automatically to the pre-stimulus window while it has not been edited.
   - **Direction**.
3. **Statistical test**
   - **Design**: Paired (same animals) / Unpaired (independent) / ANOVA (2+ groups).
   - **Method**: Parametric / Nonparametric (ranks).
   - **Compare** A vs B, for two-group designs. The difference is always B − A.
   - A one-line hint that explains the design. For paired designs it says that subjects are matched by number: #1 of A with #1 of B.
   - **Run test**.
4. **Export**
   - Format dropdown: PDF (vector), SVG (vector), EPS (vector), PNG 300 dpi, PNG 600 dpi, TIFF 600 dpi.
   - **Export figure…**.
   - **Export values & report…**: either a `.csv` with Group, Subject and value plus a `_report.txt`, or a `.mat` holding the full result struct.

Right side: three tabs.
- **Files**: a table with #, File, Group, Series and Value.
  - # is the subject number inside the group, which is what sets the pairing.
  - The Group cell is editable: change it to move the file to another group.
  - Toolbar: **▲ Move up** / **▼ Move down** (within the file's group), **Remove**, **Clear all**, and a note on pairing.
- **Results**:
  - A Quantity/Value table: test and method, design, feature and unit, n per group (and pairs), mean ± SD, mean ± SEM, median [IQR], statistic, df, p with stars, effect size(s), difference [95% CI], robustness check (the other test family, marked consistent or DISAGREES), and assumptions.
  - A **Pairwise comparisons** table: comparison, difference, 95% CI, p, method.
  - A copy-ready report box: a summary sentence, the assumptions, the robustness check, the settings, and for paired designs the list of pairs, e.g. `1: control_animal01.mat ↔ stimulated_animal01.mat`.
- **Plot**:
  - Shows every subject as a dot with a deterministic horizontal spread, grey lines joining pairs in paired designs, and either mean ± SEM (bar plus error bar) or a box plot (median, IQR, whiskers to the last value within 1.5 IQR). Choose with the **Style** dropdown.
  - Significance brackets with stars and p: the tested difference, or for ANOVA the significant post-hoc pairs.
  - The title shows the test, statistic and p. The y label carries the unit: PU when every file is LDF, otherwise "signal units".
  - A summary line sits under the plot.

The Results table's assumptions note is written for each case:
- **Paired designs:** explains the pairing and the assumption of normally distributed differences.
- **Welch:** gives the SD ratio.
- **ANOVA:** gives the SD ratio and warns when the same animals appear in every group (the groups are then not independent; repeated measures would be better).
- **Few subjects (n < 10):** warns that normality cannot be checked reliably.
- **Disagreeing tests:** warns when the parametric and rank-based results disagree.
- **Exclusions:** says how many subjects or pairs were dropped because of NaN.

Enable states and the primary button follow the next action, in this order: Add files (fewer than 2 groups) → Run test (no result, or the result is out of date) → Export figure. Changing any file or setting marks the result out of date, and the status bar says "click Run test again".

## New public API (all dialog-free)

SignalCharacterizationApp:
- `ok = addGroupFiles(paths, groupName)`
  - `paths`: char, string or cellstr.
  - Unreadable files are skipped and listed in a warning alert.
- `ok = removeGroupFile(idx)`
- `ok = moveGroupFile(idx, delta)`: `delta` is −1 or +1, within the file's group.
- `clearGroups()`
- `ok = loadGroupDemo()`
  - Writes the demo files and loads all 3 conditions.
  - Presets: Peak amplitude, File (mean trace), t0 = 0, baseline −5..0 s, Paired, Parametric, Control vs Stimulated.
  - Leaves `app.GroupDemo`, which holds the demo's `.truth`.
- `ok = runGroupStats(feature, design, method, pair)`
  - All arguments are optional; empty means "use the current field".
  - `design`: `'paired'|'unpaired'|'anova'` or a menu item.
  - `method`: `'parametric'|'nonparametric'` or a menu item.
  - `pair`: `{A, B}`.
  - The result goes to `app.GroupResult`: the `GroupStats.compare` output plus `labels`, `feature`, `subjectMode`, `designLabel`, `unit` and `settings`.
- `setGroupPlotStyle(style)`: `'mean'` or `'box'`.
- `ok = exportFigure(path, format, target)`
  - `format`: `pdf|svg|eps|png300|png600|tif` or a dropdown label.
  - `target`: `'groups'`, `'series'` or `'auto'`.
  - The written path goes to `app.LastExportPath`.
- `ok = exportGroupResults(path)`: `.csv` (+ `_report.txt`) or `.mat`.

GroupStats (static; every p is two-sided):
- `describe(x)`
- `quantile(x, p)`
- `ttestPaired(a, b)`
- `ttestWelch(a, b)`
- `anova1way(values, groups[, postHoc 'tukey'|'holm'])`
- `wilcoxonSignedRank(a, b[, method 'auto'|'exact'|'approx', correct])`
- `mannWhitney(a, b[, method, correct])`
- `kruskalWallis(values, groups)`
- `cohensD`, `hedgesG`, `hedgesJ(m)`, `dz`
- `compare(values, names, design, method)`
- Distributions: `normcdf`, `norminv`, `tcdf`, `pT2`, `tinv`, `fUpper`, `chi2Upper`, `ptukey`, `qtukey`
- Helpers: `holm`, `tiedRank`, `formatP`, `statText`, `stars`

Every test returns the same fields: `test`, `statName`, `stat`, `df`, `p`, `n`, `nExcluded`, `meanDiff`, `medianDiff`, `ci`, `effectName`, `effect`, `effect2Name`, `effect2`, `method`, `note`. ANOVA and Kruskal–Wallis add `groupNames`, `means`, `table` and `posthoc`.

FigureExport:
- `out = FigureExport.export(src, filePath, format, opts)`
- `FigureExport.formats()`
- `FigureExport.formatKey(label)`
- `[fmt, ext, dpi, isVector] = FigureExport.parseFormat(format)`
- `FigureExport.findAxes(src)`

Options (`opts`):

| Option | Default |
|---|---|
| Width, Height | 8.5 × 6.5 cm for one axes; 17.5 cm wide for several |
| FontName | Helvetica |
| FontSize | 8 pt |
| LineWidth | 0.75 |
| MinDataLineWidth | 1 |
| KeepTitle | true |
| Grid | false |

- **How it copies:** it copies the children (bottom-most first), limits, ticks, labels, legend and colorbar into an invisible `figure`.
- **Style:** it flattens transparency on white and applies the style.
- **How it writes:** it uses `exportgraphics` with `'ContentType','vector'` or `'Resolution'`. If that fails, it falls back to `print`: `-vector`, then `-painters`, for the formats `-dsvg`/`-dpdf`/`-depsc`/`-dpng`/`-dtiff`.
- The source view is never touched.

`demoGroups(folder)`, default folder `tempdir/NeuroAnalyzerDemo/groups`:
- Writes `control|stimulated|drug_animalNN.mat`, each with `segmentedLDF` (8×251), `segmentedTime` (−5..20 s) and `Fs` = 10, like `DemoData.ldfTrials`.
- Returns `folder`, `conditions`, `paths` (1×3 cell of 8×1 cellstr), `files` and `truth`.
- `truth` holds:
  - `meanAmplitude` [18 30 24] and `peakDelay` 4.
  - The SDs: animal 3, animal×condition 2.5, trial 2.
  - `amplitude` (8×3, the realized per-file truth).
  - `effect`: `meanDiff` 12; population `dz` 3.27 and `d` 3.02; `sampleDz` and `sampleD` computed from the realized amplitudes.
  - `anovaEta2` 0.60.

Suggested DemoData wiring (not done, since DemoData.m was off limits):
- Add a kind `'groups'` to `DemoData.file` that returns `demoGroups(fullfile(DemoData.folder(), 'groups'))`, or call it from `writeAll`.
- Add `DemoData.groupsTruth()`.

## Tests

`tests/StatsFeaturesTest.m`:
- `testDescribe_knownValues`: n, missing, mean, SD, SEM, quartiles, and the t-based 95% CI with t(0.975, 4) = 2.776445.
- `testTDistribution_criticalValuesAndSymmetry`:
  - tinv against tabled values for df 1, 9, 27 and ∞.
  - tcdf symmetry, tcdf(tinv) = p, and pT2 consistent with tcdf.
  - χ²(2) tail = exp(−x/2).
- `testStudentizedRange`:
  - k = 2 identity P(Q ≤ q) = 1 − p₂(q/√2), for df from 1 to ∞, to 1e-6.
  - Tabled q₀.₉₅: (3, ∞) = 3.314, (3, 10) = 3.877, (4, 20) = 3.958.
- `testPairedT_sleepData`: sleep data (Student 1908, R `sleep`) gives t = −4.0621, df 9, p = 0.002833, CI [−2.4599, −0.7001], and d_z.
- `testWelchT_sleepData`: t = −1.8608, df = 17.776, p = 0.07939, CI [−3.3655, 0.2055].
- `testWelchT_handComputedAndSymmetric`:
  - a = 1..5, b = 3..7 give t = −2, df = 8, and p = I(8/12; 4, ½); swapping a and b gives the same p.
  - Cohen's d = −2/√2.5; Hedges' g uses the exact J(8).
- `testAnova_plantGrowth` (R `PlantGrowth`):
  - SSB 3.76634, SSW 10.49209, F(2, 27) = 4.846, p = 0.01591, and η².
  - Tukey HSD p = 0.3908711 / 0.1979960 / 0.0120064 and CI [0.1738, 1.5562], matching R's `TukeyHSD`.
  - The values+labels input gives the same result as the cell input.
- `testAnova_equalMeansGivesZeroF`: F = 0, p = 1, η² = 0.
- `testAnova_twoGroupsIsStudentTSquared`: F = t² of the pooled t-test with the same p; the Holm option with one pair gives the plain Welch p.
- `testWilcoxon_exactHollanderWolfe`:
  - W+ = 40, exact p = 20/512 (checked by hand: 10 of the 512 sign patterns have W− ≤ 5).
  - 8 positive pairs give p = 2/256 and r = 1.
- `testWilcoxon_normalApproxWithTiesAndZero`: the sleep data give V = 0, z = −22/√71.125 and p = 0.009091, as in R's `wilcox.test` with correction.
- `testMannWhitney_exactMatchesEnumeration`:
  - U = 35; the exact p equals full enumeration of the C(15, 10) = 3003 splits.
  - One-sided p = 0.1272, as in R's help example.
  - Complete separation 4 vs 4 gives p = 2/70.
- `testMannWhitney_tiesSymmetry`: with ties, U_a + U_b = n_a·n_b, p is symmetric, r is antisymmetric, and the approximation is used.
- `testKruskalWallis_plantGrowth`: H = 7.9882, df 2, p = 0.01842, as in R's `kruskal.test`.
- `testHolm`: known adjusted vector.
- `testCompare_pairedSummaryAndDirection`: B − A sign, p, robustness family, summary text, and which tests run for each method.
- `testCompare_errors`: unequal paired lengths and 3 groups in an unpaired design raise the error IDs.
- `testCompare_pairedDropsIncompletePairs`: a NaN drops the whole pair (n 9, df 8, nExcluded [1 1]).
- `testDemoGroups_filesAndTruth`: file shape, time base and Fs, the truth values, and determinism.
- `testDemoGroups_pairedTestDetectsEffect`:
  - Per-file peak amplitude of the mean trace is within 2.5 PU of the simulated amplitude.
  - Paired p < 0.05; the difference is within 1.5 PU of the realized difference, and its CI excludes 0.
  - d_z is within 30% of the sample truth and above 1.
  - Wilcoxon agrees in direction with p < 0.05.
  - The unpaired Hedges' g is within 35% of the sample d.
- `testDemoGroups_anovaThreeGroups`: F(2, 21) with p < 0.05; three Tukey pairs, Stimulated − Control significant; group means within 1.5 PU of the truth.
- `testFigureExport_writesVectorAndPng`:
  - PDF, SVG, EPS and PNG files are written and non-empty; the PNG is wider than 600 px.
  - The source axes are unchanged and no figure is left behind.
- `testFigureExport_tiledLayout`: a two-tile layout exports to PNG.
- `testFigureExport_uiaxes`: a uiaxes in a uifigure exports to PDF. The test is skipped without a display.
- `testFigureExport_formatKeys`: labels map to keys, `parseFormat` works, and an unknown format errors.

`tests/StatsWalkthroughTest.m` (skipped without a display):
- `testGroupsAndStatistics` saves frames x01–x09:

  | Frame | Step | Checks |
  |---|---|---|
  | x01 | start | |
  | x02 | `loadGroupDemo` | 24 files |
  | x03, x04 | paired Control vs Stimulated (Plot and Results) | p < 0.05; difference ≈ truth ±2 PU; d_z > 1; checks agree |
  | x05, x06 | ANOVA | df [2 21]; p < 0.05; 3 post-hoc rows |
  | x07 | box plot | |
  | x08 | Wilcoxon | p < 0.05; r > 0 |
  | x09 | exports | figure to PDF, SVG and PNG, plus values CSV and report TXT, all non-empty |

- `testSingleFileFigureExport`: `loadDemo`, then `extract`, then `exportFigure` to PNG 300 and EPS (target `'series'`); saves frame x10.

Why the demo effects are large: the demo's variability was chosen so that the paired test, Welch and the ANOVA are significant with near certainty for 8 animals.
- ANOVA noncentrality ≈ 37, power > 0.999.
- The MATLAB random-number realization differs from Octave's, so the tests do not rely on one lucky draw.

## Verification done here

- `__parse_file__` passes for all 6 MATLAB files.
- The GroupStats numbers above reproduced R's published outputs to every printed digit when run in Octave.
  - Examples: Tukey p 0.3908711 / 0.1979960 / 0.0120064 and CI 0.1737839 / 1.5562161.
  - The exact Mann–Whitney p matched brute-force enumeration.
  - `ptukey` agrees with the k = 2 identity to 6e-9 for df from 1 to ∞.
- The StatsFeaturesTest bodies ran in Octave through a shim: 149 checks pass. The only failures are Octave limitations:
  - `char(8722)` is not supported in Octave.
  - The FigureExport tests need MATLAB graphics objects, `uiaxes` and `tiledlayout`.
- The app ran headless in Octave with stand-in widgets. Every group method was driven:
  - demo, paired, ANOVA, box style, unpaired nonparametric, a latency test on another pair;
  - the three Value-per modes;
  - move, remove, and the unequal-paired error;
  - editing a Group cell, an unknown feature, `.mat` export, clear, and adding a missing file.
  - The single-file open/extract regression ran the same way.

Not verified (needs CI with real MATLAB):
- FigureExport end to end: `exportgraphics` and the `print` fallback, `copyobj` from UIAxes, and legend remapping.
- The visual layout: card heights in the 900 px window (the left column is scrollable if it overflows), and that the tab strip and the editable Group dropdown look right.
- The `.csv` path of `exportGroupResults` (`table`/`writetable`; not in Octave).
- Whether `exportgraphics` writes SVG in the CI release. If it does not, the automatic fallback is `print -dsvg`.

## References cited (in core/GroupStats.m)

- Student (1908). The probable error of a mean. Biometrika, 6(1), 1–25.
- Welch, B. L. (1947). The generalization of 'Student's' problem when several different population variances are involved. Biometrika, 34(1–2), 28–35.
- Satterthwaite, F. E. (1946). An approximate distribution of estimates of variance components. Biometrics Bulletin, 2(6), 110–114.
- Kramer, C. Y. (1956). Extension of multiple range tests to group means with unequal numbers of replications. Biometrics, 12(3), 307–310.
- Holm, S. (1979). A simple sequentially rejective multiple test procedure. Scandinavian Journal of Statistics, 6(2), 65–70.
- Wilcoxon, F. (1945). Individual comparisons by ranking methods. Biometrics Bulletin, 1(6), 80–83.
- Mann, H. B., & Whitney, D. R. (1947). On a test of whether one of two random variables is stochastically larger than the other. Annals of Mathematical Statistics, 18(1), 50–60.
- Kruskal, W. H., & Wallis, W. A. (1952). Use of ranks in one-criterion variance analysis. Journal of the American Statistical Association, 47(260), 583–621.
- Cohen, J. (1988). Statistical Power Analysis for the Behavioral Sciences (2nd ed.). Lawrence Erlbaum Associates.
- Hedges, L. V. (1981). Distribution theory for Glass's estimator of effect size and related estimators. Journal of Educational Statistics, 6(2), 107–128.

Needs reference (these methods are described in the code without a citation):
- The numerical-integration formula for the studentized range CDF.
- The matched-pairs and two-sample rank-biserial correlation.
- η²_H = (H − k + 1)/(N − k) for Kruskal–Wallis.
- The quantile definition, type 7. Hyndman & Fan (1996), The American Statistician 50(4), 361–365, would fit if a citation is wanted.
- Tukey's original HSD: an unpublished 1953 manuscript, so only Kramer (1956) is cited.

## Ready-to-paste Help text (topic "Signal Characterization")

### Quick start addition: Groups & statistics

1. Open the **Groups & statistics** tab. Or click **Try group demo** to load the example groups.
2. **1 Files and groups**: pick or type a name in **Group** (e.g. Control) and click **Add files…**. Select one .mat per animal. Repeat for the other group (e.g. Stimulated).
   - The **Files** tab lists every file with its subject number **#**. Paired designs match #1 with #1, #2 with #2, and so on.
   - Use **▲ Move up** / **▼ Move down** to fix the order, or double-click a Group cell to move a file to another group.
3. **2 Feature**: choose the **Feature**, **Value per**, **Onset t0 (s)**, **Baseline (s)** and **Direction**.
   - For **Value per**, File (mean trace) is recommended: one animal = one file, and the feature is taken from its average trace.
4. **3 Statistical test**: choose the **Design**, the **Method**, and for two groups **Compare** A vs B (the difference is B − A). Then click **Run test**.
   - **Design**: Paired (same animals), Unpaired (independent) or ANOVA (2+ groups).
   - **Method**: Parametric, or Nonparametric (ranks).
   - The **Plot** tab shows every animal, pair lines, mean ± SEM (or **Box plot** under **Style**) and the significance bracket.
   - The **Results** tab lists the test, statistic, df, p, effect size, 95% CI, n per group, the other test family as a robustness check, and the assumptions. It also has a copy-ready report.
5. **4 Export**: choose a format and click **Export figure…**.
   - PDF / SVG / EPS are vector files; PNG and TIFF are images at 300 or 600 dpi.
   - The figure is 8.5 cm wide, 8 pt Helvetica, on white, with no grid. The window itself is not changed.
   - **Export values & report…** saves the per-animal values (.csv plus a _report.txt) or the full result (.mat).
6. In the **Single file** tab, **Export figure…** above the plot saves the selected trace the same way.

### Demo data: what you should get (Try group demo)

- **The data:** 24 files, `control_animal01.mat` … `drug_animal08.mat` in `tempdir/NeuroAnalyzerDemo/groups`.
  - The same 8 animals in Control, Stimulated and Drug.
  - Each file has 8 LDF trials from −5 to 20 s at 10 Hz, with the stimulus at 0 s.
  - The true peak hyperemia is 18, 30 and 24 PU. Animals differ by about 3 PU; each animal's response in each condition varies by a further ~2.5 PU.
- **Paired t-test, Peak amplitude, Control vs Stimulated:**
  - Stimulated − Control ≈ +12 PU, with a 95% CI of roughly +9 to +15 PU.
  - p < 0.001, and d_z ≈ 3 (the simulated value is 3.3).
  - Wilcoxon signed-rank (the robustness check): p ≈ 0.008. All 8 animals increase, and 0.008 is the smallest exact p possible with 8 pairs.
- **Unpaired (Welch) on the same data:** also significant, with a smaller t, because the animal-to-animal differences are no longer removed.
- **ANOVA (2+ groups):**
  - F(2, 21) is large and p < 0.001.
  - Tukey–Kramer: Stimulated − Control ≈ +12 PU (p < 0.001). Drug lies about 6 PU from each of the others; those two pairs are usually, but not always, significant.
- **Peak latency:** ≈ 4 s in every group, so no difference is expected.

### Troubleshooting

| Problem | What to do |
|---|---|
| "The paired design needs the same number of subjects in both groups" | Every animal needs one file in each group. Add the missing file or remove the extra one; the **#** column shows the pairing. |
| Wrong animals paired | The Results report lists every pair (`1: fileA ↔ fileB`). Files are added in alphabetical order; fix the order with **▲ Move up** / **▼ Move down**. |
| **Run test** is disabled | Add files to at least two groups. For a two-group design, choose two different groups in **Compare**. |
| "… value(s) excluded because the feature could not be computed" | The feature was NaN for those files (peak not found or never crossing 50%). Check **Onset t0**, **Baseline** and **Direction**, or choose another feature. |
| "The parametric and rank-based tests disagree" | This usually means few animals or an outlier. Look at the Plot tab, and report the rank-based result or add animals. |
| Same animals in 3 or more conditions | The one-way ANOVA assumes independent groups. A repeated-measures ANOVA is not available: compare the conditions of interest with paired tests (and correct for multiple comparisons), or use a statistics package. |
| **Export figure…** is disabled | Run a test first (Groups & statistics), or load a file (Single file). |
| The journal wants Arial or another size | Export as PDF or SVG (vector) and change the font or size in Illustrator or Inkscape; the text stays editable. |
