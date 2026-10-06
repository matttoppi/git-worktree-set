---
name: git-worktree-set
description: Create and manage an isolated task workspace across independent Git repositories that live side by side in one directory (a polyrepo, not a monorepo) with the `git worktree-set` command. Use when the project root is the directory that holds the repositories and a task changes files in one or more of them, when the user asks for a worktree, an isolated workspace, or parallel work across repositories, when the user asks to remove or clean up worktree sets that are merged or stale, or when the current directory is inside `.worktrees/<name>/`. Do not use when the project root is itself one Git repository, or for files outside the repositories, such as reports or presentations.
---

# Git worktree set

A worktree set is one directory with one Git worktree for each repository that a task needs, all on one branch:

```text
<root>/                      <root>/.worktrees/<name>/
├── api/      (main checkout)   ├── api/    (branch <name>)
├── web/      (main checkout)   └── web/    (branch <name>)
└── lambdas/  (main checkout)
```

- The **root** is the directory that holds the repositories. It is usually not a Git repository.
- The **name** of the set is the branch name in each repository.
- There is no state file. Git holds all state. Plain Git commands work in each worktree.

## Before you start

1. Run `git worktree-set help`. Do not use `--help`: Git sends it to `man`, and there is no manual page. If the command is missing, stop and tell the user. Do not build the layout by hand.
2. Run `git worktree-set status` from the root or from inside a repository. If a set for this task exists, continue in it. Do not make a second one.

## Start a task

Make a set only for changes to files inside repositories. Put other output, such as reports, presentations, and evidence, in a directory outside `.worktrees/`, for example `<root>/output/`, unless the user names a location.

1. List the repositories: the child directories of the root that contain `.git`.
2. Select the repositories that the task will change. Start small. You can add more at any time.
3. Select a name: the issue identifier and a short description, in lowercase, with dashes and no slash. Example: `eng-123-upload-retry`. If the user or the project gives a branch convention, use it.
4. Create the set from the root or from inside a repository:

```sh
git worktree-set new <name> <repository>...
```

The last line of output is the absolute path of the set. Do all work for the task below that path.

- New branches start from the default branch of the repository: the Git configuration key `worktree-set.defaultBranch`, else the default branch of `origin`. Use `--from <ref>` for a different base. Options can come before or after the name.
- If the branch `<name>` exists in a repository or on `origin`, the worktree continues from it.
- If `new` prints `warning: <repository>: fetch failed`, the base can be old. Tell the user.
- With no repository, `new` makes an empty set. Use this when you do not know yet which repositories you need.

## Add a repository at any time

When you find that the task needs one more repository, add it. Do not edit the main checkout in the root.

```sh
git worktree-set add <repository>...            # inside the set
git worktree-set new <name> <repository>...     # from the root or a repository
```

To only read a repository that is not in the set, you can read its main checkout in the root. That checkout can be on a different branch and can contain work that is not committed. Add the repository to the set if you need the default branch content or if you will change it.

## Work in the set

- Change files only inside the repository worktrees of the set, `<root>/.worktrees/<name>/<repository>/`. Do not write files directly in `<root>/.worktrees/<name>/`: `remove` refuses a set directory that has unknown files.
- Never change, commit, or switch branches in the main checkouts for this task. Other work can be in progress there.
- Do not use `git stash`. All worktrees of a repository share one stash list, so a `pop` can apply the changes of another checkout. Use a commit to set work aside.
- Do not detach HEAD in a set worktree. A set with a detached HEAD is never removed by `remove --merged`.
- `remove` deletes ignored files, and `remove --merged` can run on a schedule with no person present. Do not keep results that you need later, such as test reports or measurements, only in ignored directories of a set. Commit them, or copy them to a directory outside `.worktrees/`.
- If your shell does not keep the working directory between commands, use absolute paths and `git -C <path>`.
- Commit in each repository separately. One commit cannot span repositories.
- A new worktree has no installed dependencies and no ignored files, unless the root has a setup hook or a `.worktreeinclude` file. If a build or a test fails because of this, install the dependencies in the worktree. Do not copy secrets by hand into tracked files.
- If the set directory has a `.worktree-set.env` file, read values such as ports from it.
- Use `git worktree-set status` for one view of all repositories. `--porcelain` gives tab-separated fields: set, repository, branch, changed files, commits on no remote, path.

## Parallel agents

To run agents or threads in parallel, make one set for each of them, and start each agent in its set. For an agent that works in one repository, use the path `<root>/.worktrees/<name>/<repository>`. Do not use the worktree feature of the agent application for these repositories: those worktrees are not locked, and `status` and `remove --merged` do not see them.

## Move the work to the main checkout

Do this only when the user asks for it. One branch can be checked out in only one worktree.

1. Commit all work in the set.
2. Run `git worktree-set remove <name>`. The branch stays when it has work that is not pushed or merged.
3. In the main checkout, run `git switch <name>`. If `remove` deleted the local branch because it is pushed, Git makes it again from `origin/<name>`.

## Publish

Do this only when the user asks for it.

- Push each repository: `git -C <repository> push -u origin HEAD`.
- Open one pull request for each repository, from the same branch name. Put a link to the other pull requests in each description.
- State the merge order when one repository depends on another: the provider first, then the consumer.

## Remove a set

Remove a set only when the user asks, or when the task is merged and the user agreed to cleanup.

```sh
git worktree-set remove <name>
```

- `remove` refuses when a worktree has modified, staged, or untracked files, or when the set directory has unknown files. It removes nothing in that case. Report the listed items to the user. Commit or delete them only with the user's agreement.
- `remove` deletes ignored files, as `git worktree remove` does. If you edited an ignored file such as `.env.local` in the set, tell the user before removal.
- `remove` keeps a branch that has changes that are not pushed or merged. This is correct. Do not delete that branch.
- To check before you remove, add `--dry-run`. It reports what `remove` or `remove --merged` would do and changes nothing.
- For a cleanup of all finished sets, run `git worktree-set remove --merged --dry-run` first, then `git worktree-set remove --merged`. It removes each set in which no branch has changes outside the default branch, with the same refusals, and keeps all other sets. It also keeps a set that had Git activity in the last day, and a set with a detached HEAD; use `remove <name>` for such a set. Run it only when the user asks. Report the removed sets and the kept sets.
- Never go around a refusal. Do not use `git worktree remove --force`, `git worktree unlock`, `git branch -D`, or `rm -rf` on a set. The lock on each worktree is deliberate.

## Report

When you finish, tell the user: the set name, the set path, the repositories in it, and the state of each one (committed, pushed, pull request).
