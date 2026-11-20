#!/usr/bin/env bash
# Mede debug = true (padrão do Cargo, como no Sussurro) contra line-tables-only com dependências sem debuginfo,
# no ciclo "mudei a crate base, recompila os testes". Mede também o tamanho de target/.
set -euo pipefail
L=$HOME/.cache/rust-lab
P=$L/sussurro
OUT=$L/debuginfo-sussurro.json
SLIM="--config $L/slim.toml"
EDIT="$L/edit.sh $P/src/paths.rs"
cd "$P"
for v in full slim; do
  extra=""; [ "$v" = slim ] && extra=$SLIM
  echo "== aquecendo $v"; date
  # shellcheck disable=SC2086 # extra são opções separadas de propósito
  env CARGO_TARGET_DIR="$L/target-dbg-$v" cargo test --no-run -q $extra 2>&1 | tail -3
  du -sh "$L/target-dbg-$v"
done
date
hyperfine -N --style basic --runs 5 --export-json "$OUT" \
  --prepare "$EDIT" --prepare "$EDIT" \
  -n full "env CARGO_TARGET_DIR=$L/target-dbg-full cargo test --no-run -q" \
  -n slim "env CARGO_TARGET_DIR=$L/target-dbg-slim cargo test --no-run -q $SLIM"
du -sh "$L"/target-dbg-full "$L"/target-dbg-slim
