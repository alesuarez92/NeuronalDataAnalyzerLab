# Handoff — NeuroAnalyzer improvement strand

Start a new session by reading, in order: `CLAUDE.md`, this file,
`docs/UI_STYLE.md`, `docs/dev/AGENT_RULES.md`, then `docs/dev/reports/*.md`.
Classification of the ongoing work: **EXISTING STRAND**.

- **Branch:** `claude/admiring-cori-52ekpa`. Every commit is pushed there. No PR exists yet, and the owner hasn't asked for one.
- **Repo rule** (from `CLAUDE.md`): no AI or agent attribution in commits, PRs or anything else visible on GitHub.

## 1. What exists now

### Done and green in CI (real MATLAB)

1. **Bug-fix pass.** Signal features (FWHM, rise and decay used the peak's time where they needed its amplitude). Imaging maths. ERP averaging included skipped epochs as zeros. The LFP sampling rate saved after downsampling was wrong. MUA smoothing nulled the saved signal. LDF re-processing compounded filtering. Also MUA sorting crashes and polarity handling, ROI RGB/TIFF loading, and Signal Characterization's direction and ERP-file handling. Details are in the CHANGELOG "Unreleased" section and the commit messages.
2. **CI:** `.github/workflows/ci.yml`.
   - MATLAB via `matlab-actions`: code analysis (fails on errors) plus `run_tests`.
   - An Xvfb virtual display, so real windows open.
   - Screenshots are uploaded as an artifact and also **force-pushed to the branch `ci/screenshots`**. The container's network can't download artifacts, so fetch the branch instead:
     `git fetch origin ci/screenshots && git archive FETCH_HEAD | tar -x -C /tmp/shots`
3. **UI redesign of all 14 windows.**
   - `core/UIKit.m` provides shared building blocks: window, dialog, header with Help, step cards, fields, status bar, busy dialog, alerts, `styleAxes`, `emptyAxes`.
   - `core/UITheme.m` holds the colours, including an Okabe–Ito plot palette.
   - Every window uses numbered step cards on the left, plots on the right and a status bar.
   - Help (`apps/HelpApp.m`) has a topic list; each page has quick start, demo data, inputs/outputs, how it works and troubleshooting.
4. **Demo data** (`core/DemoData.m`): deterministic synthetic LDF, TDT-like tank, LFP, MUA and imaging data, each with a `.truth` field.
   - `DemoData.file(kind)` caches the files in `tempdir/NeuroAnalyzerDemo`.
   - Every window has **Try demo data** (`loadDemo()`), and every Help topic has **▶ Try it with demo data**.
   - The windows expose dialog-free public methods (`openFile`, `runERP(params)`, `runSorting(params)`, …).
5. **Tests** (`tests/`, run with `run_tests`; about 55 tests, all green at `f19e455`):
   - unit tests: Validation, Processor, DataLoader, SignalFeatures, Imaging, DemoData (ground-truth recovery);
   - `AppSmokeTest`: every window opens and is screenshotted;
   - `DemoWalkthroughTest`: every window is driven step by step on demo data, with a frame per step.

### Validated against demo ground truth (walkthrough frames)

- **LDF:** peak about 4 s after onset, about +30 PU.
- **LFP:** N1 at about 15 ms, deepest on channel 4; CSD sink on channel 4.
- **Imaging:** ΔF/F peaks at 3, 7 and 11 s; vessel diameter 9–15 px with a 5 s period; red blood cell at 2 px/frame.
- **MUA:** sorting over-split channel 4 into 4 clusters. Wave 1 fixes this.

### Preview page

- The private artifact "NeuroAnalyzer Tool Tour" is at https://claude.ai/artifact/8nJqKUUxYBGiXc8ivNeTBZ.
- Its source is not in the repo. The website below replaces it.

## 2. In flight when this handoff was written — WAVE 1 (five background agents)

Each agent implements one area, commits its own files and pushes. It also
writes its full report (API, tests, references, ready-to-paste Help text) to
`docs/dev/reports/<area>.md`. **None of this work has been through CI yet.**

| Area | Main files | Report |
|---|---|---|
| MUA: auto-merge over-split clusters, manual merge/split/undo, raster + PSTH, auto/cross-correlograms, optional headless `core/MUAPipeline.m` | `apps/MUAAnalysisApp.m`, `core/ClusterTools.m`, `core/SpikeTrains.m` | `mua.md` |
| Imaging: sub-pixel and outlier-robust vessel diameter, rigid motion correction (phase correlation), multiple ROIs, automatic cell detection (local correlation image) | `apps/ROIAnalysisApp.m`, `core/imaging/*` | `imaging.md` |
| LFP time–frequency: Morlet TF, STFT spectrogram, Welch PSD, band power, ERSP/ITPC; headless `core/ERPAnalysis.m` | `apps/LFPAnalysisApp.m`, `core/TimeFrequency.m`, `core/ERPAnalysis.m` | `lfp-time-frequency.md` |
| Formats: Intan RHD, Open Ephys binary, NWB read; NWB-style export (not validated unless matnwb is present) | `apps/ExtractEphysApp.m`, `core/io/*` | `formats.md` |
| Group statistics (paired and Welch t-test, one-way ANOVA with post-hoc, Wilcoxon, Mann–Whitney, effect sizes) and publication figure export (vector PDF/SVG) | `apps/SignalCharacterizationApp.m`, `core/GroupStats.m`, `core/FigureExport.m` | `group-stats.md` |

Each area also adds `core/demo/*.m` generators and
`tests/<Area>FeaturesTest.m` plus `tests/<Area>WalkthroughTest.m`.

### First job for the next session: close out wave 1

1. Check which wave-1 commits landed: run `git log --oneline -15` and list `docs/dev/reports/`.
   - If an area has no commit, its agent didn't finish. Relaunch that area with the matching prompt, which is summarised in the table above; the rules are in `docs/dev/AGENT_RULES.md`.
2. Check CI through the GitHub MCP tools (`actions_list` → `list_workflow_runs` for the branch, then `get_job_logs` with `failed_only`). Fix the failures.
   - Reproduce the failure mentally from the log.
   - Keep each fix minimal, then push.
   - CI takes about 3–5 minutes. Wait with a background `sleep`, not polling.
3. Review the new walkthrough frames on `ci/screenshots` (`walkthrough/*_x*.png`) for layout problems and for results that disagree with the `.truth` values.
4. Integrate the pieces left to the lead:
   - wire `core/demo/*` generators into `DemoData.file(kind)` (new kinds);
   - paste the Help text from the reports into `apps/HelpApp.m`, covering each topic's quick start, demo expectations and troubleshooting;
   - update the launcher (`core/Main.m`) if needed;
   - add CHANGELOG entries.

## 3. WAVE 2 (not started)

1. **Batch processing.**
   - A new `core/Batch.m` plus a `BatchApp` window and a launcher card.
   - It runs a pipeline over a folder or file list with one set of settings: LDF segmentation + features, LFP ERP (+CSD), MUA sorting + rates, ROI analysis, Signal Characterization features.
   - It writes one summary table (CSV/MAT) plus a per-file log, and it continues past per-file errors.
   - Prerequisite: headless core functions. `ERPAnalysis`, `SignalFeatures` and `core/imaging` exist; `MUAPipeline` exists if the MUA agent did it. LDF segmentation still lives inside `ProcessingLDFApp`; extract it to `core/LDFPipeline.m` first, with identical results.
2. **Session files and reports.**
   - `core/Session.m`: settings, input file provenance (path, size, MD5 via Java `MessageDigest`), toolbox version (`UITheme.version`), MATLAB version, date and results, saved as `.nasession.mat`, with load/restore.
   - `core/Report.m`: a one-page PDF per analysis, made by exporting the window with `exportapp` plus a text summary page.
   - Hook both into every window's last step card through small UIKit helpers.
3. **Help and launcher:** add the new windows and features, and the demo expectations for them.
4. **Tidy-ups noticed but not done:**
   - Extract Ephys: the MUA stacked view is crowded (the offset is too small and the legend overlaps).
   - Several apps have their own copies of `setButtonStyle` and `stepCard`. Move them into UIKit (`UIKit.setPrimary`, `UIKit.stepCard`).
   - Update the Node 20 deprecation in the Actions versions (`checkout@v5`, `upload-artifact@v5`) when available.

## 4. Support website (after wave 2, so it documents real capabilities)

- **Location:** `website/` in the repo. It's static HTML/CSS/JS with no build step, so it deploys as-is to Cloudflare Pages (build command: none, output directory: `website`) or to GitHub Pages.
- **Started so far:**
  - `website/assets/site.css`: the design system, IBM Plex fonts, colours matching UITheme, light and dark themes, a walkthrough-player style and a DEMO badge style;
  - `website/assets/frames/`: walkthrough and window screenshots;
  - `website/assets/figures/`: the help figures from `docs/`.
- **Image quality:** the images are the original PNGs, only **losslessly** optimised with optipng. The owner asked for no quality loss, so never use lossy compression (pngquant or similar).
- **Pages to build:**
  - `index` (overview and pipelines)
  - `install`
  - one page per pipeline (`ldf`, `ephys` covering LFP and MUA, `imaging`, `features` covering Signal Characterization and statistics), each with capabilities, a walkthrough player, inputs/outputs, method notes with citations, and demo expectations
  - `guide` (window by window, with troubleshooting)
  - `formats`
  - `batch`
  - `demo-data`: how the data is generated, its parameters and ground truth
  - `validation`: simulated vs measured, and the tests
  - `references`
  - `about`: cite (from `CITATION.cff`), licence ("All rights reserved"), author
  - `404`
  - a `README.md` with deployment instructions
- **Shared script:** one `assets/site.js` renders the header, footer and the "all data shown is synthetic demo data" strip on every page, plus a data-driven walkthrough player (`data-tour="ldf"`).
- **Owner's requirements:**
  - Every data figure is labelled **DEMO DATA — synthetic, generated by `core/DemoData.m`**; the CSS has a `.badge` class for this.
  - Anything taken from public sources must be referenced properly. Use one `references.html`; pages cite with anchors. Cite only references you are certain of. Candidate core references, to verify before use:
    - Nicholson & Freeman 1975, J Neurophysiol 38:356 (CSD)
    - Mitzdorf 1985, Physiol Rev 65:37 (CSD)
    - Kaiser 1990, ICASSP (Teager–Kaiser energy / NEO)
    - Mukhopadhyay & Ray 1998, IEEE TBME 45:180 (NEO spike detection)
    - Quiroga, Nadasdy & Ben-Shaul 2004, Neural Comput 16:1661 (MAD threshold)
    - Rousseeuw 1987, J Comput Appl Math 20:53 (silhouette)
    - Ester et al. 1996, KDD (DBSCAN)
    - Hill, Mehta & Kleinfeld 2011, J Neurosci 31:8699 (sorting quality metrics)
    - Kleinfeld et al. 1998, PNAS 95:15741 (line-scan RBC velocity)
    - Grienberger & Konnerth 2012, Neuron 73:862 (calcium imaging)
    - Bonner & Nossal 1981, Appl Opt 20:2097 (LDF model)
    - Boynton et al. 1996, J Neurosci 16:4207 (gamma response model used in the demo)
    - Okabe & Ito, Color Universal Design (palette)
    - Butterworth 1930
    - Intan RHD2000 data file format documentation
    - Open Ephys binary format documentation
    - Rübel et al. 2022, eLife 11:e78362 (NWB)
  - The figures in `docs/*.png` are schematic illustrations of unknown origin. **Ask the owner** whether they authored them. Until then, credit them as "illustration from the NeuroAnalyzer help figures".
  - The ERP schematic (`docs/LFPAnalysisPrinciple.png`) labels "P2" twice; the first negative peak should be N1. Tell the owner and suggest a fix.
- **Publishing:** the owner hasn't decided yet between an artifact preview, publishing it themselves on Cloudflare Pages, or GitHub Pages. Build the site to work from any static host with relative links only.

## 5. How to work cheaply

- Delegate large edits to background agents using `docs/dev/AGENT_RULES.md`. Give them disjoint file sets, and have them commit their own files and write reports to `docs/dev/reports/`.
- Octave is available after `apt-get install -y octave`, for parse checks and quick numeric checks. Real verification is CI.
- Keep status messages to the owner short, and send screenshots from `ci/screenshots` with SendUserFile.

## 6. Open questions for the owner

1. Where do the `docs/*.png` help figures come from? This affects how the website credits them.
2. Publish the website as an artifact preview first, or hand over the `website/` folder for Cloudflare?
3. Signal Characterization now defaults the baseline to the pre-stimulus period when trials start before t0. Keep that, or restore the old 0–0.05 s default?
4. When the strand is finished: open a PR into `main`, and should `ci/screenshots` stay?
