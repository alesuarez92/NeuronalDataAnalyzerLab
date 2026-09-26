# Changelog

All notable changes to NeuronalDataAnalyzerLab are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Histology / culture** (launcher → Imaging → *Histology / culture*,
  `apps/HistologyApp.m`, `core/Histology.m`): count cells in still images
  of sections or cultures. Load one or several images (TIFF pages or
  PNG / JPG colours as channels, or .mat; the pixel size is read from
  ImageJ TIFFs), optionally align the channels (colour shift) and the
  images onto the first (automatic shift for time points, or clicked
  landmarks with an affine fit for serial sections), count cells in the
  nuclear channel (background subtraction, automatic threshold, touching
  cells split at their narrow waist, size and shape limits in µm), score
  each cell as positive or negative for every other channel, and count per
  hand-drawn region and per mm². A *Checks* tab explains in plain language
  where the pixel size came from, how well the alignment worked, which
  threshold was used and what was left out. Export as .csv (one row per
  cell, plus counts per image and region) or .mat; sessions, report and
  methods text (citing Otsu 1979) as in every window. New demo
  `demo_histology.mat` (two culture images with 60 nuclei, 24 then 39
  marker-positive, touching pairs, debris, a fibre and a stage shift, all
  known) and a Help topic with the answers.
- **Methods text**: a *Methods text…* button next to the session
  buttons of every analysis window drafts a methods section from the
  analysis: every step in the past tense with the values actually used
  (filters, trial and epoch windows, thresholds, CSD method and
  parameters, spike-sorting settings, statistical tests and corrections),
  the NeuroAnalyzer and MATLAB versions, and a reference list (e.g.
  Pettersen et al. 2006, Potworowski et al. 2012, Mauchly 1940,
  Greenhouse & Geisser 1959, Holm 1979, Friedman 1937). What the session
  does not know (animals, surgery, hardware) is left as a bracketed
  placeholder; nothing is invented. The text can be edited, copied or
  saved as UTF-8 .txt, and *Add saved sessions…* combines several
  sessions of a pipeline in pipeline order (`core/MethodsWriter.m`;
  scriptable with `MethodsWriter.fromSession` / `fromSessions`).
- **Virtual lab** (launcher → *Virtual lab*, `apps/VirtualLabApp.m`,
  `core/VirtualLab.m`): a simulated experiment to learn by doing. The
  student reads how laser Doppler flowmetry works, plans a whisker
  stimulation experiment (probe position, stimulus, number of stimuli,
  time between them, baseline, sampling rate; the protocol is previewed
  as the values change), records it (a LabChart-style file with a known
  answer, different for every student), analyses it from scratch in
  Extract / Process / Average LDF, reports the numbers and gets feedback
  on the plan, the processing (from the saved sessions) and the numbers.
  The reference values stay hidden until *Show solution*; submissions
  (`.navlab.mat`) record the attempts, and instructors grade a folder of
  submissions into one CSV table. Help → *Virtual lab* explains the
  simulation and the grading.
- **Website**: a *Virtual lab* page with a walkthrough of the demo student
  (screenshots from the automated tests), a Virtual lab section in the
  guide, and the methods text on the sessions page.
- **Average LDF** shows the results under *Plot grand average*: baseline,
  peak increase (and % of baseline) and time to peak, with the peak
  marked on the plot; sessions and reports include them.
- **EEG, step 1: reading EEG already cleaned in MATLAB** (`core/io/EEGSource.m`,
  `readEEGLAB`, `readFieldTrip`, `readEEGMatrix`; no window yet). EEGLAB
  `.set` files (numbers inside or in a `.fdt` file, or an `EEG` variable in
  a `.mat`), FieldTrip raw and averaged data, and plain `.mat` arrays (the
  variables are recognised and a map is suggested) are read into one
  shape: trials with a condition each (or a continuous recording with its
  events), channel names and positions as stored, the reference, and
  what was already done (filters, re-reference, removed ICA components,
  rejected trials, interpolated channels) in plain sentences from the
  EEGLAB history or FieldTrip `cfg.previous`. Nothing in a file is run;
  EEGLAB and FieldTrip are not needed. Values stored in volts are
  converted to µV, and the note says so.
