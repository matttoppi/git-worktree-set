#!/usr/bin/env bash
# par needs Python 3.12 or later, so uv installs it with a managed Python. par is
# pinned to a commit of https://github.com/coplane/par (version 0.2.2; the
# repository has no tags).
set -euo pipefail
commit=7416a80726ec517d4cdfaa443e80605fc3b6a225
command -v uv >/dev/null || pipx install uv
uv tool install --python 3.12 "git+https://github.com/coplane/par@$commit"
echo "$(par --version) (commit $commit)"
