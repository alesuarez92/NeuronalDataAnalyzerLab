# Wave 2 report: batch processing (headless LDF pipeline, batch runner, Batch window)

> Development notes for the in-progress improvement strand. They are removed before merging to `main`.

Classification: NEW STRAND (area: batch processing).

Nothing here has been run in real MATLAB yet. What was checked:

- Every new or changed file parses in Octave 8.4 (`__parse_file__`).
- The numeric code ran in Octave with test-only stand-ins kept outside the repo:
  - `RandStream`, `table` / `writetable` / `readtable` / `height` / `width`;
  - `std(..., 'omitnan')`, which Octave lacks and MATLAB has;
  - simple Signal Processing Toolbox stand-ins: a bilinear Butterworth low-pass, a forward-backward `filtfilt`, and `decimate` / `downsample`.
- The three new test files ran in Octave through a small fake `TestCase` harness:
  - `LDFPipelineTest`: 69 checks passed; the window test cannot run there (no uifigure).
  - `BatchFeaturesTest`: 177 checks passed; `testMUA` skipped, since spike sorting needs findpeaks / pca / kmeans.
  - `BatchWalkthroughTest.testBatchPipelines`: 41 checks passed, with handle-object stand-ins for the UI widgets and `UIKit`.
- The MUA row assembly (units, rates, per-channel errors) was checked with a stub `MUAPipeline`.

## Files

Changed
- `apps/ProcessingLDFApp.m`: `applyFilter`, `getFilterMode` and `segmentLDFByOnsets` now call `core/LDFPipeline.m`. Public methods, status and alert messages, plots and the saved file format (`segmentedLDF`, `segmentedTime`, `Fs`) are unchanged. The header names the new core file.
- `core/Main.m`: fifth workflow card "Batch · Many files at once" with a **Batch processing** button and a `?` for Help topic `Batch processing`. It adds the properties `BatchPanel` and `BatchBtn`. The content grid now has 5 rows and the default window height is 940 px (was 820); the card area already scrolls.
- `tests/AppSmokeTest.m`: `testBatch` opens `BatchApp`.

New
- `core/LDFPipeline.m`: headless LDF processing (decimate / filter / onsets / trials).
- `core/Batch.m`: the batch runner (5 pipelines, summary table, CSV / MAT / log).
- `apps/BatchApp.m`: the Batch Processing window.
- `core/demo/demoBatch.m`: demo file sets with known, slightly different truths per file.
- `tests/LDFPipelineTest.m`, `tests/BatchFeaturesTest.m`, `tests/BatchWalkthroughTest.m`.
- `docs/dev/reports/batch.md`: this report.

Nothing needs wiring into `DemoData`. `BatchApp.loadDemo` calls `demoBatch` directly and writes to `DemoData.folder()/batch/<pipeline>`. If `DemoData.file` should also serve these sets, a kind such as `'batchLdf'` could map to `demoBatch('ldf')`.

## Public API

### `core/LDFPipeline.m` (static)

```matlab
p   = LDFPipeline.defaultParams()          % downsample 1, filterType 1 (none), designType 1, filterOrder 4,
                                           % cutoffLow/High NaN, threshold 0.5, preSec 2, postSec 4, minISI 1
s   = LDFPipeline.loadCropped(filePath)    % stim, LDF, t, Fs; error ...:LDFPipeline:missingVars
msg = LDFPipeline.validateProcessing(p, Fs)   % '' or the app's message (Nyquist, low >= high, order)
[LDF, stim, t, Fs, b, a] = LDFPipeline.process(LDF, stim, t, Fs, p)
mode = LDFPipeline.filterMode(filterType)
onsets = LDFPipeline.detectOnsets(stim, Fs, threshold, minISI)          % samples, row ([] if none)
[seg, tSeg, onsets, bounds] = LDFPipeline.segment(ldf, stim, Fs, threshold, preSec, postSec, minISI)
r = LDFPipeline.run(LDF, stim, t, Fs, p)   % segmentedLDF, segmentedTime, Fs, onsets, nOnsets, nTrials,
                                           % LDF, stim, t; errors ...:invalidFilter, ...:noTrials
```

