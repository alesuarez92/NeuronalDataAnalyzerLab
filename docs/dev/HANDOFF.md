# Handoff — NeuroAnalyzer improvement strand

> Development notes for the in-progress improvement strand. They are removed before merging to `main`.

Start a new session by reading, in order: `CLAUDE.md`, this file,
`docs/UI_STYLE.md`, `docs/dev/AGENT_RULES.md`, then `docs/dev/reports/*.md`.
Classification of the ongoing work: **EXISTING STRAND**.

- **Branch:** `claude/admiring-cori-52ekpa`. Every commit is pushed there. No PR exists yet, and the owner hasn't asked for one.
- **Repo rule** (from `CLAUDE.md`): no AI or agent attribution in commits, PRs or anything else visible on GitHub.

## 0. First steps for the next session

- **Merging to `main`:** use "Squash and merge", which gives one commit signed by GitHub under the owner's name.
- **`docs/dev/` (decided by the owner, 2026-09-24):** these are development notes, worded neutrally. **Delete `docs/dev/` before merging to `main`.**

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
- **MUA:** sorting over-split channel 4 into 4 clusters. Fixed in wave 1 (auto-merge: 3 units, r = 0.98).

### Preview page

- The private artifact "NeuroAnalyzer Tool Tour" is at https://claude.ai/artifact/8nJqKUUxYBGiXc8ivNeTBZ.
- Its source is not in the repo. The website below replaces it.

## 2. WAVE 1 — landed and integrated (2026-09-24)

Status: all five areas are committed. `DemoData.file` knows the new kinds,
Help and CHANGELOG cover the features, and CI run 38 was 161 passed / 1 failed
(an Intan error-message bug); after the fix, run 39 at `eb57d46` is **green**. The cosmetic items from the review of the walkthrough frames were fixed on
2026-09-24 (units on ephys plots, MUA cluster list / PSTH / status, ROI title,
cell numbering left to right, detection threshold label, LFP band-power status
from 50 ms, Signal Characterization export dropdown and assumptions rows).

### Original wave-1 plan (for reference)

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

## 3. WAVE 2 — in flight (started 2026-09-24)

Two background agents, disjoint files, **not committing** (the lead reviews, integrates and pushes once):
- **Batch:** `core/LDFPipeline.m` (extracted from ProcessingLDFApp, identical results), `core/Batch.m`, `apps/BatchApp.m`, launcher card in `core/Main.m`, BatchApp in AppSmokeTest; tests `LDFPipelineTest`, `BatchFeaturesTest`, `BatchWalkthroughTest`; report `docs/dev/reports/batch.md`.
- **Sessions and reports:** `core/Session.m`, `core/Report.m`, UIKit helpers, hooks in 7 analysis windows (not ProcessingLDFApp: the lead adds it from the report); tests `SessionFeaturesTest`, `SessionWalkthroughTest`; report `docs/dev/reports/session-report.md`.
If this session ends before they finish, check `git status` for their uncommitted files; if the working tree is lost, relaunch both areas with this description.

### Original wave-2 plan

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
  - The figures in `docs/*.png` were **made by the owner** (with AI help). Credit them as the owner's own figures. The owner welcomes **redrawing them to improve them**; keep the same file names so Help and the website pick them up.
  - The ERP schematic (`docs/LFPAnalysisPrinciple.png`) labels "P2" twice; the first negative peak should be N1. Fix it when redrawing.
- **Publishing (decided):** the owner deploys `website/` on **Cloudflare Pages** themselves and will share the link later. Build it to work from any static host with relative links only; once the link exists, use it for Help's "Learn more ↗" links.

### 4b. In-app Help vs website (decision proposed to the owner, 2026-09-24)

Hybrid, with one source of content:

- **In-app Help stays short and task-focused:**
  - quick start per window, demo expectations and troubleshooting;
  - the **▶ Try it with demo data** button, which can only work inside MATLAB;
  - available offline and always matching the installed version.
- **The website gets the long-form content:**
  - methods and theory, references, video-style walkthroughs;
  - large figures, file-format details, FAQ, glossary and search;
  - the heavy base64 images move out of `HelpApp`: pages currently reach about 2.4 MB, which makes Help slow.
- **Links between them:**
  - each Help topic gets a "Learn more ↗" link to the matching website page;
  - each numbered step card in the windows gets a "?" that opens that step's Help section.
- **Single source:** write the text once, for example as `docs/help/<topic>.md` with front-matter for the quick start, demo expectations and troubleshooting. `HelpApp` renders it via uihtml, and the website uses the same files, so they can't drift apart.
- **Content work:**
  - add the wave-1 features: cluster merge/split, raster/PSTH, correlograms, time–frequency, motion correction, multiple ROIs, cell detection, file formats, group statistics, figure export;
  - shorter pages;
  - a glossary with units;
  - a version stamp on every page.
- The owner raised this; confirm the approach with them before building it.

## 5. How to work cheaply

- **CI budget (owner's rule: spend nothing on GitHub).** The repo is public, so Actions on standard runners and MathWorks' MATLAB actions are free, and the account's default spending limit is $0. Still, keep runs low:
  - batch fixes into one push instead of many;
  - leave the workflow's `concurrency` (cancel superseded runs) and `paths-ignore` (docs/website) settings as they are;
  - never add scheduled or cron workflows or larger runners;
  - if the repo is ever made private, CI minutes become metered, so check with the owner first.

- Delegate large edits to background agents using `docs/dev/AGENT_RULES.md`. Give them disjoint file sets, and have them commit their own files and write reports to `docs/dev/reports/`.
- Octave is available after `apt-get install -y octave`, for parse checks and quick numeric checks. Real verification is CI.
- Keep status messages to the owner short, and send screenshots from `ci/screenshots` with SendUserFile.

## 6. Open questions for the owner

Answered on 2026-09-24: the help figures are the owner's (redraw them freely); the owner deploys the website on Cloudflare and will send the link; keep the pre-stimulus baseline default in Signal Characterization.

Also decided:
- Open **one PR into `main` after wave 3** (Help/launcher updates). Before merging, delete `docs/dev/`; the owner uses **Squash and merge**.
- **Delete the `ci/screenshots` branch** once the work is done and tested, and remove the "Publish screenshots branch" step from `.github/workflows/ci.yml` in the same change. The website keeps its own copies of the frames it needs.
- Growth ideas live in `ROADMAP.md` (public, for collaborators), not on the website.

No open questions right now.
