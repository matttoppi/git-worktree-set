#!/usr/bin/env bash
# spawnpoint, pinned to release v0.12.0 (commit 8dac476), with the documented `go install`.
# `go install` provides only the `spawnpoint` command, not the `sp` alias.
set -euo pipefail
go install github.com/mihirgupta0900/spawnpoint@v0.12.0
spawnpoint --version
