# `system-template.md` — bootstrap a project's doc system

You are an AI coding agent (Claude Code, Codex, Cursor, Aider — any) that opened a repository containing this file. Read it end-to-end **before** taking any action. This file is the only manual artifact a human had to drop here; everything from here is on you.

Your job: bootstrap this project to follow the per-project doc system, then silently register it with the brain if a brain installation is present. The project stays the agent's frame of reference — the brain is enhancement, never a dependency.

**There is also a CLI option** — if the brain is installed, the human (or you) can run `engram register <repo-path> --bootstrap <tier> --apply` to do this programmatically. The CLI does Steps 0-11 below for you. This file is the manual / educational version for cases where the CLI isn't available or you want to understand what's being created.

---

## Step 0 — Classify + pick a tier

Announce the classification:

```text
[Bootstrap]
Project state:   <greenfield | has-code-no-docs | has-some-docs | already-bootstrapped>
Stack signals:   <comma-list of what you detected — *.sln, package.json, pyproject.toml, etc.>
Brain present:   <yes / no — check for ~/Documents/code/Engram/projects/registry.yaml>
Tier proposed:   <minimal | standard | full>
```

**If `already-bootstrapped`** (this repo already has `CLAUDE.md` + `docs/INDEX.md` + `docs/sessions/HANDOFF.md`): your job is verification + delta, not re-bootstrap. Run Step 11 (brain registration if absent) and stop.

### Three tiers — pick the right one for the project

| Tier | What it ships | Fits |
|---|---|---|
| **Minimal** | `CLAUDE.md` + `AGENTS.md` + `.brain/` folder. **No `docs/`**. | Personal projects, single-author tools, MATLAB toolboxes, Vite landings, small static sites. The 80% case where a full doc-system is overkill. |
| **Standard** | Minimal + `docs/INDEX.md` + `docs/sessions/HANDOFF.md` + `docs/sessions/log.md`. No subtree pre-creation. | Small-to-medium projects with active iteration. The default for any team-or-future-team project. |
| **Full** | Standard + per-subtree skeleton (`docs/database/`, `docs/deployment/`, etc.) + CI workflows (docs-discipline gate). | Production multi-tenant SaaS with many strands of work running in parallel. Heavy ceremony — only earn it when complexity demands it. |

**Default to the lightest tier that the project's complexity actually demands.** A small project does NOT need 11 subtrees and a CI gate; it needs an agent contract and a place to capture context. The full tier is for projects where the friction of the doc system pays for itself in cross-session continuity.

If the project is greenfield or you're unsure: pick **standard**. Upgrade to full later if subtrees actually accumulate. Cannot downgrade easily — start light.

---

## Step 1 — Read the repo

Before writing anything, take stock:

