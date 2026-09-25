# Changelog

All notable changes to NeuronalDataAnalyzerLab are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-09-25

### Added

- **CSD methods** in LFP Analysis: inverse CSD (iCSD delta / step /
  spline; Pettersen et al. 2006) and kernel CSD (kCSD with R and λ chosen
  by cross-validation; Potworowski et al. 2012) next to the unchanged
  standard CSD (`core/CSDMethods.m`). Step 4 has a Method dropdown with
  the parameters of the chosen method; exports and sessions store the
  method and its parameters; `core/demo/demoCSD.m` gives laminar data with
  a known CSD.
- **Repeated-measures statistics** in Signal Characterization → Groups &
  statistics: design *Repeated measures (same animals, 3+ conditions)*
  with repeated-measures ANOVA (partial and generalized η², Mauchly's
  test, Greenhouse–Geisser / Huynh–Feldt corrections, Holm-corrected
  paired t-tests with d_z and CI) and the Friedman test (Kendall's W,
  Holm-corrected Wilcoxon tests).
- **Logo and icon**: the NeuroAnalyzer logo in the launcher and Help
  headers, and as the window icon of every window.
- **Help → Learn more ↗** opens the matching page of the website.

### Fixed

- **Website**: the menu marks the current page on hosts that serve pages
  without `.html` (Cloudflare); fonts are hosted with the site (no
  requests to third-party servers).

## [0.2.0] - 2026-09-25

### Changed

- **Redesigned every window** on a shared UI kit (`core/UIKit.m`): numbered
  step cards (Load → Settings → Run → Save), plots on the right, a status
  bar that says what happened and what to do next, in-window alerts,
  controls enabled only when their step is possible, tooltips and units
  everywhere, and a colourblind-safe plot palette. Legacy `figure` windows
  are now `uifigure`s; results that used to open extra figure windows are
  shown in tabs.
- **Help** has a topic list with a quick start, inputs and outputs,
  expected demo results and troubleshooting for every window.

### Added

- **Demo data** (`core/DemoData.m`): synthetic LDF, electrophysiology, MUA
  and imaging recordings with known ground truth. Every window has a
  *Try demo data* button, Help has *Try it with demo data* per topic, and
  the launcher links to it.
- **CI walkthroughs**: every window is opened and driven through its steps
  on demo data in real MATLAB; the frames are uploaded as a CI artifact
  (kept 7 days).
- **MUA Analysis**: auto-merge of over-split clusters (mean-waveform
  correlation and amplitude ratio), manual *Merge selected* / *Split
  selected* / *Undo*, *Raster & PSTH* and *Correlograms* tabs; the sorting
  runs headless via `core/MUAPipeline.m`.
- **LFP Analysis**: time–frequency step (Welch spectrum, spectrogram,
  Morlet ERSP / ITPC, band power); headless ERP / CSD in
  `core/ERPAnalysis.m`.
- **ROI Analysis**: rigid motion correction (phase correlation), several
  ROIs with one trace each, automatic cell detection (local correlation
  image), and a sub-pixel, blood-cell-robust vessel diameter.
- **Extract Ephys** loads Intan RHD2000 (.rhd), Open Ephys binary and
  NWB 2.x recordings (`core/io`); *Export NWB…* writes the processed LFP as
  NWB (matnwb when installed, otherwise an NWB-style export, not
  validated).
- **Signal Characterization**: *Groups & statistics* tab (paired / Welch
  t-test, one-way ANOVA with Tukey–Kramer, Wilcoxon, Mann–Whitney,
  Kruskal–Wallis, effect sizes with 95% CI) and publication figure export
  (vector PDF / SVG / EPS, 300 / 600 dpi PNG / TIFF) in `core/GroupStats.m`
  and `core/FigureExport.m`.
- **More demo data** (`core/demo/`, reachable via `DemoData.file`): LFP
  with theta and evoked gamma, a jittered imaging stack with three cells,
  three groups of eight animals, and the demo tank as Intan, Open Ephys
  and NWB files. Help covers every new feature with its expected demo
  results.
- **Batch processing**: new window (Main → Batch processing) and `core/Batch.m` run one pipeline (LDF trials + response features, LFP ERP/CSD per channel, MUA spike sorting per channel, imaging ΔF/F and vessel diameter, response features) on a folder of files with one set of settings, writing one summary table (CSV + MAT) and a log; files that fail are listed with their error and the batch goes on. LDF Processing's filtering and trial cutting moved to `core/LDFPipeline.m` (same results).
- **Sessions and reports** (`core/Session.m`, `core/Report.m`): every analysis window has **Save session…**, **Open session…** and **Report (PDF)…** in its last step card. A `.nasession.mat` stores the input files (path, size, date, MD5), all settings, the results and notes, and reopening it checks the inputs (changed / moved / missing) and re-runs the analysis. The report is a one-page A4 PDF with an image of the window, the versions, inputs with MD5, settings and key results.
- Unit tests for `SignalFeatures` and `core/imaging` checked against
  analytic answers (`SignalFeaturesTest`, `ImagingTest`).
