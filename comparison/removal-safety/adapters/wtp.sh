# Adapter for wtp v0.1.1. It keeps its config in ~/.wtp, so each case gets its
# own HOME. Layout: ~/.wtp/workspaces/<name>/<repository>.
adapter_setup() {
  mkdir -p "$WORK/home"
  cp "$HOME/.gitconfig" "$WORK/home/" 2>/dev/null
  export HOME=$WORK/home
}
# `wtp create` makes the workspace; `wtp switch` from each repository adds a
# worktree on a new branch named after the workspace.
adapter_create() {
  local name=$1 repository
  shift
  wtp create "$name" || return
  for repository in "$@"; do
    (cd "$ROOT/$repository" && wtp switch "$name") || return
  done
}
adapter_path() { printf '%s/.wtp/workspaces/%s/%s' "$HOME" "$1" "$2"; }
adapter_dir() { printf '%s/.wtp/workspaces/%s' "$HOME" "$1"; }
# `wtp rm NAME` has no prompt; it refuses on dirty worktrees without --force.
adapter_remove() { wtp rm "$1"; }
# No bulk cleanup command. The default (n/a) applies.
