# Changelog

All notable changes to Neuronal Data Analyzer Lab are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

*Versions up to 0.5.0 were released before the public repository started
at 0.5.1; their notes are kept below as a record of what the tool does.*

## [Unreleased]

### Added

- **Laser speckle flowmetry** (launcher → Blood flow → *Laser speckle*,
  `apps/LSCIAnalysisApp.m`, `core/LaserSpeckle.m`): blood-flow maps from
  laser speckle images. Loads raw speckle images from the camera, speckle
  contrast images, or the perfusion / flux images a commercial system
  exports (.mat, multi-frame TIFF or video; the type is judged from the
  images when the file does not say). Spatial (N × N window) or temporal
  (N frames) speckle contrast after the camera dark level, a flow index
  (1/K², or 1/τc from the exposure model with β), the flow of each ROI
  over time (K² averaged over the ROI before conversion), trials around
  each stimulus (from the stimulus trace in the file or a regular
  protocol) as % change from each trial's baseline, the average response
  (mean ± SD, with the mean change in a response window) and a response
  map. A *Checks* tab says in plain words what to look at: saturated
  pixels, a missing dark level, a small window, an unusual contrast,
  trials left out, too few trials. Export as .csv / .mat; *Save trials*
  writes the LDF trial format, so LDF Average and Response features open
  it. Sessions, report and methods text (citing Briers & Webster 1996,
  Boas & Dunn 2010, Bandyopadhyay et al. 2005, Cheng et al. 2003) as in
  every window. New demo `demo_lsci.mat` (`core/demo/demoLSCI.m`): raw
  speckle with known contrast in cortex, a vessel and static tissue, and
  a +25% flow response of an activated area after four stimuli; new Help
  topic *Laser Speckle* with the answers.
- **Blood-flow recordings from the common acquisition systems**
  (`core/io/SignalSource.m`, `readSignalText.m`, `readBiopacACQ.m`,
  `writeBiopacACQ.m`): LabChart .mat exports with several blocks, channel
  rates, units and comments; LabChart and AcqKnowledge text exports;
  BIOPAC AcqKnowledge .acq files (3.x to 5.x, Windows and Mac, compressed
  or not, with event markers; checked against the 32 sample files of the
  bioread project); AcqKnowledge and Spike2 .mat exports; any delimited
  table (PeriSoft, moorVMS-PC, spreadsheets: decimal comma, clock times,
  units rows). The flow and stimulus channels are found from their names,
  and comments / markers can be the stimulus. New demo files
  (`core/demo/demoLDFFormats.m`): the LDF demo as a LabChart text export,
  an AcqKnowledge .acq, a PeriSoft-style table, a Spike2 export and a table
  without a time column.
- `core/io/readImageStack.m`: one reader for image stacks over time
  (.mat, multi-page TIFF with the ImageJ frame interval, channels and
  pixel size, and video).
- **Perimed PeriCam PSI recordings** (`core/io/readPerimedDat.m`,
  `perimedPerfusion.m`, `writePerimedDat.m`): PIMSoft .dat files (file
  versions 1 to 3) open in the Laser speckle window as speckle contrast
  images (β · SD / intensity from the variance and intensity images),
  with the frame rate and pixel size of the header; PIMSoft's perfusion
  (gain × (1/C − 1), 0–3000 PU) is available as well. Other laser speckle
  systems (moorFLPI, RWD, SIM, Omegawave) keep their undocumented files:
  open their TIFF, video or MATLAB exports.
- **TIFF metadata** (`core/io/tiffMeta.m`, `unitScale.m`): one reading of
  what microscope and slide software writes into TIFFs, used by Histology,
  ROI analysis and Laser speckle: ImageJ hyperstacks (channels, slices,
  frames, frame interval, z spacing), OME-TIFF (DimensionOrder, sizes,
  physical pixel size with units, time increment, plane times, channel
  names), ScanImage (saved channels, frame rate, field of view in µm,
  slices with flyback frames, frame timestamps) and Aperio .svs (MPP,
  magnification). Multi-channel TIFFs open on one channel and the first
  slice.
- **Imaging files from microscope software** (`core/io/readImagingFolder.m`,
  `writeImagingFormat.m`), in ROI analysis and every reader of image
  stacks: Inscopix .isxd movies (uint16, float32, uint8; frame rate and
  pixel size from the JSON footer), ThorImageLS folders (Experiment.xml +
  .raw, channels, averaging, fast z), Bruker Prairie View T-series and
  Z-series (PVScan .xml, one TIFF per frame, frame times, microns per
  pixel) and UCLA Miniscope folders (numbered videos, timeStamps.csv /
  timestamp.dat, metaData.json). ROI analysis now also reads the frame
  interval of TIFFs.

### Changed

- **Extract LDF** opens every recording above, not only the LabChart .mat
  export. Step 1 now has *LDF*, *Stimulus* and *Block* choices, guessed from
  the channel names (the old convention, stimulus on channel 6 and LDF on
  channel 8, stays for LabChart files with 8 or more unnamed channels);
  the stimulus can also be the comments / event markers of the file, or
  none. The plots are titled with the channel names, the file label shows
  the format, rate, duration and channels, and a table without a time
  column asks for its sampling rate. The cropped .mat also keeps
  `flowName`, `flowUnits` and `stimName`; sessions store the format and
  the channel choice (older sessions still open), and the methods text
  names the acquisition software and the channels.
- **Launcher:** *Laser speckle* joins LDF under Blood flow, so the tiles
  now take four rows at the default width (Blood flow and EEG, then
  Electrophysiology, Imaging and Across techniques).

### Fixed

