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