The code is the app's code moved verbatim: the same `decimate` / `downsample` / trim, `butter` / `cheby1(…, 0.5, …)` / `fir1`, `filtfilt`, and the same debounce and trial rules. The test file keeps a verbatim copy of the old inline code and compares against it.

### `core/Batch.m` (static)

```matlab
names = Batch.pipelines()                  % {'ldf','erp','mua','roi','features'}
d     = Batch.describe(pipeline)           % label, input, output, extensions
p     = Batch.defaults(pipeline)
spec  = Batch.paramSpec(pipeline)          % name, label, kind, items, limits, tooltip, value (form fields)
p     = Batch.completeParams(pipeline, p)
files = Batch.listInputs(inputs, pipeline) % folder | file | cellstr (folders expanded, sorted by name)
R     = Batch.run(pipeline, inputs, params, outFolder, 'Name', n, 'Progress', f, 'Cancel', g, 'Echo', tf)
[rows, info] = Batch.processFile(pipeline, file, params, outFolder)
[vals, baseVal, dirn] = Batch.seriesFeatures(t, y, t0, bl, dirChoice)   % 9 features, Signal Characterization rules
cols  = Batch.columns(pipeline)            % {name, 'double'|'char'} summary columns after File, Status, Message
T     = Batch.rowsToTable(pipeline, rows)  % struct rows (or cell of struct arrays) -> table
% Constants: Batch.FeatureNames, Batch.FeatureColumns, Batch.FilterTypes, Batch.FilterDesigns
```

`Batch.run` returns `R` with these fields:
- `pipeline`, `params`, `files`;
- `summary` (table), `fileStatus` (`ok` / `warning` / `error` / `skipped` per file), `messages`;
- `log` (cellstr);
- `paths` (`folder`, `csv`, `mat`, `log`, `trials`);
- `nOK`, `nWarning`, `nError`, `nSkipped`, `cancelled`, `elapsed`.

It writes these files to `outFolder`:
- `<Name>_summary.csv`;
- `<Name>_summary.mat` (`summary` table and a `batch` struct);
- `<Name>_log.txt`;
- for `ldf` with `saveTrials`, `trials/<file>_segments.mat` in the LDF Processing format.

`Progress` is called as `f(k, n, fileName, status, message)`: once with `'running'` before each file and once with the file's status after it. `Cancel` is polled before each file.

A failing file becomes one row with `Status = 'error'` and the one-line error message, and the batch goes on. For MUA, a failing channel gives an error row for that channel while the other channels are kept, and the file status is then `warning`.

Default settings (`Batch.defaults`):

| Pipeline | Defaults |
|---|---|
| `ldf` | downsample 10, `Low-pass` `Butterworth` order 4, cutoffLow 0.05 / cutoffHigh 1 Hz (only the one the filter type uses is passed on), threshold 2.5, pre 5 s, post 20 s, minISI 1 s, direction `Auto`, saveTrials true |
| `erp` | pre 0.1 s, post 0.3 s, threshold 0.5, minISI 0.5 s, channels [] (all), N1 window 5–50 ms, P2 window 20–150 ms, computeCSD true, spacing 100 µm, amplitudeScale 1e6, amplitudeUnit `uV` |
| `mua` | channels [], `MAD`, k = 4, `negative`, `PCA`, `K-means`, min 20 spikes/cluster, autoMerge true, seed 0, stim threshold 0.5, stim min ISI 1 s, response window 5–55 ms, baseline window −100–0 ms |
| `roi` | measure `All`, baselineFrames 30, line [] (no diameter), robust true, motionCorrection false, roiMask [] (from the file) |
| `features` | t0 0, autoBaseline true (pre-t0 part of the trace, as Signal Characterization on load), baselineStart 0 / baselineEnd 0.05 (used when autoBaseline is false), direction `Auto`, seriesMode `Mean of series` |

For MUA, the global stream is seeded (`rng(seed, 'twister')`) before every channel and restored afterwards. The seed does not depend on the file order.

`MUAPipeline.sort` console output is captured with `evalc` so the batch log stays readable.

The feature rules (baseline, `Auto` direction, the nine `SignalFeatures` calls) are copied from `SignalCharacterizationApp`'s local functions, which cannot be called from outside the app. If that app changes its rules, `Batch.seriesFeatures` must follow. Moving them to one shared core function would remove the duplication; that needs an edit to `SignalCharacterizationApp`, which was not in scope.

