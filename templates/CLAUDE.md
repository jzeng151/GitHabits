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
# GitHabits END
