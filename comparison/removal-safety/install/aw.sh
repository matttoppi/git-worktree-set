#!/usr/bin/env bash
# aw (lldxflwb): Go. The documented `go install github.com/lldxflwb/aw@latest`
# cannot work: go.mod declares the module path github.com/anthropics/aw. So
# build from a clone. Pinned to the latest commit, v0.2.0-2. aw has no
# version command.
set -euo pipefail
commit=1a64f7feec4a0b1edd232f03afb687168a2c9b47
git clone -q https://github.com/lldxflwb/aw.git /opt/aw
git -C /opt/aw checkout -q "$commit"
(cd /opt/aw && go build -o /usr/local/bin/aw .)
echo "aw: commit $commit"
