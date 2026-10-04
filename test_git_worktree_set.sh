#!/usr/bin/env bash
# Tests for git-worktree-set. Uses throwaway repositories in a temporary directory.
# Run: ./test_git_worktree_set.sh            (or: BASH_UNDER_TEST=/bin/bash ./test_git_worktree_set.sh)
set -uo pipefail

tool="$(cd "$(dirname "$0")" && pwd)/git-worktree-set"
shell=${BASH_UNDER_TEST:-bash}
sandbox=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$sandbox"' EXIT
export HOME=$sandbox/home GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
mkdir -p "$HOME" "$sandbox/remotes" "$sandbox/root"
root=$sandbox/root
failures=0

worktree_set() { "$shell" "$tool" "$@"; }

check() { # check <description> <command...>
  local description=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'ok    %s\n' "$description"
  else
    printf 'FAIL  %s\n' "$description"
    failures=$((failures + 1))
  fi
}

refuses() { ! "$@"; }

for repository in ui bridge lambdas; do
  git init -q --bare -b main "$sandbox/remotes/$repository.git"
  git clone -q "$sandbox/remotes/$repository.git" "$root/$repository" 2>/dev/null
  (
    cd "$root/$repository" || exit
    printf 'node_modules/\n.env.local\nlocal-data/\n' >.gitignore
    echo base >file.txt
    git add . && git commit -qm init && git push -q origin main
    echo SECRET=1 >.env.local
  )
done
printf '/.env.local\n/file.txt\n' >"$root/.worktreeinclude"
echo "# guide" >"$root/AGENTS.md"
cat >"$root/.worktree-set-setup" <<'EOF'
#!/bin/sh
echo "$GIT_WORKTREE_SET_NAME $GIT_WORKTREE_SET_REPOSITORIES $GIT_WORKTREE_SET_PORT_BASE $PWD" > "$GIT_WORKTREE_SET_ROOT/hook.log"
ln -sf "$GIT_WORKTREE_SET_ROOT/AGENTS.md" AGENTS.md
echo "PORT=$GIT_WORKTREE_SET_PORT_BASE" > .worktree-set.env
EOF
chmod +x "$root/.worktree-set-setup"
cd "$root" || exit

# --- new
output=$(worktree_set new cas-1 ui bridge 2>/dev/null)
set_directory=$root/.worktrees/cas-1
check "new prints only the set directory on stdout" test "$output" = "$set_directory"
check "new creates a worktree for each named repository" test -e "$set_directory/ui/.git" -a -e "$set_directory/bridge/.git"
check "new does not touch repositories that were not named" test ! -e "$set_directory/lambdas"
check "each worktree is on the set branch" test "$(git -C "$set_directory/bridge" branch --show-current)" = cas-1
check "new copies an ignored file listed in .worktreeinclude" test "$(cat "$set_directory/ui/.env.local")" = SECRET=1
check "new leaves the worktree clean (tracked files are not copied)" test -z "$(git -C "$set_directory/ui" status --porcelain)"
check "setup hook ran in the set directory with name, repositories and port base" \
  grep -qE "^cas-1 ui bridge 1[0-9]{3}0 $set_directory\$" "$root/hook.log"
check "setup hook wrote .worktree-set.env in the set directory (remove must accept it later)" grep -q '^PORT=1' "$set_directory/.worktree-set.env"
check "new refuses a set member that exists" refuses worktree_set new cas-1 ui
check "new refuses an unknown repository before it changes anything" refuses worktree_set new cas-2 ui missing
check "a refused new leaves no directory" test ! -e "$root/.worktrees/cas-2"
check "new can add a repository to a set later" worktree_set new cas-1 lambdas
check "the root is found from inside a worktree" test "$(cd "$set_directory/ui" && worktree_set status --porcelain | wc -l | tr -d ' ')" = 3

# --- the lock protects against other tools
check "git worktree remove --force is refused by the lock" refuses git -C "$root/ui" worktree remove --force "$set_directory/ui"

# --- status
echo change >>"$set_directory/ui/file.txt"
check "status --porcelain reports a changed file" \
  test "$(worktree_set status --porcelain cas-1 | awk -F'\t' '$2 == "ui" { print $3, $4, $5 }')" = "cas-1 1 0"
check "status shows the set in the human format" sh -c "'$shell' '$tool' status | grep -q '1 changed'"

# --- remove: each of these must block, and must leave everything in place
check "remove refuses a modified file" refuses worktree_set remove cas-1
git -C "$set_directory/ui" checkout -q file.txt
echo new >"$set_directory/ui/untracked.txt"
check "remove refuses an untracked file" refuses worktree_set remove cas-1
rm "$set_directory/ui/untracked.txt"
echo notes >"$set_directory/notes.txt"
check "remove refuses a file in the set directory that is not in a worktree" refuses worktree_set remove cas-1
rm "$set_directory/notes.txt"
git -C "$set_directory/lambdas" checkout -q --detach
(cd "$set_directory/lambdas" && echo c >>file.txt && git commit -qam "on no branch")
check "remove refuses a detached HEAD with commits on no branch" refuses worktree_set remove cas-1
git -C "$set_directory/lambdas" checkout -q cas-1
git -C "$root/lambdas" worktree unlock "$set_directory/lambdas"
git -C "$root/lambdas" worktree lock --reason "mine" "$set_directory/lambdas"
check "remove refuses a worktree that another owner locked" refuses worktree_set remove cas-1
git -C "$root/lambdas" worktree unlock "$set_directory/lambdas"
check "after the refusals each worktree still exists" test -e "$set_directory/ui/file.txt" -a -e "$set_directory/bridge/file.txt" -a -e "$set_directory/lambdas/file.txt"

