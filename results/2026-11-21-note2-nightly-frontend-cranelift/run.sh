#!/usr/bin/env bash
# run.sh CFG SUBCMD: cargo nightly numa das configurações, com target próprio.
#   fe1 = front-end sequencial (como no stable) · fe2 = padrão do nightly desde 2026-11-14 (2 threads)
#   fe4 = front-end com 4 threads · cl2 = back-end Cranelift com o front-end padrão
# A contagem de threads vai por --config em target.<triplo>.rustflags porque esse array se soma ao
# do projeto (o Switchyard tem rustflags próprios); RUSTFLAGS no ambiente os substituiria.
# Flag: --jobs-frontend, conforme blog.rust-lang.org/2026/11/16/enabling-parallel-frontend-on-nightly.
set -euo pipefail
cfg=$1 sub=$2
pre=()
case $cfg in
  fe1|fe4) pre+=(--config "target.x86_64-unknown-linux-gnu.rustflags=[\"-Zunstable-options\",\"--jobs-frontend=${cfg#fe}\"]") ;;
  cl2) export CARGO_PROFILE_DEV_CODEGEN_BACKEND=cranelift; pre+=(-Zcodegen-backend) ;;
  fe2) ;;
  *) echo "run.sh: configuração desconhecida: '$cfg' (esperado fe1, fe2, fe4 ou cl2)" >&2; exit 64 ;;
esac
export CARGO_TARGET_DIR="$TGT/$sub-$cfg"
exec cargo +nightly "${pre[@]}" "$sub" -q
