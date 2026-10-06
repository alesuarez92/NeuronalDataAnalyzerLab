# Changelog

All notable changes to Neuronal Data Analyzer Lab are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

*Versions up to 0.5.0 were released before the public repository started
at 0.5.1; their notes are kept below as a record of what the tool does.*

## [Unreleased]

### Changed

- **Launcher: the Course is open.** Under **Learn**, the Course tile's
  button is now **Open the Course**: it opens the Course,
  https://toolbox.neuroanalyzerlab.com/course/, in your web browser (free
  step-by-step lessons in the real windows, open to everyone without an
  account; Lesson 1, laser Doppler flowmetry, is open). The
  status bar says when the website was opened; if no browser can be opened,
  the address is shown so you can copy it. The Help (Welcome topic) says
  where the Course is. The **Virtual lab** is still *Coming soon*.
- **Website address.** The toolbox website moved to
  https://toolbox.neuroanalyzerlab.com (the footer link of every window and
  **Learn more** in the Help open it); the old addresses on
  neuroanalyzerlab.com redirect there.
- **Statistics tests use the project's own numbers.** The checks of the
  t-tests, rank tests, ANOVA, Tukey HSD and Kruskal-Wallis no longer use
  published data sets; they use made-up numbers whose expected results
  were computed independently with SciPy (`tests/StatsFeaturesTest.m`).
  The statistics themselves are unchanged.

### Removed

Readers whose file layout has no format specification published by the
vendor are removed. *If you used one of them, export the recording with
the vendor's own software to a format that is read (for example NWB, EDF,
TIFF, a video or a MATLAB file), or keep using 1.0.1 for it.*

- **Multi Channel Systems HDF5** (Extract Ephys): `readMCS`, `writeMCS`
  and their demo file. The reader followed the layout the vendor's
  open-source tool reads, not a published specification.
- **Inscopix `.isxd`, ThorImageLS `Experiment.xml` + `.raw`, Bruker
  Prairie View and UCLA Miniscope folders** (ROI analysis):
  `readImagingFolder` and `writeImagingFormat`. `readImageStack` now
  refuses a folder with a message saying to export the images as TIFF.
  Multi-frame TIFF (with ImageJ, OME-TIFF and ScanImage metadata) and
  videos open as before.
- As in 1.0.1, these removals break the promise in `docs/FORMATS.md` that
  the `read*` functions keep their names until 2.0; they are made for
  legal reasons. `docs/FORMATS.md` now lists the published description
  each remaining reader follows.

## [1.0.1] - 2026-10-05

**A legal-compliance release.** It removes file readers whose layouts did
not come from a specification the vendor publishes, rewrites code that
followed another package, replaces AI-made figures and simplifies the
licence. *If you used one of the removed formats, export the recording
from the vendor's software to a format that is read (for example NWB,
EDF, a MATLAB file or a text table), or keep using 1.0.0 for it.*

### Removed

- **Perimed PeriCam PSI `.dat`** (Laser speckle): `readPerimedDat`,
  `writePerimedDat`, `perimedPerfusion`. Export perfusion images as TIFF,
  video or MATLAB instead; they open as before.
- **Plexon `.plx`** and **Axon ABF 2 `.abf`** (Extract Ephys):
  `readPlexon`, `writePlexon`, `readABF`, `writeABF`, and their demo files.
- **BIOPAC AcqKnowledge `.acq`** (Extract LDF) and **EGI `.mff`** (EEG):
  `readBiopacACQ`, `writeBiopacACQ`, `readMFF`, `writeMFF`, and their demo
  files.
- These removals break the promise in `docs/FORMATS.md` that the `read*`
  functions keep their names until 2.0. They are made for legal reasons
  and only the readers named here are affected.

### Changed

- **EEG filters and scalp maps rewritten from the papers.** The FIR
  filters (Hamming-windowed sinc, zero phase, edges padded with an odd
  mirror image) follow Widmann, Schröger & Maess (2015); the spherical
  splines follow Perrin et al. (1989, 1990). Results agree with 1.0.0 to
  within a fraction of a microvolt; the 50 Hz notch is now narrower
  (stop band 49.5-50.5 Hz) and its filter shorter. The Methods text cites
  the papers.
