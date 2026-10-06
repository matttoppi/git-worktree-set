# Adapter for brunch. brunch finds canonical clones only in a ghq-style tree,
# <root>/<forge>/<org>/<repo>, so setup moves the clones to
# <work>/clones/github.com/test/<repo> and names that root in the config file.
# Layout: <root>/<name>/brunch.toml and <root>/<name>/<repository>.
# Per-case XDG directories keep config and archives apart between cases.
export XDG_CONFIG_HOME="$WORK/config" XDG_DATA_HOME="$WORK/data"
adapter_setup() {
  mkdir -p "$WORK/clones/github.com/test" "$XDG_CONFIG_HOME/brunch" &&
    mv "$ROOT/api" "$ROOT/web" "$WORK/clones/github.com/test/" &&
    printf 'root = "%s/clones"\n' "$WORK" >"$XDG_CONFIG_HOME/brunch/config.toml"
}
adapter_main() { printf '%s/clones/github.com/test/%s' "$WORK" "$1"; }
adapter_create() { # `brunch init`, then one `brunch add` for each repository.
  local name=$1 repository
  shift
  brunch init "$name" -p "$ROOT" || return
  for repository in "$@"; do
    brunch add "test/$repository" -w "$ROOT/$name" || return
  done
}
adapter_path() { printf '%s/%s/%s' "$ROOT" "$1" "$2"; }
adapter_dir() { printf '%s/%s' "$ROOT" "$1"; }
adapter_remove() { brunch rm -w "$ROOT/$1"; }
# brunch has no bulk cleanup command (`fsck --fix` only prunes stale worktree
# records), so adapter_cleanup_merged keeps the default.
