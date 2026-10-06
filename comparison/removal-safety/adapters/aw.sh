# Adapter for aw. `aw new -b <branch>` makes ../<root name>-<branch> with a
# worktree of every repository in the root. `aw rm` in the workspace removes it
# (no --force, no --branch). aw has no bulk cleanup of merged workspaces:
# `aw prune` only drops registry entries whose directory is already gone.
adapter_setup() { :; }
adapter_create() { aw new -b "$1"; }
adapter_dir() { printf '%s-%s' "$ROOT" "$1"; }
adapter_path() { printf '%s-%s/%s' "$ROOT" "$1" "$2"; }
adapter_remove() { (cd "$(adapter_dir "$1")" && aw rm); }
