# compile-speed-lab

> **EN:** A reproducible lab that compiles the *same* program in Rust, Go, C (gcc, clang, tcc), Odin, Zig, Object Pascal and V, and measures clean build, no-op rebuild and one-line-change rebuild. Rust is measured in several setups (LLVM, Cranelift, lld, mold, wild) so each new community technique becomes one more column, showing how close it brings Rust to the fast-compiling languages.

Laboratório reproduzível para medir o quanto o Rust está longe das linguagens que compilam rápido, e o quanto cada técnica nova (backend, linker, frontend paralelo, mudança no compilador) encurta essa distância.

## O que é medido

O mesmo programa é gerado em cada linguagem: `M` módulos com `F` funções cada, só com a biblioteca padrão. O `./lab.sh verify` compila todas as variantes e confere que todas imprimem o mesmo número; se uma divergir, a comparação não vale e o script para.

Para cada variante, com [hyperfine](https://github.com/sharkdp/hyperfine) (mediana de várias execuções):

| Cenário | O que simula |
|---|---|
| `clean` | build do zero, com a biblioteca padrão já pronta |
| `noop` | build sem nenhuma mudança (custo fixo da ferramenta) |
| `incr` | mudar o corpo de uma função e compilar de novo (o ciclo do dia a dia) |

## Variantes

| Variante | Compilador |
|---|---|
| `go` | `go build` |
| `rust-llvm` | `cargo build`, backend LLVM, linker padrão (lld) |
| `rust-llvm-mold`, `rust-llvm-wild` | idem, com os linkers mold e wild |
| `rust-cranelift`, `rust-cranelift-wild` | nightly com o backend Cranelift |
| `rust-check` | `cargo check` (só análise, sem gerar código), como referência |
| `c-gcc`, `c-clang`, `c-tcc` | um objeto por arquivo, via `make -j` |
| `odin` | `odin build -o:none` |
| `zig` | `zig build-exe -O Debug` |
| `pascal` | Free Pascal (`fpc`), uma unit por arquivo |
| `v` | `v` (gera C e compila com tcc) |

Jai ficou de fora: o compilador não é distribuído publicamente.

## Uso

```bash
./lab.sh variants          # o que está instalado nesta máquina
./lab.sh gen 50 200        # 50 módulos x 200 funções = 10 mil funções por linguagem
./lab.sh verify 50x200     # todas imprimem o mesmo número?
./lab.sh run 50x200        # mede tudo; ou: ./lab.sh run 50x200 go rust-llvm rust-cranelift
./lab.sh report 2026-11-20-<host>-50x200
```

Rode numa máquina parada: outras cargas mudam os números. `RUNS_CLEAN` e `RUNS_INCR` ajustam quantas vezes cada cenário roda.

## Limites conhecidos

- O código sintético mede a escala do compilador, não um projeto real: não tem genéricos, traits, macros nem dependências externas, que são justamente onde o Rust mais gasta. Próximos cenários: genéricos com muitas instanciações e um workspace com várias crates.
- Rust, Go, Odin, Zig e V compilam o programa como uma unidade; C e Pascal compilam um arquivo por vez. Isso é parte da diferença entre as linguagens, não um erro de medição.
- Só mede o build de debug. O tempo do build otimizado e a velocidade do binário gerado entram depois.

## Licença

MIT
