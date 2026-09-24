# Wave 1 report: imaging (robust vessel diameter, motion correction, multiple ROIs, cell detection)

Classification: part of the wave-1 EXISTING STRAND (area: imaging / ROI analysis).
Nothing here has been run in real MATLAB yet. What was checked:

- The numeric core and `tests/ImagingFeaturesTest.m` ran in Octave 8, with a
  `RandStream` shim and `verify*` shims (all 16 tests pass, about 4 s).
- The existing `tests/ImagingTest.m` and `DemoDataTest/testImagingGroundTruth`
  still pass in Octave.
- `apps/ROIAnalysisApp.m` was parse-checked. Its logic was then driven end to
  end in Octave with the real `UIKit` and permissive stubs for the `ui*` and
  graphics functions. See "Verification".

## Files

Changed
- `apps/ROIAnalysisApp.m` (+1047 / −292 lines): multiple ROIs, rigid motion correction, cell detection, robust diameter, advanced demo, dialog-free export.
- `core/imaging/vesselDiameterFromLine.m` (+183 / −43 lines): the walls are located to sub-pixel precision; optional robust mode; extra outputs. The signature is unchanged.

New
- `core/imaging/registerStackRigid.m`: rigid motion correction (FFT phase correlation, sub-pixel).
- `core/imaging/localCorrelationImage.m`: mean correlation of each pixel with its 8 neighbours.
- `core/imaging/detectCellsFromCorrelation.m`: threshold, connected components (bwlabel or a toolbox-free flood fill), then area, elongation and hole filling. Returns a list of masks.
- `core/imaging/robustTimeSeries.m`: Hampel filter (running median / MAD).
- `core/demo/demoImagingAdvanced.m`: jittered stack with 3 cells, a vessel and an RBC that crosses the diameter line, with its ground truth.
- `tests/ImagingFeaturesTest.m`: 16 unit tests.
- `tests/ImagingWalkthroughTest.m`: 2 UI walkthroughs that save frames `ROIAnalysisApp_x01..x08_*.png`.
- `docs/dev/reports/imaging.md`: this report.

`git diff --stat` for the tracked files:
```
 apps/ROIAnalysisApp.m                 | 1339 ++++++++++++++++++++++++++-------
 core/imaging/vesselDiameterFromLine.m |  226 ++++--
 2 files changed, 1230 insertions(+), 335 deletions(-)
```

## New public API

### core/imaging (base MATLAB only; `bwlabel` is optional)

```matlab
[diameter, t, profile, isOutlier, info] = vesselDiameterFromLine(stack, lineStart, lineEnd, timeVec, method, Name, Value, ...)
%   Old calls are unchanged. Options can also follow the line directly:
%   vesselDiameterFromLine(stack, p1, p2, 'Robust', true).
%   Options:
%     'SubPixel' (true)        wall position interpolated between samples ('fwhm')
%     'Robust' (false)         see below
%     'Window' (7)             Hampel window, frames
%     'NMad' (3)               Hampel threshold, robust SDs
%     'EdgeFraction' (0.15)    share of samples at each end used as background
%     'CorePercentile' (2)     percentile of the profile used as vessel core
%     'Polarity' ('dark')      'bright' for a fluorescent lumen
%     'LineWidth' (1)          number of parallel lines averaged
%   isOutlier (1 x N): frames the Hampel filter replaced.
%   info: rawDiameter, edges (N x 2, px from lineStart), level (N x 2),
%         baseline (N x 2), core, spacing.

[registered, shifts, info] = registerStackRigid(stack, ref, opts)
%   ref: 'mean' (default), a frame index, or an H x W image.
%   opts (struct or name-value): MaxShift, PeakSigma (1), PeakFit ('gaussian'|'parabolic'),
%     Iterations (2), Apply ('interp'|'fft'), Taper (0.25).
%   shifts: N x 2 [dy dx], the displacement of each frame's content.
%     With ref = 'mean' the shifts have zero mean.
%   info: reference, peak (1 x N), iterations, validMask (pixels inside every shifted frame).

C = localCorrelationImage(stack, 'HighPass', frames)       % H x W, in [-1, 1]

[masks, props, labels, thr] = detectCellsFromCorrelation(C, opts)
%   opts: Threshold ('auto' = median + NSigma * 1.4826 * MAD, at least MinThreshold),
%     NSigma (4), MinThreshold (0.2), MinArea (20), MaxArea (1000), MaxElongation (3),
%     FillHoles (true), MaxCells (Inf), UseToolbox (true), BorderMargin (0 px).
%   masks: 1 x K cell of logical masks.
%   props: centroid [x y], area, meanCorr, peakCorr, elongation, bbox.

[y, isOutlier, med, sigma] = robustTimeSeries(x, window, nMad)   % Hampel filter, defaults 7 / 3
```

