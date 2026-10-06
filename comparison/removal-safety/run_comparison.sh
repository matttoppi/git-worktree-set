#!/usr/bin/env bash
# Runs each data-loss scenario against each tool and prints a Markdown table.
#
# Each case uses a new root with two repositories, `api` and `web`, that are
# clones of bare remotes. The adapter of a tool makes a workspace with one
# worktree of each repository on one branch. The scenario puts work at risk in
# the `web` worktree. The adapter then runs the normal remove command of the
# tool: no force option, and "y" for each prompt, as an agent would answer.
# The scenario then checks whether the work still exists.
#
# Usage: run_comparison.sh [<tool>...]     (default: every file in adapters/)
# Details of each case go to $LOG (default /tmp/removal-safety.log).
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
LOG=${LOG:-/tmp/removal-safety.log}
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
git config --global init.defaultBranch main
git config --global advice.detachedHead false

scenarios=(modified untracked unpushed detached stray foreign_lock merged_cleanup merged_cleanup_finds)
headers=("Modified file" "Untracked file" "Commit not pushed" "Commit on detached HEAD"
  "File in workspace folder" "Lock of another tool" "Bulk cleanup, untracked file"
  "Bulk cleanup removes a finished set")

make_root() { # make_root <work directory>: <work>/root/{api,web} and <work>/remotes
  local work=$1 repository
  for repository in api web; do
    git init -q --bare "$work/remotes/$repository.git"
    git clone -q "$work/remotes/$repository.git" "$work/root/$repository" 2>/dev/null
    (
      cd "$work/root/$repository" || exit 1
      printf 'node_modules/\n' >.gitignore
      echo base >file.txt
      git add . && git commit -qm init && git push -q origin main
    )
  done
}

# True if commit $2 is reachable from a ref or a reflog of the main checkout of $1.
reachable() {
  git -C "$(adapter_main "$1")" rev-list --all --reflog 2>/dev/null | grep -qx "$2"
}

squash_merge_on_remote() { # squash_merge_on_remote <repository> <branch>
  local clone
  clone=$(mktemp -d)
  git clone -q "$WORK/remotes/$1.git" "$clone" 2>/dev/null
  git -C "$clone" merge -q --squash "origin/$2" >/dev/null &&
    git -C "$clone" commit -qm "squash of $2" &&
    git -C "$clone" push -q origin main
  git -C "$(adapter_main "$1")" fetch -q origin
}

remove_quietly() { yes 2>/dev/null | adapter_remove "$@" >>"$LOG" 2>&1; }

# For a case in which the tool must refuse to remove `web`: "kept" if the work
# and the clean `api` worktree both remain, "partial" if the tool removed `api`
# before it refused, and $1 (LOST or removed) if the work is gone.
refusal_result() { # refusal_result <word for gone> <command that is true when the work remains>
  local gone=$1
  shift
  if ! "$@"; then
    echo "$gone"
  elif [ -d "$(adapter_path task-1 api)" ]; then
    echo kept
  else
    echo partial
  fi
}

scenario_modified() {
  local web
  web=$(adapter_path task-1 web)
  echo "local change" >>"$web/file.txt"
  remove_quietly task-1
  refusal_result LOST grep -q "local change" "$web/file.txt"
}

scenario_untracked() {
  local web
  web=$(adapter_path task-1 web)
  echo notes >"$web/notes.txt"
  remove_quietly task-1
  refusal_result LOST test -f "$web/notes.txt"
}

scenario_unpushed() {
  local web commit
  web=$(adapter_path task-1 web)
  echo "unpushed" >>"$web/file.txt"
  git -C "$web" commit -qam "unpushed work"
  commit=$(git -C "$web" rev-parse HEAD)
  remove_quietly task-1
  if reachable web "$commit"; then echo kept; else echo LOST; fi
}

scenario_detached() {
  local web commit
  web=$(adapter_path task-1 web)
  git -C "$web" switch -q --detach
  echo "detached" >>"$web/file.txt"
  git -C "$web" commit -qam "work on a detached HEAD"
  commit=$(git -C "$web" rev-parse HEAD)
  remove_quietly task-1
  if reachable web "$commit"; then echo kept; else echo LOST; fi
}

