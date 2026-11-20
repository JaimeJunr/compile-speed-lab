#!/usr/bin/env bash
# Laboratório de tempo de compilação: gera o mesmo programa em várias linguagens e mede
# build limpo, rebuild sem mudança (noop) e rebuild depois de mudar uma linha (incr).
#
#   ./lab.sh gen <módulos> <funções-por-módulo>   gera work/<M>x<F>/<linguagem>
#   ./lab.sh gen-multi <unidades> <funções>       gera work/multi-<M>x<F>: uma unidade de compilação
#                                                 por módulo, todas dependendo da base m0
#   ./lab.sh verify <tamanho>                     compila tudo e confere que todos imprimem o mesmo número
#   ./lab.sh run <tamanho> [variante...]          mede com hyperfine e grava em results/
#   ./lab.sh report <pasta-de-resultado>          tabela em Markdown
#   ./lab.sh variants                             lista as variantes disponíveis nesta máquina
set -euo pipefail

LAB=$(cd "$(dirname "$0")" && pwd)
for f in "$LAB"/langs/*.sh; do source "$f"; done

ALL_VARIANTS=(go rust-llvm rust-llvm-mold rust-llvm-wild rust-cranelift rust-cranelift-wild rust-check
  c-gcc c-clang c-tcc odin zig pascal v)
LANGS=(go rust c odin zig pascal v)

die() { echo "lab: $*" >&2; exit 1; }
lang_of() { case $1 in rust-* | c-*) echo "${1%%-*}" ;; *) echo "$1" ;; esac; }

tool_of() {
  case $1 in
    go) echo go ;; rust-*cranelift*) echo cargo ;; rust-*) echo cargo ;;
    c-*) echo "${1#c-}" ;; odin) echo odin ;; zig) echo zig ;; pascal) echo fpc ;; v) echo v ;;
  esac
}

available() {
  local v=$1
  command -v "$(tool_of "$v")" >/dev/null || return 1
  case $v in *wild*) command -v wild >/dev/null || return 1 ;; esac
  case $v in *mold*) command -v mold >/dev/null || return 1 ;; esac
  case $v in *cranelift*) rustup component list --toolchain nightly --installed 2>/dev/null |
    grep -q codegen-cranelift || return 1 ;; esac
  return 0
}

workdir() { echo "$LAB/work/$1/$(lang_of "$2")"; }

cmd_gen() {
  local m=${1:?módulos} f=${2:?funções} l
  for l in "${LANGS[@]}"; do
    rm -rf "$LAB/work/${m}x$f/$l"
    "${l}_gen" "$LAB/work/${m}x$f/$l" "$m" "$f"
  done
  echo "gerado: work/${m}x$f ($((m * f)) funções por linguagem)"
}

cmd_gen_multi() {
  local m=${1:?unidades} f=${2:?funções} l
  ((m >= 2)) || die "gen-multi precisa de pelo menos 2 unidades, recebeu $m"
  for l in "${MULTI_LANGS[@]}"; do
    rm -rf "$LAB/work/multi-${m}x$f/$l"
    "${l}_gen_multi" "$LAB/work/multi-${m}x$f/$l" "$m" "$f"
  done
  echo "gerado: work/multi-${m}x$f ($m unidades, $((m * f)) funções por linguagem)"
}

# Muda o número da linha marcada: mudança de corpo de função, sem mexer em interface.
# Alvo "base" é a linha "// EDIT"; "leaf" é "// EDIT-LEAF" (só no cenário multi).
cmd_edit() {
  local marker files
  case ${3:-base} in
    base) marker='// EDIT' ;; leaf) marker='// EDIT-LEAF' ;;
    *) die "alvo de edição inválido: recebeu '$3', esperado base ou leaf" ;;
  esac
  files=$(grep -rlE --exclude-dir={target,gocache,gocache-std,units,zig-cache} "$marker\$" "$1")
  [ -n "$files" ] || die "nenhum arquivo com '$marker' em $1"
  # shellcheck disable=SC2086 # lista de arquivos sem espaço, gerada pelo próprio lab
  sed -i -E "s#[0-9]+(\)?;? *$marker)\$#$((RANDOM + 1))\1#" $files
}

has_leaf() { grep -rqE --exclude-dir={target,gocache,gocache-std,units} '// EDIT-LEAF$' "$1"; }

cmd_build() { "$(lang_of "$2")_build" "$1" "$2"; }
cmd_clean() { "$(lang_of "$2")_clean" "$1" "$2"; }

run_bin() {
  case $2 in rust-*) "$1/target/debug/bench" ;; *) "$1/bin" ;; esac 2>&1
}

cmd_verify() {
  local size=${1:?tamanho, ex.: 10x50} v d out ref=""
  for v in "${ALL_VARIANTS[@]}"; do
    [[ $v == rust-check ]] && continue
    available "$v" || { echo "pulando $v (ferramenta ausente)"; continue; }
    d=$(workdir "$size" "$v")
    [ -d "$d" ] || continue # o cenário multi não gera todas as linguagens
    cmd_clean "$d" "$v" && cmd_build "$d" "$v" >/dev/null
    out=$(run_bin "$d" "$v")
    printf '%-22s %s\n' "$v" "$out"
    [ -z "$ref" ] && ref=$out
    [ "$out" = "$ref" ] || die "$v imprimiu $out, esperado $ref (mesmo programa, resultado diferente)"
  done
  echo "ok: todas as variantes imprimem $ref"
}

version_of() {
  local l
  l=$(lang_of "$1")
  case $l in c) c_version "$1" ;; rust) rust_version "$1" ;; *) "${l}_version" ;; esac 2>&1 | head -1
}

cmd_run() {
  local size=${1:?tamanho, ex.: 10x50}; shift
  local variants=("$@") out v d self="$LAB/lab.sh"
  [ ${#variants[@]} -gt 0 ] || variants=("${ALL_VARIANTS[@]}")
  [ -d "$LAB/work/$size" ] || die "work/$size não existe; rode ./lab.sh gen primeiro"
  out="$LAB/results/$(date +%Y-%m-%d)-$(hostname -s)-$size"
  mkdir -p "$out"
  { echo "host: $(hostname -s)"; echo "cpu: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2-)"
    echo "nproc: $(nproc)"; echo "date: $(date -Is)"; } > "$out/machine.txt"
  for v in "${variants[@]}"; do
    available "$v" || { echo "pulando $v (ferramenta ausente)"; continue; }
    d=$(workdir "$size" "$v")
    [ -d "$d" ] || continue
    echo "== $v: $(version_of "$v")" | tee -a "$out/versions.txt"
    hyperfine -N --style basic --runs "${RUNS_CLEAN:-5}" \
      --prepare "$self _clean $d $v" --export-json "$out/$v-clean.json" "$self _build $d $v"
    hyperfine -N --style basic --warmup 1 --runs "${RUNS_INCR:-10}" \
      --export-json "$out/$v-noop.json" "$self _build $d $v"
    hyperfine -N --style basic --warmup 1 --runs "${RUNS_INCR:-10}" \
      --prepare "$self _edit $d $v base" --export-json "$out/$v-incr.json" "$self _build $d $v"
    has_leaf "$d" || continue
    hyperfine -N --style basic --warmup 1 --runs "${RUNS_INCR:-10}" \
      --prepare "$self _edit $d $v leaf" --export-json "$out/$v-leaf.json" "$self _build $d $v"
  done
  echo "resultados em ${out#"$LAB"/}"
}

# Mediana de um campo das medições do hyperfine 2 (o JSON dele não traz mais a mediana pronta).
median_of() {
  jq -r --arg k "$2" '[.results[0].measurements[][$k].value] | sort
    | if length == 0 then "-" else .[(length / 2 | floor)] end' "$1"
}

# Instruções de CPU variam bem menos que o tempo de relógio numa máquina com outras cargas.
cmd_report() {
  local dir=${1:?pasta de resultado} v s f scenarios=(clean noop incr) leaf_col="" incr_col="mudou 1 linha"
  [ -d "$dir" ] || dir="$LAB/results/$dir"
  if compgen -G "$dir/*-leaf.json" >/dev/null; then
    scenarios+=(leaf)
    leaf_col=" mudou a folha (s) |"
    incr_col="mudou a base"
  fi
  echo "| variante | limpo (s) | sem mudança (s) | $incr_col (s) |$leaf_col RAM pico, limpo (MiB) | instruções, limpo (bi) |"
  echo "|---|---:|---:|---:|${leaf_col:+---:|}---:|---:|"
  for v in "${ALL_VARIANTS[@]}"; do
    # Variante ainda rodando deixa o JSON pela metade: pula até ele ficar válido.
    jq -e . "$dir/$v-incr.json" >/dev/null 2>&1 || continue
    printf '| %s' "$v"
    for s in "${scenarios[@]}"; do
      f=$(median_of "$dir/$v-$s.json" time_wall_clock)
      LC_NUMERIC=C printf ' | %.2f' "$f"
    done
    f=$(median_of "$dir/$v-clean.json" memory_peak_resident)
    LC_NUMERIC=C printf ' | %.0f' "$(echo "$f / 1048576" | bc -l)"
    f=$(median_of "$dir/$v-clean.json" instructions)
    LC_NUMERIC=C printf ' | %.1f |\n' "$(echo "$f / 1000000000" | bc -l)"
  done
}

case ${1:-} in
  gen) shift; cmd_gen "$@" ;;
  gen-multi) shift; cmd_gen_multi "$@" ;;
  verify) shift; cmd_verify "$@" ;;
  run) shift; cmd_run "$@" ;;
  report) shift; cmd_report "$@" ;;
  variants) for v in "${ALL_VARIANTS[@]}"; do available "$v" && echo "$v" || echo "$v (ausente)"; done ;;
  _build) cmd_build "$2" "$3" ;;
  _clean) cmd_clean "$2" "$3" ;;
  _edit) cmd_edit "$2" "$3" "${4:-base}" ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 64 ;;
esac
