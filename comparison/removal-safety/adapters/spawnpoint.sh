# Adapter for spawnpoint v0.12.0. It keeps its config in ~/.spawnpoint, so each
# case gets its own HOME. Layout: ~/.spawnpoint/workspaces/<branch>/<repository>.
adapter_setup() {
  mkdir -p "$WORK/home/.spawnpoint"
  cp "$HOME/.gitconfig" "$WORK/home/" 2>/dev/null
  export HOME=$WORK/home
  # Only scan_dirs is set; every other key keeps its default.
  printf "scan_dirs = ['%s']\n" "$ROOT" >"$HOME/.spawnpoint/config.toml"
}
adapter_create() {
  local name=$1 repositories
  shift
  repositories=$(IFS=,; echo "$*")
  spawnpoint create --no-input --repos "$repositories" --branch "$name"
}
adapter_path() { printf '%s/.spawnpoint/workspaces/%s/%s' "$HOME" "$1" "$2"; }
adapter_dir() { printf '%s/.spawnpoint/workspaces/%s' "$HOME" "$1"; }
# `spawnpoint cleanup` is the remove command. Without --no-input it opens a
# terminal picker. --no-input skips the final "Proceed?" prompt, which the
# harness answers "y" anyway, and requires a branch choice. --delete-branches
# is the default answer of the interactive "Delete branches from parent repos?"
# prompt and the choice in the README and agent skill examples.
adapter_remove() { spawnpoint cleanup --no-input --workspaces "$1" --delete-branches; }
# No bulk cleanup of merged or stale workspaces: `light-cleanup` deletes only
# reinstallable directories such as node_modules. The default (n/a) applies.