scenario_stray() {
  local directory
  directory=$(adapter_dir task-1)
  if [ -z "$directory" ]; then echo n/a; return; fi
  echo notes >"$directory/notes.md"
  remove_quietly task-1
  refusal_result LOST test -f "$directory/notes.md"
}

# Another tool locked the clean `web` worktree. "removed" means the tool
# deleted a worktree that another owner protects.
scenario_foreign_lock() {
  local web main
  web=$(adapter_path task-1 web)
  main=$(adapter_main web)
  git -C "$main" worktree unlock "$web" 2>/dev/null
  git -C "$main" worktree lock --reason "another tool" "$web"
  remove_quietly task-1
  refusal_result removed test -d "$web"
}

finish_task() { # Commit in `web`, push the branch, and squash-merge it on the remote.
  local web=$1
  echo "finished" >>"$web/file.txt"
  git -C "$web" commit -qam "finished work"
  git -C "$web" push -q origin HEAD:refs/heads/task-1 2>/dev/null
  squash_merge_on_remote web task-1
  git -C "$(adapter_main api)" fetch -q origin
}

# The branch of `web` is squash-merged, but `web` has an untracked file. The
# bulk cleanup command of the tool must keep it.
scenario_merged_cleanup() {
  local web status
  web=$(adapter_path task-1 web)
  finish_task "$web"
  echo notes >"$web/notes.txt"
  yes 2>/dev/null | adapter_cleanup_merged task-1 >>"$LOG" 2>&1
  status=$?
  if [ "$status" = 2 ]; then echo n/a; return; fi
  if [ -f "$web/notes.txt" ]; then echo kept; else echo LOST; fi
}

# The same finished set with nothing at risk. "yes" means bulk cleanup removes
# it, so a "kept" in the column before comes from a check, not from a tool
# that does not see the set as finished.
scenario_merged_cleanup_finds() {
  local web status
  web=$(adapter_path task-1 web)
  finish_task "$web"
  yes 2>/dev/null | adapter_cleanup_merged task-1 >>"$LOG" 2>&1
  status=$?
  if [ "$status" = 2 ]; then echo n/a; return; fi
  if [ -d "$web" ]; then echo no; else echo yes; fi
}

run_case() { # run_case <tool> <scenario>: prints one result
  local tool=$1 scenario=$2
  WORK=$(mktemp -d)
  ROOT=$WORK/root
  export WORK ROOT
  printf '\n===== %s / %s (%s)\n' "$tool" "$scenario" "$WORK" >>"$LOG"
  (
    make_root "$WORK" >>"$LOG" 2>&1 || { echo error:fixture; exit; }
    cd "$ROOT" || exit
    # Defaults that an adapter can replace. The scenarios call them.
    # shellcheck disable=SC2329
    adapter_main() { printf '%s/%s' "$ROOT" "$1"; }
    # shellcheck disable=SC2329
    adapter_cleanup_merged() { return 2; }
    # shellcheck source=/dev/null
    source "$here/adapters/$tool.sh"
    adapter_setup >>"$LOG" 2>&1 || { echo error:setup; exit; }
    adapter_create task-1 api web >>"$LOG" 2>&1 || { echo error:create; exit; }
    if [ ! -d "$(adapter_path task-1 web)" ]; then echo error:path; exit; fi
    "scenario_$scenario" 2>>"$LOG"
  )
}

tools=("$@")
if [ ${#tools[@]} -eq 0 ]; then
  for adapter in "$here"/adapters/*.sh; do tools+=("$(basename "$adapter" .sh)"); done
fi
: >"$LOG"

printf '| Tool |'
for header in "${headers[@]}"; do printf ' %s |' "$header"; done
printf '\n|---|'
for _ in "${headers[@]}"; do printf -- '---|'; done
printf '\n'
for tool in "${tools[@]}"; do
  printf '| %s |' "$tool"
  for scenario in "${scenarios[@]}"; do printf ' %s |' "$(run_case "$tool" "$scenario")"; done
  printf '\n'
done
