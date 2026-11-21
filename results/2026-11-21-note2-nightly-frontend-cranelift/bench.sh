#!/usr/bin/env bash
# Mede front-end paralelo e Cranelift em projetos reais: check e build do zero (configurações
# alternadas a cada rodada, contra aquecimento do notebook) e rebuild depois de mudar uma linha.
set -uo pipefail
B=$(cd "$(dirname "$0")" && pwd)
R=$B/results-fe; mkdir -p "$R"
export TGT=$B/targets PATH=$HOME/.cargo/bin:$PATH
CSV=$R/clean.csv
[ -f "$CSV" ] || echo "project,metric,cfg,run,seconds,maxrss_kb,rc" > "$CSV"
{ date -Is; nproc; lscpu | grep 'Model name'; rustc +nightly -vV; cargo +nightly -V; } > "$R/env.txt"
declare -A EDIT=(
  [context-engine]=src/shared/config.rs
  [serverust]=serverust-core/src/config.rs
  [switchyard]=crates/libsy/src/observability.rs
)
RUNS=3
for p in context-engine serverust switchyard; do
  cd "$B/projects/$p" || exit 1
  echo "== $p $(date -Is)"
  cargo +nightly fetch -q || { echo "fetch falhou em $p"; continue; }
  for metric in check build; do
    cfgs="fe1 fe2 fe4"; [ $metric = build ] && cfgs="fe1 fe2 fe4 cl2"
    # Cranelift do serverust e do Switchyard: em bench2.sh, com aws-lc-rs >= 1.18.2
    [ $p != context-engine ] && cfgs=${cfgs% cl2}
    for run in $(seq $RUNS); do
      for cfg in $cfgs; do
        grep -q "^$p,$metric,$cfg,$run," "$CSV" && continue
        rm -rf "$TGT/$metric-$cfg"
        log=$R/$p-$metric-$cfg.log
        /usr/bin/time -o "$R/.t" -f '%e %M %x' "$B/run.sh" $cfg $metric > "$log" 2>&1
        read -r s kb rc < <(tail -1 "$R/.t")
        echo "$p,$metric,$cfg,$run,$s,$kb,$rc" | tee -a "$CSV"
      done
    done
  done
  # rebuild incremental: os targets do último build do zero estão quentes
  for cfg in fe1 fe2 fe4 cl2; do
    out=$R/incr-$p-$cfg.json
    [ -f "$out" ] && continue
    grep -q "^$p,build,$cfg,.*,0$" "$CSV" || { echo "pula incr $p $cfg: build falhou"; continue; }
    hyperfine -N --style basic --runs 20 --warmup 2 --export-json "$out" \
      --prepare "$B/edit-sync.sh $B/projects/$p/${EDIT[$p]}" \
      -n "$cfg" "$B/run.sh $cfg build" 2>&1 | tail -4
  done
  du -sh "$TGT"/* > "$R/du-$p.txt" 2>/dev/null
  rm -rf "$TGT"
done
echo "[bench fim] $(date -Is)"
