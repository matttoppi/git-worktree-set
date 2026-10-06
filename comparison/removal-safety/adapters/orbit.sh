# Adapter for Orbit. Main clones live in <root>/.repos/<repository>; a
# workspace is <root>/<name>/<repository> on branch ws/<name>/main.
# Orbit has no command that removes one whole workspace directly: the user
# marks it with `orbit done` in the workspace, then runs `orbit prune <name>`
# from the root. `orbit remove <repository>` removes only one worktree.
adapter_setup() {
  local repository
  for repository in api web; do
    orbit clone "$WORK/remotes/$repository.git" || return
  done
  # The pool replaces the plain clones. Orbit would see them as workspaces.
  rm -rf "$ROOT/api" "$ROOT/web"
}
adapter_main() { printf '%s/.repos/%s' "$ROOT" "$1"; }
adapter_create() {
  local name=$1 repository
  shift
  orbit new "$name" --name "$name" || return
  for repository in "$@"; do
    (cd "$ROOT/$name" && orbit add "$repository") || return
  done
}
adapter_path() { printf '%s/%s/%s' "$ROOT" "$1" "$2"; }
adapter_dir() { printf '%s/%s' "$ROOT" "$1"; }
adapter_remove() { (cd "$ROOT/$1" && orbit "done") && orbit prune "$1"; }
# Bulk form: `orbit prune` with no name reclaims each workspace marked done.
adapter_cleanup_merged() { (cd "$ROOT/$1" && orbit "done") && orbit prune; }
