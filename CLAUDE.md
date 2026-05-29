# CLAUDE.md — agent contract for NeuroAnalyzer (NMD Lab)

If you're an AI coding agent (Claude Code, Codex, Cursor, Aider) opening this repo, **start here**.

## Read order

1. **This file** — agent contract.
2. **`README.md`** — what this project is.
3. **`.brain/`** (if present) — any cross-session notes / helper artifacts.

This project uses the **minimal tier** of the per-project doc system: no `docs/` subtree yet. Session continuity lives in commit messages + `.brain/` notes. Upgrade to standard tier when work needs cross-session tracking.

## Classification ritual

Before any meaningful work, announce one of:

- `NEW STRAND`: multi-PR / multi-session effort.
- `EXISTING STRAND`: continuation of in-flight work.
- `HOTFIX`: urgent, single-PR.
- `MINOR / EVERYDAY`: small change.
- `ASK USER`: classification ambiguous.

## Work discipline

- Tests + CI green on every change. No "trivial" exemption.
- Build clean (0 errors; warnings acceptable if pre-existing).
- Use your own CLI tools (`gh`, `git`, language toolchains). Don't ask the human what you can run yourself.
- No AI/agent attribution on commits, PRs, or other GitHub-visible artefacts.

## Boundaries

- No umbrella-aware references in tracked files outside `.brain/`.
- If `.brain/` doesn't exist yet and you need a contained surface for session notes, create it.

## After every checkpoint

- Commit with a clear message describing the change.
- If session-continuity context would help next session, append to `.brain/log.md`.
