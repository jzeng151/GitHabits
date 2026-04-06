# GitHabits — Design Document

**Status:** APPROVED
**Created:** 2026-04-06
**Branch:** main

---

## Problem Statement

New developers using Claude Code are completely unfamiliar with git workflows. They don't know what branching is, why it matters, or when to commit. Critically: they will never call git themselves — Claude is their entire interface for git operations.

Every existing branch-protection tool was built by experienced developers for experienced developers. They block the action and stop there. No tool currently enforces git best practices AND teaches why those practices matter at the exact moment of violation.

**The insight:** This is a tutor, not a guardrail.

---

## Core Design Principle: Tutor-Voice, Not Error-Voice

Every intervention must read like a mentor explaining, not a linter blocking.

**BAD:**
```
BLOCKED: cannot commit to main branch.
```

**GOOD:**
```
Learning moment: you're about to commit directly to main.

Senior engineers never do this — here's why: 'main' is the branch
your teammates (and future-you) rely on being stable. One accidental
commit can break everyone's work.

What to do instead:
  git checkout -b feature/your-feature-name
  git add .
  git commit -m "describe what you changed"
  git push origin feature/your-feature-name

I've paused the command. Want me to create that branch for you?
```

This principle applies to every hook message, every CLAUDE.md instruction, every response augmentation.

---

## Target User

A new developer using Claude Code who:
- Has zero git knowledge — doesn't know what branching is or why it matters
- Will never type a git command themselves — Claude is their entire interface
- Trusts Claude completely and is handing it their keyboard

This shapes everything. The tool is not a guardrail for experienced developers who already know the rules. It is a tutor for beginners who are learning through Claude.

---

## What Makes This Cool

The target user already trusts Claude completely. GitHabits turns Claude's authority and trust relationship into a teaching moment. Instead of a cryptic error, they get: "here's what a senior engineer does and why, and here's the exact command to do it right."

**The bigger vision: a board developer's assistant.** GitHabits eventually helps the user create a feature roadmap at the start of a project. Claude uses that roadmap to track progress — and when it detects the user has finished a feature, it prompts: "Looks like you finished 'user login' — want me to commit, push, and create a PR?"

---

## Approach: PreToolUse Hook Guardian + CLAUDE.md Pedagogy

Three alternatives were evaluated:

| Approach | Summary | Completeness | Chosen |
|----------|---------|-------------|--------|
| A: Pure CLAUDE.md | Instructions only, no hooks | 5/10 | No — no hard enforcement |
| **B: Hook + CLAUDE.md** | PreToolUse hook (hard block) + CLAUDE.md (explanation) | **9/10** | **Yes** |
| C: Git Hooks + Claude Hooks | Belt and suspenders | 7/10 | No — target users never call git directly |

Approach B is chosen because:
- Hard enforcement via hooks is absolute — Claude cannot override it
- CLAUDE.md handles the explanation layer (best-effort, but sufficient for MVP)
- The architecture maps cleanly to a standalone CLI later
- Ships in days, not weeks

---

## Message Template

The block message uses dual output:

1. **stderr** — displayed directly in Claude Code's chat UI as a hook notification (human sees it immediately)
2. **stdout JSON** — `{"decision": "block", "reason": "..."}` — Claude reads the `reason` field and elaborates in its response

This gives two teaching moments: the hook notification and Claude's response.

```
Learning moment: you're about to commit directly to main.

Senior engineers never do this — here's why: 'main' is the branch
your teammates (and future-you) rely on being stable. One accidental
commit can break everyone's work.

What to do instead:
  git checkout -b feature/your-feature-name
  git add .
  git commit -m "describe what you changed"
  git push origin feature/your-feature-name

I've paused the command. Want me to create that branch for you?
```

---

## CLAUDE.md Rules

Three rules injected into global CLAUDE.md, delimited by `# GitHabits START` / `# GitHabits END`:

1. Before running any git command, explain each part in plain English before executing it.
2. Before committing, check the current branch. If main — ask the user to name a feature branch first. *(Soft pre-check. Hard block happens in the hook.)*
3. After every successful push, give a one-sentence summary of what the git history looks like now.

**Limitation:** CLAUDE.md instructions can be deprioritized in long contexts. The explanation layer (rules 1 and 3) is best-effort. The enforcement layer (rule 2 + the hook) is hard. Known and acceptable tradeoff for MVP.

---

## Distribution

**MVP:** GitHub repo + `curl | bash` setup script. Pure shell, no binary, no Node runtime.

**Post-MVP:** `npx githabits init` / Homebrew for discoverability. GitHub Actions CI.

**Distribution gap (V2):** The target user (new developer with zero git knowledge) doesn't know to run `setup.sh`. V2 needs an onboarding mechanism — a template that experienced developers share with learners, or integration with Claude Code's extension ecosystem.

---

## Constraints

- Target users have zero git knowledge. Assume nothing.
- Claude is the only interface to git these users will use.
- MVP must be installable with a single command.
- Architecture must allow future extraction to a standalone CLI.
- No bun, no Node runtime required for MVP. Pure shell + CLAUDE.md.
- Requires Claude Code with the JSON+exit2 hook fix (April 2026+).

---

## Key Design Decisions

**1. JSON+exit2 dual output (not exit2 alone)**
Claude Code had a bug (Issue #24327, fixed April 2026) where `exit 2` alone caused Claude to stop rather than reading the stderr feedback. The correct pattern is: `stdout JSON {"decision":"block","reason":"..."} + exit 2 + stderr message`. Both channels are used for dual teaching moments.

**2. Override not in block message**
`GITHABITS_ALLOW_MAIN=1` env var bypass is documented in README only — not in the hook's block message. Claude can read block messages and self-apply overrides, which would defeat enforcement. The override is for human use only.

**3. Global install by default**
Beginners benefit from one setup that works everywhere. `--project` flag available for per-project scoping.

**4. python3 for JSON, not jq**
python3 is available by default on macOS and Linux. jq is not. python3 is primary; jq is used as fallback if available. If neither is present, the hook exits 0 (allow through) rather than blocking everything.

---

## Open Questions

1. How does "intent inference" work — detecting "new feature" vs. "hotfix" from conversation context? CLAUDE.md instruction is the approach for MVP. Hook-level inference if needed in v2.

---

## Success Criteria

- Install takes one command.
- After install, `git commit` on main triggers a readable, friendly educational message.
- After install, Claude explains every git command it runs before running it.
- A beginner who reads the first hook message understands both what happened AND what to do next without googling anything.
