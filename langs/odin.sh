# Odin: um pacote main com M arquivos. Odin não tem build incremental: todo build é completo.

odin_gen() {
  local d=$1 m=$2 f=$3 i j
  mkdir -p "$d"
  {
    echo 'package main'
    echo 'import "core:fmt"'
    echo 'main :: proc() {'
    echo '	acc: u64 = 0'
    for ((j = 0; j < m; j++)); do echo "	acc += run$j(acc)"; done
    echo '	fmt.println(acc)'
    echo '}'
  } > "$d/main.odin"
  for ((j = 0; j < m; j++)); do
    {
      echo 'package main'
      for ((i = 0; i < f; i++)); do
        echo "f${j}_$i :: proc(x: u64) -> u64 {"
        echo "	a := x ~ $((i * 7 + j))"
        echo "	a = a * 6364136223846793005 + $i"
        ((i == 0)) && echo "	a = a + 7 // EDIT"
        echo "	if a % 3 == 0 { return a >> 1 }"
        echo "	return a + $j"
        echo "}"
      done
      echo "run$j :: proc(x: u64) -> u64 {"
      echo "	a := x"
      for ((i = 0; i < f; i++)); do echo "	a = f${j}_$i(a)"; done
      echo "	return a"
      echo "}"
    } > "$d/m$j.odin"
  done
}

odin_edit_file() { echo "$1/m0.odin"; }
odin_bin() { echo "$1/bin"; }
odin_clean() { rm -f "$1/bin" "$1"/bin.o; }
odin_build() { (cd "$1" && odin build . -out:bin -o:none); }
odin_version() { odin version; }
