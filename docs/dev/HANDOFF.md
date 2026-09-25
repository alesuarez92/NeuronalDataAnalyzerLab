# Handoff (2026-09-25)

Working branch: `claude/admiring-cori-52ekpa`. Owner decision: `docs/dev/` stays out of `main`.
**Delete this file from the branch before merging any PR.**

## Done (on main)
- v0.3.0 released earlier. Since then merged:
  - #4 screenshots refresh; `.github/workflows/screenshots.yml` (manual "Update screenshots": runs tests in MATLAB CI, commits frames to a branch, optional `review-screens/` for review, which must be removed before the PR).
  - #5 Virtual lab (LDF, `core/VirtualLab.m`, `apps/VirtualLabApp.m`), Methods text (`core/MethodsWriter.m`), Average LDF results line, and validation fixes: LDF trigger downsampling keeps short pulses; one onset rule (last kept onset) for LDF/ERP/MUA; "Speed (flow)" removed (same as Movement; old sessions map to Movement); MUA QC results stored; unit-free drift merge distances and unclustered-bin spikes kept as noise; MUA Random seed. "NMD Lab" removed everywhere. Product goal in CLAUDE.md.
  - #6 screenshots after #5.
- CHANGELOG `[Unreleased]` lists all of the above (not yet released as 0.4.0).

## In flight
- **PR #7** (this branch): website Virtual lab page (`website/lab.html`, walkthrough `TOURS.lab` in `site.js`, frames `VirtualLabApp_01..10`), guide section, methods text on sessions page, remaining "Speed" wording removed from Help/website. MATLAB CI was started at ~12:53 UTC. Owner has NOT yet said go for #7: when green, ask the owner, then squash-merge (after deleting this file from the branch).
- Cloudflare "Workers Builds" preview check fails on every PR (not caused by the PRs; log only in the owner's Cloudflare dashboard). Production deploys from main work.

## Next steps (owner to confirm with "go")
1. Histology / culture window: load single/multichannel TIFF; coregister channels / sections / time points (rigid via existing phase correlation `registerStackRigid`, affine via landmark points); cell counting (background subtraction, threshold, watershed split, size/shape filter), counts per ROI and per mm², co-localisation across channels; demo images with known counts (`core/demo/`), tests, Help, website; later a virtual-lab exercise.
2. Techniques explainers (website section + Help "Learn" text): LDF, laminar electrophysiology (LFP/MUA/CSD), two-photon / calcium imaging, histology and culture imaging: what is measured, typical rig and settings, pitfalls, which windows to use.
3. Remaining validation work: cross-checks against MATLAB built-ins (statistics, pwelch), MUA ground-truth per-unit precision/recall, CSD / ERSP reference comparisons (see the owner's private audit), plain-language quality-checks panel.
4. Next virtual experiments: laminar ERP/CSD, then spike sorting.
5. Release 0.4.0 when the owner asks (bump `core/UITheme.m`, CITATION.cff, website VERSION/index/about, CHANGELOG section; run release.yml on main).

## Working rules learned
- Keep CI minutes low: open the PR and cancel the duplicate `push` run on the branch (the `pull_request` run is the one that counts); docs/website-only diffs skip CI.
- Commit identity: owner (see CLAUDE.md); no AI trailers.
- Validate non-UI MATLAB code in Octave before pushing (a RandStream shim is needed for Octave).
- Ask the owner before merging or starting a new feature; act on "go".

## Open questions for the owner
- Go for Histology/culture window and/or Techniques explainers (order)?
- NeuroVascularSim shows as public in the repo list; the owner created it as private. Intended?
- Cloudflare preview build log (to fix the failing preview check).
