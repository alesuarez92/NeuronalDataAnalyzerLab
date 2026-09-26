# Roadmap

What NeuroAnalyzer can do, what is being built next, and open items that
collaborators are welcome to pick up. Status is updated as work lands; the
[CHANGELOG](CHANGELOG.md) records each release.

To work on an open item, open an [issue](https://github.com/alesuarez92/NeuronalDataAnalyzerLab/issues)
first so we can agree on the scope, then follow [CONTRIBUTING.md](CONTRIBUTING.md).
Every change needs tests (`run_tests`), and new analysis steps should come with
synthetic demo data that has a known answer (see `core/DemoData.m` and `core/demo/`).

**Status:** ✅ done · 🔨 in progress · 📅 planned · 🟢 open for contributors

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
| ✅ | Histology and culture images | Imaging | Cell counts in still images, marker-positive cells, counts per region and per mm², channel and section / time-point alignment (shift or landmarks), with plain-language checks. |
| ✅ | More acquisition systems | Data formats | Intan RHD2000, Open Ephys binary and NWB 2.x import; NWB export. |
| ✅ | Batch processing | Every pipeline | Run one pipeline over a folder of animals or sessions with the same settings and get one summary table plus a per-file log. |
| ✅ | Session files and reports | Reproducibility | Save settings, input-file provenance (with checksums) and results together; a one-page PDF report per analysis for the lab notebook. |
| ✅ | CSD methods | LFP | Inverse CSD (delta, step, spline) and kernel CSD next to the standard CSD, tested against laminar data with a known CSD. |
| ✅ | Repeated-measures statistics | Response features | Repeated-measures ANOVA with sphericity checks and corrections, and the Friedman test, for the same animals in several conditions. |
| 📅 | EEG | New pipeline | Scalp and rodent EEG, first from data already cleaned in MATLAB, then from raw recordings of the most used systems. Plan below. |

## EEG (planned)

EEG will get its own window, reusing the ERP, time–frequency and statistics
code the LFP window already uses. It will stay general at first (any
electrode layout, the most used file formats); formats and features for
particular labs and systems will be added when they are needed.

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
| 🔨 | EEGLAB (`.set` / `.fdt`, or an `EEG` variable in a `.mat`) | Trials, events, channel positions, removed ICA components and history. |
| 🔨 | FieldTrip raw and averaged structures | `trial`, `time`, `label`, `trialinfo`, electrode positions; history from `cfg.previous`. |
| 🔨 | Plain matrix `.mat` | A form says which variable is the data, the sampling rate, the trial and channel dimensions and the conditions. No code needed. |
| 📅 | EDF / EDF+ / BDF | BioSemi, most clinical systems, and exports from OpenBCI, Natus, Compumedics and others. |
| 📅 | BrainVision (`.vhdr` / `.eeg` / `.vmrk`) | Brain Products; also a common export from MNE and EEGLAB. |
| 📅 | EGI `.mff` | Magstim EGI geodesic nets. |
| 📅 | EEG-BIDS folders | Shared datasets (OpenNeuro): the readers above plus the channel, electrode and event tables. |
| 🟢 | Neuroscan / ANT `.cnt`, g.tec, Brainstorm, ERPLAB | Later, when needed: one small, separately tested reader each. |

NWB recordings are already read by Extract Ephys.

### Electrode layouts (any convention)

- Positions stored in the file are used first (EEGLAB `chanlocs`, FieldTrip
  `elec`, BrainVision coordinates, EGI sensor layouts, BIDS `electrodes.tsv`,
  NWB electrode tables).
- Otherwise a template is matched to the channel names: 10-20, 10-10 and
  10-5 (computed from the system's definition; old and new names such as
  T3 / T7 both accepted, any case), BioSemi A1–D32 and EGI HydroCel
  (manufacturers' published coordinates, after checking their licence),
  EasyCap / actiCAP.
- Your own layout: a positions file (`.elc`, `.sfp`, `.loc` / `.locs`,
  `.ced`, `.xyz`, `.elp`, `.bvef`, or a CSV of name and x / y / z or angle
  / radius), or a small editor.
- Rodent and other skull montages: positions in mm from bregma
  (anterior–posterior, medial–lateral), drawn on a skull outline.
- Every format's coordinates are converted to one orientation; tests check
  that the same electrode from different files lands in the same place.
- A layout check draws every electrode on the head (or skull) and lists
  the channels matched, renamed (for example "T3 treated as T7"), without
  a position, duplicated or outside the head. It is confirmed before any
  map is drawn. Without positions, everything except scalp maps still works.

### Steps (one pull request each, with tests, demo data and Help)

| | Step | Notes |
|---|---|---|
| 🔨 | 1. Data model and MATLAB importers | `core/io/EEGSource.m`, `core/demo/demoEEG.m`, `tests/EEGFormatsTest.m`; the form for plain `.mat` files is in the window (step 2). EEGLAB, FieldTrip, plain `.mat`. Synthetic demo with known answers: 32 channels on 10-20 positions, three conditions, a known P1 / N1 / P300 and scalp distribution, known alpha, some trials already rejected; a rodent version with a few skull electrodes. The demo is written in every supported format, so each importer is tested against the same data. |
| 🔨 | 2. EEG Analysis window | Written (`apps/EEGAnalysisApp.m`, `core/EEGAnalysis.m`, tests, Help, launcher card, sessions and methods text): Overview (channels, trials per condition, what was already done), the form for plain `.mat` files, continuous recordings cut into trials, ERP per condition (butterfly, chosen channels, difference waves, grand average), peak and mean amplitude in a window per participant, and the repeated-measures statistics of Groups & statistics run in the window itself on those values. |
| 📅 | 3. Electrode layouts | Templates, position files, bregma coordinates and the layout check. |
| 📅 | 4. Scalp maps | Topography at a time or window: spherical spline on scalp layouts, flat interpolation on skull layouts; tested on the demo's known distribution. |
| 📅 | 5. Time–frequency per condition | ERSP / ITPC and band power from the existing time–frequency code. |
| 📅 | 6. Raw recordings | EDF / BDF, BrainVision, EGI `.mff`, EEG-BIDS, each with a tested writer. Basic steps only: filter, re-reference, cut trials at events, reject trials by amplitude, mark bad channels. ICA and advanced cleaning stay in EEGLAB / FieldTrip; Help explains how to bring their result back. |
| 📅 | 7. Batch, sessions, methods text, website | Same as the other pipelines, plus a walkthrough and later an EEG lesson in the virtual lab. |

## Direction: understand, check and teach

NeuroAnalyzer aims to be the analysis tool that is easiest to use
correctly and that teaches while it is used:

- **Own methods, end to end.** Every analysis runs inside NeuroAnalyzer
  with no other software to install. Its own methods keep improving and
  are measured against public ground-truth data; "better" is claimed only
  where that validation shows it.
- **Works alongside the established tools.** Results from specialised
  tools (for example Kilosort / Phy for spike sorting, Suite2p for
  calcium imaging) can be imported, checked, explained and compared with
  NeuroAnalyzer's own methods on the same data. Each importer is one small,
  separate, tested file, and NWB is preferred as the common format.
- **Explains itself.** Warnings in plain language, live previews of what a
  parameter does, and methods text generated from the analysis.
- **Teaches.** Lessons on synthetic data with known answers can check a
  student's result automatically.

| | Item | Notes |
|---|---|---|
| ✅ | Methods-section writer | *Methods text…* in every window drafts the methods from one or several saved sessions: every step, parameter, software version and citation, with placeholders for what only you know. |
| 📅 | Quality checks | A plain-language check per step (too few trials, refractory violations, CSD sink at an edge contact, sphericity, motion larger than a cell), each saying why it matters and what to try. |
| 📅 | Live parameter previews | Thresholds, filters, CSD smoothing: a small preview updates as the value changes. |
| 📅 | Import and compare | Kilosort / Phy units and Suite2p ROIs: quality checks, and side-by-side comparison with NeuroAnalyzer's own sorting and cell detection. |
| 🔨 | Virtual lab and lessons | First virtual experiment done: plan and record a simulated LDF experiment, analyse it in the normal windows and get feedback on the plan, processing and results; instructors grade a folder of submissions. Next: electrophysiology and imaging experiments, a course built on them. |
| 📅 | Ground-truth playground | Change noise, electrode spacing, sink depth, spike overlap or motion in the demo data and see where each method holds up or fails. |

## Open for contributors

Scoped items that are known to be missing. Each is self-contained.

### Data formats

| | Item | Notes |
|---|---|---|
| 🟢 | Validated NWB export | Without [matnwb](https://github.com/NeurodataWithoutBorders/matnwb) the built-in writer follows the NWB 2.7 layout but is not validated. Run `nwbinspector` / `pynwb.validate` on the exported files in CI and fix any findings. |
| 🟢 | Intan stimulation files (`.rhs`) | Only `.rhd` recording files are read today (`core/io/readIntanRHD.m`). |
| 🟢 | Intan "one file per signal type / per channel" | Only the traditional single-file `.rhd` format is supported. |
| 🟢 | Legacy Open Ephys format (`.continuous`) | Only the binary format (`structure.oebin`) is read. |
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