- README: the version badge said 0.5.1 in the 0.5.2 release.
- Histology: the pixel size of ImageJ TIFFs saved with the unit µm was not
  read (ImageJ writes it as `\u00B5m`); the Greek mu is accepted too, and
  an unknown unit falls back to the TIFF resolution tags.

## [0.5.2] - 2026-09-29

### Changed

- **Launcher: Course and Virtual lab** keep their tiles under **Learn** with
  a greyed-out *Coming soon* button; they no longer point to website pages,
  which are offline until the Course and the Virtual lab are ready.

## [0.5.1] - 2026-09-29

### Changed

- **Name: Neuronal Data Analyzer Lab** everywhere you read it: the website,
  the Help, the window titles and footers, reports, methods texts and the
  link previews (it was "NeuroAnalyzer" in most places). The command that
  opens it is now `NeuroAnalyzerLab` (was `NeuroAnalyzer`); sessions saved
  before open as before.
- **Licence: PolyForm Noncommercial 1.0.0 with a citation condition** (was
  "All rights reserved"). Free for noncommercial use (universities, public
  research, hospitals, charities, personal study): use it, change it and
  share it for these purposes. Commercial use needs a separate licence from
  the author. If you publish or present work that used it, cite it
  (`CITATION.cff`). `LICENSE.txt`, README, `CITATION.cff` and the window
  footers say so.
- **Course and Virtual lab: coming soon.** They are not in this release. In
  the launcher their tiles under **Learn** show a greyed-out *Coming soon*
  button; on the website their pages say what they will offer. Everything
  needed to learn the tool stays free: the in-app Help, *Try with demo
  data* and the website's guide and walkthroughs.
- **Launcher: Help and demo data in one place.** The Learn area keeps only
  the Course and Virtual lab. **? Help** (top right) opens the Help, where
  every window's topic has *Try it with demo data*; each tile's **?** opens
  its topic directly.
- **The website is kept apart from this repository.** It stays online
  (Help → *Learn more* opens it); its source is no longer in the toolbox.

### Removed

- The Course and Virtual lab windows (`CourseApp`, `VirtualLabApp`), their
  Help topics, tests and website lesson pages.

## [0.5.0] - 2026-09-28

### Added

- **New launcher**: a cover picture (neurons with signals travelling along
  the axons) and two areas. **Learn**: Course, Virtual lab, *Try with demo
  data* (choose a window: it opens with synthetic data whose answers are
  known) and Help. **Analyses**: one tile per technique, grouped as Blood
  flow, Electrophysiology, EEG, Imaging and Across techniques, the same
  order as the website's Analyses menu. A tile says what the technique is
  for, shows its steps as numbered buttons (the tooltip says which file
  goes in and out), the files in and out, and a **?** that opens its Help
  topic. The *Sessions and reports* tile opens any saved session in the
  window that saved it. The tiles re-flow into 3, 2 or 1 columns as the
  window is resized, keeping each family together.
- **One table of techniques** (`core/Techniques.m`): the launcher, Help's
  *Try it* buttons and website links, and the tests read it, so a new
  technique is one new row.
- **Website**: the Analyses menu is grouped by family in the launcher's
  order; a *Course* page (what each lesson covers, the numbers you report
  and how they are checked) in the Learn menu; the home page opens with
  the cover picture; a step-by-step EEG walkthrough.
- **Course** (launcher → Learn → *Course*, `apps/CourseApp.m`, `core/Course.m`):
  step-by-step lessons in the real analysis windows. The course makes
  sample data with a known answer, and each step says what to do, why,
  what you should see and what usually goes wrong; *Open <window>* opens
  the window the step uses with the right file. You type the numbers you
  read in the windows and *Check my results* compares them with a
  reference analysis of the same files, and checks your settings from the
  session files you saved (filter, trial window, baseline, measure…).
  *Show solution* shows the reference values and how the data were made.
  Lesson 1: from a LabChart recording to the average blood-flow response
  (LDF). Lesson 2: ERPs, a P300 measure and statistics from cleaned EEG.
  New Help topic *Course*.

- **EEG: BrainVision files** (Brain Products Recorder and Analyzer, and
  exports from EEGLAB / MNE; `core/io/readBrainVision.m`,
  `writeBrainVision.m`): the EEG Analysis window now loads `.vhdr` files
  (with their `.vmrk` and `.eeg` files next to them). Continuous
  recordings keep their markers as events (`S  1` is shown as `S 1`) and
  can be cut into trials in the window; segments exported from Analyzer
  become trials, with the marker at time 0 as the condition. Binary
  (16- / 32-bit integers, 32-bit floats, either byte order) and text
  data, each channel's resolution and unit, electrode positions, the
  reference channel, and, in plain words, the amplifier and software
  filters used when recording, pauses, bad intervals and averages. The EEG
  demo is also written in this format.

### Changed

- **New logo**, drawn like the cover picture: a neuron whose cell body is
  the peak of a recording trace, with a signal travelling along it (from
  a slow blood-flow wave to spikes). It is the window icon, the logo in
  the launcher and Help headers, the website header and the tab icon
  (a bolder version for small sizes).
- **Website**: when a page is shared, a preview picture (logo, name and
  cover art) and the page's title and description are shown (Open Graph
  and Twitter tags); home-screen icon; the home page description now
  mentions EEG and the lessons. New GitHub social preview picture.

## [0.4.0] - 2026-09-26

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
  the Neuronal Data Analyzer Lab and MATLAB versions, and a reference list (e.g.
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
- **Logo and icon**: the Neuronal Data Analyzer Lab logo in the launcher and Help
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

[unreleased]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/compare/v0.5.2...HEAD
[0.5.2]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/releases/tag/v0.5.2
[0.5.1]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/releases/tag/v0.5.1