### core/demo

```matlab
s = demoImagingAdvanced(opts)        % opts: Jitter (true), RBC (true), Seed (20260965)
%   s.stack: 96 x 96 x 150 single. s.timeVec: 10 Hz.
%   s.truth: shifts, cellCenters, cellRadii, cellMasks, eventTimes, dff, cellF0,
%     vesselCenterX, diameter, lineStart, lineEnd, rbcPath, rbcSpeedPxPerFrame,
%     rbcCrossFrames, rbcAmplitude.
```

### apps/ROIAnalysisApp

All existing public methods and the constructor are kept: `openFile`, `loadDemo`, `setROIMask`, `setLine`, `runAnalysis`, `showFrame`, `drawROI`, `drawLine`, `clearShapes` and the others. The new public, dialog-free methods are:

```matlab
ok  = app.loadAdvancedDemo()        % generates demoImagingAdvanced; truth in app.DemoTruth
ok  = app.setMotionCorrection(tf)   % estimates the shifts the first time
ok  = app.runMotionCorrection()     % registers to the mean (2 passes), plots the shifts
n   = app.detectCells(opts)         % opts: any detectCellsFromCorrelation option; returns #cells
idx = app.addROI(mask, name)        % name optional
      app.removeROI(idx)            % idx optional: selected row, else last
      app.renameROI(idx, name)
      app.setRobustDiameter(tf)
      app.setDisplay(mode)          % 'first' | 'mean' | 'correlation' (prefix ok)
ok  = app.exportResultsTo(path)     % .csv or .mat, no dialog; exportResults() now calls it
```

New public properties:
- `ROIs`: struct array with fields Id, Name, Mask, Position, Source, Handle.
- `Shifts`, `RegStack`, `RegValid`, `CorrImage`, `DemoTruth`, `DetectThreshold`.
- `DiameterPlain`, `DiameterRaw`, `DiameterOutliers`.
- `ResultROINames`, `ResultROIMasks`.
- UI handles: `MotionCb`, `MotionLabel`, `DetectBtn`, `AdvDemoBtn`, `RobustCb`, `ROITable`, `RemoveROIBtn`, `DisplayDropdown`, `DetectThresholdEdit`, `AxesMotion`, `ResultTabs`, `ResultTab`, `MotionTab`.

ROI-based results are now **K x N**, one row per ROI. With one ROI this is 1 x N, as before.

## Behaviour changes and backward compatibility

- **vesselDiameterFromLine: sub-pixel walls are now the default for 'fwhm'.** I treat this as a strict improvement that still passes the old tests:
  - Before, the width was a count of samples times `lineLen / nPix`. That value was quantised, and also slightly mis-scaled, because the samples are `lineLen / (nPix − 1)` apart.
  - Now each wall is located by linear interpolation between the two samples that straddle the half level.
  - The half level is still the min/max midpoint by default.
  - Numbers:

    | Case | Before | Now | Check |
    |---|---|---|---|
    | `ImagingTest` 10 px band | 9 | 9.84 | tolerance ±1.5 |
    | DemoData stack, mean (truth 12) | 12.04 | 12.27 | tolerance ±3 |
    | DemoData stack, max error | 1.45 px | 0.92 px | |
    | Synthetic soft-walled vessels 6–18 px, max error | 0.84 px | 0.15 px | |

  - `'SubPixel', false` restores the old counting.
  - `'threshold'` is still the old sample count.
