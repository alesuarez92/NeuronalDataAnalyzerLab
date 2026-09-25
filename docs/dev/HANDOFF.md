# Handoff (2026-09-25, session 3, end)

Working branch: `claude/admiring-cori-52ekpa`. Owner decision: `docs/dev/` stays out of `main`.
**Delete this file from the branch before merging any PR.**

## Done
- PR #7 (website Virtual lab page) merged into `main` as `21ee836` (owner said go).
- Branch restarted from `main` for the next strand. The remote still had the two
  pre-squash commits of #7; a force push was blocked, so the old tip was **merged**
  into the branch (no content change) and pushed normally.
- Owner said **go** for both: Histology / culture window first, then the Techniques pages.

## In flight: Histology / culture window (NEW STRAND, PR open)
Done on the branch (session 3):
- `core/Histology.m`, `core/demo/demoHistology.m`, `apps/HistologyApp.m` (session 2).
- Wired in: launcher Imaging card (second button, "or" between), Help topic `Histology`
  (quick start, demo answers, how it works, troubleshooting; demoWindow, websitePage),
  `MethodsWriter.histology` (+ Otsu 1979 reference, PipelineOrder), `DemoData` kind
  `histology` (demo_histology.mat, writeAll), CHANGELOG, README, ROADMAP, website
  (imaging page section, guide section, demo-data row, reference 24 Otsu).
- Demo: positives now chosen per half, so the per-region answers hold by construction:
  day 1 12 + 12, day 3 18 + 21 (A + B). Checks text names directions ("9.2 px right and
  6.4 px up").
- Tests: `tests/HistologyWalkthroughTest.m` (frames `HistologyApp_01..08_*.png`),
  AppSmokeTest.testHistology, MethodsWriterTest.testHistology, DemoDataTest histology,
  HistologyTest locks the per-region answers. Verified in Octave: HistologyTest 15/15;
  the app pipeline replayed headless gives every Help number exactly (default settings).
  The window itself has still never run in MATLAB: CI is its first real test.

## State at handoff
- PR #8 (https://github.com/alesuarez92/NeuronalDataAnalyzerLab/pull/8) is open. MATLAB CI
  on head 248de7c is **green** (run 36150789957): HistologyApp, the walkthrough and the
  smoke test all passed on the first MATLAB run. Only "Workers Builds" (Cloudflare) is red.
- Owner's latest request (verbatim): "Push and publish everything and fix the problem of
  the bot". Read as: fix the Cloudflare preview check, then merge PR #8 and get the
  website deployed. Treat it as the owner's go for merging #8, once the handoff file has
  been removed and CI is green.

## Cloudflare "Workers Builds" investigation (in progress)
- `wrangler.jsonc` (repo root): name neuronalanalyzerlab, assets ./website, 404-page.
- `npx wrangler@4.140.0 deploy --dry-run` from the repo root **succeeds locally** (133
  files read from website/). So the config and the files are valid; the failure is in
  the Cloudflare project's build settings or credentials, which are only visible in the
  dashboard (build b6e1b8d8-029c-40b7-a850-142fe4d9afc7).
- Likely causes to check with the owner (they need to open "View logs" in the bot
  comment, or paste the log): the build/deploy command in Workers Builds settings (for
  preview branches Cloudflare runs `npx wrangler versions upload`); the root directory
  setting; a Worker name in the dashboard that differs from "neuronalanalyzerlab"; an
  expired / missing API token for the build; a build command (e.g. `npm run build`) with
  no package.json in the repo.
- Possible repo-side fix to try if the log shows "Missing entry-point" or a missing
  package.json: add a minimal `package.json` (no dependencies) or set the build command
  to empty. Do not guess further without the log.

## Next steps (in order)
1. Get the Workers Builds log (ask the owner to paste it or open "View logs"); fix the
   repo side if it is ours, otherwise give the owner the exact dashboard setting.
2. Merge PR #8: delete `docs/dev/HANDOFF.md` from the branch in a commit (keep a copy of
   its contents in the chat / the next session's prompt), push, wait for CI green, then
   squash-merge. Cancel the duplicate push run.
3. After merge: branch from main again; run *Update screenshots* with include_all, copy
   the `HistologyApp_*` frames into `website/assets/frames/`, add an imaging tour in
   `website/assets/site.js` and a figure in the guide's Histology section.
4. Techniques explainers (website section + Help "Learn" text): LDF, laminar ephys
   (LFP/MUA/CSD), two-photon / calcium, histology and culture imaging.
5. Later: a virtual-lab histology exercise; remaining validation work; release 0.4.0 on request.

## Working rules learned
- Keep CI minutes low: open the PR and cancel the duplicate `push` run.
- Commit identity: owner (see CLAUDE.md); no AI trailers.
- Validate non-UI code in Octave: `apt-get install -y octave` (8.4); RandStream shim and
  a small functiontests runner are easy to recreate (Octave lacks `unique(...,'stable')`
  third output and RandStream).
- Ask the owner before merging or starting a new feature; act on "go".
- The owner once sent questions meant for another chat (vessel pressure / O2 / BOLD) and
  said to disregard them: not a task here.

## Open questions for the owner
- NeuroVascularSim shows as public in the repo list; the owner created it as private. Intended?
- Cloudflare preview build log (to fix the failing "Workers Builds" check on every PR).