- **Figures in the Help**: every explanatory figure is now drawn by a
  script (`docs/art/make_figures.py`) from synthetic signals; the
  AI-made images are gone.
- **Licence**: the unmodified PolyForm Noncommercial License 1.0.0. Citing
  the toolbox is now a request, not a licence condition (`LICENSE.txt`,
  README, `CITATION.cff`, the window footers).

### Added

- `THIRD_PARTY_NOTICES.md`: the open-source projects whose published
  descriptions were followed or used for checks, with their licences.

## [1.0.0] - 2026-10-05

**1.0: a stable release.** From 1.0 on, the session files, exported
files and script functions listed in `docs/FORMATS.md` keep their names
until 2.0. Every window has its quality checks and was tested on
synthetic data with known answers; the Help and the website were checked
against every window.

### Changed

- **Formats frozen for 1.0** (listed in `docs/FORMATS.md`, locked by
  tests). *If you read these files with your own scripts or spreadsheets,
  update the names below:*
  - EEG measures have the same columns everywhere: `Participant,
    Condition, Value_uV, Latency_ms, Trials, PeakAtEdge` in EEG Analysis'
    `.csv` and `.mat` (latency was `Latency_s`) and in
    `EEGAnalysis.measureTable` (was `Value, Latency, AtEdge`, latency in
    s), as in Batch.
  - Batch: **Export…** to `.mat` saves the same `batch` record as
    `<name>_summary.mat` (it saved the whole run result under that name);
    `Batch.run` returns it as `R.record`.
  - Sessions: `Session.load` reads `formatVersion`, upgrades older files
    in one place (`Session.upgrade`) and refuses a file from a newer
    format with a message to update the toolbox.
  - The same names across windows: ROI Analysis' `.csv` starts with
    `Time_s` (was `Time`) and always names the ROI (`DFF_<ROI>`, also
    with one ROI, where it wrote `DFF`); Signal Characterization's
    features table and `.csv` start with `Series` (was `Trial_Channel`),
    as Batch, and its group `.mat` holds `results` (was `result`), as the
    other windows; EEG channel positions (`chanlocs`) get `labels`,
    EEGLAB's name, next to `label`.

### Added

- **Saving without dialogs** for scripts and tests, as in the other
  windows: `MUAAnalysisApp.saveResultsTo(path)` and
  `SignalCharacterizationApp.exportResultsTo(path)`.
- **Extract Ephys: Electrode spacing (µm)** in step 4, saved with the LFP
  as `lfp_spacing_um` (0 = not known) and kept in sessions; LFP Analysis
  and Batch use it for the CSD and the spacing check says it came from
  the file. Until now only the demo files carried it.

### Fixed

- **Help** checked against every window: the demo results it quotes (EEG,
  laser speckle, LDF, LFP, MUA, Groups & statistics) and the labels and
  step numbers now match what the windows show. The quick starts show each
  window's own step numbers (extra entries no longer shift them), and the
  lists of file formats in the Help and on the launcher tiles name every
  reader (LDF, laser speckle, electrophysiology, EEG, imaging).
- **Histology / culture** shows µm and µm² in its setting labels, tooltips
  and session summary (the exported column names keep ASCII `um`, `um2`).

## [0.10.0] - 2026-10-05

### Added

- **Quality checks, one format for every window** (quality checks step 1).
  A check is a row with a result (**OK**, **Check**, **Warning** or
  **Note**), a topic, what was found, why it matters and what to try
  (`core/QualityChecks.m`). One shared **Checks** tab (`UIKit.checksTab`):
  a table Result / Topic / Finding, coloured by result, and the whole row
  when you click it. Laser speckle and Histology / culture now use it,
  with their checks split into what was found, why and what to try
  (`Histology.checks` and `LaserSpeckle.checks` also return the rows;
  `R.checks` keeps its "OK: / Check: / Warning:" lines, `R.checkRows`
  holds the rows). Sessions store the checks (`session.checks`, and a
  "Checks: …" line in the key results), the PDF report lists them with the
  warnings first, and the methods text says what they reported. Laser
  speckle's status bar now says when a run gave warnings.
