# C: M arquivos .c (cada um é uma unidade de compilação) e um Makefile com objeto por arquivo.
# Variantes pelo compilador: c-gcc, c-clang, c-tcc.

c_gen() {
  local d=$1 m=$2 f=$3 i j
  mkdir -p "$d"
  {
    echo '#include <stdint.h>'
    for ((j = 0; j < m; j++)); do echo "uint64_t run$j(uint64_t x);"; done
  } > "$d/bench.h"
  {
    echo '#include <stdio.h>'
    echo '#include "bench.h"'
    echo 'int main(void) {'
    echo '    uint64_t acc = 0;'
    for ((j = 0; j < m; j++)); do echo "    acc += run$j(acc);"; done
    echo '    printf("%llu\n", (unsigned long long)acc);'
    echo '    return 0;'
    echo '}'
  } > "$d/main.c"
  for ((j = 0; j < m; j++)); do
    {
      echo '#include "bench.h"'
      for ((i = 0; i < f; i++)); do
        echo "static uint64_t f$i(uint64_t x) {"
        echo "    uint64_t a = x ^ $((i * 7 + j))u;"
        echo "    a = a * 6364136223846793005ull + $i;"
        ((i == 0)) && echo "    a = a + 7; // EDIT"
        echo "    if (a % 3 == 0) return a >> 1;"
        echo "    return a + $j;"
        echo "}"
      done
      echo "uint64_t run$j(uint64_t x) {"
      echo "    uint64_t a = x;"
      for ((i = 0; i < f; i++)); do echo "    a = f$i(a);"; done
      echo "    return a;"
      echo "}"
    } > "$d/m$j.c"
  done
  cat > "$d/Makefile" <<'EOF'
CC ?= gcc
CFLAGS ?= -O0 -g
SRCS := main.c $(wildcard m[0-9]*.c)
OBJS := $(SRCS:.c=.o)
bin: $(OBJS)
	$(CC) -o $@ $(OBJS)
%.o: %.c bench.h
	$(CC) $(CFLAGS) -c $< -o $@
EOF
}

c_edit_file() { echo "$1/m0.c"; }
c_bin() { echo "$1/bin"; }
c_clean() { rm -f "$1"/*.o "$1/bin"; }
c_cc() { echo "${1#c-}"; }

c_build() {
  local cc
  cc=$(c_cc "$2")
  make -s -C "$1" -j"$(nproc)" CC="$cc" CFLAGS="-O0 -g"
}

c_version() { "$(c_cc "$1")" --version 2>/dev/null | head -1 || "$(c_cc "$1")" -v; }