# --- remove: success
mkdir "$set_directory/ui/node_modules" && echo x >"$set_directory/ui/node_modules/x.js"
echo SECRET=changed >"$set_directory/ui/.env.local" # ignored files do not block: the rule is the same as for git worktree remove
(cd "$set_directory/bridge" && echo c >>file.txt && git commit -qam "local only")
(cd "$set_directory/lambdas" && echo c >>file.txt && git commit -qam "pushed" && git push -q origin cas-1 2>/dev/null)
check "remove succeeds from inside the set when nothing can be lost" sh -c "cd '$set_directory/ui' && '$shell' '$tool' remove"
check "remove deletes the set directory" test ! -e "$set_directory"
check "remove leaves no worktree record" test "$(git -C "$root/ui" worktree list | wc -l | tr -d ' ')" = 1
check "a branch with a commit on no remote is kept" git -C "$root/bridge" show-ref --verify --quiet refs/heads/cas-1
check "a branch with no commits of its own is deleted" refuses git -C "$root/ui" show-ref --verify --quiet refs/heads/cas-1
check "a pushed branch is deleted locally" refuses git -C "$root/lambdas" show-ref --verify --quiet refs/heads/cas-1
check "the main checkout and its ignored file are not touched" test "$(cat "$root/ui/.env.local")" = SECRET=1

# --- new again resumes the kept branch
worktree_set new cas-1 bridge >/dev/null 2>&1
check "new on a kept branch resumes its commits" test "$(git -C "$set_directory/bridge" log -1 --format=%s)" = "local only"

# --- branch names with a slash
output=$(worktree_set new --from main feature/cas-3 ui 2>/dev/null)
check "a slash in the branch name becomes a dash in the directory name" test "$output" = "$root/.worktrees/feature-cas-3"
check "the branch keeps its full name" test "$(git -C "$output/ui" branch --show-current)" = feature/cas-3
check "remove accepts the branch name" worktree_set remove feature/cas-3

# --- an empty set, then add from inside it
empty=$(worktree_set new cas-4 2>/dev/null)
check "new without repositories makes an empty set" test -d "$empty" -a -z "$(find "$empty" -mindepth 1 -maxdepth 1 -type d)"
check "add from inside the set adds a repository on the set branch" \
  sh -c "cd '$empty' && '$shell' '$tool' add ui && test \"\$(git -C ui branch --show-current)\" = cas-4"
check "add outside a set is refused" refuses worktree_set add bridge

# --- a branch that was merged with a squash is deleted
(cd "$empty/ui" && echo feature >>file.txt && git commit -qam "feature work" && echo more >>file.txt && git commit -qam "more work")
(cd "$root/ui" && git fetch -q origin && git checkout -q --detach origin/main && git merge -q --squash cas-4 >/dev/null 2>&1 && git commit -qm "squash of cas-4" && git push -q origin HEAD:main && git checkout -q main)
check "remove succeeds for the squash-merged set" worktree_set remove cas-4
check "a branch whose changes are in the default branch is deleted" refuses git -C "$root/ui" show-ref --verify --quiet refs/heads/cas-4

# --- remove --merged removes only the sets that are merged, clean, and not new
worktree_set new cas-5 lambdas >/dev/null 2>&1
echo draft >"$root/.worktrees/cas-5/lambdas/notes.txt"
worktree_set new cas-6 ui >/dev/null 2>&1
(cd "$root/.worktrees/cas-6/ui" && echo open >>file.txt && git commit -qam "open work" && git push -q origin cas-6 2>/dev/null)
worktree_set new cas-7 ui lambdas >/dev/null 2>&1
(cd "$root/.worktrees/cas-7/ui" && echo finished >>file.txt && git commit -qam "finished work")
(cd "$root/ui" && git checkout -q --detach origin/main && git merge -q --squash cas-7 >/dev/null 2>&1 && git commit -qm "squash of cas-7" && git push -q origin HEAD:main && git checkout -q main)
worktree_set new cas-8 lambdas >/dev/null 2>&1
git -C "$root/ui" worktree add -q --detach "$root/.worktrees/plain" >/dev/null 2>&1
touch -t 202001010000 "$root"/.worktrees/cas-[1567] "$root/.worktrees/plain"
check "remove --merged succeeds" worktree_set remove --merged
check "remove --merged keeps a merged set that has a file that is not committed" test -e "$root/.worktrees/cas-5/lambdas/notes.txt"
check "remove --merged keeps a pushed set that is not merged" test -e "$root/.worktrees/cas-6/ui/file.txt"
check "remove --merged removes a merged set after an earlier refusal" test ! -e "$root/.worktrees/cas-7"
check "remove --merged keeps a set with a commit on no remote" test -e "$root/.worktrees/cas-1/bridge/file.txt"
check "remove --merged keeps a directory that is itself a worktree" test -e "$root/.worktrees/plain/file.txt"
check "remove --merged keeps a set that is less than one day old" test -e "$root/.worktrees/cas-8/lambdas/file.txt"
touch -t 202001010000 "$root/.worktrees/cas-8"
worktree_set remove --merged >/dev/null 2>&1
check "remove --merged removes the same set when it is one day old" test ! -e "$root/.worktrees/cas-8"

# --- root discovery does not go above the directory that holds the repositories
check "a directory above the root is not taken as a root" sh -c "cd '$sandbox' && ! '$shell' '$tool' status"

if [ "$failures" -eq 0 ]; then
  echo "all tests passed"
else
  echo "$failures test(s) failed"
  exit 1
fi
