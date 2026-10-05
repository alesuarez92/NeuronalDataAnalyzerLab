# Contributing to Neuronal Data Analyzer Lab

Thanks for your interest. This is a research toolbox
(currently v1.0.0) and contributions that flow back to the canonical
repo are welcome.

## How to use it

Please install the project from a release ZIP (see the
[README](README.md#install)) rather than maintaining a long-running fork.
Neuronal Data Analyzer Lab is free for noncommercial use under the PolyForm
Noncommercial License 1.0.0 with a citation condition
([LICENSE.txt](LICENSE.txt)): you may change it and share it for
noncommercial purposes. Still, if you need a change,
the most useful path for everyone is to file an issue or open a PR back
here, so the fix reaches every user.

## Reporting bugs

Open an [issue](https://github.com/alesuarez92/NeuronalDataAnalyzerLab/issues)
with:

- The version (shown in every app's footer next to the copyright, or check
  `core/UITheme.version`).
- MATLAB version (`ver`).
- A minimal example that reproduces the problem (which app, which inputs,
  what you expected, what you got).
- Any error text from the MATLAB Command Window.

## Suggesting features

Open an issue with the use case before sending code. A short description
of the experimental workflow and the analysis you wish the tool did is
the most useful starting point — it lets us pick a design that fits the
rest of the toolbox instead of bolting on a one-off function.

## Submitting a pull request

1. Fork to develop your change, then open a PR back here.
2. Branch from `main`. Use a short descriptive name
   (`fix/extract-ldf-crash`, `feature/spike-clustering-export`).
3. Match the existing code style: classdef-per-app, `core/` for shared
   utilities, UI through `UITheme`. Don't introduce a different layout
   pattern in a single window.
4. Add or update tests under `tests/` when the change is testable
   (validation, processing, signal features). Run `run_tests` locally.
5. Update [CHANGELOG.md](CHANGELOG.md) under the `[Unreleased]` section
   (Added / Changed / Fixed).
6. Open the PR against `main`. Keep the PR scoped — one logical change
   per PR makes review tractable.

## Contribution licensing and attribution

By submitting a contribution to this repository (issue, pull request, patch,
or otherwise), you grant the project maintainer (Alejandro Suarez, Ph.D.) a
perpetual, worldwide, royalty-free, non-exclusive license to use, modify,
sublicense, and distribute your contribution, and you license it to everyone
under this project's licence, the PolyForm Noncommercial License 1.0.0
with its citation condition ([LICENSE.txt](LICENSE.txt)). You confirm that
you have the right to submit the contribution (you wrote it, or its licence
allows this). You retain copyright on your changes;
incorporating them into the project does not transfer ownership.

In-file attribution — i.e. who is named in `LICENSE`, `README`, `CITATION.cff`,
package metadata, and similar surfaces — remains at the maintainer's
discretion. The maintainer may, but is not obligated to, add a contributor's
name to those files. Standard `git log` author records on merged commits are
not affected by this rule and are the canonical record of who wrote what.

## Versioning and releases

The project follows [SemVer](https://semver.org/) (MAJOR.MINOR.PATCH).
The version constant lives in `core/UITheme.version` and is the single
source of truth — every app's footer reads from it.

- `PATCH` — bug fixes, no behavior change for existing data.
- `MINOR` — new analysis, new app, or new option that's backwards
  compatible.
- `MAJOR` — incompatible change to the data formats consumed/produced
  by an app, or removal of a public-facing feature.

Releases are git tags (`v0.4.0`, ...) with a corresponding entry in
[CHANGELOG.md](CHANGELOG.md). Release checklist:

1. Set the new version in `core/UITheme.m` and `CITATION.cff` (with the
   release date), the README badge, install link and *How to cite*.
2. Move the CHANGELOG's Unreleased entries under the new version.
3. Update Help for anything new: text, expected demo
   results, and screenshots from the CI artifact `window-screenshots`
   (optimised losslessly only).
4. Run **Actions → Release → Run workflow** on `main` (or push the tag).
   It refuses to publish if CITATION.cff shows another version.

## Questions

For anything that's not a bug or a concrete proposal, open a
[discussion](https://github.com/alesuarez92/NeuronalDataAnalyzerLab/discussions)
or email the author (see the GitHub profile linked in the README).
