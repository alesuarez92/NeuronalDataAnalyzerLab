# CLAUDE.md — agent contract for NeuroAnalyzer (NMD Lab)

If you're an AI coding agent (Claude Code, Codex, Cursor, Aider) opening this repo, **start here**.

## Read order

1. **This file** — agent contract.
2. **`README.md`** — what this project is.

This project uses the **minimal tier** of the per-project doc system: no `docs/` subtree yet. Session continuity lives in commit messages. Upgrade to standard tier when work needs cross-session tracking.

## Product goal (owner's words, guides every change)

Make processing very easy to understand and accessible for experimental
scientists who are not programmers: they use every tool effectively
without writing code, and they understand what each step does and why.
Every feature, message, Help page and lesson is judged against this:
plain language, no hidden steps, explanations and checks inside the app.

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
- No AI/agent attribution on commits, PRs, or other GitHub-visible artefacts. The owner, Alejandro Suarez, is the sole author of this repository; only add other people who are real collaborators.
- Before the first commit of every session, set the commit identity to the owner (cloud containers default to another identity):
  `git config user.name "Alejandro Suarez" && git config user.email "107207149+alesuarez92@users.noreply.github.com"`
  Never add `Co-Authored-By` or session-link trailers.

## After every checkpoint

- Commit with a clear message describing the change.

## Context budget

A project hook (`.claude/hooks/context-handoff.sh`, wired in `.claude/settings.json`) fires once per session when the conversation reaches **30% of the context window**. When it fires, do these steps in this order, before any other work:

1. Finish the current small step or park it cleanly. Don't leave half-edited files: commit finished work and revert or stash anything unfinished.
2. Update `docs/dev/HANDOFF.md`:
   - what is done;
   - what is in flight, including any background agents and where they report;
   - the next steps;
   - open questions for the owner.
3. Commit and push the handoff. No AI attribution.
4. Post the ready-to-paste prompt for the next session in chat, so the owner has it even if step 5 fails:
   > Continue the NeuroAnalyzer work on branch `<branch>`. Read `CLAUDE.md` and `docs/dev/HANDOFF.md` first and follow them. Next: <first task>. Keep CI runs to a minimum.
5. Only then create the new session on the same repo and branch with that same prompt (`mcp__Claude_Code_Remote__create_session`). Tell the owner it's ready and that this session can be left.

Don't start new work in the old session after the handoff.