- **Robust mode (`'Robust', true`)** is opt-in. It works in three stages:
  - **Levels.** The background comes from the median of the first and last 15 % of samples, with one level per wall. The vessel core is the 2nd percentile of the profile. Both are then replaced by their running medians over the Hampel window, because a red blood cell that fills the lumen raises the core for 1–2 frames.
  - **Walls.** The walls are the outermost crossings of the half level, so a bright spot inside the lumen moves neither the level nor the walls.
  - **Temporal filter.** A Hampel filter over time replaces the remaining spikes. It also fills frames where the lumen was hidden: those frames have no width and are NaN before the filter.
  - Without robust mode, textured backgrounds can also break the min/max level: on some seeds, frames with no RBC nearby jump by about 20 px. Robust mode fixes those too.
- **ROI app:**
  - **Add ROI** (formerly **Draw ROI**) now *adds* a rectangle; it no longer replaces the previous one.
  - `setROIMask(mask)` still replaces all ROIs with that single mask (single-ROI semantics).
  - Drawn rectangles stay editable. Moving one updates its mask and clears the results, as before.
  - **Clear ROIs and line** removes drawn, added and detected ROIs and the line. ROIs from the file or from `setROIMask` are kept, as the old roiMask was.
  - Loading a new stack unticks **Motion correction** and drops all caches.
  - The app plots ROI traces in their ROI colours: `UITheme.plotColors` rows 1–5 and 7, with sky blue kept for the line. ROI 1 is blue (the ΔF/F trace used to be purple).
  - Movement and Speed alone are now drawn on the left axis. **Both** keeps the left/right axes. With one ROI it keeps the old colours and the Brightness/Movement legend.
  - Setting the public property `app.ROIMask` directly no longer defines the ROI (it now mirrors ROI 1). Scripts must use `setROIMask` / `addROI`; the documented API already did.
  - A `.mat` may now hold `roiMasks` (H x W x K), with optional `roiNames`, as well as `roiMask`. The file's `truth` is kept in `DemoTruth`.
- **ROI app layout:**
  - The window is 1200 x 900 (was 840).
  - Left column: 1 Load stack (adds **Try advanced demo (motion, 3 cells)**), 2 Preprocess (adds **Motion correction (rigid)** plus a "max shift" indicator), 3 ROIs and line (**Add ROI**, **Detect cells**, **Draw line**, **Clear ROIs and line**), 4 Analysis (adds **Robust diameter (ignore blood cells)**), 5 Export.
  - Right, top: the image (**Show**: First frame / Mean image / Correlation image), with the ROI table, **Remove ROI** and **Detect: min correlation** beside it.
  - Right, bottom: tabs **Result** and **Motion correction** (estimated dy/dx; the true shifts are dashed for the advanced demo).
  - The left cards add up to about 740 px. The column is still scrollable if the screen is smaller.

## Tests

`tests/ImagingFeaturesTest.m` (headless; about 4 s in Octave)

| Test | Checks |
|---|---|
| `testAdvancedDemoTruth` | sizes; jitter within ±3 px and zero-mean; RBC crossings exist; deterministic |
| `testRegistrationRecoversDemoShifts` | `'mean'` reference: every frame's [dy dx] within **0.3 px** of truth. Octave, 20 seeds: max 0.17 |
| `testRegistrationToFrameOne` | frame-1 reference within 0.4 px (a single noisy frame is a weaker reference; Octave, 20 seeds: max 0.28) |
| `testRegistrationValidMask` | `validMask` matches the shift extent |
| `testRegistrationAlignsTheScene` | after correction the RMS difference from the jitter-free stack is less than half of before |
| `testRegistrationFourierShiftAndOptions` | exact Fourier-shifted image [1.3 −2.6] recovered within 0.1 px (`'Apply','fft'`); parabolic fit; RGB 4-D input |
| `testSubPixelDiameterOnSyntheticProfiles` | soft-walled vessels 6–18 px: max error **< 0.5 px** (default and robust), better than sample counting |
| `testSubPixelDiameterDiagonalAndBright` | 45° vessel (10.6 px) and `'Polarity','bright'` within 0.5 px |
| `testRobustDiameterRemovesRbcSpikes` | jitter-free demo: standard error > 10 px at RBC crossings. Robust: max error < 2.5 px, RMS < 1 px, crossing frames flagged. Octave, 20 seeds: max 1.72, RMS ≤ 0.86 |
| `testRobustDiameterAfterMotionCorrection` | robust diameter on the registered stack < 2.5 px (also with `'LineWidth', 3`) |
| `testVesselDiameterLegacyForms` | `'threshold'` and `'SubPixel', false` give the old count (9); options right after the line |
| `testRobustTimeSeriesFlagsSpikes` | exactly the injected spikes and NaN are flagged; a clean sine is untouched |
| `testLocalCorrelationImage` | coherent patch > 0.9, independent noise ≈ 0, constant pixels 0 |
| `testDetectCellsFindsDemoCells` | exactly 3 cells on the registered demo, centres **within 3 px** (Octave: ≤ 0.2 px); the toolbox-free labelling gives identical masks |
| `testMultiRoiDffPeaksAtEventTimes` | ΔF/F of each detected cell peaks within 0.5 s of **its own** events; no cross-talk (< 0.1) outside them |

