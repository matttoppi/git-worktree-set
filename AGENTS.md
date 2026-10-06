# git-worktree-set

A Git subcommand in one Bash file (`git-worktree-set`), its tests
(`test_git_worktree_set.sh`), and an agent skill (`skills/git-worktree-set/SKILL.md`).

## Rules

- Keep the script compatible with Bash 3.2 and Git 2.38. No dependencies other than Git
  and POSIX tools.
- Keep the design: no state file, no required configuration, and no force option. Every
  removal checks all worktrees of a set before it changes anything.
- Each fix or feature gets one check in `test_git_worktree_set.sh` that fails without it.
- When a command or a rule changes, update `README.md` and the skill in the same commit.
- Write documentation in short, direct sentences, with one term for one concept.

## Verify

```sh
shellcheck git-worktree-set test_git_worktree_set.sh
./test_git_worktree_set.sh
BASH_UNDER_TEST=/bin/bash ./test_git_worktree_set.sh   # macOS: Bash 3.2
```
