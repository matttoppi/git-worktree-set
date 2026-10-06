#!/usr/bin/env bash
# git-worktree-manager (nanasess): Bash 4, installed as the README says (a clone
# and a `worktree` link on PATH). Pinned to the latest commit, v1.0.0-11.
set -euo pipefail
commit=65eade57c329c2e9fb47165323f199d40674f784
git clone -q https://github.com/nanasess/git-worktree-manager.git /opt/git-worktree-manager
git -C /opt/git-worktree-manager checkout -q "$commit"
ln -s /opt/git-worktree-manager/worktree /usr/local/bin/worktree
# The script reports v0.1.0: its VERSION variable was not changed for v1.0.0.
echo "git-worktree-manager: $(worktree --version), commit $commit"