### `apps/BatchApp.m`

Layout (UIKit.window, 1440×860) has three columns:
1. Step 1 (Pipeline dropdown, input description, **Try demo batch**) and step 2 (**Add folder...**, **Add files...**, **Remove**, **Clear**, file list and count).
2. Step 3 (settings generated from `Batch.paramSpec`; the tooltips give units) and step 4 (output folder with **Output folder...**, **Cancel**, **Run batch**, progress line). This column scrolls for long settings.
3. Step 5 (**Open folder**, **Export...**, result line, then the summary table) above the log.

Table rows are tinted by Status: green ok, orange warning, red error, gray skipped. The Status cell is bold in the matching colour. While the batch runs, the table lists the queued files and updates each row's status. The status bar and the step-4 line show "File k of n: name". **Cancel** stops before the next file. Help topic: `Batch processing`.

Public, dialog-free methods:

```matlab
ok = app.setPipeline(name)        % key ('ldf', ...) or menu label
n  = app.addFiles(paths)          % files and/or folders; returns the number added
app.removeFiles(idx)              % default: the selected files
app.clearFiles()
app.setParams(struct)             % fills the fields; fields without a control are kept (e.g. roiMask)
p  = app.getParams()              % complete settings (Batch.completeParams)
app.setOutputFolder(folder)
[ok, R] = app.runBatch(outFolder) % ok = the batch ran (some files may have failed)
app.cancelBatch()
ok = app.exportSummary(path)      % .csv / .xlsx (table) or .mat (summary + batch)
ok = app.loadDemo(pipeline)       % default: the current pipeline
app.openOutputFolder()            % system file browser
```

Dialog wrappers used by the buttons are `addFolderDialog`, `addFilesDialog`, `chooseOutputFolder` and `exportDialog`. `updateControls()` sets every enable state:
- Run needs files;
- Open folder and Export need a result;
- everything except Cancel is disabled while running.

The next action is primary: Add files when the list is empty, Run batch when there are files and no result, and Open folder after the run.

### `core/demo/demoBatch.m`

`demo = demoBatch(pipeline, folder, n)` returns `folder`, `files`, `truth` (one per file) and `params` (settings that suit the demo). It is deterministic: `RandStream('mt19937ar', 'Seed', 20260930 + offset)`.

| Pipeline | Files | Truth per file k |
|---|---|---|
| `ldf` | 4 cropped LDF, 200 s at 1000 Hz, 7 stimuli (5 V, 5 s) at 10, 40, …, 190 s | amplitude 15 + 5k PU (20–35), peak delay 2.5 + 0.5k s (3–4.5), baseline 115 + 5k, 7 onsets, 6 trials (pre 5 / post 20 s) |
| `erp` | 3 LFP, 8 channels 100 µm apart, 20 s at 1000 Hz, 10 stimuli every 2 s | N1 at 9 + 3k ms (12, 15, 18) of −(80 + 20k) µV, P2 25 ms later; depth profile (SD 150 µm) centred on channel 2 + k = CSD sink (3, 4, 5) |
| `mua` | 2: the DemoData MUA recording, and the same with `mua_data × 2` (an exact scaling) | DemoData's truth plus the gain; demo params use channel 4 |
| `roi` | 3 stacks 64×64×100 at 10 Hz; cell disk (radius 5, `roiMask`) with F = F0(1 + ΔF/F); dark vertical vessel at x = 44 | peak ΔF/F ≈ 0.5k (0.5, 1.0, 1.5) at ≈ 3.2 s; mean diameter 8 + 2k px (10, 12, 14), ±2 px at 0.2 Hz; line `[25 50 63 50]` |
| `features` | 4 segmented-trial files, 8 trials, −5 to 20 s at 10 Hz | as `ldf`: amplitude 20–35 PU (truth = realized mean over trials), peak delay 3–4.5 s, baseline 120 |

## Tests

### `tests/LDFPipelineTest.m` (no display needed except one test; about 5 s)

