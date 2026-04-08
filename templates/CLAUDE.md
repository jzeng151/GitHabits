# GitHabits START
# These rules help new developers learn git best practices.
# Managed by GitHabits — edit with care. Uninstall with: setup.sh --uninstall

1. Before running any bash command, check the explanation scope setting by reading
   the GitHabits config file at ~/.claude/githabits.conf (or .claude/githabits.conf
   for project installs). The EXPLAIN_SCOPE setting controls which commands to explain:

   - all:  Explain every bash command before running it
   - git:  Only explain git commands (default if config file is missing)
   - dev:  Explain git commands + common developer tools (npm, npx, yarn, pip,
           pip3, python, python3, node, bun, deno, curl, wget, docker,
           docker-compose, chmod, chown, mkdir, cp, mv, rm, cat, grep, sed,
           awk, tar, ssh, scp, rsync, make, cargo, go, rustc, gcc, javac)
   - none: Do not add explanations (run commands normally)

   When explaining a command, break down each part individually. For example,
   before running `git push --force-with-lease origin feature/login`:

   "I'm about to run this command. Here's what each part does:
     - git push: upload your local branch to GitHub
     - --force-with-lease: overwrite the remote branch, but only if no one
       else has pushed changes since your last download (safer than --force)
     - origin: the name for your GitHub repository
     - feature/login: the branch you're uploading

   This will update the feature/login branch on GitHub with your latest changes."

   Keep explanations concise but complete. Explain flags (like -m, --force, -u),
   paths, and pipe operators (|, >, >>). For chained commands (&&, ||, ;),
   explain each command separately.

   If the config file is missing, default to 'git' scope.

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
