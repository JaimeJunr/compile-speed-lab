#!/usr/bin/env bash
# Mede lld (padrão) contra wild no ciclo "mudei a crate base, recompila os testes" do serverust.
# Cada linker tem o próprio target: RUSTFLAGS diferente invalida o cache do outro.
set -euo pipefail
L=$HOME/.cache/rust-lab
P=$L/serverust
OUT=$L/linker-serverust.json
WILD="CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=clang CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS=-Clink-arg=--ld-path=wild"
EDIT="$L/edit.sh $P/serverust-core/src/lib.rs"
cd "$P"
for l in lld wild; do
  extra=""; [ "$l" = wild ] && extra=$WILD
  echo "== aquecendo $l"; date
  env CARGO_TARGET_DIR="$L/target-$l" $extra cargo test --workspace --no-run -q 2>&1 | tail -3
done
date
hyperfine -N --style basic --runs 5 --export-json "$OUT" \
  --prepare "$EDIT" --prepare "$EDIT" \
  -n lld "env CARGO_TARGET_DIR=$L/target-lld cargo test --workspace --no-run -q" \
  -n wild "env CARGO_TARGET_DIR=$L/target-wild $WILD cargo test --workspace --no-run -q"
du -sh "$L"/target-lld "$L"/target-wild