- **Quality checks for blood flow, needle probe and images together**
  (quality checks step 2). `core/PerfusionChecks.m` holds the checks every
  blood-flow source shares, on a probe trace (PU) or on the flow of each
  ROI of laser speckle or perfusion images: baseline drift (%/min, before
  the first stimulus or across the trial baselines; Check above 3%/min,
  Warning above 10%/min), movement artefacts (jumps away from a 1 s moving
  median; Warning inside a trial), a signal stuck at 0 or at the top,
  stimuli left out and too few trials, short trial baselines and the time
  resolution (Check above 0.5 s per value, Warning above 2 s). With several
  ROIs each check is one row naming the ROIs.
  - **LDF Process** gets a **Checks** tab (filled after Segment trials,
    kept in sessions): the shared checks plus the probe's own, baseline
    plausibility (about 30–600 PU; a Check, never a Warning) and the
    filter against the response (low-pass below 0.5 Hz, high-pass above
    0.02 Hz). `LDFPipeline.checks`; `LDFPipeline.run` returns `checkRows`.
  - **Batch processing** (LDF): a **Checks** column with each file's checks
    in one cell, and the same at the end of its log line.
  - **Laser speckle**: field shift between frames (Check above 1 px,
    Warning above 3 px), speckle size (autocorrelation of raw frames),
    exposure outside 1–20 ms, illumination drift, high baseline contrast in
    a ROI (static scattering), perfusion images clipped at the export range
    (e.g. PIMSoft 0–3000 PU), notes on device units and on the checks that
    need raw images, then the shared checks on the ROI traces.
    `LaserSpeckle.analyze` takes the ROI names and returns `roiNames`,
    `roiK`, `intensity` and `shift`.
  - **Demo data with each fault**: `demo_ldf_faults.mat` (drift, a movement
    artefact in trial 3, a dropout to 0), `demo_lsci_faults.mat` (field
    shift, speckles smaller than a pixel, illumination drift, 25 ms
    exposure, a ROI through the skull) and `demo_perfusion_faults.mat`
    (perfusion images clipped at 3000 PU, one per second).
