# Cenário com várias unidades de compilação: m0 é a base, m1..m(M-1) dependem dela.
# Só para linguagens que compilam uma unidade por vez (crate, pacote, arquivo, unit).
# "// EDIT" fica na base (mudança de corpo, sem mexer na interface: o caso do
# Relink-Don't-Rebuild do Rust); "// EDIT-LEAF" fica na última unidade.

MULTI_LANGS=(rust go c pascal)

edit_marker() {
  if (($1 == 0)); then echo "// EDIT"; elif (($1 == $2 - 1)); then echo "// EDIT-LEAF"; fi
}

rust_gen_multi() {
  local d=$1 m=$2 f=$3 i j mk
  mkdir -p "$d/src"
  {
    printf '[package]\nname = "bench"\nversion = "0.1.0"\nedition = "2021"\n\n[dependencies]\n'
    for ((j = 1; j < m; j++)); do echo "m$j = { path = \"m$j\" }"; done
    printf '\n[workspace]\nmembers = ["m*"]\n'
  } > "$d/Cargo.toml"
  {
    echo 'fn main() {'
    echo '    let mut acc: u64 = 0;'
    for ((j = 1; j < m; j++)); do echo "    acc = acc.wrapping_add(m$j::run(acc));"; done
    echo '    println!("{acc}");'
    echo '}'
  } > "$d/src/main.rs"
  for ((j = 0; j < m; j++)); do
    mkdir -p "$d/m$j/src"
    printf '[package]\nname = "m%s"\nversion = "0.1.0"\nedition = "2021"\n' "$j" > "$d/m$j/Cargo.toml"
    ((j > 0)) && printf '\n[dependencies]\nm0 = { path = "../m0" }\n' >> "$d/m$j/Cargo.toml"
    mk=$(edit_marker "$j" "$m")
    {
      for ((i = 0; i < f; i++)); do
        echo "fn f$i(x: u64) -> u64 {"
        echo "    let mut a = x ^ $((i * 7 + j));"
        echo "    a = a.wrapping_mul(6364136223846793005).wrapping_add($i);"
        ((i == 0)) && [ -n "$mk" ] && echo "    a = a.wrapping_add(7); $mk"
        echo "    if a % 3 == 0 { a >> 1 } else { a.wrapping_add($j) }"
        echo "}"
      done
      ((j == 0)) && echo "pub fn base(x: u64) -> u64 {" && echo "    let mut a = x;"
      ((j > 0)) && echo "pub fn run(x: u64) -> u64 {" && echo "    let mut a = m0::base(x);"
      for ((i = 0; i < f; i++)); do echo "    a = f$i(a);"; done
      echo "    a"
      echo "}"
    } > "$d/m$j/src/lib.rs"
  done
}

go_gen_multi() {
  local d=$1 m=$2 f=$3 i j mk
  mkdir -p "$d"
  printf 'module bench\n\ngo 1.22\n' > "$d/go.mod"
  {
    echo 'package main'
    echo 'import ('
    echo '	"fmt"'
    for ((j = 1; j < m; j++)); do echo "	\"bench/m$j\""; done
    echo ')'
    echo 'func main() {'
    echo '	var acc uint64'
    for ((j = 1; j < m; j++)); do echo "	acc += m$j.Run(acc)"; done
    echo '	fmt.Println(acc)'
    echo '}'
  } > "$d/main.go"
  for ((j = 0; j < m; j++)); do
    mkdir -p "$d/m$j"
    mk=$(edit_marker "$j" "$m")
    {
      echo "package m$j"
      ((j > 0)) && echo 'import "bench/m0"'
      for ((i = 0; i < f; i++)); do
        echo "func f_$i(x uint64) uint64 {"
        echo "	a := x ^ $((i * 7 + j))"
        echo "	a = a*6364136223846793005 + $i"
        ((i == 0)) && [ -n "$mk" ] && echo "	a = a + 7 $mk"
        echo "	if a%3 == 0 {"
        echo "		return a >> 1"
        echo "	}"
        echo "	return a + $j"
        echo "}"
      done
      ((j == 0)) && echo "func Base(x uint64) uint64 {" && echo "	a := x"
      ((j > 0)) && echo "func Run(x uint64) uint64 {" && echo "	a := m0.Base(x)"
      for ((i = 0; i < f; i++)); do echo "	a = f_$i(a)"; done
      echo "	return a"
      echo "}"
    } > "$d/m$j/m$j.go"
  done
}

