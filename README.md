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

It is one Bash file. It needs Bash 3.2 or later and Git 2.38 or later.

```sh
ln -s "$PWD/git-worktree-set" /usr/local/bin/git-worktree-set
```

Git runs any executable named `git-<name>` on the `PATH` as `git <name>`.
Git sends `git worktree-set --help` to `man`, and there is no manual page. Use
`git worktree-set help`.

### Agent skill

`skills/git-worktree-set/SKILL.md` tells a coding agent how to use the tool.
Link it into the skill directory of your agent:

```sh
ln -s "$PWD/skills/git-worktree-set" ~/.claude/skills/git-worktree-set   # Claude Code
ln -s "$PWD/skills/git-worktree-set" ~/.codex/skills/git-worktree-set    # Codex
```

## Design

- **No state.** Git is the database. The members of a set are the worktrees in
  its directory. The branch, the main checkout, and the lock come from Git.
- **No configuration.** The root is the directory that holds your
  repositories. A repository is a child directory that contains `.git`. The
  tool finds the root from inside any checkout, any worktree, or the root.
- **Same shape as the root.** A set uses the same directory names as the root,
  so relative paths between repositories continue to work. The set is below
  the root, so a tool that reads files from parent directories still finds the
  files of the root. Examples are Claude Code with `CLAUDE.md` and direnv with
  `.envrc`. Codex reads `AGENTS.md` only from the repository root down, so it
  does not read a root `AGENTS.md` from inside a set.
- **Removal cannot lose work.** See below. There is no force option.

## Commands

### `new [--from <ref>] [--all] <name> [<repository>...]`

For each repository:

1. Fetch `origin`.
2. If branch `<name>` exists, check it out. If only `origin/<name>` exists,
   create `<name>` from it, so that pushed work continues. If neither exists,
   create `<name>` from `--from`, or from the default branch (see below).
3. Lock the worktree. A locked worktree makes `git worktree remove --force`
   and `git worktree prune` refuse, so other tools cannot delete it by accident.
4. Copy the files that `.worktreeinclude` lists (see below).

All checks run before the first change. `new` prints only the set directory on
stdout, so scripts can use `cd "$(git worktree-set new ...)"`. Options can come
before or after the name.

With no repository, `new` makes an empty set. This is useful when you do not
know yet which repositories the task needs.

For `--from <branch>` and for the default branch, `new` uses
`origin/<branch>`. It uses the local `<branch>` when that branch contains
`origin/<branch>` and has more commits. If each has commits that the other does
not have, `new` uses `origin/<branch>` and prints a warning.

### Default branch

The default branch of a repository is the value of the Git configuration key
`worktree-set.defaultBranch`, else the default branch of `origin`
(`origin/HEAD`). Set the key when work merges into a different branch:

```sh
git -C web config worktree-set.defaultBranch dev
```

`new` starts new branches from the default branch. `remove` and
`remove --merged` compare each branch with it.

### `add <repository>...`

Run it inside a set. It adds the repositories to that set, on the set branch.
An agent that starts in an empty set can add each repository when it needs it.

### `status [--porcelain] [<name>]`

Without a name, it shows the set that contains the current directory, or all
sets. `--porcelain` prints one line for each worktree, with tab separators:

```text
<set> <repository> <branch> <changed files> <commits on no remote> <path>
```

For a worktree with a detached HEAD, `status` shows where the set branch is
checked out, if another worktree has it. A directory in `.worktrees/` that is
itself a worktree is not a set. `status` marks it, and `--porcelain` leaves it
out.

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
the set. Keep results that you need later, such as test reports or
measurements, outside the worktrees.

Then it runs `git worktree remove` without `--force`. It deletes the branch in
two cases only:

- Each commit of the branch is on a remote. `new <name>` then continues from
  `origin/<name>`.
- A merge of the branch into the default branch changes nothing. This is true
  after a squash merge or a rebase merge.

In all other cases the branch stays, and `new <name>` continues from it.

### `remove --merged`

`remove --merged` fetches each repository, then removes each set in which a
merge of every branch into the default branch changes nothing. The same
refusals apply to each set. It keeps all other sets and prints one line for
each of them.

A new set has no commits, so it counts as merged, as a new branch does for
`git branch --merged`. For this reason `remove --merged` keeps a set that had
activity in the last day. Activity is a change to the set directory (`new` or
`add`), or a change to the index or the HEAD log of one of its worktrees (a
commit, a checkout, or a Git command that found changed files). It is thus
safe to run on a schedule. `remove <name>` has no such limit.

`remove --merged` also keeps a set in which a worktree has a detached HEAD, and
a directory in `.worktrees/` that is itself a worktree.

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
echo "PORT=$GIT_WORKTREE_SET_PORT_BASE" > .worktree-set.env
for repository in $GIT_WORKTREE_SET_REPOSITORIES; do
  if [ -f "$repository/package-lock.json" ]; then (cd "$repository" && npm ci --prefer-offline); fi
done
```

## Claude Code

Claude Code can make a set for `claude --worktree <name>` when you start it in
the root. Put two hooks in `<root>/.claude/settings.json`. The `WorktreeCreate`
hook was tested with Claude Code 2.1.287, where the hook input field is `name`.
The `WorktreeRemove` hook is not tested yet. The hooks need `jq`.

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

The workflow in `.github/workflows/test.yml` runs the tests on Linux and macOS.

## Limits

- The repositories must be normal clones, one level below the root. Bare
  repositories and submodules are not supported.
- File names that contain a newline are not supported in `.worktreeinclude`.
- Two set names can get the same port block (1 in 1000).
- If Git refuses to remove a worktree after all checks pass, `remove` stops.
  The worktrees that it removed before stay removed, and the others stay.
  Correct the cause and run `remove` again.
- Windows is not tested.

## Related tools

- worktrunk and gwq manage the worktrees of one repository.
- Conductor and the Codex app make worktrees for agents, one repository at a
  time.
- worktree-flow, brunch, and qdpi make worktrees across several repositories.
- mani and repo run commands across many repositories. They do not make
  worktrees.

`git-worktree-set` keeps no state outside Git, refuses each removal that can
lose work, and leaves a layout that plain Git commands and agents can use.

## License

MIT
