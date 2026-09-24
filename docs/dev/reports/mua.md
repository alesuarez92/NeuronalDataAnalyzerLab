# Wave 1 report: MUA spike sorting (cluster clean-up, raster/PSTH, correlograms, headless pipeline)

> Development notes for the in-progress improvement strand. They are removed before merging to `main`.

Classification: part of the wave-1 EXISTING STRAND (area: MUA spike sorting).

Nothing here has been run in real MATLAB yet:
- The numeric core and the features tests were run in Octave 8 (see "Verification").
- The app's own logic was run headless in Octave with stand-in widgets.
- The UI layout itself was parse-checked only.

## Files

Changed
- `apps/MUAAnalysisApp.m` (+649 / −789 lines; the sorting code moved to `core/MUAPipeline.m`).

New
- `core/ClusterTools.m`: compare, merge and split clusters. Base MATLAB only.
- `core/SpikeTrains.m`: stimulus onsets, raster + PSTH, auto- and cross-correlograms. Base MATLAB only.
- `core/MUAPipeline.m`: the headless detection → alignment → features → clustering → auto-merge → QC that used to live in `doSpikeSorting`, plus the drift-correction merge helpers.
- `tests/MUAFeaturesTest.m`: 11 unit tests.
- `tests/MUAWalkthroughTest.m`: 2 UI tests that save frames `MUAAnalysisApp_x01..x10_*.png`.
- `docs/dev/reports/mua.md`: this report.

No `core/demo/` file was needed. The synthetic waveforms and spike trains are local fixtures in the test file, and the demo checks use the existing `DemoData.file('mua')`. Nothing needs wiring into DemoData.

`git diff --stat`: `apps/MUAAnalysisApp.m | 1438 ++++++++++++++++++++++---------------------------` (649 insertions, 789 deletions).

## What changed in MUA Analysis

### 1. Merging over-split clusters

**Configure… dialog** (section "Features & clustering") has two new rows:
- **Auto-merge similar clusters**: a checkbox, on by default.
- **Merge threshold (correlation)**: default 0.95, range 0.5–1.

The dialog is now 860 px tall. After clustering, it repeatedly merges the most similar pair of units that meets both conditions:
- their mean waveforms have correlation ≥ threshold, allowing a ±0.2 ms shift;
- their peak-to-peak amplitude ratio (smaller / larger) is ≥ 0.85.

`mergeMinAmpRatio` is a sorting parameter but is not shown in the dialog. The lower ID is kept, and noise (0) is never touched. The status bar says what merged, for example:

> Sorted 595 spikes into 3 units (0 rejected) on Ch 4 in 0.7 s · Auto-merged cluster 3 into 1 (r = 0.97, amplitude ratio 0.99) (Undo in step 4 keeps them apart) - review the tabs, then Save results (step 5)

The params label in step 3 shows "auto-merge r ≥ 0.95".

**Clusters card (step 4)** has a new layout:
- listbox;
- [Select all | Clear | **Undo**];
- [**Merge selected** | **Split selected**];
- quality summary.

The buttons:
- **Merge selected** merges the selected units into the lowest ID. It needs ≥ 2 units selected.
- **Split selected** runs k-means into 2 on the unit's waveform PCA. It needs exactly 1 unit selected. The larger part keeps the ID; the other part gets max ID + 1.
- **Undo** has the tooltip "Undo last change". It steps back through merges, splits and auto-merges, including the auto-merge done while sorting.

After every change the app recomputes the per-cluster waveforms, SNR and ISI QC. It then refreshes the list, all plots and the Quality table, and reports in the status bar.

Saving: the list of edits is saved as `info.clusterEdits`, a cellstr.

Window size: the window is now 1280×920 (was 880) so the Clusters list keeps its height with the extra button row.

### 2. Per-unit responses

There are two new tabs, placed after "Spike rate". Both are drawn when shown, so selection changes stay fast.

