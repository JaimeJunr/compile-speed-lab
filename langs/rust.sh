# Rust: um crate binário com M módulos (uma unidade de compilação, como o pacote único do Go).

rust_gen() {
  local d=$1 m=$2 f=$3 i j
  mkdir -p "$d/src"
  printf '[package]\nname = "bench"\nversion = "0.1.0"\nedition = "2021"\n' > "$d/Cargo.toml"
  {
    for ((j = 0; j < m; j++)); do echo "mod m$j;"; done
    echo 'fn main() {'
    echo '    let mut acc: u64 = 0;'
    for ((j = 0; j < m; j++)); do echo "    acc = acc.wrapping_add(m$j::run(acc));"; done
    echo '    println!("{acc}");'
    echo '}'
  } > "$d/src/main.rs"
  for ((j = 0; j < m; j++)); do
    {
      for ((i = 0; i < f; i++)); do
        echo "fn f$i(x: u64) -> u64 {"
        echo "    let mut a = x ^ $((i * 7 + j));"
        echo "    a = a.wrapping_mul(6364136223846793005).wrapping_add($i);"
        ((i == 0)) && echo "    a = a.wrapping_add(7); // EDIT"
        echo "    if a % 3 == 0 { a >> 1 } else { a.wrapping_add($j) }"
        echo "}"
      done
      echo "pub fn run(x: u64) -> u64 {"
      echo "    let mut a = x;"
      for ((i = 0; i < f; i++)); do echo "    a = f$i(a);"; done
      echo "    a"
      echo "}"
    } > "$d/src/m$j.rs"
  done
}

rust_edit_file() { echo "$1/src/m0.rs"; }
rust_bin() { echo "$1/target/debug/bench"; }
rust_clean() { rm -rf "$1/target"; }

# Variantes: LLVM ou Cranelift, linker padrão (lld) ou wild, build ou só check.
# RUSTC_WRAPPER vazio desliga o sccache global, senão o "build limpo" viraria acerto de cache.
rust_build() {
  local d=$1 variant=$2 tc=stable cmd=build flags=() envs=()
  envs+=(CARGO_BUILD_RUSTC_WRAPPER= RUSTC_WRAPPER= CARGO_TARGET_DIR="$d/target")
  case $variant in *cranelift*)
    tc=nightly
    flags+=(-Zcodegen-backend)
    envs+=(CARGO_PROFILE_DEV_CODEGEN_BACKEND=cranelift) ;;
  esac
  case $variant in *wild*) envs+=(RUSTFLAGS="-Clinker=clang -Clink-arg=--ld-path=wild") ;; esac
  case $variant in *mold*) envs+=(RUSTFLAGS="-Clinker=clang -Clink-arg=--ld-path=mold") ;; esac
  case $variant in *check*) cmd=check ;; esac
  (cd "$d" && env "${envs[@]}" cargo "+$tc" "${flags[@]}" "$cmd" -q)
}

rust_version() {
  case $1 in *cranelift*) rustc +nightly --version ;; *) rustc +stable --version ;; esac
}
