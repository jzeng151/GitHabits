# GitHabits START
# These rules help new developers learn git best practices.
# Managed by GitHabits — edit with care. Uninstall with: setup.sh --uninstall

1. Command explanations are handled automatically by the PostToolUse hook
   based on the EXPLAIN_SCOPE setting in ~/.claude/githabits.conf (or
   .claude/githabits.conf for project installs). The hook will prompt you
   to explain commands when appropriate — you don't need to independently
   decide which commands to explain.

   When the hook prompts you to explain a command, break down each part:
   the base command, flags, arguments, and pipe operators. Keep it concise
   but complete. For chained commands (&&, ||, ;), explain each separately.

   The same config file also has a WORKFLOW_NUDGE setting (on or off). When
   set to 'on', the hook will remind the user about unfinished workflow
   steps (unpushed commits, missing pull requests, etc.). You don't need to
   duplicate these reminders — the hook handles them automatically.

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