- **Quality checks for electrophysiology** (quality checks step 3): LFP,
  MUA and EEG Analysis get a **Checks** tab (kept in sessions), and Batch
  processing a **Checks** column for LFP, MUA and EEG files (one cell per
  row, the same at the end of each file's log line; the checks never
  change a file's Status).
  - **LFP Analysis** (`ERPAnalysis.checks`), after Run ERP and Compute
    CSD: **Epochs** (stimuli left out, fewer than 10 averaged), **Stimulus
    artefact** (a deflection in the first 1.5 ms above 10 times the
    baseline noise; Warning when it lasts into the N1 window, 5–50 ms;
    says whether it is the same on every contact), **Electrode spacing**
    (Check when the file does not give it and the default 100 µm was used,
    or when it differs from the file's) and **CSD sink** (Warning at an
    edge contact: the first or last two for the standard CSD, which copies
    the end contacts; the first or last for iCSD and kCSD). LFP files may
    carry `lfp_spacing_um`, which fills the Spacing box; in Batch a
    spacing of 0 uses each file's, and a file with none gets its ERP rows
    without a CSD instead of failing.
  - **MUA Analysis** (`MUAPipeline.checks`), after sorting and after each
    cluster edit (merge, split, Undo): **Refractory period** (the share
    of inter-spike intervals shorter than the refractory period, 1 ms;
    Check above 1% or when a unit was rejected for it, Warning when a
    kept unit is above 2%), **Signal-to-noise** (Check when a kept unit
    is below 3, Warning when no unit reaches 3.5: the spikes are buried in
    the noise) and **Amplitude drift** (a line through the median spike
    amplitude of five groups of spikes in time; Check above 20%, Warning
    above 40%; units of the same shape that fire one after the other are
    measured together, so a drifting unit split in two is still caught).
  - **EEG Analysis** (`EEGAnalysis.checks`), after Cut into trials / Apply
    rejection, Show ERPs and Measure: **Trials per condition** (Check
    below 20, Warning below 10), **Rejection balance** (the share of each
    condition rejected; Check when two differ by more than 20 percentage
    points, Warning above 40), **Condition balance** (more than twice the
    trials: Check with a peak measure, OK with the mean amplitude),
    **Bad channels** (Check above 10%, Warning above 20%) and
    **Interpolated channels** (read from the EEGLAB / FieldTrip history;
    Warning when every measured channel was interpolated).
    `EEGAnalysis.interpolatedChannels` reads them; `loadFaultsDemo()` opens
    the faults participant with the suggested bad channels, a 100 µV
    rejection and the P300 at Pz filled in.
  - **Demo data with each fault**: `demo_lfp_faults.mat` (a stimulus
    artefact on every contact into the N1 window, the sink at the deepest
    contact, no spacing in the file), `demo_mua_faults.mat`
    (channel 3: noise raised to 40 µV; channel 4: a unit that fires
    doublets 0.8–0.95 ms apart; channel 5: a unit shrinking to half its
    size over the 30 s) and `demo_eeg_faults.mat` / `eeg/faults`
    (blinks in most Target trials, 8 of 32 channels noisy or flat, Pz
    interpolated in EEGLAB). `demo_lfp.mat` and the LFP batch demo files
    now carry `lfp_spacing_um` (100 µm).
- **Quality checks for imaging and statistics** (quality checks step 4):
  ROI Analysis and the Groups & statistics tab of Signal Characterization
  get a **Checks** tab (kept in sessions, reports and the methods text;
  the status bar says when there are warnings). The checks never change
  the results.
  - **ROI Analysis** (`core/ImagingChecks.m`), after every Run:
    **Motion** (how far the frames move from their usual position against
    the size of the smallest ROI, the width of a disk of the same area;
    estimated on up to 100 frames when motion correction is off; Check
    above 20% of it, Warning from half of it: the cell slides out of its
    ROI; with motion correction the same rules on what is left, and a
    Check when frames had moved by more than a whole ROI; line methods:
    Check above 2 px), **Bleaching** (each ROI's baseline at the end
    against the start; Check above 10%, Warning above 25% darker; a Check
    when it brightens), **Saturation** (ROI pixels at the top value of the
    stack; Check above 0.1%, Warning above 1% of a ROI's pixel-frames; a
    camera ceiling such as 4095 or values piling up count, a single
    brightest value does not) and **Preprocessing** (Normalize each frame
    with Brightness or ΔF/F).
  - **Groups & statistics** (`GroupStats.checks`), after every test:
    **Sample size** (Warning when every series is counted as a subject,
    with fewer than 3 per group, or when the exact rank-based test cannot
    reach p < 0.05 with these n; Check below 8), **Normality**
    (`GroupStats.shapiroWilk`, Royston's algorithm, the same W and p as R
    and SciPy, on the paired differences, each group or the
    repeated-measures residuals; Check at p < 0.05, Warning when the
    rank-based test gives another verdict; the most extreme animal named),
    **Sphericity** (repeated measures: Check when Mauchly's test rejects
    it or cannot be computed, Warning when the correction would change
    the verdict of the uncorrected p reported), **Equal spread** (ANOVA:
    Check above an SD ratio of 2, Warning with unequal group sizes),
    **Robustness check** and **Missing values**.
  - **EEG Analysis**: **Compare conditions** (step 6) adds the same
    checks of the test to its Checks tab, after the checks of the trials,
    worded for participants (`GroupStats.checkOptions`: `subject`,
    `valuesTab`, `missingAction`); the Statistics tab sums them up and a
    new measure removes them with the old test.
- **ROADMAP: what 1.0 means**: every window with its checks (done), the
  session, export and script formats frozen, the tool used on the lab's
  real recordings, and one pass over the Help and website.
  - **Demo data with each fault**: `demo_imaging_faults.mat`
    (`DemoData.imagingFaults`: a 12-bit movie whose field slides 14 px,
    the dye fading to ~65% and Cell 2 clipped at 4095, with three cell
    ROIs) and `groups_faults/` (`demoGroups(folder, struct('Faults',
    true))`: 6 animals, animal 6 responding three times as much to
    Stimulated, the same Drug rise in every animal; `loadGroupDemo(true)`
    opens it). The clean demos' numbers are unchanged.

## [0.9.0] - 2026-10-03

### Added

- **Batch Processing: EEG** (ROADMAP EEG step 7). A new pipeline, *EEG:
  ERPs and a measure per condition*, runs the steps of EEG Analysis on
  every file of a folder (one per participant, raw or cleaned: BrainVision,
  EDF / BDF, EEGLAB, FieldTrip, XDF) with one set of settings, in the
  window's order: bad channels (typed, the file's own, optionally the
  suggested ones), filters, reference, trials around renamed events,
  rejection, ERPs with a baseline, and the mean or peak amplitude in a
  window at chosen channels. One row per file and condition: trials kept
  and rejected, value (µV), latency, edge-peak flag, channels used, bad
  channels, reference. The numbers equal the window's with the same
  settings (tested). *Try demo batch* loads the 3 raw demo recordings:
  exactly the blink trials are rejected (62 trials per file) and the P300
  at Pz is Target > Novel > Standard in every file. The event parsing,
  mastoid pair and notch frequencies are now shared in `EEGAnalysis`
  (`parseEvents`, `mastoidChannels`, `notchFrequencies`).

