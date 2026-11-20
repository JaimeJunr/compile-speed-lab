# Zig: main.zig importa M arquivos (o compilador vê o programa inteiro de uma vez).

zig_gen() {
  local d=$1 m=$2 f=$3 i j
  mkdir -p "$d"
  {
    echo 'const std = @import("std");'
    for ((j = 0; j < m; j++)); do echo "const m$j = @import(\"m$j.zig\");"; done
    echo 'pub fn main() void {'
    echo '    var acc: u64 = 0;'
    for ((j = 0; j < m; j++)); do echo "    acc +%= m$j.run(acc);"; done
    echo '    std.debug.print("{d}\n", .{acc});'
    echo '}'
  } > "$d/main.zig"
  for ((j = 0; j < m; j++)); do
    {
      for ((i = 0; i < f; i++)); do
        echo "fn f_$i(x: u64) u64 {"
        echo "    var a = x ^ $((i * 7 + j));"
        echo "    a = a *% 6364136223846793005 +% $i;"
        ((i == 0)) && echo "    a = a +% 7; // EDIT"
        echo "    if (a % 3 == 0) return a >> 1;"
        echo "    return a +% $j;"
        echo "}"
      done
      echo "pub fn run(x: u64) u64 {"
      echo "    var a = x;"
      for ((i = 0; i < f; i++)); do echo "    a = f_$i(a);"; done
      echo "    return a;"
      echo "}"
    } > "$d/m$j.zig"
  done
}


# O cache global guarda a stdlib e o compiler_rt; ele fica (como a stdlib pronta do Rust).
# O cache local do projeto é o que o build limpo apaga.
zig_clean() { rm -rf "$1/zig-cache" "$1/bin"; }
zig_build() {
  (cd "$1" && zig build-exe main.zig -O Debug --cache-dir zig-cache \
    --global-cache-dir "$1/../zig-global-cache" -femit-bin=bin)
}
zig_version() { echo "zig $(zig version)"; }