- `testSegmentMatchesLegacyCode`: `LDFPipeline.segment` gives identical trials, time axis and onsets to a verbatim copy of the old app code. This is checked for 3 threshold / ISI settings, for column inputs, and for windows longer than the recording (0 trials, 9 onsets).
- `testDemoOnsetsAndTrials` (no toolbox): demo onsets are at `truth.onsets × Fs + 1` (±1 sample). The trial matrix is 8 × 25001 with a −5 to 20 s time axis.
- `testProcessMatchesLegacyCode` (Signal Processing Toolbox): `LDFPipeline.process` equals the old code (`AbsTol` 1e-12; identical stim, t, Fs, b, a) for 6 settings:
  - the walkthrough low-pass;
  - none;
  - decimation only;
  - FIR high-pass;
  - Chebyshev band-pass;
  - Butterworth notch.
- `testAppMatchesPipeline` (toolbox and display): `ProcessingLDFApp` is driven with `loadDemo` → `applyProcessingParams` (10×, Butterworth low-pass 1 Hz, order 4) → `segmentByOnsetsConfig`. Its `SegmentedLDF`, `SegmentedTime`, `Fs` and processed `LDF` equal `LDFPipeline.run` on the demo file (`AbsTol` 1e-12). `saveData` still writes exactly `segmentedLDF`, `segmentedTime`, `Fs`.
- `testDemoTruth` (toolbox): 100 Hz, 9 onsets, 8 trials. The mean trial peaks 4 ± 0.5 s after onset at 30 ± 5 PU above the pre-onset mean, and the baseline is 120 ± 8.
- `testErrors`: Nyquist and low ≥ high messages, `invalidFilter`, `noTrials`, `missingVars`, `filterMode`.

### `tests/BatchFeaturesTest.m` (about 10–40 s in MATLAB, depending on the MUA sorting time)

- `testLDF` (toolbox): the 4 demo files plus a corrupt text file named `.mat` and a `.mat` without the LDF variables, placed in the middle and at the end of the list. Checks:
  - statuses `ok ok error ok ok error` and non-empty messages; the missing-variables message is readable;
  - NaN features on the error rows;
  - per good file: 7 onsets, 6 trials, 100 Hz, peak latency ±0.4 s, amplitude ±3 PU, baseline ±8, amplitudes increasing with the file;
  - the trial files have the LDF Processing format (6 × 2501, −5 to 20 s, Fs 100);
  - CSV (readtable: same rows and names), MAT (`summary` and `batch`) and log (one `[k/n] file` line per file, the ERROR line, the settings) are written.
- `testERP` (folder input): 24 rows (8 per file). Per file:
  - the sink channel equals the truth;
  - at the sink: 10 epochs, N1 latency ±1.5 ms, N1 amplitude within 20%, CSD minimum negative at the N1 latency ±2 ms;
  - the largest N1 is on the sink channel.

  Channel subset with CSD off gives rows 2, 3, 4 and a NaN sink. A channel not in the file is an error row with "not in the file".
- `testROI`: per stack, peak ΔF/F ±0.1, its time ±0.15 s, mean diameter ±0.75 px, 10 Hz and 100 frames. Measure `Vessel diameter` alone gives the same diameter and a NaN ΔF/F. With no line it fails with "needs a line".
- `testFeatures`: per file, 8 series, peak latency ±0.35 s, amplitude ±1.5 PU, baseline ±1, and `DataType` `LDF segments`. The values are identical to `Batch.seriesFeatures` on the mean trial. `Each series` gives 16 rows for 2 files, named `Trial k`.
- `testMUA` (Signal + Statistics toolboxes): both demo files on channel 4. Checks:
  - 2–3 units, > 300 spikes, evoked rate > 3 × baseline rate, 15 onsets, mean SNR > 2;
  - the gain-2 copy gives the same spike count (`RelTol` 5%);
  - running file 1 again gives the same spikes and units;
  - the global random stream is the same after `Batch.run` as before.
- `testErrorsAndCancel`: a garbage `.mat`, an unsupported `.mat` and a missing path between good files give `ok error error ok ok error`, with the expected messages, and the outputs are written. A Progress callback that asks to cancel after file 2 gives `ok ok skipped`, `R.cancelled`, a `skipped` row and "cancelled" in the log.
- `testDefaultsAndInputs`:
  - every `paramSpec` name is a default;
  - `completeParams` gives all defaults;
  - an error-only table has all columns;
  - unknown pipeline and no-input errors are raised;
  - `listInputs` returns sorted `.mat` files only (`roi` also `.tif`) and mixes folders with files.

