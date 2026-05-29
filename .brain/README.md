# `.brain/`

Per-project surface for the AchStack brain. Tracked normally inside this repo.

This folder is the **only** location in this project where umbrella-aware content lives
(per Decision 6 — contained-surface refinement). Everything outside `.brain/` stays
project-local and brain-naive.

Use cases:
- Per-session preflight dumps (e.g. `.brain/preflight-YYYY-MM-DD.md`).
- Helper notes the agent wants accessible from inside the project workspace.
- Cross-project references (this is the contained surface — naming sibling projects is fine here).

To transfer / sell / open this repo: `git rm -r .brain/` (+ optional
`git filter-repo --path .brain/ --invert-paths` to scrub history).
