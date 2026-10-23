#!/usr/bin/env bash
# Writes THIRD-PARTY-NOTICES.txt: the license texts of every crate in
# Cargo.lock that the prebuilds compile in, for any target, using the
# cargo-about config and template next to this script. Proc-macro crates are
# listed too, though they aren't linked in; cargo-about can't leave them out.
# CI fails if the committed file is stale.
#
# Needs cargo-about: cargo install cargo-about --version 0.9.2 --locked --features cli
#
# Usage: scripts/notices.sh

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

# --fail stops on a crate whose license can't be identified. Needs the network:
# scripts/about.toml fetches the napi-rs license from GitHub.
cargo about generate --locked --fail -c scripts/about.toml scripts/about.hbs \
  -o THIRD-PARTY-NOTICES.txt

# A clarification that no longer matches only warns and falls back to the bare
# SPDX text, which has no copyright line.
if grep -q '<year> <copyright holders>' THIRD-PARTY-NOTICES.txt; then
  echo "THIRD-PARTY-NOTICES.txt has a placeholder copyright line; check the warnings above and scripts/about.toml" >&2
  exit 1
fi