### `tests/BatchWalkthroughTest.m` (display needed; about 30–60 s)

`testBatchPipelines` drives the window and saves frames `BatchApp_x01..x10`:
- `x01_start`: Run is disabled.
- `x02_ldf_demo_loaded`: 4 demo files plus a corrupt file.
- `x03_ldf_summary_with_error`: 4 OK and 1 error; trials 6; amplitudes 20–35 ±3; latencies 3–4.5 ±0.4; red row 5; CSV written; log filled.
- `x04_ldf_file_removed`: after Export to CSV, the file is removed and the results are cleared.
- `x05_erp_settings`, then `x06_erp_summary`: sink channels 3/4/5; N1 12/15/18 ms ±1.5.
- `x07_roi_summary`: `getParams` returns line `[25 50 63 50]`; ΔF/F 0.5/1/1.5 ±0.1; diameters 10/12/14 ±0.75.
- `x08_features_each_series`: 32 rows.
- `x09_features_mean`: amplitudes 20–35 ±1.5.
- `x10_mua_settings`: channel 4 and MAD set; Clear disables Run.

The LDF frames are skipped without the Signal Processing Toolbox.

`testBatchMUA` (both toolboxes): the MUA demo batch in the window gives 2 OK, 2–3 units and equal spike counts. Frame: `BatchApp_x11_mua_summary`.

## Not verified / risks

- **Real MATLAB numerics for `ldf`.** The Octave run used simplified stand-ins for `decimate` and `filtfilt`. The measured amplitudes and latencies there were within 1.1 PU and 0.11 s of the truth, and the tolerances are ±3 PU and ±0.4 s. MATLAB's own filters should be at least as close, but this has not been seen.
- **MUA in the batch has not been run at all.** No findpeaks, pca or kmeans were available. Assumptions:
  - The demo assertions reuse the conditions of `MUAFeaturesTest.testDemo_autoMergeAndPSTH`: channel 4, MAD, k = 4, negative, `rng(0, 'twister')`.
  - The gain-2 copy is an exact power-of-two scaling, so detection is identical. PCA / k-means should then give the same labels, but LAPACK may round differently; the test allows 5%.
  - If `testMUA` fails, look at `R.summary` in the test output.
- **Layout is unrendered.** Please review `BatchApp_x*.png` and `BatchApp.png`, in particular:
  - the three-column window at 1440×860 (on smaller screens `UIKit.centeredPosition` shrinks it);
  - the settings card for MUA (13 fields; column 2 scrolls);
  - the row tints of the uitable;
  - the fifth Main card at 940 px height.
- `uistyle('FontWeight', 'bold')`, `addStyle(…, 'row' | 'cell', …)` and `removeStyle` need R2019b+, and `uilabel` `Interpreter` needs R2021a. This matches the repo minimum. `uitable` gets no Tooltip, since support in R2021a is uncertain.
- `openOutputFolder` uses `winopen` / `open` / `xdg-open`. It is not called by the tests.
- The Help button opens topic `Batch processing`, which does not exist until the text below is added. Until then HelpApp falls back to Welcome. `HelpApp.demoWindow('Batch processing')` should return `'BatchApp'`. `tryDemo` then calls `loadDemo()`, which loads the LDF demo batch.
- **Parallel work.** A session / report agent is adding `UIKit.sessionButtons` to other windows. `BatchApp` has no session buttons, and `ProcessingLDFApp` was changed here only in `applyFilter`, `getFilterMode`, `segmentLDFByOnsets` and the header. Merge conflicts should be limited to those spots.

## References

None cited. Every method used is either existing code (LDF processing, ERP / CSD with the Mitzdorf 1985 reference already in `ERPAnalysis`, MUAPipeline, the imaging functions, SignalFeatures) or simple bookkeeping.

## Ready-to-paste Help topic (`HelpApp`)

Add the title `Batch processing` to the header list of topic keys, then add a `topicBatch` function (listed after Signal Characterization) and map `'Batch processing'` to `'BatchApp'` in `demoWindow`.

