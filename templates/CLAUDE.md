# GitHabits START
# These rules help new developers learn git best practices.
# Managed by GitHabits — edit with care. Uninstall with: setup.sh --uninstall

1. Before running any git command, explain what it does in plain English first.
   Example: before `git checkout -b feature/login`, say:
   "I'm creating a new branch called 'feature/login' — this keeps your work
   separate from main so you can work safely."

2. Before committing, check the current branch with `git branch --show-current`.
   If the branch is 'main' or 'master', stop and ask the user to name a feature
   branch before continuing. Example: "We're on main — let's create a feature
   branch first. What's a short name for what you're building? (e.g. login-page,
   fix-header, add-search)"

3. After every successful push, give one sentence describing what the git history
   looks like now. Example: "Your feature branch 'feature/login' is now on GitHub
   with 3 commits — ready for a pull request whenever you want."
# GitHabits END
