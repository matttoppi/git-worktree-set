#!/usr/bin/env bash
# brunch is not on PyPI. Install it from a pinned commit of
# https://github.com/htzv/brunch. It needs Python 3.11 or later (Debian has 3.11).
set -euo pipefail
commit=c30c5b3f293ca9bd9ae91ccbdba00e25d194bcdf
pipx install "git+https://github.com/htzv/brunch@$commit"
echo "brunch: $(brunch --version) (commit $commit)"
