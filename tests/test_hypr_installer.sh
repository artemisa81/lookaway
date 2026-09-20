#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 artemisa81

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export LOOKAWAY_HYPR_RULE_PATH="$tmp/lookaway.lua"

"$root/bin/lookaway-hypr" install
grep -Fqx -- '-- LookAway-managed: io.github.artemisa81.lookaway' "$LOOKAWAY_HYPR_RULE_PATH"

printf '\n-- local edit\n' >> "$LOOKAWAY_HYPR_RULE_PATH"
"$root/bin/lookaway-hypr" install
test -f "$LOOKAWAY_HYPR_RULE_PATH.lookaway-backup"
"$root/bin/lookaway-hypr" uninstall
test ! -e "$LOOKAWAY_HYPR_RULE_PATH"
shopt -s nullglob
backups=("$LOOKAWAY_HYPR_RULE_PATH.backup."*)
test "${#backups[@]}" -ge 1

printf 'unowned config\n' > "$LOOKAWAY_HYPR_RULE_PATH"
if "$root/bin/lookaway-hypr" install >/dev/null 2>&1; then
  printf 'installer overwrote an unowned config\n' >&2
  exit 1
fi

printf 'hypr installer tests passed\n'