```matlab
        %% topicBatch - Batch processing: one pipeline on many files
        function t = topicBatch()
            t = mkTopic('Batch processing', 'All pipelines · many files', ...
                'Run one analysis with the same settings on a whole folder and get one summary table.');
            t.quick = {
                '**1 Pipeline**: choose what to run on every file: **LDF: trials + response features**, **LFP: ERP (+ CSD) per channel**, **MUA: spike sorting per channel**, **Imaging: ROI dF/F and vessel diameter** or **Response features (any trace file)**. The line below says which files it reads. **Try demo batch** adds a few synthetic files with known answers and fills the settings.'
                '**2 Input files**: click **Add folder...** (every file of the folder that this pipeline reads) or **Add files...** (multi-select). Select files and click **Remove** to drop them; **Clear** empties the list. Files are processed in list order.'
                '**3 Settings**: one set of settings for every file (hover a field for its unit and meaning). They are the settings of the matching window: e.g. downsampling, filter and trial window for LDF; epoch, N1 window and electrode spacing for LFP; detection, clustering and random seed for MUA.'
                '**4 Run**: choose the **Output folder...** and click **Run batch**. The table and the status bar show which file is being processed; **Cancel** stops before the next file. A file that fails does not stop the batch: it gets a red row with the reason.'
                '**5 Results**: one row per file (LFP and MUA: per channel; imaging: per ROI). Green = ok, orange = warning (some channels failed), red = error, gray = skipped. **Open folder** shows the summary (.csv and .mat), the log (.txt) and, for LDF, the trial files; **Export...** saves a copy of the table (.csv, .xlsx or .mat).'};
            t.demo = {
                '* **Data**: **Try demo batch** writes synthetic files for the chosen pipeline, each with slightly different known answers, and fills the settings.'
                '* **LDF**: 4 cropped recordings (200 s, 7 stimuli of 5 s). **What you should get**: 7 onsets and **6 trials** per file (the last stimulus is too close to the end); peak latency **~3, 3.5, 4 and 4.5 s** and peak amplitude **~20, 25, 30 and 35 PU** (within ~2 PU); one trial file per recording in the trials folder.'
                '* **LFP**: 3 recordings, 8 channels 100 µm apart. **What you should get**: 8 rows per file; the N1 is largest and the CSD sink (SinkChannel) is on **channel 3, 4 and 5**, with the N1 at **~12, 15 and 18 ms** (about −90, −115 and −135 µV).'
                '* **MUA**: the demo MUA recording and a copy recorded at twice the gain, channel 4. **What you should get**: **2–3 units** and the **same spike count in both files** (sorting does not depend on the gain); the evoked rate (5–55 ms after each stimulus) is several times the baseline rate.'
                '* **Imaging**: 3 stacks with a cell (roiMask) and a vessel crossed by the line 25 50 63 50. **What you should get**: peak ΔF/F **~0.5, 1.0 and 1.5** at ~3.2 s and mean vessel diameter **~10, 12 and 14 px**.'
                '* **Response features**: 4 trial files. **What you should get**: peak latency ~3, 3.5, 4, 4.5 s and peak amplitude ~20, 25, 30, 35 PU (one row per file); Series = Each series gives one row per trial (32 rows).'};
            t.inputs = {
                'LDF: cropped `.mat` files from LDF Extract (`stim`, `LDF`, `t`, `Fs`)'
                'LFP: `.mat` files from Extract Ephys (`lfp_data`, `stim_data`, `lfp_fs`, `stim_fs`; `t_lfp`, `lfp_channels` optional)'
                'MUA: `.mat` files from Extract Ephys (`mua_data`, `mua_fs`; `t_mua`, `mua_channels`, `stim_data` + `t_stim` optional)'
                'Imaging: `.mat` with `stack` (or `frames`), optional `timeVec` / `t` and `roiMask` / `roiMasks`, or a multi-frame TIFF'
                'Response features: any file Signal Characterization reads (`segmentedLDF` + `segmentedTime`, `lfp_data` + `t_lfp`, `t` + `y`, `t` + `LDF`)'};
            t.outputs = {
                '`<name>_summary.csv` and `<name>_summary.mat` (table `summary` + struct `batch` with the settings, files, statuses and log): columns File, Status, Message, then the pipeline''s results'
                '`<name>_log.txt`: date, settings and one line per file (result or error)'
                'LDF: `trials/<file>_segments.mat` per recording (`segmentedLDF`, `segmentedTime`, `Fs`), ready for LDF Average'};
            t.details = {
                '## What each pipeline measures'
                '* **LDF**: the LDF Process steps (decimate, filter, cut trials around each onset), then the response features of the **mean trial** (onset 0 s, baseline = the pre-onset part): peak latency and amplitude, onset delay, FWHM, AUC, rise and decay time, integral.'
                '* **LFP**: ERP per channel as in LFP Analysis (onsets on the mean-subtracted stimulus). **N1** = minimum in the N1 window, **P2** = maximum in the P2 window; latency in ms after the stimulus, amplitude relative to the pre-stimulus mean, multiplied by Amplitude scale (1e6: V to µV). With **Compute CSD** (≥ 3 channels, in the listed order, top to bottom): the CSD minimum in the N1 window per channel (AmpUnit / mm²) and the sink channel of the file.'
                '* **MUA**: spike sorting per channel as in MUA Analysis. The random generator is set to **Random seed** before every channel, so the same file always gives the same clusters, whatever its position in the list. Per channel: spikes in units, units (good / rejected by the quality check: SNR < 2 or > 2% ISIs below the refractory period), mean rate and rate per unit, mean SNR, worst ISI violation and, with a stimulus, the rate in the response window vs the baseline window.'
                '* **Imaging**: per ROI the mean brightness and ΔF/F (F0 = mean of the first baseline frames) with its peak and peak time; with a line, the vessel diameter (FWHM; **Robust diameter** ignores red blood cells) as mean, min and max. No smoothing or normalisation is applied; **Motion correction** registers every frame onto the mean image first.'
                '* **Response features**: the nine features of Signal Characterization, for the mean of the series in each file or for every series.'
                '## Good to know'
                '* Channels are the numbers saved in the file (`lfp_channels` / `mua_channels`), otherwise the row numbers. Empty = all channels.'
                '* Vector fields take numbers separated by spaces, e.g. `5 50` for a window or `45 70 75 70` for a line.'
                '* The same pipelines run from scripts: `R = Batch.run(''ldf'', folder, params, outFolder)`; `Batch.defaults(''ldf'')` lists the settings.'};
            t.trouble = {
                'A row is red with "Missing variable(s)"', 'The file was not saved by the step this pipeline expects (e.g. a raw LabChart export in the LDF pipeline). Use the files named under Inputs, or choose the matching pipeline.'
                'A row is red with "Unable to read" / "not a binary MAT-file"', 'The file is damaged or not a MAT file. Remove it (select it, **Remove**) or re-export it; the other files are not affected.'
                'LDF: "No stimulus onsets found above threshold"', 'The stimulus never crosses **Stim threshold**: lower it (e.g. 0.5 for a 1 V trigger, 2.5 for 5 V TTL).'
                'LDF: "no complete trial fits"', 'Pre-onset + Post-onset is longer than the recording around the stimuli: shorten the windows.'
                'LFP: "Channel(s) … not in the file"', 'The Channels field lists numbers the file does not have: clear it (all channels) or use the numbers shown in LFP Analysis.'
                'MUA: a red channel row (file orange) with "Too few spikes for clustering"', 'That channel has almost no spikes at this threshold: lower Threshold (k) or Min spikes / cluster, or leave the channel out; the other channels of the file are kept.'
                'Imaging: "needs a line" or no diameter columns', 'Type the line across the vessel in **Line x1 y1 x2 y2 (px)** (read the coordinates in ROI Analysis).'
                'Imaging: "No ROI"', 'The stacks have no `roiMask`: draw and export ROIs in ROI Analysis, or measure Vessel diameter only.'
                'The batch takes long', 'MUA sorting is the slowest part (seconds per channel): select only the channels you need. **Cancel** stops after the current file and still writes the summary of the files done.'};
            t.images = {};
        end
```

## CHANGELOG line

```text
- Batch processing: new window (Main → Batch processing) and `core/Batch.m` run one pipeline (LDF trials + response features, LFP ERP/CSD per channel, MUA spike sorting per channel, imaging ΔF/F and vessel diameter, response features) on a folder of files with one set of settings, writing one summary table (CSV + MAT) and a log; files that fail are listed with their error and the batch goes on. LDF Processing's filtering and trial cutting moved to `core/LDFPipeline.m` (same results).
```
