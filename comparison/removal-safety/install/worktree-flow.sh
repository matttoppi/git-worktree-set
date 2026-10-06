#!/usr/bin/env bash
# worktree-flow 0.0.26 (latest release that is not a prerelease) from npm. Its
# dependencies need a newer Node than Debian's Node 18, so this script installs
# Node 22 in /opt and a `flow` wrapper that uses it.
set -euo pipefail
version=0.0.26
node_version=v22.20.0
case $(dpkg --print-architecture) in amd64) arch=x64 ;; arm64) arch=arm64 ;; *) exit 1 ;; esac
node_dir=/opt/node-$node_version-linux-$arch
curl -fsSL "https://nodejs.org/dist/$node_version/node-$node_version-linux-$arch.tar.gz" | tar -xz -C /opt
PATH=$node_dir/bin:$PATH npm install -g --prefix /opt/worktree-flow "worktree-flow@$version"
printf '#!/bin/sh\nexec %s/bin/node /opt/worktree-flow/lib/node_modules/worktree-flow/dist/cli.js "$@"\n' \
  "$node_dir" >/usr/local/bin/flow
chmod +x /usr/local/bin/flow
# `flow --version` prints a fixed 0.1.0, so read the installed package version.
echo "worktree-flow: $(jq -r .version /opt/worktree-flow/lib/node_modules/worktree-flow/package.json) (Node $node_version)"
