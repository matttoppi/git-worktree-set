#!/usr/bin/env bash
# Grove (`gw`), pinned to release v1.1.18 (commit 777e1fd), with the documented `go install`.
set -euo pipefail
go install github.com/nicksenap/grove/cmd/gw@v1.1.18
gw --version
