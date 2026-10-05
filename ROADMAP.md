# Roadmap

What Neuronal Data Analyzer Lab can do, what is being built next, and open items that
collaborators are welcome to pick up. Status is updated as work lands; the
[CHANGELOG](CHANGELOG.md) records each release.

To work on an open item, open an [issue](https://github.com/alesuarez92/NeuronalDataAnalyzerLab/issues)
first so we can agree on the scope, then follow [CONTRIBUTING.md](CONTRIBUTING.md).
Every change needs tests (`run_tests`), and new analysis steps should come with
synthetic demo data that has a known answer (see `core/DemoData.m` and `core/demo/`).

**Status:** ✅ done · 🔨 in progress · 📅 planned · 🟢 open for contributors

## Version 1.0

1.0 is a promise of stability, not a feature count: from 1.0 on, a change
that breaks sessions, exports or scripts waits for 2.0. Released as 1.0.0
on 2026-10-05, when all of these held:

| | Condition | What it means |
|---|---|---|
| ✅ | Every window has its checks | A Checks tab in every analysis window and a Checks column in Batch (quality checks steps 1–4, released in 0.10.0). |
| ✅ | Formats and script functions frozen | The session file, the .csv / .mat exports and the main script functions (`GroupStats`, `EEGAnalysis`, `Batch`, the readers) keep their names and fields: listed in [docs/FORMATS.md](docs/FORMATS.md), made consistent across windows and locked by tests. |
| ✅ | Tested on data with known answers | Every window and reader tested on synthetic recordings whose answers are known (the demo data, and the demo written in each vendor's file format to its published specification). The lab's own recordings are not the author's to share, so they are not part of the tests. Readers for other imagers come only from real sample files, after 1.0. |
| ✅ | Help and website checked | One full pass over the Help and the website against fresh frames of every window (after 0.10.0), and frames that show each window's session buttons. |

Live parameter previews, Import and compare and the other planned items
below can come after 1.0.

## Found by the demo data

The synthetic demo recordings have known ground truth. Running every window on
them exposed two limits, which are now fixed.

| | Item | Area | What changed |
|---|---|---|---|
| ✅ | Merge over-split clusters | MUA | K-means split one unit into near-identical clusters. Auto-merge by mean-waveform correlation and amplitude ratio, plus *Merge selected*, *Split selected* and *Undo*. The demo now gives the simulated units. |
| ✅ | Robust vessel diameter | Imaging | A bright red blood cell crossing the line made the diameter jump. Walls are now located to sub-pixel precision, with an optional robust mode (running medians and a Hampel filter). |

## Features

| | Item | Area | Notes |
|---|---|---|---|
| ✅ | Group statistics | Response features | Paired / Welch t-test, one-way ANOVA with Tukey–Kramer, Wilcoxon, Mann–Whitney, Kruskal–Wallis, effect sizes with 95% CI. |
| ✅ | Publication figures | Response features | Vector PDF / SVG / EPS and 300 / 600 dpi PNG / TIFF. |
| ✅ | Time–frequency analysis | LFP | Welch spectrum, spectrogram, Morlet ERSP / ITPC and band power next to the ERP and CSD. |
| ✅ | Per-unit responses | MUA | Raster and PSTH per unit, auto- and cross-correlograms. |
| ✅ | Motion correction and many ROIs | Imaging | Rigid registration, several ROIs at once, automatic cell detection from a local correlation image. |
| ✅ | Laser speckle flowmetry | Blood flow | Raw speckle, contrast or perfusion images: speckle contrast, flow index, flow per ROI over time, trials and a response map. |
| ✅ | Histology and culture images | Imaging | Cell counts in still images, marker-positive cells, counts per region and per mm², channel and section / time-point alignment (shift or landmarks), with plain-language checks. |
| ✅ | More acquisition systems | Data formats | Intan RHD2000, Open Ephys binary and NWB 2.x import; NWB export. Then SpikeGLX, Blackrock, Neuralynx, Plexon `.plx`, Multi Channel Systems HDF5, Intan `.rhs`, Open Ephys legacy `.continuous` and Axon ABF 2 in Extract Ephys; LabChart, AcqKnowledge, Spike2, EDF and tables in Extract LDF. |
| ✅ | Batch processing | Every pipeline | Run one pipeline over a folder of animals or sessions with the same settings and get one summary table plus a per-file log. |
| ✅ | Session files and reports | Reproducibility | Save settings, input-file provenance (with checksums) and results together; a one-page PDF report per analysis for the lab notebook. |
| ✅ | CSD methods | LFP | Inverse CSD (delta, step, spline) and kernel CSD next to the standard CSD, tested against laminar data with a known CSD. |
| ✅ | Repeated-measures statistics | Response features | Repeated-measures ANOVA with sphericity checks and corrections, and the Friedman test, for the same animals in several conditions. |
| ✅ | EEG | New pipeline | Scalp and rodent EEG, from data already cleaned in MATLAB (v0.4.0: EEG Analysis window) and from raw recordings of the most used systems: readers, basic cleaning, electrode layouts, scalp maps, time–frequency and batch processing (steps 1–7 below). More formats and cap templates when needed. |

## EEG

EEG has its own window (since 0.4.0), reusing the ERP, time–frequency and
statistics code of the LFP window. It is general (any electrode layout, the
most used file formats); formats and features for particular labs and
systems are added when they are needed.

**Data already cleaned in MATLAB comes first.** Cleaned EEG is usually
already cut into trials with a condition per trial, so the window accepts
trials as well as continuous recordings. Nothing is cleaned a second time:
what was already done (filters, rejected trials, removed ICA components,
interpolated channels) is read from the file and shown in plain words, and
the data are used as they are. EEGLAB and FieldTrip are not needed to read
their files.

### Formats

| | Source | Notes |
|---|---|---|
| ✅ | EEGLAB (`.set` / `.fdt`, or an `EEG` variable in a `.mat`) | Trials, events, channel positions, removed ICA components and history. |
| ✅ | FieldTrip raw and averaged structures | `trial`, `time`, `label`, `trialinfo`, electrode positions; history from `cfg.previous`. |
| ✅ | Plain matrix `.mat` | A form says which variable is the data, the sampling rate, the trial and channel dimensions and the conditions. No code needed. |
| ✅ | EDF / EDF+ / BDF | BioSemi, most clinical systems, and exports from OpenBCI, Natus, Compumedics and others. Continuous recordings; EDF+ annotations and BioSemi trigger codes become events; EDF+D gaps kept. |
| ✅ | BrainVision (`.vhdr` / `.eeg` / `.vmrk`) | Brain Products Recorder and Analyzer; also a common export from MNE and EEGLAB. Continuous recordings with their markers, Analyzer segments (condition = marker at time 0), positions, units, and the amplifier filters used when recording. |
| ✅ | EGI `.mff` | Magstim EGI geodesic nets: continuous recordings with pauses, events, positions and channel gains (segmented files are read as one piece). |
| ✅ | EEG-BIDS folders | Shared datasets (OpenNeuro): the readers above plus the channel, electrode and event tables. |
| ✅ | XDF (Lab Streaming Layer) | LabRecorder files: the EEG stream and marker streams as events, clock offsets applied. |
| 🟢 | Neuroscan / ANT `.cnt`, g.tec, Brainstorm, ERPLAB | Later, when needed: one small, separately tested reader each. |

NWB recordings are already read by Extract Ephys.

### Electrode layouts (any convention)

Done in step 3 (*Electrode layout…* in the EEG window; `core/EEGLayout.m`,
`core/io/readElectrodes.m`, `core/io/writeElectrodes.m`):

- Positions stored in the file are used first (EEGLAB `chanlocs`, FieldTrip
  `elec`, BrainVision coordinates, EGI sensor layouts, BIDS `electrodes.tsv`).
- Otherwise the channels are placed by name on the 10-5 system (345
  positions, which include the 10-20 and 10-10 ones), computed from the
  system's definition on an idealized sphere; old and new names such as
  T3 / T7 are both accepted, in any case, and `EEG ` prefixes and reference
  suffixes are dropped. actiCAP and EasyCap caps use these names.
- Your own layout: a positions file (`.elc`, `.sfp`, `.loc` / `.locs`,
  `.ced`, `.xyz`, `.elp`, `.bvef`, EasyCap / BioSemi `Site Theta Phi`
  lists, a CSV / TSV of name and x / y / z, angles or ap / ml, BIDS
  `electrodes.tsv`), or the table of the layout window (a 10-5 name per
  channel, or AP / ML in mm).
- Rodent and other skull montages: positions in mm from bregma
  (anterior–posterior, medial–lateral), drawn on a skull outline.
- Every format's coordinates are converted to one orientation (x = right
  ear, y = nose, z = up), with a check against the template for files
  whose axes are unclear; tests check that the same electrode from
  different files lands in the same place.
- A layout check draws every electrode on the head (or skull) and lists
  the channels matched, renamed (for example "T3 treated as T7"), without
  a position, duplicated or outside the head. *Use this layout* confirms
  it; scalp maps (step 4) use the layout and say when it is not
  confirmed. Without positions, everything except scalp maps still works.

| | Still open | Notes |
|---|---|---|
| 📅 | BioSemi A1–D32 and EGI HydroCel templates | From the manufacturers' published coordinates, once their licence is checked. Until then, load the manufacturer's coordinate file as a positions file. |
| 🟢 | NWB electrode tables | When the EEG window reads NWB recordings (Extract Ephys reads them today). |

### Steps (one pull request each, with tests, demo data and Help)

| | Step | Notes |
|---|---|---|
| ✅ | 1. Data model and MATLAB importers | `core/io/EEGSource.m`, `core/demo/demoEEG.m`, `tests/EEGFormatsTest.m`; the form for plain `.mat` files is in the window (step 2). EEGLAB, FieldTrip, plain `.mat`. Synthetic demo with known answers: 32 channels on 10-20 positions, three conditions, a known P1 / N1 / P300 and scalp distribution, known alpha, some trials already rejected; a rodent version with a few skull electrodes. The demo is written in every supported format, so each importer is tested against the same data. |
| ✅ | 2. EEG Analysis window | In v0.4.0 (`apps/EEGAnalysisApp.m`, `core/EEGAnalysis.m`, tests, Help, launcher card, sessions and methods text): Overview (channels, trials per condition, what was already done), the form for plain `.mat` files, continuous recordings cut into trials, ERP per condition (butterfly, chosen channels, difference waves, grand average), peak and mean amplitude in a window per participant, and the repeated-measures statistics of Groups & statistics run in the window itself on those values (they stay in the EEG window; not sent to Signal Characterization). |
| ✅ | 3. Electrode layouts | `core/EEGLayout.m` (the 10-5 template computed, name matching, one orientation, skull layouts in mm from bregma, the check), `core/io/readElectrodes.m` / `writeElectrodes.m` (position files), the *Electrode layout…* window in step 1, sessions and methods text; `tests/EEGLayoutTest.m`, `tests/ElectrodesFileTest.m`, walkthrough. BioSemi and EGI HydroCel templates wait for the licence check (above). |
| ✅ | 4. Scalp maps | `core/ScalpMap.m`, *Scalp maps* in step 5 of the window (`apps/EEGAnalysisApp.m`), sessions, methods text and Help; `tests/ScalpMapTest.m`, walkthrough. The mean voltage in the window of step 5, one map per condition and A minus B, one colour scale: spherical splines on scalp layouts (Perrin et al., 1989; as MNE-Python's interpolation matrix without regularization), a thin-plate spline inside the electrodes on skull layouts. Tested against MNE-Python and scipy and on the demo's known distributions (P300 at Pz, N1 at Cz, the rodent VEP over V1). |
| ✅ | 5. Time–frequency per condition | Step 7 of the window (`EEGAnalysis.timeFrequency`, `grandTimeFrequency`; `apps/EEGAnalysisApp.m`), sessions, methods text and Help; tests in `tests/EEGAnalysisTest.m`, walkthrough. Morlet wavelets of `core/TimeFrequency.m` on every trial: ERSP per condition and A minus B, ITPC with its chance level, band power as % change (mean ± SEM), per participant and across participants. Values only where the whole wavelet lies inside the trial (the same as from the continuous recording); the window says which frequencies the trial length allows. The demo's alpha halves after Target (O1 / Oz / O2, 350–650 ms) as a known answer. |
| ✅ | 6. Raw recordings | BrainVision read first (the author's lab records with Brain Products); EDF / BDF, EGI `.mff` and EEG-BIDS done, each with a tested writer. Basic steps in the window (steps 2 and 3): bad channels (suggested, left out of the reference, rejection and ERPs), zero-phase FIR filters as MNE-Python (high-pass, low-pass, notch), re-reference (average, linked mastoids, chosen channels), trials cut at named events, trials rejected by peak-to-peak or absolute amplitude; a raw demo with known artefacts. ICA and advanced cleaning stay in EEGLAB / FieldTrip; Help explains how to bring their result back. |
| ✅ | 7. Batch, sessions, methods text, website | Sessions, methods text, Help and the website came with each step. Batch: the pipeline *EEG: ERPs and a measure per condition* (`Batch.fileEEG`) runs the window's steps on a folder, one row per file and condition, with the same numbers as the window; demo batch on the raw recordings; `tests/BatchFeaturesTest.m`, walkthrough frames. |

## Direction: understand, check and teach

Neuronal Data Analyzer Lab aims to be the analysis tool that is easiest to use
correctly and that teaches while it is used:

- **Own methods, end to end.** Every analysis runs inside Neuronal Data Analyzer Lab
  with no other software to install. Its own methods keep improving and
  are measured against public ground-truth data; "better" is claimed only
  where that validation shows it.
- **Works alongside the established tools.** Results from specialised
  tools (for example Kilosort / Phy for spike sorting, Suite2p for
  calcium imaging) can be imported, checked, explained and compared with
  Neuronal Data Analyzer Lab's own methods on the same data. Each importer is one small,
  separate, tested file, and NWB is preferred as the common format.
- **Explains itself.** Warnings in plain language, live previews of what a
  parameter does, and methods text generated from the analysis.
- **Teaches.** Lessons on synthetic data with known answers can check a
  student's result automatically.

| | Item | Notes |
|---|---|---|
| ✅ | Methods-section writer | *Methods text…* in every window drafts the methods from one or several saved sessions: every step, parameter, software version and citation, with placeholders for what only you know. |
| ✅ | Quality checks | A plain-language check per step (too few trials, refractory violations, CSD sink at an edge contact, sphericity, motion larger than a cell), each saying why it matters and what to try. Step 1 done: one format and one Checks tab for every window (Laser speckle and Histology use it), kept in sessions, reports and the methods text. Step 2 done: blood flow, the needle probe and perfusion images with the same checks (drift, movement artefacts, signal stuck at 0 or at the top, trials, time resolution) plus each source's own (probe baseline and filter; speckle field shift, speckle size, exposure, illumination, static scattering; clipped perfusion images), in LDF Process, Batch and Laser speckle, with demo files that contain each fault. Step 3 done: electrophysiology, in LFP, MUA and EEG Analysis and Batch (LFP: a stimulus artefact into the N1 window, the CSD sink at an edge contact, a missing electrode spacing; MUA: refractory violations, low signal-to-noise, spike amplitude drift; EEG: trials left per condition, a rejection that hits one condition more, unbalanced trial counts with a peak measure, many bad channels, a measured channel that was interpolated), with demo files that contain each fault. Step 4 done: imaging and statistics, in ROI Analysis (motion larger than a cell, bleaching, clipped pixels) and Groups & statistics and EEG Analysis' statistics (n and pseudoreplication, normality with Shapiro–Wilk, sphericity, equal spread), with demo files that contain each fault. |
| 📅 | One-click installer | A `.mltbx` toolbox file, so installing and upgrading is one click instead of replacing the folder. |
| 📅 | Live parameter previews | Thresholds, filters, CSD smoothing: a small preview updates as the value changes. |
| 📅 | Import and compare | Kilosort / Phy units and Suite2p ROIs: quality checks, and side-by-side comparison with Neuronal Data Analyzer Lab's own sorting and cell detection. |
| 📅 | Course and Virtual lab | A very interactive, hands-on course that uses a virtual lab: plan, record and analyse simulated experiments in the real windows, with feedback on every step. Coming soon (the launcher shows them as *Coming soon*). |
| 📅 | Ground-truth playground | Change noise, electrode spacing, sink depth, spike overlap or motion in the demo data and see where each method holds up or fails. |

## Open for contributors

Scoped items that are known to be missing. Each is self-contained.

### Data formats

| | Item | Notes |
|---|---|---|
| 🟢 | Validated NWB export | Without [matnwb](https://github.com/NeurodataWithoutBorders/matnwb) the built-in writer follows the NWB 2.7 layout but is not validated. Run `nwbinspector` / `pynwb.validate` on the exported files in CI and fix any findings. |
| 🟢 | Intan "one file per signal type / per channel" | Only the traditional single-file `.rhd` format is supported. |
| 🟢 | Plexon `.pl2` | Only `.plx` files are read; export `.pl2` recordings to `.plx` in Plexon's software for now. |
| 🟢 | NWB 1.x and 3-D series | Only NWB 2.x files with 2-D ElectricalSeries are read. |
| 🟢 | Long recordings | Recordings are loaded into memory in full. Read in chunks, or use memory-mapped files for Open Ephys and NWB. |
| 🟢 | Spike export to NWB | Export sorted units (spike times, waveforms, cluster quality) as an NWB `Units` table. |

### Analysis

| | Item | Area | Notes |
|---|---|---|---|
| ✅ | One stimulus-onset rule | LDF / LFP / MUA | All three keep a crossing only if it comes after the minimum interval from the last kept onset (a pulse train gives one onset). LFP still thresholds the mean-subtracted stimulus. |
| 🟢 | Time–frequency in the ERP export | LFP | *Export ERP / CSD…* does not include spectra, ERSP / ITPC or band power. |
| 🟢 | Non-rigid motion correction | Imaging | Motion correction handles translation only; add piecewise-rigid registration for tissue deformation. |
| 🟢 | Neuropil correction | Imaging | Subtract a scaled surround signal from each cell's trace before ΔF/F. |
| ✅ | Reproducible sorting | MUA | *Configure...* has a Random seed (default 0); the window sets it before every run, so the same data and settings give the same clusters. |

### Documentation

| | Item | Notes |
|---|---|---|
| 🟢 | Missing citations | Some methods are described in the code without a reference: FFT phase correlation (`registerStackRigid`), the Hampel filter (`robustTimeSeries`), the local correlation image (`localCorrelationImage`), the studentized-range integration and rank-biserial correlation (`GroupStats`), and the ITPC chance level (Rayleigh approximation). Add verified references. |
| 🟢 | Translations | Help and the website are in English only. |