- GitHub Actions CI: MATLAB code analysis and unit tests on every push.
- Smoothing and percentile normalization work without the Image Processing
  / Statistics toolboxes; the launcher warns when the Signal Processing
  Toolbox is missing.
- Releases: pushing a version tag publishes the GitHub Release with that
  version's changelog section (`.github/workflows/release.yml`).

### Fixed

- **Signal Characterization**: FWHM, rise time and decay time used the peak
  latency as the peak amplitude, so their thresholds were wrong; rise time's
  10%/90% levels collapsed onto the peak; FWHM counted samples outside the
  peak lobe. All features now share one baseline rule and honour a new
  **Direction** option (Auto / Positive / Negative). ERP files saved by
  Extract Ephys (`t_lfp`) are now accepted.
- **LFP / ERP**: edge epochs were averaged in as zeros; onset timing was one
  sample late. Downsampled LFP saved the requested rate instead of the real
  one (e.g. 1017.25 Hz, not 1000 Hz, for TDT data). CSD input is validated.
- **MUA**: the saved MUA signal was nearly nulled by unrectified smoothing;
  polarity "both" never clustered; the NEO option did not apply NEO; the
  ISI-violation check could never fire; "Filter before detection" was
  ignored; Plot Spike Rate always crashed; drift-correction relabelling mixed
  up cluster IDs and merged noise into cluster 1.
- **LDF**: re-running processing compounded filtering/downsampling;
  downsampling now anti-aliases; crop started one sample early; a stale
  crop could be saved after loading a new file.
- **ROI / imaging**: RGB TIFFs crashed on load; `roiMask` from `.mat` was
  discarded; propagation-speed estimates had the wrong sign/magnitude;
  vessel diameter crashed on `[x1 y1 x2 y2]` lines.
- Input validation across dialogs and file loaders instead of crashes.

### Removed

- `.brain/` tooling folder.

## [0.1.0] - 2026-05-07

First public release. The repo bundles a complete UI, the LDF and electrophysiology
processing pipelines, ROI / coregistered image analysis, and the signal-feature
extractor. The version string is displayed in every app footer next to the
copyright and is the single source of truth in `core/UITheme.version`.

### Added

- **Main launcher** with three sections — Filtering & Signal Processing,
  Imaging & ROI, Signal Characterization — and a project-directory bar that
  remembers Import / Export folders across sessions.
- **LDF pipeline**: Extract LDF Data (load, crop, save), Process LDF Data
  (filter, downsample, segment by stimulus onsets), Average LDF Viewer
  (grand average across trials with optional baseline correction).
- **Electrophysiology pipeline**: Extract Ephys Data (TDT tank load,
  multi-channel select), Process LFP Data (ERP averaging, CSD analysis),
  Process MUA Data (configurable spike sorting — detection method,
  threshold, refractory, alignment, polarity, feature extraction,
  clustering, drift correction).
- **ROI / Coregistered Image Analysis** (`apps/ROIAnalysisApp.m` plus
  `core/imaging/`): ROI- and line-based brightness, movement, ΔF/F
  for calcium imaging, blood-flow speed, kymograph, vessel diameter.
  Includes preprocessing toggles (B&W 256, Gaussian smoothing,
  per-frame normalization).
- **Signal Characterization**: peak latency, onset delay (50%), FWHM,
  AUC positive / negative, rise time, decay time, peak amplitude,
  stimulation–response integration. Multi-select the features to
  compute; results land in a uitable; export to CSV or MAT.
- **Help window** (`apps/HelpApp.m`) with workflow and principle figures
  for each pipeline.
- **Shared UI theme** (`core/UITheme.m`) — color palette, header height,
  axes-panel padding, version constant. Used by every app to keep the
  look consistent.
- **Imaging utilities** under `core/imaging/`: `deltaFOverF`, `kymograph`,
  `propagationSpeedFromKymograph`, `roiFlowSpeed`, `roiIntensityOverTime`,
  `roiMovement`, `vesselDiameterFromLine`, plus `imageStackNormalize`,
  `imageStackSmooth`, `imageToGrayscale256`.

### Notes

This is an early release — the UI works end-to-end on the lab's data
formats, but the public surface is not yet stable. Expect tightening
of error handling, more validation around input formats, and additional
analyses in 0.2.x.

[unreleased]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/releases/tag/v0.1.0