c_gen_multi() {
  local d=$1 m=$2 f=$3 i j mk
  c_gen "$d" 1 1 # reaproveita o Makefile
  rm -f "$d"/m*.c
  {
    echo '#include <stdint.h>'
    echo 'uint64_t base(uint64_t x);'
    for ((j = 1; j < m; j++)); do echo "uint64_t run$j(uint64_t x);"; done
  } > "$d/bench.h"
  {
    echo '#include <stdio.h>'
    echo '#include "bench.h"'
    echo 'int main(void) {'
    echo '    uint64_t acc = 0;'
    for ((j = 1; j < m; j++)); do echo "    acc += run$j(acc);"; done
    echo '    printf("%llu\n", (unsigned long long)acc);'
    echo '    return 0;'
    echo '}'
  } > "$d/main.c"
  for ((j = 0; j < m; j++)); do
    mk=$(edit_marker "$j" "$m")
    {
      echo '#include "bench.h"'
      for ((i = 0; i < f; i++)); do
        echo "static uint64_t f$i(uint64_t x) {"
        echo "    uint64_t a = x ^ $((i * 7 + j))u;"
        echo "    a = a * 6364136223846793005ull + $i;"
        ((i == 0)) && [ -n "$mk" ] && echo "    a = a + 7; $mk"
        echo "    if (a % 3 == 0) return a >> 1;"
        echo "    return a + $j;"
        echo "}"
      done
      ((j == 0)) && echo "uint64_t base(uint64_t x) {" && echo "    uint64_t a = x;"
      ((j > 0)) && echo "uint64_t run$j(uint64_t x) {" && echo "    uint64_t a = base(x);"
      for ((i = 0; i < f; i++)); do echo "    a = f$i(a);"; done
      echo "    return a;"
      echo "}"
    } > "$d/m$j.c"
  done
}

pascal_gen_multi() {
  local d=$1 m=$2 f=$3 i j mk uses=""
  mkdir -p "$d/units"
  for ((j = 1; j < m; j++)); do uses+="${uses:+, }m$j"; done
  {
    echo 'program main;'
    echo '{$mode objfpc}{$Q-}{$R-}'
    echo "uses $uses;"
    echo 'var acc: QWord;'
    echo 'begin'
    echo '  acc := 0;'
    for ((j = 1; j < m; j++)); do echo "  acc := acc + run$j(acc);"; done
    echo '  writeln(acc);'
    echo 'end.'
  } > "$d/main.pas"
  for ((j = 0; j < m; j++)); do
    mk=$(edit_marker "$j" "$m")
    {
      echo "unit m$j;"
      echo '{$mode objfpc}{$Q-}{$R-}'
      echo 'interface'
      ((j == 0)) && echo 'function base(x: QWord): QWord;'
      ((j > 0)) && echo "function run$j(x: QWord): QWord;"
      echo 'implementation'
      ((j > 0)) && echo 'uses m0;'
      for ((i = 0; i < f; i++)); do
        echo "function f$i(x: QWord): QWord;"
        echo 'var a: QWord;'
        echo 'begin'
        echo "  a := x xor $((i * 7 + j));"
        echo "  a := a * QWord(6364136223846793005) + $i;"
        ((i == 0)) && [ -n "$mk" ] && echo "  a := a + 7; $mk"
        echo "  if a mod 3 = 0 then Result := a shr 1 else Result := a + $j;"
        echo 'end;'
      done
      ((j == 0)) && echo 'function base(x: QWord): QWord;'
      ((j > 0)) && echo "function run$j(x: QWord): QWord;"
      echo 'var a: QWord;'
      echo 'begin'
      ((j == 0)) && echo '  a := x;'
      ((j > 0)) && echo '  a := base(x);'
      for ((i = 0; i < f; i++)); do echo "  a := f$i(a);"; done
      echo '  Result := a;'
      echo 'end;'
      echo 'end.'
    } > "$d/m$j.pas"
  done
}
