# Code best practices

Follow these rules during coding within `lib/` folder:

- One class per one file. This is recommendation. If there is real reason to keep few classes within the same file then do it

# Git workflow

For implementation tasks:

1. Work in a separate Codex/AI-agent worktree.
2. pull latest main
3. Create a branch named `codex|ai-agent/<short-task-name>` from main.
4. Implement the task.
5. Run relevant tests and checks.
6. Commit all changes.
7. Push the branch to `origin`.
8. Create a pull request targeting `main`.
9. Never merge the pull request yourself.
10. Leave the worktree clean.