#!/usr/bin/env bash
# Orbit (orbcli): one Bash file. install.sh from a local checkout copies the
# runtime to ~/.local/bin and uses no network. Pinned to the latest commit,
# v0.2.0-1 (adds `orbit remove <repo>`).
set -euo pipefail
commit=4673a1e0a89b35aa50de17f4186693d4a4e09eca
git clone -q https://github.com/orbcli/orbit.git /opt/orbit
git -C /opt/orbit checkout -q "$commit"
/opt/orbit/install.sh >/dev/null
echo "orbit: $(orbit version), commit $commit"
