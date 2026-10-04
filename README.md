# git-worktree-set

One directory, one branch, one worktree for each repository.

`git worktree` isolates a task in one repository. `git worktree-set` does the
same for a task that spans several independent repositories, without a
monorepo, submodules, or a state file.

```text
~/dev/platform/                      ~/dev/platform/.worktrees/cas-123/
├── api/        (main)               ├── api/     (branch cas-123)
├── web/        (main)      new      └── web/     (branch cas-123)
└── lambdas/    (main)    ------->
```

```sh
git worktree-set new cas-123 api web    # create the set; prints its directory
git worktree-set add lambdas            # inside the set: add a repository later
git worktree-set status                 # branch, changed files, commits on no remote
git worktree-set remove cas-123         # refuses if any work could be lost
git worktree-set remove --merged        # remove each set that is merged
```

## Install

It is one Bash file with no dependencies other than Git 2.31 or later.

```sh
ln -s "$PWD/git-worktree-set" /usr/local/bin/git-worktree-set
```

Git runs any executable named `git-<name>` on the `PATH` as `git <name>`.

## Design

- **No state.** Git is the database. The members of a set are the worktrees in
  its directory. The branch, the main checkout, and the lock come from Git.
- **No configuration.** The root is the directory that holds your
  repositories. A repository is a child directory that contains `.git`. The
  tool finds the root from inside any checkout, any worktree, or the root.
- **Same shape as the root.** A set uses the same directory names as the root,
  so relative paths between repositories continue to work. The set is below
  the root, so files such as `CLAUDE.md` and `.envrc` above it stay in effect.
- **Removal cannot lose work.** See below. There is no force option.

## Commands

### `new [--from <ref>] [--all] <name> [<repository>...]`

For each repository:

1. Fetch `origin`.
2. If branch `<name>` exists, check it out. If not, create it from `--from`,
   or from the default branch of `origin`.
3. Lock the worktree. A locked worktree makes `git worktree remove --force`
   and `git worktree prune` refuse, so other tools cannot delete it by accident.
4. Copy the files that `.worktreeinclude` lists (see below).

All checks run before the first change. `new` prints only the set directory on
stdout, so scripts can use `cd "$(git worktree-set new ...)"`.

With no repository, `new` makes an empty set. This is useful when you do not
know yet which repositories the task needs.

### `add <repository>...`

Run it inside a set. It adds the repositories to that set, on the set branch.
An agent that starts in an empty set can add each repository when it needs it.

### `status [--porcelain] [<name>]`

Without a name, it shows the set that contains the current directory, or all
sets. `--porcelain` prints one line for each worktree, with tab separators:

```text
<set> <repository> <branch> <changed files> <commits on no remote> <path>
```

### `remove [<name>]`

`remove` checks every worktree first. It removes nothing if it finds one of
these conditions:

| Condition | Why |
|---|---|
| A modified, staged, or untracked file | The work is not committed. |
| A detached HEAD with commits on no branch | The commits would become unreachable. |
| A lock that another owner made | Someone else protects this worktree. |
| A file in the set directory that is not in a worktree | It would be deleted with the directory. |

Ignored files do not block removal. This is the rule of `git worktree remove`:
a file that Git ignores is a file that can be made again. If you edit an
ignored file such as `.env.local` in a set, copy the edit before you remove
the set.

Then it runs `git worktree remove` without `--force`. It deletes the branch in
two cases only:

- Each commit of the branch is on a remote.
- A merge of the branch into the default branch changes nothing. This is true
  after a squash merge or a rebase merge.

In all other cases the branch stays, and `new <name>` continues from it.

### `remove --merged`

`remove --merged` fetches each repository, then removes each set in which a
merge of every branch into the default branch changes nothing. The same
refusals apply to each set. It keeps all other sets and prints one line for
each of them.

A new set has no commits, so it counts as merged, as a new branch does for
`git branch --merged`. For this reason `remove --merged` keeps a set for one
day after the last change of its members (the modification time of the set
directory). It is thus safe to run on a schedule. `remove <name>` has no such
limit.

A directory in `.worktrees/` that is itself a worktree is not a set.
`remove --merged` keeps it.