`tests/ImagingWalkthroughTest.m` (UI; skipped without a display). Each frame goes to `test-artifacts/screens/walkthrough/ROIAnalysisApp_x<NN>_<step>.png`.

`testROIAdvancedDemo`:

| Frame | Step | Checks |
|---|---|---|
| x01 | `loadAdvancedDemo` | no ROIs yet |
| x02 | `runMotionCorrection` (Motion correction tab) | shifts within 0.3 px |
| x03 | `setDisplay('correlation')` + `detectCells` | 3 cells within 3 px |
| x04 | `runAnalysis('dff')` | 3 x N traces peaking at each cell's events |
| — | `exportResultsTo` .csv and .mat | Time + 3 DFF columns; 3 masks, 3 names, motionCorrection true |
| x05 | Vessel diameter, standard | error > 10 px at crossings |
| x06 | Vessel diameter, robust | error < 2.5 px; frames replaced |

`testROIMultiRoiEditing` (basic demo):

| Frame | Step | Checks |
|---|---|---|
| — | `loadDemo` | roiMask becomes ROI 1 |
| x07 | `addROI` (background) + ΔF/F | 2 x N; cell peaks at 3/7/11 s; background flat |
| — | `renameROI` and `removeROI` | results cleared |
| x08 | `setMotionCorrection(true)` on a motion-free stack, then **Both** | shifts < 0.3 px; the Both run succeeds |

## Verification (Octave 8)

- **Registration.** Default demo: max error 0.13 px. Over 20 seeds: 0.10–0.17 px (mean reference), 0.17–0.28 px (frame-1 reference).
  - Taper 0.25 was chosen because 0.1 gave up to 0.68 px with the frame-1 reference.
  - On the original DemoData stack (no motion), the estimated shifts are ≤ 0.11 px.
- **Detection.** 3/3 cells on 20/20 seeds once `BorderMargin` = max shift (without it, 1 seed had an edge-copy blob in a corner). On the original demo it finds the single cell and rejects the vessel.
- **ROI app, end to end with UI stubs.** The real `UIKit` and app code ran every step:
  - advanced demo, motion correction (0.15 px), `detectCells` (3), ΔF/F per cell (peaks within 0.2 s);
  - .mat export, standard vs robust diameter (40.3 vs 1.07 px), Kymograph, Brightness, Movement, Both, Speed;
  - rename, remove (selected), add, Motion correction off/on, clear;
  - loading a `.mat` with `roiMask` and with `roiMasks` + `roiNames`, and the legacy ΔF/F / vessel / kymograph flow;
  - the no-toolbox `drawrectangle` alert.
  - Both walkthrough tests pass there, except the parts the stubs cannot cover (tab lookup, `exportapp`, CSV via `table`).

**Unverified (needs real MATLAB / CI):**
- Real rendering and layout: card heights, the 250 px ROI panel, the uitable colour styles (`addStyle`/`uistyle`, wrapped in try/catch).
- `drawrectangle` / `drawline` re-creation after redraws.
- The CSV branch of `exportResultsTo` (`table` / `writetable` / `makeValidName`).
- `legend` with `yyaxis`.
- Exact numbers under MATLAB's `RandStream`. Octave used a shim, so the random realisations differ from MATLAB's; tolerances were set from the 20-seed spread.

## References

