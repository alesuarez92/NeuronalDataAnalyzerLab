# Validation paper plan (CSD + spike sorting on public ground truth)

Status: planning note, 2026-09-24. Literature scan limited to ~25 targeted searches; every reference below was checked against a web source (publisher, PubMed or repository page) unless marked **unverified**.

## 1. Recommended format

**Primary: eNeuro, Research Article — Methods/New Tools** (fallback: *J Neurosci Methods*; *Neuroinformatics* "Software Original Article"). **Later: a short JOSS paper** after the blockers below are cleared.

Why:
- The deliverable is *validation results*. JOSS states that "your paper must not focus on new research results accomplished with the software" and caps papers at 750–1750 words (Summary, Statement of need, State of the field, Software design, Research impact statement, AI usage disclosure). So the benchmark numbers need a conventional methods journal. JOSS can later cite that paper as its "research impact" evidence.
- **JOSS blockers today:** (a) an OSI-approved licence is required, but `LICENSE.txt` is currently "All Rights Reserved"; (b) at least six months of public, iterative development history (the first commit here is dated 2026-05-07); (c) documented research use. MATLAB is accepted, but JOSS "strongly prefers" software that does not depend on proprietary environments and may ask the authors to help find reviewers. JOSS charges no fees.
- **eNeuro** requires custom code that is central to the conclusions to be deposited (e.g. GitHub) and submitted as Extended Data (one ZIP), plus a "Code Accessibility" statement in Methods. A 2019 editorial (Open Source Tools and Methods category) sets a 4500-word limit and a 500-word introduction. Current limits should be re-checked at submission.
- **J Neurosci Methods** considers software/algorithm papers only if there is a research component, and reanalyses of public data only with "rigorous benchmarking or comparison of methods". A ground-truth benchmark meets that. The house abstract headings (Background / New method / Results / Comparison with existing methods / Conclusions) are **unverified** and should be checked in the guide for authors.
- **Neuroinformatics** Software Original Articles must include "a validation of its exactness according to accepted standards and an evaluation of its advantages to comparable software packages, including benchmarking if applicable", which is the same shape as this plan.
- **Minimal writing:** each Results subsection is one script that writes one figure, one table (CSV and LaTeX) and a `numbers.json`. The prose uses fixed templates that pull those numbers in. Methods text is reused from function docstrings. The model is SpikeForest/SpikeInterface: pipeline paper plus a public results page.

Before submitting anywhere, the licence has to be decided. Every venue above expects public code, and JOSS requires an OSI licence.

## 2. Section skeleton → figures/tables → `validation/` scripts

| Section | Content | Figure / table | Script |
|---|---|---|---|
| Abstract, Introduction | Gap: an integrated MATLAB GUI + headless pipeline for LDF/ephys/imaging, where component validation is usually missing. Position against Brainstorm, Wave_clus, SpikeInterface and kCSD. | none | none |
| Software overview | Architecture: GUI over headless `core/`. Data flow and supported formats. | Fig 1: architecture/workflow (reuse `docs/*Workflow.png`) | `v00_make_overview.m` |
| Methods: datasets | Table of ground-truth sets (Section 3), with versions and checksums | Table 1 | `v01_fetch_datasets.m` (downloads, verifies SHA-256, writes the table) |
| Methods: metrics | Definitions from Section 4 | none | `metrics/` (shared functions, unit-tested) |
| Results A: CSD, analytic | Known 1-D Gaussian monopole/dipole sources put through the forward model to give LFP, plus noise and channel-dropout sweeps. Compare standard δ-CSD (and iCSD if implemented). | Fig 2: true vs estimated CSD maps; error vs SNR and vs inter-contact spacing | `v10_csd_analytic.m` |
| Results B: CSD, biophysical model | Simulated laminar LFP with model CSD (Rimehaug 2023 data; optionally an LFPy/hybridLFPy run) | Fig 3: CSD image + sink-depth error; Table 2: r, relRMSE per condition | `v11_csd_model.m` |
| Results C: spike detection | Detection recall/precision vs threshold on simulated tetrode/single-channel data | Fig 4: ROC-style curves per SNR | `v20_detect.m` |
| Results D: spike sorting | k-means / GMM / DBSCAN ± auto-merge on Quiroga simulations, MEArec and paired recordings | Fig 5: accuracy vs SNR per unit (SpikeForest style); Table 3: mean precision/recall/accuracy, units with accuracy ≥ 0.8 | `v21_sort_sim.m`, `v22_sort_paired.m` |
| Results E: optional reference | Same inputs through Wave_clus (MATLAB) as an external reference point | Table 3 column | `v23_ref_waveclus.m` |
| Runtime | Wall-clock time vs recording length and channel count | Table 4 | `v30_runtime.m` |
| Discussion | Limits: simulated noise, single-shank CSD, no drift correction | none | none |
| Code/data availability | Repo tag, archive DOI, dataset DOIs, `run_all_validation.m` | none | `run_all_validation.m` (runs everything and writes `validation/out/`) |

