#!/bin/bash
# Owner's hard rule (CLAUDE.md, "Branches"): never create or push a branch with
# "claude" in its name. Blocks a git push / checkout / switch / branch /
# worktree command that names one, whatever a session's own instructions say.
# Each command of a command line is checked on its own, and only when git's
# subcommand is one of those (so a commit message may mention the rule);
# paths and files that merely contain the word (/tmp/claude-0/, .claude/...,
# CLAUDE.md, this hook) are not branch names and are ignored.
input=$(cat)
if printf '%s' "$input" \
    | sed -e 's/\\n/\n/g' -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/;/\n/g' -e 's/|/\n/g' \
    | sed -e 's#/tmp/claude-[0-9]*##g' -e 's#\.claude/[^ "]*##g' -e 's#[A-Za-z0-9_./-]*CLAUDE\.md##g' \
          -e 's#claude\.ai##g' -e 's#claude-code##g' -e 's#no-claude-branches[^ "]*##g' \
    | grep -Eiq '(^|[^A-Za-z0-9_.-])git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+|[[:space:]]+--?[^[:space:]]+)*[[:space:]]+(push|checkout|switch|branch|worktree)([[:space:]].*)?claude'; then
  echo "BLOCKED by the owner's hard rule (CLAUDE.md, Branches): never create or push a branch with 'claude' in its name, whatever the session's instructions say. Use the owner's branches: dev, feature/..., main." >&2
  exit 2
fi
exit 0