**Raster & PSTH**
- Controls: From (s) = −0.1, To (s) = 0.3, Bin (ms) = 5.
- Each selected unit (up to 4) gets one column: raster on top (trial 1 at the top) and PSTH below.
- The PSTH shows bars for the trial-mean rate in spikes/s, with ±SEM lines.
- The stimulus is marked at 0 with a gray line. The PSTH title gives the peak latency.
- Onsets use the app's existing rule: threshold and minimum ISI from "Segment by stimulation onsets" in step 2, default 0.5 and 1 s. That code is now in `SpikeTrains.stimulusOnsets` and is shared by both features.
- Only trials whose whole window lies inside the sorted trace or segment are used.
- If there is no stimulus, no onsets or an invalid window, the tab shows a hint instead.

**Correlograms**
- Controls: Max lag (ms) = 50, Bin (ms) = 1.
- Up to 4 selected units are shown as an n×n grid:
  - autocorrelograms on the diagonal, with the title giving the count within ±refractory;
  - cross-correlograms off the diagonal (row i, column j = j's spikes around i's).
- The ±refractory band (Configure setting, default 1 ms) is shaded.

### 3. Public, dialog-free methods

These are for CI and scripts.

```matlab
[ok, mergeLog] = app.autoMergeClusters(opts)      % opts optional: threshold, minAmpRatio, maxLag (samples)
ok = app.mergeClusters(ids)                       % default: selected units
ok = app.splitCluster(id)                         % default: the single selected unit
ok = app.undoClusterEdit()
ok = app.showRasterPSTH(unitIds, window, bin)     % window [from to] s, bin in s (e.g. 0.005)
ok = app.showCorrelograms(unitIds, maxLagMs, binMs)
```

All of them:
- are undoable where relevant;
- write to the status bar, with a warning for invalid input;
- never open a modal dialog.

Existing public methods and the no-arg, non-blocking constructor are unchanged. `optimizeClusterMerging`, `mergeClustersAcrossBins`, `mergeWithinClusters` and `mergeSimilarClusters` are still app methods with the same signatures, and now delegate to `MUAPipeline`.

### 4. Headless pipeline (`core/MUAPipeline.m`), done

```matlab
p = MUAPipeline.defaultParams()          % = the old defaults + autoMerge 1, mergeThreshold 0.95, mergeMinAmpRatio 0.85
p = MUAPipeline.completeParams(p)
[results, info] = MUAPipeline.sort(x, t, fs, params, stageFcn)
[results, qc]   = MUAPipeline.qualityMetrics(results, labels, waves, locs, t, fs, params)
opts = MUAPipeline.mergeOptions(params, fs)
s = MUAPipeline.errorTitle(identifier)
% moved unchanged from the app (static):
MUAPipeline.optimizeClusterMerging / mergeClustersAcrossBins / mergeWithinClusters / mergeSimilarClusters
MUAPipeline.tryKMeans / tryGMM / tryDBSCAN
```

`results` has exactly the fields of `app.SpikeResults`:
- `segmentedMUA`, `segmentedTime`
- `waveformsAligned`, `waveformsRaw`
- `spikeTimes`, `clusterIdx`, `waveforms`
- `isiViolationRate`, `snr`, `noiseSNR`, `rejectedClusters`

`info` holds:
- `locs`, `threshLines`, `qc` (the display QC struct);
- `waves`: per-spike aligned waveforms matching `clusterIdx`, also correct after drift time-binning;
- `labelsBeforeMerge`, `mergeLog`.

Failures throw `NeuroAnalyzer:MUAPipeline:{filter|noSpikes|tooFewSpikes|tooFewWaveforms|unknownFeature|driftBins|clustering}` with the same messages as before. The app maps them back to the same alert titles ("Filter Error", "Detection Error", "Clustering Error", "Spike sorting") via `failSort`. Unexpected errors still reach the "Spike sorting failed: …" path.

**Behaviour preserved.** The old `doSpikeSorting` body and drift helpers were diffed against the new code after normalising the mechanical substitutions (`app.setStage` → `stageFcn`, `app.failSort` → throw, `app.SpikeResults.` → `results.`). The only differences are:
- the new auto-merge step, which is off with `autoMerge = 0`;
- the rejection reason built with char instead of string. The resulting `qc.reason` char is identical.
- one duplicated line removed (`clusterWaves` computed twice);
- unused `bestK` variables removed.

