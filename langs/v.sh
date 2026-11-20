# V: um módulo main com M arquivos. V gera C e compila com o tcc embutido no build de debug.

v_gen() {
  local d=$1 m=$2 f=$3 i j
  mkdir -p "$d"
  {
    echo 'module main'
    echo 'fn main() {'
    echo '	mut acc := u64(0)'
    for ((j = 0; j < m; j++)); do echo "	acc += run$j(acc)"; done
    echo '	println(acc)'
    echo '}'
  } > "$d/main.v"
  for ((j = 0; j < m; j++)); do
    {
      echo 'module main'
      for ((i = 0; i < f; i++)); do
        echo "fn f${j}_$i(x u64) u64 {"
        echo "	mut a := x ^ u64($((i * 7 + j)))"
        echo "	a = a * u64(6364136223846793005) + $i"
        ((i == 0)) && echo "	a = a + 7 // EDIT"
        echo "	if a % 3 == 0 {"
        echo "		return a >> 1"
        echo "	}"
        echo "	return a + $j"
        echo "}"
      done
      echo "fn run$j(x u64) u64 {"
      echo "	mut a := x"
      for ((i = 0; i < f; i++)); do echo "	a = f${j}_$i(a)"; done
      echo "	return a"
      echo "}"
    } > "$d/m$j.v"
  done
}

v_edit_file() { echo "$1/m0.v"; }
v_bin() { echo "$1/bin"; }
v_clean() { rm -f "$1/bin"; }
# O pacote vlang-bin do AUR vem sem o tcc embutido, e o libgc.a dele (feito com gcc) dá
# "section type conflict" no tcc do sistema; sem isso o V cai no gcc em silêncio.
# -gc none é neutro aqui: o programa não aloca.
v_build() {
  local err
  err=$(cd "$1" && v -cc tcc -gc none -o bin . 2>&1) || { echo "$err" >&2; return 1; }
  if grep -q 'falling back' <<< "$err"; then
    echo "v: o tcc falhou e o V usou outro compilador: $err" >&2
    return 1
  fi
}
v_version() { v version; }
