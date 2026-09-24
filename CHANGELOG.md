# Changelog

All notable changes to NeuronalDataAnalyzerLab are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Added

- Unit tests for `SignalFeatures` and `core/imaging` checked against
  analytic answers (`SignalFeaturesTest`, `ImagingTest`).
- GitHub Actions CI: MATLAB code analysis and unit tests on every push.
- Smoothing and percentile normalization work without the Image Processing
  / Statistics toolboxes; the launcher warns when the Signal Processing
  Toolbox is missing.

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

[unreleased]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/releases/tag/v0.1.0