The drift helpers are byte-identical apart from `app.` → `MUAPipeline.`. Detection, alignment, features, clustering, drift correction and QC are untouched.

**Deliberate behaviour change.** Auto-merge is ON by default, as requested. Sorting now returns fewer clusters when K-means over-splits; Undo restores the K-means result.

## Why the amplitude-ratio default is 0.85 (not 0.8)

Demo channel 4 was simulated in Octave with the real `DemoData` code and a RandStream stand-in, across 11 seeds.

K-means (best silhouette) usually gives 4 clusters, sometimes 6:
- unit 2 is split into two halves: r = 0.97–0.99, amplitude ratio 0.94–1.00;
- unit 1 is sometimes split the same way;
- sometimes there is a mixed cluster.

Units 1 and 2 are the problem pair. Their mean waveforms correlate at r = 0.95–0.98 even though they are different cells, and their amplitude ratio is 0.73–0.79. So the correlation threshold alone cannot keep them apart, and a 0.8 amplitude cut-off has almost no margin. 0.85 sits between the two groups.

After auto-merge, every seed gave 3 units: unit 1, unit 2, and unit 3 seen attenuated from channel 5 (~−47 µV mean trough). This matches the reported "clusters 1 and 3 near-identical" case: in the emulation, "Auto-merged cluster 3 into 1 (r = 0.97, amplitude ratio 0.99)".

## Tests

### `tests/MUAFeaturesTest.m`

Runs in < 10 s. The demo test needs the Signal and Stats toolboxes and is skipped without them.

- `testSimilarity_lagAndAmplitude`: a shifted copy gives r = 1 at the right lag; a half-size copy gives amplitude ratio 0.5. Unit-1/unit-2-like shapes give r > 0.9 but amplitude ratio < 0.8.
- `testAutoMerge_mergesCopiesOfOneUnit`: clusters 1 and 3 are copies of one unit and 2 is a different unit.
  - Checks: 3 is merged into 1; 2 and noise 0 are untouched.
  - The merge log has one entry: keep 1, absorbed 3, r > 0.95, amplitude ratio > 0.9, sizes 150/150.
- `testAutoMerge_keepsDistinctUnits`: nothing merges when units differ in size (A/B) or in shape at similar size (A/C). The similarity matrix confirms why.
- `testMerge_bookkeeping`: `merge` relabels to min(ids) and ignores 0. Fewer than two valid units raises an error. `renumber` is also checked.
- `testSplit_separatesMixedUnits`: a cluster mixing A (200 spikes) and B (100 spikes) is split. Checks:
  - new ID = max + 1, and the larger part keeps its ID;
  - each part is ≥ 97% pure;
  - other clusters and noise are unchanged;
  - the split is deterministic, and merge undoes it;
  - splitting 0 or a missing ID raises an error.