### Fixed

- Help, Batch Processing: the P300 values the EEG demo batch gives are
  quoted as the ranges in the release frames (Target 5.6 to 7.7, Novel 3.4
  to 4.7, Standard 0.7 to 1.9 µV at Pz).

## [0.8.0] - 2026-10-02

### Added

- **EEG Analysis: scalp maps** (ROADMAP EEG step 4). **Scalp maps** in
  step 5 (or *Scalp maps* in the plot's Show list) draws the mean voltage
  of every electrode in the window of step 5 on the head: one map per
  condition and one of A minus B, for the participant shown or the grand
  average, on one colour scale, with the electrodes used and those left
  out (bad channels). Scalp layouts use spherical splines (Perrin et al.,
  1989; m = 4, 50 Legendre terms, no regularization, so the map passes
  through every electrode): the same numbers as MNE-Python's spherical
  spline interpolation matrix. Rodent skull layouts get a flat map, a
  thin-plate spline in mm from bregma drawn only inside the electrodes
  (the same numbers as scipy's `RBFInterpolator`). Sessions keep the maps
  (window, participant, conditions), and the methods text and the
  report describe them. `core/ScalpMap.m`, `EEGAnalysis.windowMean`,
  `tests/ScalpMapTest.m`; Help gives the demo's maps (P300 over Pz, N1
  over Cz, the rodent VEP over V1).
- **EEG Analysis: time–frequency per condition** (ROADMAP EEG step 5), in
  a new step 7 (Save is now step 8). Complex Morlet wavelets (the code of
  LFP Analysis: unit energy, ±3 SD, 1 Hz steps, 3 cycles by default) of
  every trial at the chosen channels, per participant and condition and
  across participants: **ERSP** (dB against each condition's baseline;
  one image per condition and one of A minus B), **phase locking (ITPC)**
  with its chance level, and the **power of one band** (delta to gamma)
  as % change from the baseline, mean ± SEM. A value is kept only where
  the whole wavelet lies inside the trial, so it equals what a longer
  recording gives (tested against `TimeFrequency.ersp` on the continuous
  signal); the rest is grey, and the window says which frequencies the
  trial length allows. Sessions keep the settings and the view, the .mat
  export holds the results, and the methods text and Help describe them.
  `EEGAnalysis.timeFrequency`, `grandTimeFrequency`,
  `describeTimeFrequency`, `TimeFrequency.supportSamples`.
- **EEG demo**: after Target the alpha over O1 / Oz / O2 halves from 350
  to 650 ms (power −75%, −6 dB), a known answer for time–frequency; the
  ERPs and every other value are unchanged in expectation (cached demos
  are written again).

### Changed

- **EEG Analysis** writes µV (not uV) on the plot, in the tables and on
  the rejection thresholds.

### Fixed

- **Batch results table on MATLAB R2026b**: the third column is called
  after its values (Fs_Hz, ROI, Series, Channel ...); in 0.7.0 it was
  still called Message, the name it had in the list of queued files.
  The window now draws the table empty before it shows other columns.
- **LDF Processing**: the threshold is named in the title of the stimulus
  plot ("dashed = threshold 2.5"); its label on the line sat over a pulse.
- **MUA Analysis**: the ISI histograms leave room above the bars for
  their legend, which covered them.

## [0.7.0] - 2026-10-01

### Added

- **EEG Analysis: raw recordings** (ROADMAP EEG step 6). Two new steps in
  the window, rebuilt from the files in a fixed order on every click (so
  sessions replay them): **2 Clean recordings** (bad channels per
  participant, with *Suggest* for flat or very noisy channels; high-pass,
  low-pass and notch filters; reference as recorded, average of the good
  channels, linked mastoids or chosen channels) and **3 Trials** (events
  renamed to conditions, e.g. `S 1 = Standard`; trial window; trials
  rejected by peak-to-peak or absolute amplitude on any good channel, with
  the counts per condition and the channels that caused them). The filters
  are zero-phase Hamming-windowed sinc FIR filters designed and applied as
  MNE-Python `raw.filter` / `notch_filter` with their defaults; filter
  taps, filtered data and the re-references were checked during
  development against MNE-Python 1.13. Bad channels are left out of the
  average reference, the rejection, the ERPs, the measures and the
  butterfly view; the grand average uses the participants where a channel
  is good. EEG-BIDS `channels.tsv` status `bad` marks channels bad. Trials
  across EEGLAB `boundary` gaps are left out. ERPs, Measure, Statistics and
  Save are now steps 4-7. ICA and advanced cleaning stay in EEGLAB /
  FieldTrip (Help explains how to load their result).
- **Raw EEG demo** (`demoEEG`, *Try raw demo (continuous, not cleaned)*): 3 BrainVision Recorder
  recordings of the oddball study against FCz with electrode offsets,
  drift, 50 Hz line noise, a noisy T7 and blinks in known trials; a
  100 uV peak-to-peak rejection after a 0.1-30 Hz band-pass and the
  average reference removes exactly the blink trials.
- **Methods text**: filters (edges, transitions, -6 dB cutoffs, order;
  MNE-Python and Widmann et al., 2015), bad channels, offline reference,
  event names and the trials rejected per condition.
- **EEG Analysis: electrode layouts** (ROADMAP EEG step 3). A new
  *Electrode layout…* button in step 1 (with a line saying how many
  channels are placed and whether the layout is confirmed) opens the
  *Electrode layout* window: every electrode drawn on the head (nose up)
  or, for rodents, on a skull outline with bregma; a table of the
  channels (Channel, Placed from, As, Status; for skull layouts AP and
  ML in mm); the summary and notes; *Cancel* and *Use this layout*.
  *Source*: positions from the files with the other channels by name
  (default), by name only (10-5 system), or from a positions file
  (*Positions file…*). The 10-5 template (345 positions) is computed with
  the idealized spherical construction (equator through Nz, T9, Iz and
  T10; Oostenveld & Praamstra, 2001; Jurcak et al., 2007) and was checked
  during development against eeg_positions as shipped with MNE-Python.
  Names match in any case; the old names T3 / T4 / T5 / T6 are read as
  T7 / T8 / P7 / P8, and an `EEG ` prefix and reference suffixes (-REF,
  -LE, -AR, -AVG, -A1, -A2, -M1, -M2) are dropped; A1 / A2 / M1 / M2, EOG
  and other non-scalp channels get no position. Every position is turned
  to one orientation (x = right ear, y = nose, z = up) from the frame its
  file states (EEGLAB, FieldTrip, BrainVision, EGI, BIDS), so the same
  electrode from different files lands in the same place; an orientation
  check against the template turns files read 90 degrees off and reports
  the others. Rodent skull layouts in mm from bregma (AP anterior +, ML
  right +). The check lists the channels placed, renamed ("T3 treated as
  T7"), without a position, in the same place or outside the head; a
  10-5 name typed in *As* (or AP / ML on a skull) places a channel by
  hand. The layout is kept in sessions, listed in the Overview and, once
  confirmed, described in the methods text (citing Oostenveld & Praamstra
  2001 and Jurcak et al. 2007). Without positions everything except scalp
  maps (a later step) works as before. The Help topic has a new
  *Electrode layout* section with the demo's answers. `core/EEGLayout.m`,
  `tests/EEGLayoutTest.m`.
- **Electrode position files** (`core/io/readElectrodes.m`,
  `writeElectrodes.m`): EEGLAB .loc / .locs / .ced / .xyz, BESA .elp /
  .sfp, ASA / FieldTrip / MNE .elc, EGI .sfp, BrainVision .bvef, EasyCap /
  BioSemi `Site Theta Phi` lists, .csv / .tsv / .txt tables (x / y / z,
  theta / phi, theta / radius, or ap / ml in mm from bregma) and BIDS
  `electrodes.tsv` (with its `coordsystem.json`), all read into the one
  orientation with the fiducials kept apart; Polhemus digitizer .elp
  files are refused with a hint. The angles and positions were checked
  during development against MNE-Python `read_custom_montage` (within
  2e-6 degrees). The writer writes every format in its own convention
  (used by the tests). `tests/ElectrodesFileTest.m`.
- **Website in every window**: the footer of the launcher and of every
  window links to [neuroanalyzerlab.com](https://neuroanalyzerlab.com)
  (methods, references and walkthroughs), next to the copyright.

### Fixed

- **EEG-BIDS positions in one frame**: when `electrodes.tsv` gives
  positions, `readEEGBIDS` takes the positions only from it; channels it
  leaves out no longer keep the positions of the data file, which were
  in another frame.
- **Settings rows on MATLAB R2026b**: in the Laser Speckle Flowmetry
  window (steps 1 and 2) and the MUA Analysis settings dialogs, a control
  or a label could be drawn over the last row; every label now stays next
  to its control.
- **Plots stuck at 0 to 1 on MATLAB R2026b**: limits read before a plot
  was first drawn (a new window, a tab not shown yet) could still be 0 to
  1 and were kept, hiding the data: the first file in Extract LDF, the
  time axis in LDF Processing, the alignment waveforms and the stimulus
  shading in MUA Analysis. The limits now come from the data
  (`UIKit.dataLimits`); the stimulus lines of Laser Speckle Flowmetry
  span the whole plot at any zoom.
- **Batch results table on MATLAB R2026b**: the column names follow the
  summary (the third column was still called Message): the table is shown
  as cells with its column names set.
- **Recording length**: Extract LDF and LDF Processing showed
  "4 min 60.0 s" for 299.97 s; the seconds are rounded before the split.
- **Colour-bar labels**: the CSD and spectrogram labels in LFP Analysis
  were cut off at the right edge; they are plain text (m², log10) with
  room next to them.
- **Laser speckle labels**: titles and checks read "1/K²" and "1/τc"
  instead of the markup "1/K^2" and "1/\tau_c".
- **Statistics hint**: in Signal Characterization the line under
  Statistical test names the post-hoc test of the chosen method
  (Wilcoxon or Mann-Whitney with Holm for ranks).
- **ERP channel for new files**: when the channels typed for earlier
  files are not in the new ones (or none were typed), EEG Analysis fills
  in Pz, Cz, Fz or Oz when the files have one, instead of the average of
  all channels, which is flat after an average reference.
- **10-5 positions next to file positions**: channels placed by name or by
  hand on the 10-5 system now sit on the head of the file's positions:
  their angle from the vertex is scaled to fit the channels that have
  both (most files and real heads have Fpz, T7, Oz and T8 near the
  equator, the idealized template 18 deg above it). A channel placed by
  hand on FT7 lands between F7 and T7, not next to FC5. The Positions
  line and the methods text give the factor. Names of electrodes on or
  beyond the head line are drawn outside it.
- **Tests on MATLAB R2026b**: the launcher layout test waits until the
  window has taken its new size and the layout has settled (late size
  events) before checking the columns.

## [0.6.0] - 2026-09-30

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
- **Histology: Import regions** (`core/io/readRegions.m`,
  `writeImageJRoi.m`): regions drawn in ImageJ / Fiji (.roi and the ROI
  Manager's RoiSet.zip: polygon, freehand, traced, rectangle and oval, with
  their names) or QuPath (GeoJSON annotations, Polygon and MultiPolygon,
  names or classifications) become Histology regions.
- **Electrophysiology recordings from eight more systems** (Extract Ephys
  → *Source*; `core/io/readSpikeGLX.m`, `readBlackrock.m`,
  `readNeuralynx.m`, `readPlexon.m`, `readMCS.m`, `readIntanRHS.m`,
  `readOpenEphysLegacy.m`, `readABF.m`): SpikeGLX (Neuropixels 1.0 / 2.0
  imec and nidq, sync and digital bits), Blackrock NSx 2.1-3.0 with the
  NEV digital input, Neuralynx .ncs folders with Events.nev TTLs, Plexon
  .plx (continuous channels placed by time stamp, AI and event channels,
  sorted spike times), Multi Channel Systems HDF5 (electrode, auxiliary
  and digital streams, events; MATLAB only), Intan .rhs (digital and
  analog inputs, stimulation current), Open Ephys legacy .continuous
  folders and Axon ABF 2 (gap-free or episodic). The format is also
  recognized from the file's extension, folder contents or first bytes;
  *Try demo data* writes the demo in each one, and the methods text names
  it. Each reader was checked during development against python-neo (and
  pyABF) on files from its synthetic writer (`write*.m`, used by the tests
  and the demo); for Multi Channel Systems, the file layout was checked
  with McsPyDataTools.
- **EDF, EDF+ and BDF files** (`core/io/readEDF.m`, `writeEDF.m`): the
  European Data Format that LabChart, clinical systems and many others
  export, with EDF+ annotations (onset, duration, text), discontinuous
  EDF+D recordings (records placed at their times) and BioSemi's 24-bit
  BDF with its Status trigger word. Extract LDF opens them again (the
  annotations can be the stimulus), and EEG analysis reads them as
  continuous EEG (the channels in volts, annotations and BioSemi trigger
  codes as events); the LDF demo and the rodent EEG demo are also written
  as EDF+ (and BDF). Values and annotations were checked during development
  against pyedflib and MNE-Python.
- **EGI .mff** (`core/io/readMFF.m`, `writeMFF.m`): Net Station
  recordings (the `.mff` folder or its `info.xml`): float32 blocks,
  channel gains, pauses placed at their times, events, sensor positions
  and the vertex reference. mffpy and MNE-Python read the files written
  here with the same values, gains, pause and events, and readMFF reads
  mffpy's files. The rodent EEG demo is also written as `.mff`.
- **XDF** (`core/io/readXDF.m`, `writeXDF.m`): LabRecorder files (Lab
  Streaming Layer): every stream with its time stamps (full or deduced)
  and clock offsets; EEG analysis reads the EEG stream and takes the
  marker streams as events. pyxdf reads the files written here with the
  same values, time stamps and markers. The rodent EEG demo is also
  written as XDF.
- **EEG-BIDS** (`core/io/readEEGBIDS.m`, `writeEEGBIDS.m`): EEG analysis
  opens the `sub-…_eeg` file of a BIDS dataset (OpenNeuro) with its
  sidecar files: only the EEG channels of `channels.tsv` (bad channels
  noted), the events of `events.tsv`, the positions of `electrodes.tsv`
  with `coordsystem.json`, and the reference and line frequency of
  `eeg.json`. The rodent demo is also written as a BIDS dataset. Checked
  during development both ways with MNE-BIDS.

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
  GPL-3.0; copies published under it keep those terms). Free for noncommercial use (universities, public
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

[unreleased]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/releases/tag/v1.0.1
[1.0.0]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/releases/tag/v1.0.0
[0.10.0]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/releases/tag/v0.10.0
[0.9.0]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/releases/tag/v0.9.0
[0.8.0]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/releases/tag/v0.8.0
[0.7.0]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/releases/tag/v0.7.0
[0.6.0]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/releases/tag/v0.6.0
[0.5.2]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/releases/tag/v0.5.2
[0.5.1]: https://github.com/alesuarez92/NeuronalDataAnalyzerLab/releases/tag/v0.5.1
