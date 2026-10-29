#!/usr/bin/env bash
# Copia o bundle sintético DEMO-001 (tests/fixtures/bundle) para web/data/, que é gitignored.
# Uso, a partir da raiz do repositório:  web/scripts/use-fixture.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
src="$root/tests/fixtures/bundle"
dst="$root/web/data"
[ -f "$src/latest.json" ] || { echo "fixture não encontrada em $src" >&2; exit 1; }
rm -rf "$dst"
mkdir -p "$dst"
cp -R "$src/." "$dst/"
echo "bundle DEMO-001 copiado para $dst"