- `testStimulusOnsets`: rising crossings, and the minimum ISI measured from the previous crossing (the app's rule).
- `testPSTH_recoversRateStep`: a 200-trial Poisson train at 10 spikes/s with 100 spikes/s from 5–45 ms. Checks:
  - evoked rate ≈ 100 (±15%) and baseline ≈ 10 (±3);
  - the peak lies inside the step;
  - SEM = SD/√n;
  - the raster matches the PSTH counts.
- `testPSTH_spanDropsIncompleteTrials`: onsets whose window falls outside the recording are left out.
- `testCorrelogram_refractoryGap`: a train with a 2.5 ms dead time. Checks:
  - bins within ±2 ms are empty, and the autocorrelogram is symmetric;
  - away from 0 the conditional rate is the mean rate;
  - identical spike times count as a pair, and only self-pairs are dropped.
- `testCorrelogram_knownLag`: train 2 follows train 1 by 5–5.8 ms. The peak is at +5.5 ms and holds every spike; swapping the trains mirrors the correlogram.
- `testDemo_autoMergeAndPSTH`: the demo file, channel 4, with loadDemo's settings and `rng(0)`. Checks:
  - 2–3 units after auto-merge, with the merge log matching the drop in clusters;
  - the results layout matches the app's;
  - the largest unit (by peak-to-peak amplitude) is truth unit 1 (> 70% of its spikes within 0.5 ms of a unit-1 spike);
  - detected onsets = truth onsets (±1.5 ms);
  - its PSTH (10 ms bins) peaks within 5–55 ms and is > 3× the baseline.

### `tests/MUAWalkthroughTest.m`

Frames go to `test-artifacts/screens/walkthrough/`.

`testMUAClusterEditingAndResponses` saves these frames:
- `x01_demo_loaded`
- `x02_sorted_no_merge` (demo settings, auto-merge off)
- `x03_auto_merged` (2–3 units; count = before − merges)
- `x04_raster_psth`
- `x05_correlograms` (n² axes)
- `x06_manual_merge`
- `x07_undo_merge` (IDs restored)
- `x08_split` (new ID = max + 1)

After the split frame, Undo restores the IDs. A final Undo returns to the K-means clusters, and one more Undo returns false. The last frame is `x09_undo_all`.

`testMUARasterWithoutStimulus`: a demo copy without `stim_*`, saved as `x10_no_stimulus`. Checks:
- before sorting, the show/merge/undo methods return false without errors;
- after sorting, the raster reports "No stimulus…";
- correlograms still work.

## Verification (Octave 8)

**Unit tests.** All 10 non-demo tests passed in Octave. The harness used:
- a fake TestCase;
- a RandStream stand-in;
- stubs for `findpeaks`, `pca`, `kmeans` (k-means++), `silhouette` (squared Euclidean, as MATLAB) and `histcounts`.

The tests also passed for 10 other seed offsets, so the statistical assertions are not seed-fragile.

**Demo assertions.** The demo test's assertions held for 8 emulated demo datasets. The weakest case was 3 units with the largest unit 83% unit 1, after a mixed cluster was merged in; the threshold is 0.7.

**App logic, headless.** The real `MUAAnalysisApp` methods were run in Octave through a subclass that replaces `buildUI` with plain-struct widgets and stubs the graphics calls. 50 checks passed, covering:
- open file → sort → auto-merge;
- raster and correlograms (correct tile counts, and each tab drawn once);
- merge / undo, split / undo, and undo of the sort-time auto-merge;
- invalid window, empty selection and no-stimulus hints;
- segmentation through the new onset helper, and a segment too short to cluster (clean "Clustering Error");
- drift time-binning with and without grid search, and dynamic clustering;
- the filter-error path;
- delegated methods.

**Parse checks.** All six files parse in Octave.

## Not verified / risks

- **Real MATLAB K-means.** It may pick a different k than the stub. The ≥ 0.85 amplitude and ≥ 0.95 correlation rule merged all over-splits in every emulated case, but I have not seen the MATLAB clusters. If CI fails `numel(units) <= 3`, look at the merge log in the test output.
- **Layout is unrendered.** Nothing has been seen on screen:
  - the Clusters card at 920 px;
  - the 3-button row, about 90 px per button ("Select all" / "Clear" / "Undo");
  - the 7 tabs;
  - the 4×4 correlogram grid.

  Please review `MUAAnalysisApp_x0*.png` from CI.
- `char(8805)` (≥) and `char(177)` (±) in status and labels are fine in MATLAB. Octave can't show them, but that only affects the test harness.
- The `rng(0)` seeding in the tests makes MATLAB's `kmeans` deterministic. The app itself stays unseeded, as before.

## References cited (in `core/SpikeTrains.m`)

- Gerstein GL, Kiang NY-S (1960). An approach to the quantitative analysis of electrophysiological data from single neurons. *Biophysical Journal* 1(1):15–28. (PSTH)
- Perkel DH, Gerstein GL, Moore GP (1967). Neuronal spike trains and stochastic point processes. I. The single spike train; II. Simultaneous spike trains. *Biophysical Journal* 7(4):391–418 and 419–440. (auto- and cross-correlograms)

Methods described without a citation:
- template (mean-waveform) similarity merging with an amplitude-ratio guard;
- the PCA + k-means split.

Neither needs a specific reference; add one if the Help should cite a spike-sorting review.

## Suggestions for the lead

- `SpikeTrains.stimulusOnsets` (MUA rule: absolute threshold, ISI from the previous crossing) and `ERPAnalysis.detectOnsets` (LFP rule: mean-subtracted stimulus) differ slightly. They could be unified later if the Help should describe one rule.
- A batch-processing feature can call `MUAPipeline.sort` per channel/file directly. For reproducible batches, seed with `rng(seed)` around the call, since `kmeans` uses the global stream.

## Ready-to-paste Help text (`HelpApp.topicMUAAnalysis`)

### Quick start: replace steps 3–4 and add 5–6 (renumber Export to 7)

```matlab
'**3 Spike sorting**: click **Configure...** (detection method, threshold, polarity, filtering, features, clustering, **Auto-merge similar clusters** with its **Merge threshold (correlation)**, drift correction) and then **Run**. With auto-merge on (default), clusters whose mean waveforms have the same shape (correlation ≥ 0.95) and size (amplitude ratio ≥ 0.85) are joined; the status bar says what was merged.'
'**4 Clusters**: select the clusters to show (**Select all** / **Clear**) and read the quality summary. Select two or more units and click **Merge selected** when they are the same neuron; select one unit and click **Split selected** to cut it in two; **Undo** reverses the last merge, split or auto-merge.'
'**5 Raster & PSTH** tab: spikes of each selected unit (up to 4) around every stimulus onset (raster) and the mean firing rate ± SEM (PSTH). Set **From (s)**, **To (s)** and **Bin (ms)**; onsets use the threshold and minimum ISI of **Segment by stimulation onsets** (default 0.5, 1 s).'
'**6 Correlograms** tab: autocorrelograms (diagonal) and cross-correlograms of up to 4 selected units; set **Max lag (ms)** and **Bin (ms)**. The shaded band is ± the refractory period: a clean unit has (almost) no spikes there.'
'**7 Export**: click **Save results...** to write spike times, cluster IDs, the sorting parameters, quality measures and the list of merges / splits (info.clusterEdits) to .mat.'
```

### Demo data: what you should get (replace the last bullet)

```matlab
'* **What you should get**: K-means alone tends to split one unit in two (e.g. 4 clusters, two with the same waveform); with **Auto-merge similar clusters** on (default) the status bar reports e.g. "Auto-merged cluster 3 into 1 (r = 0.98, amplitude ratio 0.99)" and **2–3 units** remain on channel 4: unit 1 (~90 µV), unit 2 (~50 µV) and possibly unit 3 seen weaker from channel 5. **Raster & PSTH** (−0.1 to 0.3 s, 5–10 ms bins): 15 trials; every unit fires more **5–55 ms after each stimulus** (unit 1: ~80 vs ~6 spikes/s). **Correlograms**: the autocorrelograms are empty within ±1 ms (2 ms refractory period); ISI violations ~0%.'
```

### Troubleshooting (add)

```matlab
'Two clusters have the same waveform', 'One neuron was split: select both and click Merge selected, or turn on Auto-merge similar clusters (Configure...). Lower the Merge threshold (e.g. 0.9) to merge more.'
'Auto-merge joined two different neurons', 'Click Undo (step 4) to restore the clusters, then raise the Merge threshold (e.g. 0.98) or turn Auto-merge off in Configure....'
'One cluster mixes two waveforms or has many ISI violations', 'Select that unit alone and click Split selected; Undo if the result is worse.'
'Raster & PSTH says "No stimulus channel in this file"', 'The MUA file has no stim_data; save it again from Extract Ephys with the stimulus channel. Correlograms do not need a stimulus.'
'Raster & PSTH says "No stimulus onsets"', 'The stimulus never rises above the onset threshold: tick Segment by stimulation onsets (step 2) and set a lower threshold, then untick it if you want to sort the full recording.'
'Autocorrelogram has spikes inside the shaded band', 'The unit has refractory violations: it probably contains a second neuron or noise; try Split selected or a higher detection threshold.'
```
