# Go: um pacote main com M arquivos (uma unidade de compilação).

go_gen() {
  local d=$1 m=$2 f=$3 i j
  mkdir -p "$d"
  printf 'module bench\n\ngo 1.22\n' > "$d/go.mod"
  {
    echo 'package main'
    echo 'import "fmt"'
    echo 'func main() {'
    echo '	var acc uint64'
    for ((j = 0; j < m; j++)); do echo "	acc += run$j(acc)"; done
    echo '	fmt.Println(acc)'
    echo '}'
  } > "$d/main.go"
  for ((j = 0; j < m; j++)); do
    {
      echo 'package main'
      for ((i = 0; i < f; i++)); do
        echo "func f${j}_$i(x uint64) uint64 {"
        echo "	a := x ^ $((i * 7 + j))"
        echo "	a = a*6364136223846793005 + $i"
        ((i == 0)) && echo "	a = a + 7 // EDIT"
        echo "	if a%3 == 0 {"
        echo "		return a >> 1"
        echo "	}"
        echo "	return a + $j"
        echo "}"
      done
      echo "func run$j(x uint64) uint64 {"
      echo "	a := x"
      for ((i = 0; i < f; i++)); do echo "	a = f${j}_$i(a)"; done
      echo "	return a"
      echo "}"
    } > "$d/m$j.go"
  done
}

# O GOCACHE guarda também a stdlib compilada. Para o build limpo valer o mesmo que no Rust
# (stdlib já pronta), o cache do projeto recomeça de uma cópia com só a stdlib.
go_clean() {
  local d=$1
  rm -rf "$d/gocache" "$d/bin"
  [ -d "$d/gocache-std" ] || GOCACHE="$d/gocache-std" go build std
  cp -a "$d/gocache-std" "$d/gocache"
}

go_build() { (cd "$1" && GOCACHE="$1/gocache" GOFLAGS= go build -o bin .); }
go_version() { go version; }
