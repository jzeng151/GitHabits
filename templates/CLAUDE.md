# GitHabits START
# These rules help new developers learn git best practices.
# Managed by GitHabits — edit with care. Uninstall with: setup.sh --uninstall

1. After every Bash tool call, proactively explain the command based on
   EXPLAIN_SCOPE. To determine the scope, read ~/.claude/githabits.conf
   (check .claude/githabits.conf first if it exists in the project).
   Default scope if the file is unreadable: 'git'.

   Scope rules:
   - all:  explain every command, always
   - git:  explain only commands containing 'git'
   - dev:  explain git plus common dev tools (npm, pip, docker, curl, etc.)
   - none: never explain

   When explaining a command, use inline markdown to distinguish each part:
   - Base command and subcommand: **`bold backtick`** — e.g. **`git commit`**
   - Flags: plain backtick — e.g. `-m`, `--amend`
   - Arguments and values: italic backtick — e.g. *`'fix bug'`*, *`origin`*
   - Pipe and chain operators (|, &&, ||, ;): bold — e.g. **`|`**, **`&&`**

   Example — `git commit -m 'fix bug'`:
   **`git commit`** saves a snapshot of your changes. `-m` sets the commit
   message inline; *`'fix bug'`* is the message text.

   Example — `git log --oneline | head -5`:
   **`git log`** lists commits; `--oneline` condenses each to one line.
   **`|`** pipes the output to **`head`**; `-5` limits it to the first 5.

   For chained commands (&&, ||, ;), explain each sub-command separately in
   the same paragraph. Keep explanations concise but complete.

   Note: a PostToolUse hook also monitors commands for workflow nudges
   (unpushed commits, missing PRs, etc.) — those are handled separately
   and you don't need to duplicate them. The hook's WORKFLOW_NUDGE setting
   controls this behavior.

2. Before committing, check the current branch with `git branch --show-current`.
   If the branch is 'main' or 'master', stop and ask the user to name a feature
   branch before continuing. Example: "We're on main — let's create a feature
   branch first. What's a short name for what you're building? (e.g. login-page,
   fix-header, add-search)"

3. After every successful push, give one sentence describing what the git history
   looks like now. Example: "Your feature branch 'feature/login' is now on GitHub
   with 3 commits — ready for a pull request whenever you want."

4. After each of these milestones, suggest the next step in plain English:

   After creating a feature branch:
   "You're on your new branch. Make your changes, then I'll help you commit
   and push them when you're ready."

   After pushing a feature branch to GitHub:
   "Your branch is on GitHub. The next step is to open a pull request so your
   changes can be reviewed before merging into main. Go to your repo on GitHub
   and click 'Compare & pull request', or I can show you the URL."

   After a pull request is merged:
   "Nice work! Now clean up: delete the feature branch locally and on GitHub,
   then pull the latest main so you're up to date. After that, you can start
   fresh on your next feature. Want me to handle the cleanup?"

   After deleting a feature branch and pulling main:
   "You're up to date on main. Ready to start the next feature? Just tell me
   what you're building next and I'll create a branch for it."

5. If the user asks to change GitHabits settings (explanation scope, workflow
   nudges, etc.), edit the config file at ~/.claude/githabits.conf (or
   .claude/githabits.conf for project installs) directly. Valid settings:
     EXPLAIN_SCOPE=all|git|dev|none
     WORKFLOW_NUDGE=on|off
   Confirm the change after editing. Example: "Done — explanation scope is
   now set to 'git'. I'll only explain git commands from now on."
# GitHabits END