No citations were added to the headers. Needs reference (the methods are described in the headers without a citation):
- **FFT phase correlation for image registration** (`registerStackRigid`). A likely source is Kuglin & Hines (1975), IEEE conf. on Cybernetics and Society. **Verify the details before citing.** The Gaussian-weighted cross-power spectrum with a 3-point log-parabola peak fit is a standard refinement and needs no reference.
- **Hampel identifier / filter** (`robustTimeSeries`), the running median ± k·1.4826·MAD. Commonly attributed to F. R. Hampel's robust-statistics work. **Verify before citing.**
- **Local cross-correlation image for finding active cells** (`localCorrelationImage`). Widely used in 2-photon calcium imaging (e.g. Smith & Häusser 2010, Nat. Neurosci.). **Verify before citing.**

## Wiring suggested for the lead

- **DemoData:** add a kind `'imagingAdvanced'`:
  - `DemoData.file('imagingAdvanced')` → `demoImagingAdvanced()`, file `demo_imaging_advanced.mat` (`stack`, `timeVec`, `truth`; no `roiMask`);
  - add it to `writeAll`.
  - `loadAdvancedDemo()` currently generates the data in memory (about 0.3 s) and does not need this.
- **Path:** `core/demo` must be on the path. `NeuroAnalyzer.m` / `run_tests.m` already add it (commit 95c4b69); `loadAdvancedDemo` also adds it if missing.
- **`core/imaging/README.md`** (not mine; ready to paste):
  ```markdown
  ## Motion correction
  - **registerStackRigid** – Rigid (translation) registration by FFT phase correlation with sub-pixel peak fit; reference = mean (2 passes), a frame, or an image. Returns shifts [dy dx] per frame and a valid-pixel mask.

  ## Cell detection
  - **localCorrelationImage** – Mean correlation of each pixel's time series with its 8 neighbours (active cells bright).
  - **detectCellsFromCorrelation** – Threshold (auto: median + 4 robust SD), connected components (bwlabel or toolbox-free), area / elongation limits, hole filling → list of masks.

  ## Robust time series
  - **robustTimeSeries** – Hampel filter (running median ± 3 × 1.4826 MAD); returns cleaned series and outlier mask.

  (Vessel diameter: now sub-pixel; 'Robust', true ignores blood cells crossing the line.)
  ```
- **`tests/README.md`:**
  - ImagingFeaturesTest: registration, sub-pixel and robust vessel diameter, Hampel filter, correlation image and cell detection, per-cell ΔF/F against `demoImagingAdvanced` truth.
  - ImagingWalkthroughTest: ROI window advanced tools, frames `ROIAnalysisApp_x01..x08`.
- **CHANGELOG (Unreleased):**
  - ROI analysis: rigid motion correction (phase correlation, sub-pixel), multiple ROIs (table, add/remove/rename, per-ROI traces and export), automatic cell detection from the local correlation image, correlation/mean image display.
  - Vessel diameter: sub-pixel walls, and an optional robust mode that ignores blood cells crossing the line.
  - New advanced imaging demo.

## Help text (ready to paste into `HelpApp.topicROIAnalysis`)

Quick start (replaces the current `t.quick`):
```
'**1 Load stack**: click **Load stack** and choose a .mat or multi-frame TIFF (or **Try demo data** / **Try advanced demo (motion, 3 cells)**). The first frame is shown with the size, frame count and time source; a `roiMask` / `roiMasks` in the file becomes the first ROI(s).'
'**2 Preprocess (optional)**: tick **Motion correction (rigid)** if the frames jitter — the shifts are estimated once (max shift shown next to the box, per-frame plot in the **Motion correction** tab) and applied before everything else. Then optionally **B&W 256 levels**, **Smooth** and/or **Normalize each frame**, applied in that order when you click Run.'
'**3 ROIs and line**: click **Add ROI** and drag a rectangle (repeat for more ROIs), or **Detect cells** to add one ROI per active cell automatically. ROIs are listed next to the image (double-click a name to rename, **Remove ROI** to delete). For line methods click **Draw line** (across the vessel for diameter). **Clear ROIs and line** starts over.'
'**4 Analysis**: choose the **Method** (for ΔF/F also the baseline frames; for Vessel diameter optionally **Robust diameter (ignore blood cells)**) and click **Run**. ROI methods give one trace per ROI, in the ROI''s colour.'
'**5 Export**: click **Export results** to save a .csv (time + one column per measure and ROI) or a .mat (all series, ROI masks and names, line, shifts and settings).'
```

