#!/usr/bin/env bash
# Segunda rodada: Cranelift com aws-lc-rs >= 1.18.2 (a 1.17/1.18.1 quebra o link no Cranelift,
# aws/aws-lc-rs#1231) e rebuild de uma linha com sync antes de cada medida.
# O lock muda só no aws-lc-rs/aws-lc-sys, e as duas configurações comparadas usam o mesmo lock.
set -uo pipefail
B=$(cd "$(dirname "$0")" && pwd)
R=$B/results-fe2; mkdir -p "$R"
export TGT=$B/targets2 PATH=$HOME/.cargo/bin:$PATH
CSV=$R/clean.csv
[ -f "$CSV" ] || echo "project,metric,cfg,run,seconds,maxrss_kb,rc" > "$CSV"
declare -A EDIT=([serverust]=serverust-core/src/config.rs [switchyard]=crates/libsy/src/observability.rs)
for p in serverust switchyard; do
  cd "$B/projects/$p" || exit 1
  cargo +nightly update -p aws-lc-rs 2>&1 | grep -i "updating\|locking" | tee "$R/lock-$p.txt"
  for run in 1 2 3; do
    for cfg in fe2 cl2; do
      grep -q "^$p,build,$cfg,$run," "$CSV" && continue
      rm -rf "$TGT/build-$cfg"
      /usr/bin/time -o "$R/.t" -f '%e %M %x' "$B/run.sh" $cfg build > "$R/$p-build-$cfg.log" 2>&1
      read -r s kb rc < <(tail -1 "$R/.t")
      echo "$p,build,$cfg,$run,$s,$kb,$rc" | tee -a "$CSV"
    done
  done
  cfgs="fe2 cl2"; [ $p = switchyard ] && cfgs="fe1 fe2 fe4 cl2"
  for cfg in $cfgs; do
    out=$R/incr-$p-$cfg.json
    [ -f "$out" ] && continue
    [ -d "$TGT/build-$cfg" ] || "$B/run.sh" $cfg build > "$R/$p-warm-$cfg.log" 2>&1 || { echo "pula incr $p $cfg: build falhou"; continue; }
    hyperfine -N --style basic --runs 20 --warmup 2 --export-json "$out" \
      --prepare "$B/edit-sync.sh $B/projects/$p/${EDIT[$p]}" \
      -n "$cfg" "$B/run.sh $cfg build" 2>&1 | tail -3
  done
  rm -rf "$TGT"
done
echo "[bench2 fim] $(date -Is)"
