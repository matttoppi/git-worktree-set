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
It is an [Agent Skills](https://agentskills.io) skill, so Claude Code, Codex,
and other agents can use the same file. Install it with the
[skills CLI](https://github.com/vercel-labs/skills):

```sh
npx skills add matttoppi/git-worktree-set --global
```

Or link it from a clone into the skill directory of your agent:

```sh
ln -s "$PWD/skills/git-worktree-set" ~/.claude/skills/git-worktree-set   # Claude Code
ln -s "$PWD/skills/git-worktree-set" ~/.codex/skills/git-worktree-set    # Codex
```

## Design

- **No state.** Git is the database. The members of a set are the worktrees in
  its directory. The branch, the main checkout, and the lock come from Git.
- **No required configuration.** The root is the directory that holds your
  repositories. A repository is a child directory that contains `.git`. The
  tool finds the root from inside any checkout, any worktree, or the root.
- **Same shape as the root.** A set uses the same directory names as the root,
  so relative paths between repositories continue to work. The set is below
  the root, so a tool that reads files from parent directories still finds the
  files of the root, for example direnv with `.envrc`. For agent instructions,
  see [Agent instructions](#agent-instructions).
- **Removal cannot lose work.** See below. There is no force option.
- **Everything else is optional.** The script works alone. The agent skill,
  `.worktreeinclude`, the setup hook, the Claude Code hooks, and scheduled
  cleanup are each optional, and the tool does not install any of them.

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

If you deleted a set folder without Git, for example with `rm -rf`, Git keeps a
locked record of each worktree, and `new <name>` refuses. `remove <name>` then
unlocks and prunes these records. The branches stay.

To discard a set on purpose, use Git directly. `--force` twice removes a
locked worktree with its changes:

```sh
git -C <root>/<repository> worktree remove --force --force <root>/.worktrees/<name>/<repository>
git -C <root>/<repository> branch -D <name>
```

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

Then let the scheduler of the system (`launchd`, `cron`, a systemd timer) run
`git for-each-repo`, which runs the command in each root:

```sh
git for-each-repo --config=worktree-set.root --keep-going worktree-set remove --merged </dev/null
```

`--keep-going` needs Git 2.46 or later. Without it, the first failure stops the
other roots.

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
The hook is optional. If it fails, `new` prints a warning and the set is still
usable. For setup that belongs to one repository, you can use a `post-checkout`
hook in that repository instead: Git runs it when `git worktree add` makes a
worktree. Use the set hook for setup that applies to the set, such as ports.

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

The session starts in an empty set. The agent skill tells the agent to run
`git worktree-set add <repository>` for each repository that the task needs.

## Agent instructions

Keep agent instructions in `AGENTS.md` files. Claude Code, Codex, and most
other agents read them. A set changes which files an agent finds:

- Each worktree has the `AGENTS.md` files of its repository, because they are
  tracked files.
- Claude Code also reads `AGENTS.md` files in the directories above the working
  directory, so it reads a root `AGENTS.md` from inside a set. It reads them
  only when there is no `CLAUDE.md` in the working directory or above it.
- Codex reads `AGENTS.md` files from the repository root down, so it does not
  read a root `AGENTS.md` from inside a set.

Thus put the guidance for worktree sets in the agent skill, and put the
guidance for a repository in the `AGENTS.md` of that repository.

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

- Several tools also make one workspace with a worktree for each repository:
  [Grove](https://github.com/nicksenap/grove),
  [Orbit](https://github.com/orbcli/orbit),
  [worktree-flow](https://github.com/simonpratt/worktree-flow),
  [git-worktree-manager](https://github.com/nanasess/git-worktree-manager),
  [spawnpoint](https://github.com/mihirgupta0900/spawnpoint),
  [par](https://github.com/coplane/par), and
  [Vibe Kanban](https://github.com/BloopAI/vibe-kanban).
- [worktrunk](https://github.com/max-sixty/worktrunk),
  [gwq](https://github.com/d-kuro/gwq), Claude Code, the Codex app, and
  Conductor make worktrees for one repository at a time.
- [mani](https://github.com/alajmo/mani), [gita](https://github.com/nosarthur/gita),
  and [repo](https://gerrit.googlesource.com/git-repo) run commands across many
  repositories. They do not make a worktree for each task.

`git-worktree-set` differs in its removal model and in what it does not have.
It keeps no state file and needs no configuration. It locks each worktree.
Before it removes anything, it checks every repository of the set, and it has
no force option. It finds squash merges, and `remove --merged` is safe to run
on a schedule.

### Removal safety comparison

[`comparison/removal-safety`](comparison/removal-safety) runs nine of these
tools and `git-worktree-set` in Docker with the same mock repositories. Each
case puts work at risk and then runs the normal remove command of the tool.

| Tool | Cases with lost work | Cases with a half-removed workspace | Removed a worktree that another tool locked |
|---|---|---|---|
| git-worktree-set | 0 of 7 | 0 | no |
| brunch | 0 of 6 | 2 | no |
| wtp | 1 of 6 | 2 | no |
| aw | 1 of 6 | 2 | no |
| Orbit | 2 of 7 | 1 | no |
| git-worktree-manager | 3 of 7 | 1 | no |
| worktree-flow | 2 of 7 | 0 | yes |
| Grove | 6 of 7 | 0 | yes |
| spawnpoint | 5 of 6 | 0 | yes |
| par | 5 of 6 | 0 | yes |
| Plain Git, no tool (reference) | 1 of 6 | 4 | no |

The comparison tests removal safety only. Other tools have more features. See
its README for the method, the versions, and the limits.

## License

MIT