Rules: fixed random seeds; results carry the git SHA and MATLAB version; CI runs a reduced subset (short excerpts) so the full run stays local.

## 3. Dataset shortlist

| Dataset | Ground truth | Format | Access | Licence |
|---|---|---|---|---|
| Quiroga simulated sets (Easy1/2, Difficult1/2; Quian Quiroga et al. 2004) | Spike times + unit labels, 3 units per recording, several noise levels | MAT | Univ. Leicester Wave_clus page; IEEE DataPort "Simulated dataset", DOI 10.21227/kvnr-bt09 | **unverified** |
| MEArec-generated recordings (Buccino & Einevoll) | Spike times, templates, positions of all units (tetrode, Neuropixels-like) | HDF5 (`.h5`, MEArec schema) | Zenodo records 3696926 (paper datasets), 4657314 / 3825284 (SpikeInterface datasets); or generate with MEArec (Python, MIT licence) | Code MIT; Zenodo data licence **unverified** |
| SpikeForest collections (paired, synthetic, hybrid Janelia, MEArec) | Spike times of ~35,000 GT units over 650 recordings | SpikeInterface extractors via `spikeforest` pip package + kachery-cloud (Google login); an NWB copy is reported on DANDI (000034, **unverified**) | github.com/flatironinstitute/spikeforest | **unverified** |
| Marques-Smith et al. 2018 (patch + Neuropixels) | Patch-clamp spike times for one neuron per recording | Raw binary + GT times (**format unverified**) | Kampff lab sc.io "Paired Recordings"; CRCNS `spe-1` (account required) | CC BY-SA 4.0 (stated in preprint) |
| Neto et al. 2016 (juxtacellular + polytrode) | Juxtacellular spike times | Raw binary (**unverified**) | Kampff lab sc.io | **unverified** |
| kCSD-python test sources | Analytic CSD profiles (`gauss_1d_mono`, `gauss_1d_dipole`, 2-D/3-D variants in `kcsd/validation/csd_profile.py`) | Python functions, straightforward to port to MATLAB | github.com/Neuroinflab/kCSD-python | BSD-3-Clause |
| Rimehaug et al. 2023 V1 biophysical model | Simulated LFP and CSD from a model of >50k Hodgkin–Huxley neurons, plus matched Neuropixels data | Dryad package (**formats unverified**, likely HDF5/NPY) | doi:10.5061/dryad.k3j9kd5b8 | CC0 under Dryad policy (**unverified** for this item) |
| LFPy / hybridLFPy simulations | LFP and CSD generated from the same run (known transmembrane currents) | User-generated (Python/NEURON/NEST) and exported to HDF5/MAT | github.com/LFPy/LFPy, github.com/INM-6/hybridLFPy | GPL-3.0 (code) |

Minimum viable set: Quiroga + one MEArec tetrode file + one paired recording (spikes); kCSD analytic + Rimehaug (CSD).

## 4. Metric definitions

**Spike sorting.** These follow SpikeForest and the SpikeInterface `comparison` module; the SpikeInterface defaults were checked in its source.
- Matching: a GT spike and a sorted spike match if |t_gt − t_sorted| ≤ Δ, with Δ = 0.4 ms (SpikeInterface `delta_time` default). Each GT unit is paired with a sorted unit by agreement score (Hungarian assignment; `match_score` ≥ 0.5).
- Per GT unit, with TP matched, FN missed and FP extra spikes: **accuracy = TP/(TP+FN+FP)**, **recall = TP/(TP+FN)**, **precision = TP/(TP+FP)**, FDR = FP/(TP+FP).
- Reporting: accuracy vs unit SNR scatter. Means over GT units with SNR above a threshold (SpikeForest uses 8 and notes that conclusions depend strongly on it). Unit counts: "well detected" (accuracy ≥ 0.8), redundant, over-merged and false-positive units (SpikeInterface defaults 0.8 / 0.2 / 0.2).
- Detection alone: the same TP/FN/FP counts without unit assignment.

**CSD.** These are standard definitions to report together; the exact formulas are chosen here and are not taken from a single source.
- Pearson r between the estimated and true CSD over space×time (and per time frame).
- Relative error: ‖Ĉ − C‖₂ / ‖C‖₂ (report RMSE in µA/mm³ as well). Compare on the estimate's depth grid, excluding the edge contacts that δ-CSD cannot estimate.
- Sink localisation: |z_peak-sink(est) − z_peak-sink(true)| in µm, plus the sign-agreement fraction.
- Sweeps: noise level, contact spacing, source width relative to spacing, and the conductivity assumption (Pettersen 2006 shows how finite source extent affects δ-CSD).

## 5. Reference list

