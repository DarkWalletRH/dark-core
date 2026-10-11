#!/usr/bin/env bash
# lib/dark-contracts holds verbatim copies of contracts/src (every file but DarkVault.sol, which src/
# replaces) from DarkWalletRH/dark-contracts at v1.0.4: the curve library, the key registry, the
# interfaces and the testnet token. This checks
# every file against that tag, so the copies cannot drift from the published sources.
set -euo pipefail
TAG=v1.0.4
COMMIT=1ffe0d46c38603b612b165c54de403a5002a0fa6
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git init -q "$tmp/dc"
git -C "$tmp/dc" fetch -q --depth 1 https://github.com/DarkWalletRH/dark-contracts "refs/tags/$TAG"
git -C "$tmp/dc" -c advice.detachedHead=false checkout -q FETCH_HEAD
[ "$(git -C "$tmp/dc" rev-parse HEAD)" = "$COMMIT" ] || { echo "dark-contracts $TAG is not $COMMIT" >&2; exit 1; }
n=0
while IFS= read -r f; do
  cmp -s "lib/dark-contracts/$f" "$tmp/dc/contracts/src/$f" || { echo "differs from dark-contracts $TAG: lib/dark-contracts/$f" >&2; exit 1; }
  n=$((n + 1))
done < <(cd lib/dark-contracts && find . -name '*.sol' | sed 's|^\./||' | sort)
echo "lib/dark-contracts: $n files identical to DarkWalletRH/dark-contracts $TAG ($COMMIT)"
