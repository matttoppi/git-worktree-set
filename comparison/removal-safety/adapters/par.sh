# Adapter for par, multi-repository workspace mode. `par workspace start` makes
# <data>/par/workspaces/<hash>/<name>/<repository>/<name> and a detached tmux
# session, and records them in <data>/par/global_state.json. A per-case
# XDG_DATA_HOME keeps that state file apart between cases.
export XDG_DATA_HOME="$WORK/data"
adapter_setup() { :; }
adapter_create() {
  local name=$1
  shift
  (IFS=,; par workspace start "$name" --repos "$*")
}
adapter_path() {
  jq -r --arg name "$1" --arg repository "$2" \
    '.sessions[$name].workspace_repos[] | select(.repo_name == $repository) | .worktree_path' \
    "$XDG_DATA_HOME/par/global_state.json"
}
adapter_dir() {
  jq -r --arg name "$1" '.sessions[$name].repository_path' "$XDG_DATA_HOME/par/global_state.json"
}
adapter_remove() { par rm "$1"; }
# par has no cleanup command for merged or stale work (`par rm all` removes
# every session), so adapter_cleanup_merged keeps the default.