Exemplar validation/benchmark papers
1. Magland J, Jun JJ, Lovero E, Morley AJ, Hurwitz CL, Buccino AP, Garcia S, Barnett AH (2020). SpikeForest, reproducible web-facing ground-truth validation of automated neural spike sorters. *eLife* 9:e55167. doi:10.7554/eLife.55167
2. Buccino AP, Hurwitz CL, Garcia S, Magland J, Siegle JH, Hurwitz R, et al. (2020). SpikeInterface, a unified framework for spike sorting. *eLife* 9:e61834. doi:10.7554/eLife.61834
3. Buccino AP, Einevoll GT (2021; online 2020). MEArec: a fast and customizable testbench simulator for ground-truth extracellular spiking activity. *Neuroinformatics* 19(1):185–204. doi:10.1007/s12021-020-09467-7
4. Chintaluri C, Bejtka M, Średniawa W, Czerwiński M, Dzik JM, Jędrzejewska-Szmek J, et al. (2024). kCSD-python, reliable current source density estimation with quality control. *PLoS Comput Biol* 20(3):e1011941. doi:10.1371/journal.pcbi.1011941
5. Pettersen KH, Devor A, Ulbert I, Dale AM, Einevoll GT (2006). Current-source density estimation based on inversion of electrostatic forward solution: effects of finite extent of neuronal activity and conductivity discontinuities. *J Neurosci Methods* 154(1–2):116–133. doi:10.1016/j.jneumeth.2005.12.005
6. Hagen E, Næss S, Ness TV, Einevoll GT (2018). Multimodal modeling of neural network activity: computing LFP, ECoG, EEG, and MEG signals with LFPy 2.0. *Front Neuroinform* 12:92. doi:10.3389/fninf.2018.00092
7. Hagen E, Dahmen D, Stavrinou ML, Lindén H, Tetzlaff T, van Albada SJ, Grün S, Diesmann M, Einevoll GT (2016). Hybrid scheme for modeling local field potentials from point-neuron networks. *Cereb Cortex* 26(12):4461–4496. doi:10.1093/cercor/bhw237
8. Quian Quiroga R, Nadasdy Z, Ben-Shaul Y (2004). Unsupervised spike detection and sorting with wavelets and superparamagnetic clustering. *Neural Comput* 16(8):1661–1687. doi:10.1162/089976604774201631
9. Chaure FJ, Rey HG, Quian Quiroga R (2018). A novel and fully automatic spike-sorting implementation with variable number of features. *J Neurophysiol* 120(4):1859–1871. doi:10.1152/jn.00339.2018
10. Pedreira C, Martinez J, Ison MJ, Quian Quiroga R (2012). How many neurons can we see with current spike sorting algorithms? *J Neurosci Methods* 211:58–65. DOI 10.1016/j.jneumeth.2012.06.026 **unverified** (metadata confirmed, DOI not)
11. Tadel F, Baillet S, Mosher JC, Pantazis D, Leahy RM (2011). Brainstorm: a user-friendly application for MEG/EEG analysis. *Comput Intell Neurosci* 2011:879716. doi:10.1155/2011/879716. A MATLAB GUI-toolbox precedent. Its validation approach was not reviewed here.

Ground-truth data papers
12. Neto JP, Lopes G, Frazão J, Nogueira J, Lacerda P, Baião P, et al., Kampff AR (2016). Validating silicon polytrodes with paired juxtacellular recordings: method and dataset. *J Neurophysiol* 116:892–903. doi:10.1152/jn.00103.2016. The full author list is **unverified**; a corrigendum exists (PMC9815898).
13. Marques-Smith A, Neto JP, Lopes G, Nogueira J, Calcaterra L, Frazão J, Kim D, Phillips M, Dimitriadis G, Kampff AR (2018). Recording from the same neuron with high-density CMOS probes and patch-clamp: a ground-truth dataset and an experiment in collaboration. *bioRxiv*. doi:10.1101/370080
14. Rimehaug AE, Stasik AJ, Hagen E, Billeh YN, Siegle JH, Dai K, Olsen SR, Koch C, Einevoll GT, Arkhipov A (2023). Uncovering circuit mechanisms of current sinks and sources with biophysical simulations of primary visual cortex. *eLife* 12:RP87169. doi:10.7554/eLife.87169. Data: doi:10.5061/dryad.k3j9kd5b8. The article number is **unverified**.

Venue requirements (checked on the web, 2026-09-24): JOSS `docs/submitting.md` and `docs/paper.md` (github.com/openjournals/joss); eNeuro Information for Authors and the 2019 editorial "Open Source Tools and Methods" (eNeuro 6(5):ENEURO.0342-19.2019); the J Neurosci Methods guide for authors (ScienceDirect); Neuroinformatics submission guidelines (Springer). Frontiers in Neuroinformatics offers a "Technology and Code" article type; its word limit is **unverified**.

Not covered in this scan: Elephant, MNE and other JOSS neuroscience examples; SpikeForest dataset licences; exact formats of the paired-recording files.
