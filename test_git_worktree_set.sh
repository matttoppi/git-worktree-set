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

# fails_with <text> <command...>: the command fails and its output contains the text.
fails_with() {
  local text=$1 output
  shift
  ! output=$("$@" 2>&1) && printf '%s\n' "$output" | grep -qF -- "$text"
}

# Make the set at $1 look idle for more than one day: the set directory, and the
# index and HEAD log of each worktree in it.
age_set() {
  local worktree git_directory
  touch -t 202001010000 "$1"
  for worktree in "$1"/*/; do
    git_directory=$(git -C "$worktree" rev-parse --absolute-git-dir 2>/dev/null) || continue
    touch -c -t 202001010000 "$git_directory/index" "$git_directory/logs/HEAD"
  done
}

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

# --- new again resumes the kept branch, and the pushed branch that remove deleted
worktree_set new cas-1 bridge lambdas >/dev/null 2>&1
check "new on a kept branch resumes its commits" test "$(git -C "$set_directory/bridge" log -1 --format=%s)" = "local only"
check "new on a branch that is only on origin resumes its commits" test "$(git -C "$set_directory/lambdas" log -1 --format=%s)" = "pushed"

# --- --from uses the local branch when it is ahead of origin, and options can follow the name
git -C "$root/ui" branch -q release origin/main
git -C "$root/ui" push -q origin release 2>/dev/null
git -C "$root/ui" branch -qf release "$(git -C "$root/ui" commit-tree -p release -m "local release work" "release^{tree}")"
output=$(worktree_set new cas-2 ui --from release 2>/dev/null)
check "an option after the name and the repositories is accepted" test "$output" = "$root/.worktrees/cas-2"
check "--from uses the local branch when it contains origin and has more commits" \
  test "$(git -C "$output/ui" log -1 --format=%s)" = "local release work"
worktree_set remove cas-2 >/dev/null 2>&1

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
for set in "$root"/.worktrees/cas-[1567] "$root/.worktrees/plain"; do age_set "$set"; done
touch -t 202001010000 "$root/.worktrees/cas-8" # only the set directory: its worktree is still active
check "remove --merged --dry-run reports a set that it would remove" \
  sh -c "'$shell' '$tool' remove --merged --dry-run 2>&1 | grep -q 'cas-7: would be removed'"
check "remove --merged --dry-run removes nothing" test -e "$root/.worktrees/cas-7/ui/file.txt"
check "remove --merged succeeds" worktree_set remove --merged
check "remove --merged keeps a merged set that has a file that is not committed" test -e "$root/.worktrees/cas-5/lambdas/notes.txt"
check "remove --merged keeps a pushed set that is not merged" test -e "$root/.worktrees/cas-6/ui/file.txt"
check "remove --merged removes a merged set after an earlier refusal" test ! -e "$root/.worktrees/cas-7"
check "remove --merged keeps a set with a commit on no remote" test -e "$root/.worktrees/cas-1/bridge/file.txt"
check "remove --merged keeps a directory that is itself a worktree" test -e "$root/.worktrees/plain/file.txt"
check "remove --merged keeps a set with Git activity in the last day" test -e "$root/.worktrees/cas-8/lambdas/file.txt"
age_set "$root/.worktrees/cas-8"
(cd "$(dirname "$tool")" && GIT_WORKTREE_SET_ROOT=$root "$shell" "./$(basename "$tool")" remove --merged >/dev/null 2>&1)
check "remove --merged, run by a relative path, removes the same set after one idle day" test ! -e "$root/.worktrees/cas-8"

# --- remove --dry-run
check "remove --dry-run succeeds for a set that remove would remove" worktree_set remove --dry-run cas-6
check "remove --dry-run changes nothing" test -e "$root/.worktrees/cas-6/ui/file.txt"
check "remove --dry-run fails for a set that remove would refuse" refuses worktree_set remove cas-5 --dry-run

# --- a directory in .worktrees that is itself a worktree is not a set
check "status marks a directory that is itself a worktree as not a set" \
  sh -c "'$shell' '$tool' status plain | grep -q 'a single worktree, not a set'"
check "new refuses to add to a directory that is itself a worktree" refuses worktree_set new plain bridge
check "remove refuses a directory that is itself a worktree" refuses worktree_set remove plain

# --- status tells where the branch of a detached set worktree is checked out
detached=$(worktree_set new cas-9 bridge 2>/dev/null)
git -C "$detached/bridge" switch -q --detach
git -C "$root/bridge" switch -q cas-9
check "status shows where the branch of a detached worktree is checked out" \
  sh -c "'$shell' '$tool' status cas-9 | grep -qF 'cas-9 is checked out at $root/bridge'"
git -C "$root/bridge" switch -q main
worktree_set remove cas-9 >/dev/null 2>&1

# --- a repository can name its default branch
git -C "$root/bridge" branch -q integration origin/main
git -C "$root/bridge" config worktree-set.defaultBranch integration
integration=$(worktree_set new cas-10 bridge 2>/dev/null)
(cd "$integration/bridge" && echo integrated >>file.txt && git commit -qam "integrated work")
git -C "$root/bridge" branch -qf integration cas-10
age_set "$integration"
worktree_set remove --merged >/dev/null 2>&1
check "remove --merged removes a set that is merged into the configured default branch" test ! -e "$integration"
output=$(worktree_set new cas-11 bridge 2>/dev/null)
check "new starts from the configured default branch" test "$(git -C "$output/bridge" log -1 --format=%s)" = "integrated work"
git -C "$root/bridge" config --unset worktree-set.defaultBranch

# --- conditions that must stop removal before the first worktree is removed
guarded=$(worktree_set new cas-14 ui 2>/dev/null)
git clone -q "$sandbox/remotes/bridge.git" "$guarded/zz-clone" 2>/dev/null
check "remove refuses a set that holds an independent clone" refuses worktree_set remove cas-14
check "after that refusal the worktree of the set still exists" test -e "$guarded/ui/file.txt"
mv "$guarded/zz-clone" "$HOME/independent-clone"
index=$(git -C "$guarded/ui" rev-parse --git-path index)
echo damaged >"$index"
check "remove refuses when git status fails" refuses worktree_set remove cas-14
rm "$index" && git -C "$guarded/ui" reset -q

# --- remove deletes only the branch of the set
other=$(worktree_set new cas-15 lambdas 2>/dev/null)
git -C "$other/lambdas" switch -q -c other-branch
worktree_set remove cas-15 >/dev/null 2>&1
check "remove keeps a branch that is not the branch of the set" git -C "$root/lambdas" show-ref --verify --quiet refs/heads/other-branch

# --- a set folder that was deleted by hand
deleted=$(worktree_set new cas-13 lambdas 2>/dev/null)
mv "$deleted" "$sandbox/deleted-set"
check "remove cleans the records of a set folder that was deleted by hand" worktree_set remove cas-13
check "new works again after that" worktree_set new cas-13 lambdas

# --- a failing setup hook prints a warning and does not fail new
mv "$root/.worktree-set-setup" "$root/.worktree-set-setup.saved"
printf '#!/bin/sh\nexit 1\n' >"$root/.worktree-set-setup" && chmod +x "$root/.worktree-set-setup"
output=$(worktree_set new cas-12 ui 2>/dev/null)
check "a failing setup hook leaves new successful, with the set directory on stdout" test "$output" = "$root/.worktrees/cas-12"
mv "$root/.worktree-set-setup.saved" "$root/.worktree-set-setup"

# --- root discovery does not go above the directory that holds the repositories
check "a directory above the root is not taken as a root" sh -c "cd '$sandbox' && ! '$shell' '$tool' status"

# --- land: ui has golden-hour checked out in its main checkout; in bridge,
# golden-hour is checked out nowhere and gets a commit after the set starts.
for repository in ui bridge; do git -C "$root/$repository" branch -q golden-hour origin/main; done
git -C "$root/ui" push -q origin golden-hour 2>/dev/null
git -C "$root/ui" switch -q golden-hour
landing=$(worktree_set new --from golden-hour cas-20 ui bridge 2>/dev/null)
(cd "$landing/ui" && echo landed-ui >>file.txt && git commit -qam "ui work")
(cd "$landing/bridge" && echo landed-bridge >new.txt && git add new.txt && git commit -qm "bridge work")
git -C "$root/bridge" branch -qf golden-hour "$(git -C "$root/bridge" commit-tree -p golden-hour -m "other landing" "golden-hour^{tree}")"
ui_target=$(git -C "$root/ui" rev-parse golden-hour)
bridge_target=$(git -C "$root/bridge" rev-parse golden-hour)
expected="bridge: would land in golden-hour as a merge commit on $(git -C "$root/bridge" rev-parse --short golden-hour) with 1 commit
ui: would land in golden-hour as a fast-forward from $(git -C "$root/ui" rev-parse --short golden-hour) with 1 commit; would update the checkout at $root/ui"
check "land --dry-run succeeds and prints what it would do in each repository" \
  test "$(worktree_set land --into golden-hour --dry-run cas-20 2>/dev/null; echo "exit $?")" = "$expected
exit 0"
check "land --dry-run moves no branch" test "$(git -C "$root/ui" rev-parse golden-hour) $(git -C "$root/bridge" rev-parse golden-hour)" = "$ui_target $bridge_target"
check "land refuses main" fails_with "land refuses main" worktree_set land --into main cas-20
echo draft >"$landing/ui/draft.txt"
check "land refuses a worktree with a file that is not committed" fails_with "not committed: ?? draft.txt" worktree_set land --into golden-hour cas-20
check "after that refusal no repository of the set is landed" test "$(git -C "$root/bridge" rev-parse golden-hour)" = "$bridge_target"
rm "$landing/ui/draft.txt"
echo local >>"$root/ui/file.txt"
check "land refuses a change in the target checkout that the landing would overwrite" \
  fails_with "the checkout at $root/ui: Entry 'file.txt' not uptodate" worktree_set land --into golden-hour cas-20
git -C "$root/ui" checkout -q file.txt
echo note >"$root/ui/notes.txt"
output=$(worktree_set land --into golden-hour cas-20 2>/dev/null; echo "exit $?")
check "land fast-forwards a target that the set branch contains" test "$(git -C "$root/ui" rev-parse golden-hour)" = "$(git -C "$landing/ui" rev-parse HEAD)"
check "land updates the files of the checkout that has the target branch" test "$(tail -n 1 "$root/ui/file.txt")" = landed-ui
check "land keeps a change in that checkout that the landing does not touch" test "$(cat "$root/ui/notes.txt")" = note
check "land makes a merge commit when the target has commits that the set branch does not have" \
  test "$(git -C "$root/bridge" log -1 --format='%s %P' golden-hour)" = "Merge branch 'cas-20' into golden-hour $bridge_target $(git -C "$landing/bridge" rev-parse HEAD)"
check "land leaves the files of a main checkout on another branch" test ! -e "$root/bridge/new.txt"
expected="bridge: landed in golden-hour as $(git -C "$root/bridge" rev-parse --short golden-hour), a merge commit on $(git -C "$root/bridge" rev-parse --short "$bridge_target") with 1 commit
ui: landed in golden-hour as $(git -C "$root/ui" rev-parse --short golden-hour), a fast-forward from $(git -C "$root/ui" rev-parse --short "$ui_target") with 1 commit; updated the checkout at $root/ui
exit 0"
check "land succeeds and prints one result line for each repository" test "$output" = "$expected"
check "land pushes nothing" test "$(git -C "$sandbox/remotes/ui.git" rev-parse golden-hour)" = "$ui_target"
ui_target=$(git -C "$root/ui" rev-parse golden-hour)
bridge_target=$(git -C "$root/bridge" rev-parse golden-hour)
check "land of a set that is landed changes nothing and says so" \
  test "$(worktree_set land --into golden-hour cas-20 2>/dev/null; echo "exit $?")" = "bridge: already in golden-hour; nothing changed
ui: already in golden-hour; nothing changed
exit 0"
check "after that land no branch moved" test "$(git -C "$root/ui" rev-parse golden-hour) $(git -C "$root/bridge" rev-parse golden-hour)" = "$ui_target $bridge_target"
conflict=$(worktree_set new --from golden-hour cas-21 ui 2>/dev/null)
(cd "$conflict/ui" && echo set-side >file.txt && git commit -qam "set side")
(cd "$root/ui" && echo target-side >file.txt && git commit -qam "target side")
check "land refuses a merge with a conflict" fails_with "merge conflict with golden-hour: file.txt" worktree_set land --into golden-hour cas-21
worktree_set new cas-22 lambdas >/dev/null 2>&1
check "land refuses a repository that has no local target branch" fails_with "no local branch golden-hour" worktree_set land --into golden-hour cas-22
git -C "$root/bridge" config worktree-set.defaultBranch golden-hour
configured=$(worktree_set new cas-23 bridge 2>/dev/null)
(cd "$configured/bridge" && echo configured >>file.txt && git commit -qam "configured work")
check "land without --into, from inside the set, lands into the configured default branch" \
  sh -c "cd '$configured/bridge' && '$shell' '$tool' land && test \"\$(git log -1 --format=%s golden-hour)\" = 'configured work'"
git -C "$root/bridge" config --unset worktree-set.defaultBranch
split=$(worktree_set new --from golden-hour cas-24 bridge 2>/dev/null)
(cd "$split/bridge" && mkdir directory && echo x >directory/x.txt && echo y >directory/y.txt && git add directory && git commit -qm "add a directory")
worktree_set land --into golden-hour cas-24 >/dev/null 2>&1
added=$(worktree_set new --from golden-hour cas-25 bridge 2>/dev/null)
(cd "$added/bridge" && echo z >directory/z.txt && git add directory && git commit -qm "add a file to the directory")
worktree_set land --into golden-hour cas-25 >/dev/null 2>&1
(cd "$split/bridge" && mkdir one two && git mv directory/x.txt one/ && git mv directory/y.txt two/ && git commit -qm "split the directory")
check "land refuses a conflict that names no file (a directory rename split)" \
  fails_with "merge conflict with golden-hour" worktree_set land --into golden-hour cas-24

if [ "$failures" -eq 0 ]; then
  echo "all tests passed"
else
  echo "$failures test(s) failed"
  exit 1
fi
