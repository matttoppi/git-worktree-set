# Removal safety comparison

This comparison tests whether tools that make one workspace with a worktree for
each repository lose work when you remove the workspace. It runs each tool in
a Docker container, with the same mock repositories and the same cases.

## Run it

From the repository root:

```sh
docker build -f comparison/removal-safety/Dockerfile -t worktree-removal-safety .
docker run --rm worktree-removal-safety
```

To run some tools only: `docker run --rm worktree-removal-safety bash run_comparison.sh grove wtp`.
The details of each case go to `/tmp/removal-safety.log` in the container.

## Method

Each case starts with a new root that holds two repositories, `api` and `web`.
Each one is a clone of a bare remote, with one commit on `main` that is pushed.

1. The adapter of the tool makes a workspace named `task-1` with a worktree of
   `api` and of `web`.
2. The case puts work at risk in the `web` worktree or in the workspace folder.
   The `api` worktree stays clean.
3. The adapter runs the normal remove command of the tool. It uses no force
   option, and it answers "y" to each prompt, as an agent does.
4. The case checks whether the work still exists.

Each tool has an install script in `install/` that pins a release or a commit,
and an adapter in `adapters/`. Two adapters are references:

- `plain-git` uses only `git worktree add`, `git worktree remove`, and
  `git branch -d`, with no tool.
- `unchecked-delete` deletes the workspace with no checks. It must lose the
  work in each case. This shows that each case tests what it claims.

## Cases

| Case | Work at risk | Safe result |
|---|---|---|
| Modified file | A change to a tracked file in `web` | The change remains |
| Untracked file | A new file in `web` that is not committed | The file remains |
| Commit not pushed | A commit on the workspace branch that is on no remote | A ref or reflog still reaches the commit |
| Commit on detached HEAD | A commit on a detached HEAD in `web` | A ref or reflog still reaches the commit |
| File in workspace folder | A file in the workspace folder, outside the worktrees | The file remains |
| Lock of another tool | `git worktree lock` on `web` by another owner | The worktree remains |
| Bulk cleanup, untracked file | The branch is squash-merged, but `web` has an untracked file | The file remains after the bulk cleanup command |
| Bulk cleanup removes a finished set | The same squash-merged workspace with nothing at risk | (A check of the case before) |

Result words:

- **kept**: the work remains, and the tool removed nothing.
- **partial**: the work remains, but the tool removed the clean `api` worktree
  before it stopped. The workspace is left half removed.
- **LOST**: the work is gone. **removed**: the locked worktree is gone.
- **n/a**: the tool has no bulk cleanup command.
- In the last column, **yes** means that the bulk cleanup removed the finished
  workspace. **no** means that the tool does not see it as finished, so a
  "kept" in the column before comes from that, and not from a check.

## Results

Results from 2026-10-06. Two runs gave the same table.

| Tool | Modified file | Untracked file | Commit not pushed | Commit on detached HEAD | File in workspace folder | Lock of another tool | Bulk cleanup, untracked file | Bulk cleanup removes a finished set |
|---|---|---|---|---|---|---|---|---|
| git-worktree-set | kept | kept | kept | kept | kept | kept | kept | yes |
| brunch | kept | kept | kept | kept | partial | partial | n/a | n/a |
| wtp | kept | kept | kept | LOST | partial | partial | n/a | n/a |
| aw | kept | kept | kept | LOST | partial | partial | n/a | n/a |
| orbit | kept | kept | kept | LOST | LOST | partial | kept | yes |
| git-worktree-manager | kept | LOST | kept | LOST | LOST | partial | kept | no |
| worktree-flow | kept | kept | kept | LOST | LOST | removed | kept | yes |
| grove | LOST | LOST | LOST | LOST | LOST | removed | LOST | yes |
| spawnpoint | LOST | LOST | LOST | LOST | LOST | removed | n/a | n/a |
| par | LOST | LOST | LOST | LOST | LOST | removed | n/a | n/a |
| plain-git | partial | partial | kept | LOST | partial | partial | n/a | n/a |
| unchecked-delete | LOST | LOST | LOST | LOST | LOST | removed | LOST | yes |

## Tools and adapter choices

| Tool | Version | Remove command | Notes |
|---|---|---|---|
| [git-worktree-set](../..) | this repository | `git worktree-set remove task-1` | Bulk cleanup: `remove --merged`, after the adapter makes the set idle for one day |
| [brunch](https://github.com/htzv/brunch) | commit `c30c5b3` | `brunch rm -w <workspace>` | Finds clones only in a `<root>/<forge>/<org>/<repo>` tree, so the adapter moves them there |
| [wtp](https://github.com/eddix/wtp) | v0.1.1 (`90a3149`) | `wtp rm task-1` | Built from source; the `wtp-gui` member is left out |
| [aw](https://github.com/lldxflwb/aw) | commit `1a64f7f` | `aw rm` in the workspace | `aw prune` only removes registry entries, so there is no bulk cleanup |
| [Orbit](https://github.com/orbcli/orbit) | commit `4673a1e` | `orbit done`, then `orbit prune task-1` | Orbit has no direct remove command; bulk cleanup is `orbit prune` |
| [git-worktree-manager](https://github.com/nanasess/git-worktree-manager) | commit `65eade5` | `worktree cleanup task-1` | Bulk cleanup: `worktree cleanup --merged`; no `gh` credentials in the container |
| [worktree-flow](https://github.com/simonpratt/worktree-flow) | 0.0.26 | `flow drop task-1` | Bulk cleanup: `flow prune`, which removes each clean workspace |
| [Grove](https://github.com/nicksenap/grove) | v1.1.18 | `gw delete task-1` | Bulk cleanup: `gw prune --yes`, which selects by age; the adapter sets an old creation date |
| [spawnpoint](https://github.com/mihirgupta0900/spawnpoint) | v0.12.0 | `spawnpoint cleanup --no-input --workspaces task-1 --delete-branches` | `--no-input` needs a branch choice; `--delete-branches` is the interactive default |
| [par](https://github.com/coplane/par) | commit `7416a80` | `par rm task-1` | Workspace made with `par workspace start task-1 --repos api,web` |

## Limits

- The author of git-worktree-set chose the cases. They test removal safety
  only. They do not test features, speed, or ease of use, where other tools do
  more.
- The results apply to the pinned versions.
- An adapter can contain a mistake. Each adapter is short; please report an
  error with the log of the case.