- Detect the stack by file presence (`.sln` / `.csproj` → .NET; `package.json` → JS/TS; `pyproject.toml` or `requirements.txt` → Python; `*.m` → MATLAB; etc.).
- Read the existing `README.md` if present (the project's purpose).
- Check `git remote get-url origin` and parse the owner + repo name.
- Scan for any pre-existing docs (`docs/`, `README*`, `*.md` at root) so you don't clobber them.

---

## Step 2 (ALL TIERS) — Write `CLAUDE.md` (the project's agent contract)

The project's `CLAUDE.md` describes how an agent should work in *this* repo. **Tone is project-local, not umbrella-aware.** Do not mention the brain, the umbrella org, or other projects by name in this file.

Required sections:

1. **Read order** for any session:
   - **Standard / Full tiers**: `docs/INDEX.md` → `docs/sessions/HANDOFF.md` → relevant subtree `README.md` → topic doc.
   - **Minimal tier**: there is no `docs/` yet — `CLAUDE.md` itself is the agent contract; read the README + any in-repo notes; record context in `.brain/<session>.md` as you work.
2. **Classification ritual** — before any meaningful work, emit one of: `NEW STRAND`, `EXISTING STRAND`, `HOTFIX`, `MINOR / EVERYDAY`, `ASK USER`.
3. **Work discipline**: tests + CI on every change, no "trivial" exemption. Build clean (0 errors; warnings acceptable if pre-existing). Watch CI to clean before merge. Use your own CLI tools (`gh`, `az`, `git`, language toolchains) — don't ask the human what you can run yourself.
4. **Log discipline** — at every meaningful checkpoint AND before stopping:
   - **Standard / Full**: `log.md` entry in the relevant subtree (`YYYY-MM-DD — change — PR/file link`). Update topic docs in the same PR if they became inaccurate. Update `docs/sessions/HANDOFF.md` if open threads changed.
   - **Minimal**: append to `.brain/log.md` if useful for session continuity. No formal subtree log.
5. **7-day cleanup pass** (Standard / Full only) at session start: if `docs/sessions/log.md` shows no `log consolidation` entry in the last 7 days, run it before other work.
6. **Boundaries**: no umbrella-aware references in tracked files outside `.brain/`. No AI/agent attribution on commits, PRs, or other GitHub-visible artefacts.

Keep `CLAUDE.md` under 200 lines. Reference the doc-system pattern by behavior, not by name.

---

## Step 3 (ALL TIERS) — Write `AGENTS.md`

A one-line file:

```markdown
# AGENTS.md

This project uses the per-project doc system. The agent contract is in [`CLAUDE.md`](./CLAUDE.md) — read that first.
```

For tools that look for `AGENTS.md` instead of `CLAUDE.md` (Codex, some Cursor configurations).

---

## Step 4 (ALL TIERS) — Create `.brain/` folder

`.brain/` is the per-project contained-surface for brain-aware content (Decision 6 of the brain's architecture). It's tracked normally; nothing brain-related goes outside this folder.

Add `.brain/README.md` explaining what lives here (session notes, surfaced-memory dumps, anything that names the brain or sibling projects).

---

## Step 5 (STANDARD + FULL TIERS only) — Write `docs/INDEX.md`

```markdown
# Documentation index — <Project Name>

**Read this first.** Then `docs/sessions/HANDOFF.md`. Then the relevant subtree `README.md`. Then the topic doc.

## Subtrees

| Subtree | What lives here | Index |
|---------|-----------------|-------|
| `sessions/` | Session handoffs. `HANDOFF.md` is the single canonical living doc. | [HANDOFF](sessions/HANDOFF.md) |

Subtrees added later as work begins on their topic. Each subtree has `README.md` + `log.md`.

## Agent contract

See [`CLAUDE.md`](../CLAUDE.md) at the repo root.
```

---

## Step 6 (STANDARD + FULL TIERS only) — Write `docs/sessions/HANDOFF.md` + `log.md`

`HANDOFF.md` is a living doc — every session updates it before stopping.

```markdown
# Session Handoff — <Project Name>

> **Living document.** Every session updates this on every meaningful checkpoint and especially before stopping. The next session reads `docs/INDEX.md` first, then this file.

## In-flight (claim before starting; clear when done or paused)

| Branch | Thread / classification | Owner | Started | ETA / status |
|--------|-------------------------|-------|---------|--------------|
| _none_ | _no in-flight work claimed_ | — | — | — |

## Current state

| Field | Value |
|-------|-------|
| Last updated | <today YYYY-MM-DD> |
| Stack | <auto-detected stack summary> |
| Build status | <unknown until first build run> |
| Open threads | 0 |

## Open threads (next session picks up)

_(none — fresh bootstrap)_
```

`docs/sessions/log.md`:

```markdown
# Session log

Append-only chronological log of session work. One line per session checkpoint. Also tracks the 7-day cleanup pass.

- <today YYYY-MM-DD> — project bootstrap. Doc system in place. Next due `log consolidation`: <today + 7 days>.
```

---

## Step 7 (FULL TIER only) — Subtree decision

Look at what the project already has. For each meaningful concern that's *active right now*:

- Deploy scripts / IaC / `deploy/` folder → create `docs/deployment/`.
- Integrations (Stripe, OAuth, third-party APIs) → create `docs/integrations/`.
- Database / migrations → create `docs/database/`.
- Observability config (Serilog, OpenTelemetry, App Insights) → create `docs/observability/`.
- Security review / threat model → create `docs/security/`.
- Onboarding flows → create `docs/onboarding/`.

**Don't pre-create empty subtrees.** Wait until the first topic warrants one. A fresh project can ship with just `sessions/`; everything else accumulates organically.

For each subtree you DO create, write `README.md` + `log.md`.

---

## Step 8 (FULL TIER only) — `.gitignore` convention

Optional. If the project doesn't already have one, add a section that gitignores `docs/` by default and explicitly un-ignores tracked subtrees:

```gitignore
# Per-project doc system: tracked subtrees only.
docs/*
!docs/INDEX.md
!docs/sessions/
!docs/<each-tracked-subtree>/
```

Forces explicit `git add` + un-ignore when creating a new subtree — the right friction for ceremony-heavy projects.

Skip this step for minimal / standard tiers.

---

## Step 9 (ALL TIERS) — First commit

One commit titled `chore(docs): bootstrap per-project doc system`. Do not mention the brain, the umbrella, or any external system in the commit message or body. The project looks like it independently chose this doc system.

Body (adjust for the tier you applied):

```text
Adds CLAUDE.md (agent contract) + AGENTS.md + .brain/ (contained-surface folder for any future agent-helper content).

[Standard tier additions:] + docs/INDEX.md + docs/sessions/{HANDOFF,log}.md.

[Full tier additions:] + per-subtree skeleton + .gitignore docs convention.

Subtrees populate organically per the agent contract.
```

---

## Step 10 (ALL TIERS) — Verify

Re-read these from scratch:

1. `CLAUDE.md` — does it stand alone? Could a fresh session work in this repo without reading anything else first? It must.
2. `AGENTS.md` — points at `CLAUDE.md`.
3. **Standard / Full**: `docs/INDEX.md` — read order clear? Subtrees listed?
4. **Standard / Full**: `docs/sessions/HANDOFF.md` — today's date as `Last updated`?

If any answer is "no," fix it before stopping.

---

## Step 11 — Brain registration (CONDITIONAL — silent + brain-side-only)

Check for a brain installation:

```bash
test -e ~/Documents/code/Engram/projects/registry.yaml
```

**If absent**: stop here. The project works standalone; the brain is an enhancement, not a dependency. Do not mention anything brain-related to the user.

**If present**: register this project with the brain. **All writes go to `~/Documents/code/Engram/` only — never to this project's repo** beyond what Steps 2-9 already wrote (those are project-local doc system, brain-naive).

```bash
engram register <absolute-path-to-this-project> --apply
```

Dry-run by default. If the brain's CLI isn't installed, fall back to hand-editing `~/Documents/code/Engram/projects/registry.yaml` (append the entry) and creating `~/Documents/code/Engram/memory/projects/<slug>.md`.

Commit on the **brain side** (cwd = `~/Documents/code/Engram/`). The project's commit history shows only the doc-system bootstrap.

---

## What this template does NOT do

- It does **NOT** write any reference to the brain, the umbrella org, or any sibling project into this repo's tracked files outside `.brain/`. The project's `CLAUDE.md` describes the doc system as a project-local choice.
- It does **NOT** install any tooling.
- It does **NOT** require user interaction beyond placing this file in the repo (or running the CLI). The agent reads it, executes, asks the user only when classification or tier is ambiguous.
- It does **NOT** clobber existing docs. If the project already has `CLAUDE.md`, etc., merge thoughtfully — preserve project-specific content, add only what's missing.

---

## Reference (for the agent)

- The brain repo, if present: `~/Documents/code/Engram/`
- The brain's own agent contract: `~/Documents/code/Engram/CLAUDE.md`
- The per-project doc-system pattern this template implements: `~/Documents/code/Engram/memory/patterns/universal/doc-system-contract.md`
- The confidentiality decision that gates Step 11's "brain-side-only" rule: `~/Documents/code/Engram/docs/architecture/decisions.md` (Decision 6)
- The workflow for the brain to push approved fixes back into project repos later: `~/Documents/code/Engram/memory/preferences/brain-may-push-approved-fixes-into-projects.md`

If you're working without the brain installed, none of the above is reachable — and that's fine. The template stands alone.