- **EEG Analysis window** (launcher → *EEG*, `apps/EEGAnalysisApp.m`,
  `core/EEGAnalysis.m`): load one cleaned EEG file per participant
  (EEGLAB, FieldTrip or a plain .mat, for which a short form asks what
  each variable is), read in the *Overview* tab what each file holds and
  what was already done to it, cut continuous recordings into trials
  around their events, and plot the ERPs per condition (one participant or
  the grand average, with SEM), every channel of one condition, or a
  difference wave. Measure the mean or peak amplitude in a time window
  per participant and condition (peaks on the window's edge are flagged),
  then compare the conditions within participants (paired t-test /
  Wilcoxon, or repeated-measures ANOVA / Friedman with post hoc tests).
  Export as .csv (one row per participant and condition) or .mat;
  sessions, report and methods text (citing EEGLAB or FieldTrip when the
  files came from them). Help → *EEG Analysis* gives the demo's answers;
  *Generate all demo files* now also writes the EEG demo.
- **EEG demo data** (`core/demo/demoEEG.m`): a synthetic oddball study (8
  participants, 32 channels, Standard / Target / Novel, known P1, N1,
  P300 and alpha, 5 trials already rejected) and a rodent recording (4
  skull screws with bregma coordinates, light flashes, a known visual
  evoked potential), each written as EEGLAB (`.set` and `.set` + `.fdt`),
  FieldTrip and plain `.mat`, so every reader is tested on the same data.

### Changed

- "NMD Lab" removed from the launcher, Help, README and website.
- **ROI Analysis: "Speed (flow)" removed.** It was not a speed: it
  computed the mean absolute frame-to-frame difference in the ROI,
  exactly the same as *Movement* (now shown by a test). Sessions and
  scripts that ask for it get Movement, with a message. Help, the website
  and the README no longer claim a blood-flow speed.

### Fixed

- **LDF Process / Batch: short stimulus pulses were lost when
  downsampling.** The trigger kept every r-th sample, so pulses shorter
  than the downsampling factor could vanish (and their trials with them).
  The trigger now keeps the maximum of each block of samples: long pulses
  give exactly the same onsets as before, short ones are no longer missed.
- **MUA: quality results were not stored.** Units rejected by the quality
  check (low SNR, refractory violations) were shown as rejected, but
  `results.rejectedClusters` stayed false and `results.isiViolationRate`
  empty; both now hold the real outcome.
- **MUA drift correction depended on the units of the recording.** Clusters
  were matched and merged when their mean waveforms were within a distance
  of 0.5 in raw units: everything merged for data in volts, nothing for data
  in microvolts. Distances are now relative to the waveform size (the same
  in V and µV); across time bins up to 0.5 (the amplitude may drift), within
  a bin up to 0.2, so two units of similar shape but different size stay
  apart. Spikes in time bins too small to cluster (or where clustering
  failed) were dropped from the results; they are now kept as unsorted
  (noise).
- **LFP / ERP and MUA: pulse trains gave a single onset for the whole
  recording.** A crossing was dropped when it came within the minimum
  interval of the previous *crossing*, so in a train of pulses every pulse
  after the first was dropped. Both now use the LDF rule (within the
  minimum interval of the last *kept* onset): one onset per train. Single
  pulses give the same onsets as before.
- **MUA Analysis: sorting could differ between runs.** K-means / GMM /
  t-SNE used MATLAB's random generator in whatever state it was. The
  settings now have a **Random seed** (default 0) that is set before every
  run (and the previous state restored), so the same data and settings
  always give the same clusters.
- **Help / website: MUA detection methods described correctly.** *Rolling
  MAD* uses the same threshold as MAD over the whole recording (it was
  described as a moving window); *Percentile* does not use the multiplier.

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
