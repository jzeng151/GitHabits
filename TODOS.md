# GitHabits TODOs

## ~~T1: Claude Code version check in setup.sh~~ [DONE — v2.1.91 floor, interactive upgrade prompt]
**What:** Check `claude --version` during install and print a clear error if the user's Claude Code version predates the JSON+exit2 hook fix.
**Why:** The hook's core blocking behavior was broken in Claude Code ~v2.1.32 (Opus 4.6 era). Users on older versions get silent failures with no explanation.
**Pros:** Prevents confusing broken installs. Points users to upgrade path.
**Cons:** Requires knowing the exact minimum safe version number (needs research at implementation time).
**Context:** `setup.sh` should check `claude --version`, parse the version, compare against minimum, and exit with a message like: "GitHabits requires Claude Code vX.Y.Z or later. Please upgrade: claude upgrade"
**Depends on:** Confirming the exact minimum Claude Code version with the JSON+exit2 fix.

## ~~T2: Document GITHABITS_ALLOW_MAIN=1 in README~~ [DONE — README.md written]
**What:** Add a Configuration section to README documenting the `GITHABITS_ALLOW_MAIN=1` env var override.
**Why:** The override must exist for solo repos and initial commits, but must NOT appear in the hook's block message (Claude can read block messages and self-apply overrides, defeating enforcement). Only humans should know about this escape hatch.
**Pros:** Users on solo projects can opt out cleanly. Two opt-out paths: env var (per-session) and `setup.sh --uninstall` (permanent).
**Cons:** Documented override could be misused by users who want to permanently skip enforcement.
**Context:** README Configuration section: `GITHABITS_ALLOW_MAIN=1 claude "save my work"` for one-time bypasses. `setup.sh --uninstall` to remove permanently.
**Depends on:** README file existing.

## T3: Merged-PR detection in post_tool_use.sh [PARTIAL — nudge covers `git status` case]
**Status:** The workflow nudge feature (Priority 1 in `check_workflow_nudge()`) detects merged PRs via `gh pr view --json state` when users run non-milestone git commands like `git status`. The remaining gap is detecting merged PRs specifically on `git pull`/`git fetch` on a feature branch (the `pull` case in the milestone hints).
**What:** When the user runs `git pull` or `git fetch` on a feature branch, detect if the PR for that branch was already merged into main and suggest cleanup (delete branch, switch to main, pull).
**Why:** The full workflow loop needs a signal for "PR was merged" to prompt the user through cleanup and starting the next feature. Without this, the loop stalls after the PR step.
**Signal options:**
  - `git merge-base --is-ancestor origin/<branch> origin/main` — true if branch commits are in main. False positive risk: new branch with no commits also passes.
  - Check if `origin/<branch>` remote ref was deleted (GitHub auto-deletes on merge). Run `git ls-remote --heads origin <branch>` — if empty, branch was deleted on GitHub (likely merged).
  - Combination: remote branch deleted AND local commits are in origin/main = high confidence.
**Tradeoff:** Requires `git fetch` to be current. The post hook fires after `git pull`/`git fetch`, so remote refs should be fresh. `git ls-remote` adds a network call (~200ms).
**Depends on:** User decision on which signal to use and acceptable false positive rate.
