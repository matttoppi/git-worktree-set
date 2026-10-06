# Adapter for worktree-flow (`flow`). The source repositories stay in <root>.
# Layout: <work>/workspaces/<name>/flow-config.json and .../<name>/<repository>.
# ~/.config/flow/config.json is global; setup points it at this case.
adapter_setup() {
  flow config set source-path "$ROOT" && flow config set dest-path "$WORK/workspaces"
}
adapter_create() {
  local name=$1 repository arguments=()
  shift
  for repository in "$@"; do arguments+=(--repo "$repository"); done
  flow create "$name" "${arguments[@]}" --from main
}
adapter_path() { printf '%s/workspaces/%s/%s' "$WORK" "$1" "$2"; }
adapter_dir() { printf '%s/workspaces/%s' "$WORK" "$1"; }
# The prompts of flow need a terminal. expect runs flow on a pseudo-terminal,
# selects each offered workspace, and answers "y" to the confirmation. Each
# prompt is answered once, because flow draws a prompt again after a key press.
run_on_terminal() {
  expect -f - -- "$@" <<'EXPECT'
set timeout 120
set selected 0
set confirmed 0
spawn -noecho {*}$argv
expect {
  -re {Select workspaces to prune} {
    if {!$selected} { send " \r"; set selected 1 }
    exp_continue
  }
  -re {\(y/N\)} {
    if {!$confirmed} { send "y\r"; set confirmed 1 }
    exp_continue
  }
  eof
}
exit [lindex [wait] 3]
EXPECT
}
adapter_remove() { run_on_terminal flow drop "$1"; }
# `flow prune` is the bulk cleanup: it lists the workspaces that are clean,
# lets the user select them, and removes them. It has no age or merge filter.
adapter_cleanup_merged() { run_on_terminal flow prune; }