### Scheduled cleanup

To clean several roots on a schedule, keep the list of roots in the global Git
configuration, as `git maintenance` does with `maintenance.repo`:

```sh
git config --global --add worktree-set.root /path/to/root
```

Then let the scheduler of the system (`launchd`, `cron`, a systemd timer) run:

```sh
git config --global --get-all worktree-set.root | while IFS= read -r root; do
  GIT_WORKTREE_SET_ROOT="$root" git-worktree-set remove --merged </dev/null
done
```

## Files that worktrees do not have

A new worktree has no ignored files, such as `.env.local`. List them in a
`.worktreeinclude` file (gitignore syntax). Claude Code, the Codex app,
Conductor, and worktrunk read the same file.

- `<repository>/.worktreeinclude` applies to that repository.
- `<root>/.worktreeinclude` applies to all repositories. Use it if you do not
  want to add a file to the repositories.

Only files that Git ignores are copied. A tracked file is never copied, so a
copy cannot become a change in the worktree.

## Setup hook

If `<root>/.worktree-set-setup` is executable, `new` runs it one time in the
set directory. Use it to install dependencies, assign ports, or link files.

| Variable | Value |
|---|---|
| `GIT_WORKTREE_SET_NAME` | The set name (the branch). |
| `GIT_WORKTREE_SET_PATH` | The set directory. |
| `GIT_WORKTREE_SET_ROOT` | The root. |
| `GIT_WORKTREE_SET_REPOSITORIES` | The repositories that this call added, with space separators. |
| `GIT_WORKTREE_SET_PORT_BASE` | A stable block of 10 ports, made from the name (10000 to 19990). |

The hook runs again for each `add`, so it must be safe to run more than one
time. In the set directory, `remove` accepts only symbolic links and the file
`.worktree-set.env`. Put generated values such as ports in that file.

Example:

```sh
#!/bin/sh
ln -sf "$GIT_WORKTREE_SET_ROOT/AGENTS.md" AGENTS.md
echo "PORT=$GIT_WORKTREE_SET_PORT_BASE" > .worktree-set.env
for repository in $GIT_WORKTREE_SET_REPOSITORIES; do
  if [ -f "$repository/package-lock.json" ]; then (cd "$repository" && npm ci --prefer-offline); fi
done
```

## Claude Code

Claude Code can make a set for `claude --worktree <name>` when you start it in
the root. Put two hooks in `<root>/.claude/settings.json`. Tested with Claude
Code 2.1.287; the hook input field is `name`.

```json
{
  "hooks": {
    "WorktreeCreate": [{ "hooks": [{ "type": "command",
      "command": "GIT_WORKTREE_SET_ROOT=\"$CLAUDE_PROJECT_DIR\" git-worktree-set new \"$(jq -r .name)\"" }] }],
    "WorktreeRemove": [{ "hooks": [{ "type": "command",
      "command": "GIT_WORKTREE_SET_ROOT=\"$CLAUDE_PROJECT_DIR\" git-worktree-set remove \"$(basename \"$(jq -r .worktree_path)\")\"" }] }]
  }
}
```

The session starts in an empty set. Tell the agent in the root `CLAUDE.md` to
run `git worktree-set add <repository>` for each repository that the task
needs.

## Convention for tools

An editor or an agent tool can support several repositories with two rules:

1. If the project root is not a Git repository, the repositories one level
   below it are the project.
2. A worktree of that project is a directory that contains one worktree for
   each repository, with the same directory names, on one branch.

A tool can call `git worktree-set new` and `status --porcelain`, or it can
implement the two rules itself. The layout is plain Git in both cases.

## Environment

`GIT_WORKTREE_SET_ROOT` sets the root when the tool cannot find it.

## Tests

```sh
./test_git_worktree_set.sh
BASH_UNDER_TEST=/bin/bash ./test_git_worktree_set.sh   # Bash 3.2 on macOS
```

## Limits

- The repositories must be normal clones, one level below the root. Bare
  repositories and submodules are not supported.
- File names that contain a newline are not supported in `.worktreeinclude`.
- Two set names can get the same port block (1 in 1000).

## License

MIT
