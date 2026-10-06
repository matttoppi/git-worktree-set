# Adapter for Grove (`gw`) v1.1.18. Grove keeps its config and state in
# ~/.grove, so each case gets its own HOME. Layout:
# ~/.grove/workspaces/<name>/<repository>.
adapter_setup() {
  mkdir -p "$WORK/home"
  cp "$HOME/.gitconfig" "$WORK/home/" 2>/dev/null
  export HOME=$WORK/home
  gw init "$ROOT"
}
adapter_create() {
  local name=$1 repositories
  shift
  repositories=$(IFS=,; echo "$*")
  gw create "$name" --branch "$name" --repos "$repositories"
}
adapter_path() { printf '%s/.grove/workspaces/%s/%s' "$HOME" "$1" "$2"; }
adapter_dir() { printf '%s/.grove/workspaces/%s' "$HOME" "$1"; }
# `gw delete NAME` has no prompt and no --force option.
adapter_remove() { gw delete "$1"; }
# `gw prune --yes` deletes workspaces whose created_at is older than 7 days.
# Age the workspace in state.json as if a week had passed.
adapter_cleanup_merged() {
  local state=$HOME/.grove/state.json
  jq --arg name "$1" 'map(if .name == $name then .created_at = "2020-01-01T00:00:00.000000" else . end)' \
    "$state" >"$state.new" && mv "$state.new" "$state"
  gw prune --yes
}