Demo data (append to `t.demo`):
```
'* **Advanced demo** (**Try advanced demo (motion, 3 cells)**): 96 × 96 px, 150 frames at 10 Hz. Every frame is shifted by up to **±3 px** (smooth random walk); **three cells** — cell 1 at (22, 24) with events at **4, 8.5, 13 s**, cell 2 at (26, 78) at **5.5, 10.5 s**, cell 3 at (82, 30) at **7, 12 s**; the vessel at x = 60 (12 ± 3 px, period 5 s) and a bright **red blood cell that crosses the diameter line** (35, 64)–(85, 64) about every 3 s.'
'* **Motion correction**: the Motion correction tab shows dy and dx following the dashed true shifts (error < 0.3 px), max shift ≈ 3 px.'
'* **Show → Correlation image**: the three cells are bright disks (correlation ≈ 0.9), the vessel a bright band; **Detect cells** adds exactly **Cell 1–3** (the vessel is rejected as too elongated).'
'* **ΔF/F** (Run): three traces, each peaking only at its own cell''s event times.'
'* **Vessel diameter**: without Robust diameter the trace jumps to ~50 px whenever the blood cell crosses the line; with **Robust diameter** it follows the 9–15 px sine (error < 2.5 px) and the replaced frames are circled.'
```

Troubleshooting (add to `t.trouble`):
```
'Detect cells finds nothing', 'Tick **Motion correction** first: residual motion makes every edge look correlated and raises the automatic threshold. Otherwise lower **Detect: min correlation** (e.g. 0.3; 0 = automatic).'
'Detect cells also picks up vessels or blobs at the border', 'Elongated structures (ratio > 3) and components outside 20–1000 px are rejected; after motion correction the border within the largest shift is ignored. Remove unwanted ROIs with **Remove ROI**.'
'Two touching cells become one ROI', 'Raise **Detect: min correlation** so they separate, or draw them with **Add ROI**.'
'Vessel diameter jumps for single frames', 'A bright blood cell crossing the line moves the half level. Tick **Robust diameter (ignore blood cells)**; make the line extend at least one vessel radius beyond each wall so its ends sample the background.'
'Motion correction shifts look noisy / wrong', 'It corrects translation only (not rotation or warping) and needs structure in the image; very dim or uniform stacks give unreliable shifts. Untick it to go back to the raw frames.'
'ROIs are slightly off after turning motion correction on or off', 'ROIs and the line keep their pixel positions; re-run **Detect cells** or redraw them on the image you analyse.'
```

Details (append to `t.details`):
```
'## Advanced'
'* **Motion correction (rigid)**: every frame is aligned to the mean image by FFT phase correlation with a sub-pixel peak fit (two passes), then shifted back (bilinear). Translation only.'
'* **Multiple ROIs**: every ROI method gives one trace per ROI; the ROI table shows number (in the trace colour), name, area and source (file, drawn, detected, added).'
'* **Detect cells**: local correlation image (mean correlation of each pixel with its 8 neighbours), threshold (automatic: median + 4 robust SD, at least 0.2), connected components of 20–1000 px that are not elongated, holes filled.'
'* **Robust diameter**: background from the line ends and vessel core from a low percentile (both as running medians over 7 frames), outermost half-level crossings, then a Hampel filter (7 frames, 3 robust SD) replaces remaining spikes. Walls are located to sub-pixel precision in all modes.'
```

Outputs (replace the two `t.outputs` lines):
```
'.csv: `Time` plus one column per measure (Intensity, Movement, DFF, Speed; with several ROIs `<measure>_<ROI name>`), or `Diameter_px` (+ `Diameter_standard_px`, `Replaced` when robust); for a kymograph, a matrix (first row = time)'
'.mat: struct `results` with the series (one row per ROI), `roiMasks` / `roiNames`, `roiMask` (ROI 1), `lineStart` / `lineEnd`, `motionCorrection` and `shifts`, and the preprocessing and diameter settings'
```

Inputs (replace the "Optional in the .mat" line):
```
'Optional in the .mat: `timeVec` or `t` (one time per frame), `roiMask` (logical H × W) or `roiMasks` (H × W × K, optional `roiNames`), used as the first ROIs'
```
