#!/usr/bin/env bash
# wtp, pinned to release v0.1.1 (commit 90a3149), built from source as documented.
# The release binaries need glibc 2.39 and Debian bookworm has 2.36, so build with
# rustup (Rust 1.90 or later; Debian has 1.63). The workspace member wtp-gui pulls
# the Zed repository through Git dependencies; the build drops that member only.
# The CLI source is unchanged.
set -euo pipefail
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y -q --profile minimal
# shellcheck source=/dev/null
source "$HOME/.cargo/env"
source_directory=$(mktemp -d)
git clone -q --depth 1 --branch v0.1.1 https://github.com/eddix/wtp "$source_directory"
sed -i 's/members = \[.*\]/members = ["wtp-core", "wtp-cli", "wtp-derive"]/' "$source_directory/Cargo.toml"
cargo install -q --path "$source_directory/wtp-cli" --root /usr/local
rm -rf "$source_directory" "$HOME/.cargo/registry" "$HOME/.cargo/git"
wtp --version
