# GitHabits TODOs

## T1: Claude Code version check in setup.sh
**What:** Check `claude --version` during install and print a clear error if the user's Claude Code version predates the JSON+exit2 hook fix.
**Why:** The hook's core blocking behavior was broken in Claude Code ~v2.1.32 (Opus 4.6 era). Users on older versions get silent failures with no explanation.
**Pros:** Prevents confusing broken installs. Points users to upgrade path.
**Cons:** Requires knowing the exact minimum safe version number (needs research at implementation time).
**Context:** `setup.sh` should check `claude --version`, parse the version, compare against minimum, and exit with a message like: "GitHabits requires Claude Code vX.Y.Z or later. Please upgrade: claude upgrade"
**Depends on:** Confirming the exact minimum Claude Code version with the JSON+exit2 fix.

## T2: Document GITHABITS_ALLOW_MAIN=1 in README
**What:** Add a Configuration section to README documenting the `GITHABITS_ALLOW_MAIN=1` env var override.
**Why:** The override must exist for solo repos and initial commits, but must NOT appear in the hook's block message (Claude can read block messages and self-apply overrides, defeating enforcement). Only humans should know about this escape hatch.
**Pros:** Users on solo projects can opt out cleanly. Two opt-out paths: env var (per-session) and `setup.sh --uninstall` (permanent).
**Cons:** Documented override could be misused by users who want to permanently skip enforcement.
**Context:** README Configuration section: `GITHABITS_ALLOW_MAIN=1 claude "save my work"` for one-time bypasses. `setup.sh --uninstall` to remove permanently.
**Depends on:** README file existing.
