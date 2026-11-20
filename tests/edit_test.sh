#!/usr/bin/env bash
# O cenário "mudou 1 linha" tem de mudar uma linha em um arquivo só, em toda linguagem.
set -euo pipefail
LAB=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -r "$LAB/lab.sh" "$LAB/langs" "$tmp/"
"$tmp/lab.sh" gen 3 2 >/dev/null
fail=0
for d in "$tmp"/work/3x2/*; do
  cp -r "$d" "$d.antes"
  "$tmp/lab.sh" _edit "$d" x base
  changed=$(diff -rq "$d.antes" "$d" | wc -l || true)
  if [ "$changed" -ne 1 ]; then
    echo "FALHOU $(basename "$d"): mudou $changed arquivos, esperado 1"
    fail=1
  else
    echo "ok $(basename "$d")"
  fi
done
exit $fail
