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
./lab.sh gen-multi 50 200  # 50 unidades de compilação dependendo de uma base
./lab.sh verify 50x200     # todas imprimem o mesmo número?
./lab.sh run 50x200        # mede tudo; ou: ./lab.sh run 50x200 go rust-llvm rust-cranelift
./lab.sh report 2026-11-20-<host>-50x200
```

Rode numa máquina parada: outras cargas mudam os números. `RUNS_CLEAN` e `RUNS_INCR` ajustam quantas vezes cada cenário roda.

## Primeira rodada (2026-11-20)

10 mil funções (`50x200`), notebook com 16 threads limitado a 4 núcleos pela fila de build, **com outras cargas rodando**: o tempo de relógio tem ruído alto (a variante `rust-llvm` foi de 2,6 s a 11,7 s no mesmo cenário). As instruções de CPU são o número mais estável. Dados brutos em [`results/2026-11-20-jaime-setup-50x200`](results/2026-11-20-jaime-setup-50x200).

| variante | limpo (s) | sem mudança (s) | mudou 1 linha (s) | RAM pico, limpo (MiB) | instruções, limpo (bi) |
|---|---:|---:|---:|---:|---:|
| go | 6.42 | 0.07 | 5.35 | 424 | 33.0 |
| rust-llvm | 5.74 | 0.10 | 6.18 | 436 | 21.1 |
| rust-llvm-mold | 6.27 | 0.15 | 4.44 | 408 | 21.2 |
| rust-llvm-wild | 5.89 | 0.13 | 2.59 | 436 | 21.2 |
| rust-cranelift | 3.63 | 0.08 | 2.29 | 445 | 19.4 |
| rust-cranelift-wild | 3.86 | 0.12 | 4.44 | 443 | 19.5 |
| rust-check | 2.62 | 0.08 | 1.96 | 365 | 10.8 |
| c-gcc | 3.25 | 0.02 | 0.23 | 41 | 30.0 |
| c-clang | 1.35 | 0.02 | 0.16 | 95 | 10.6 |
| c-tcc | 0.11 | 0.02 | 0.03 | 7 | 0.7 |
| odin | 1.31 | 1.34 | 1.54 | 679 | 9.1 |
| zig | 1.78 | 2.23 | 2.05 | 192 | 8.7 |
| pascal | 3.50 | 0.22 | 0.22 | 53 | 8.6 |
| v | 1.08 | 1.09 | 1.19 | 420 | 4.0 |

O que esta rodada sugere (hipóteses, não conclusões):

1. **O frontend do Rust é o piso.** Só o `cargo check`, sem gerar código, usa 10,8 bilhões de instruções e 2,6 s, mais que o `clang` compilando o mesmo programa inteiro em C (10,6 bi, 1,35 s). Em código sem genéricos, traits nem macros, a análise já custa metade do build. Trocar o backend (Cranelift) não passa desse piso.
2. **Num crate único, o build incremental quase não poupa trabalho.** Mudar uma linha custa perto do `cargo check` inteiro (1,96 s), enquanto C e Pascal recompilam só o arquivo mudado (0,03 s a 0,23 s).
3. **Num pacote único gigante, o Go não é mais rápido que o Rust.** O `go build` sempre otimiza; a vantagem dele deve aparecer com vários pacotes, que ainda não estão medidos.
4. **O linker não decide este cenário.** O binário é pequeno e a diferença entre lld, mold e wild ficou dentro do ruído.

## Cenário com várias unidades (2026-11-20)

`./lab.sh gen-multi 50 200`: 50 unidades de compilação com 200 funções cada (crates no Rust, pacotes no Go, arquivos no C, units no Pascal). `m0` é a base e as outras 49 dependem dela. "Mudou a base" troca um número dentro de uma função privada de `m0`, sem mexer na interface: é o caso que o [Relink-Don't-Rebuild](https://github.com/rust-lang/goals/issues/843) quer resolver no Rust. "Mudou a folha" faz o mesmo na última unidade, da qual ninguém depende.

O tempo de relógio desta rodada não serve: a máquina estava com outras cargas e o build limpo do `rust-cranelift` foi de 12,8 s a 19,6 s. A tabela usa instruções de CPU (`METRIC=instructions ./lab.sh report ...`), que medem o trabalho feito e não dependem da carga. Dados brutos em [`results/2026-11-20-jaime-setup-multi-50x200`](results/2026-11-20-jaime-setup-multi-50x200).

| variante | limpo (bi) | sem mudança (bi) | mudou a base (bi) | mudou a folha (bi) | RAM pico, limpo (MiB) |
|---|---:|---:|---:|---:|---:|
| go | 23.69 | 0.26 | 23.59 | 1.67 | 99 |
| rust-llvm | 22.46 | 0.13 | 5.90 | 0.63 | 137 |
| rust-llvm-wild | 22.53 | 0.13 | 5.97 | 0.70 | 138 |
| rust-cranelift | 21.18 | 0.13 | 6.55 | 0.66 | 146 |
| rust-check | 12.16 | 0.13 | 4.51 | 0.28 | 105 |
| c-clang | 10.58 | 0.03 | 0.36 | 0.36 | 89 |
| c-tcc | 0.68 | 0.03 | 0.07 | 0.07 | 7 |
| pascal | 8.65 | 0.54 | 0.70 | 0.71 | 55 |

O que esta rodada sugere:

1. **O Go recompila todos os dependentes quando o corpo de uma função da base muda.** Conferido com `go build -v`: depois da edição na base ele recompila `m0` e todas as unidades que dependem dela. Causa não verificada; a suspeita é o inlining, já que o Go exporta o corpo de funções pequenas para os outros pacotes. Próximo teste: a mesma edição numa função marcada `//go:noinline`.
2. **O incremental do Rust faz a mudança na base custar 4 vezes menos que o build limpo** (5,9 contra 22,5 bilhões), mas ainda 16 vezes mais que no C, que recompila só o arquivo mudado (0,36 bilhão).
3. **Isso dá um número para o ganho do Relink-Don't-Rebuild neste cenário.** Se o Rust só religasse os dependentes, a mudança na base deveria custar perto da mudança na folha (0,63 bilhão): cerca de 9 vezes menos que hoje. O roadmap oficial fala em 5 a 10 vezes.
4. **Mesmo aqui, a maior parte é análise.** Na mudança da base, o `cargo check` sozinho gasta 4,5 dos 5,9 bilhões.

## Próximos passos

- Rodar de novo numa máquina parada, para separar sinal de ruído (principalmente os linkers).
- Quebrar o `cargo check` por fase (`-Zself-profile`, `-Ztime-passes`) para ver onde vão as 10,8 bilhões de instruções num programa trivial.
- Repetir os dois cenários numa máquina parada, com tempo de relógio confiável.
- Cenário com genéricos e traits, onde a monomorfização pesa.

## Limites conhecidos

- O código sintético mede a escala do compilador, não um projeto real: não tem genéricos, traits, macros nem dependências externas, que são justamente onde o Rust mais gasta. Próximos cenários: genéricos com muitas instanciações e um workspace com várias crates.
- Rust, Go, Odin, Zig e V compilam o programa como uma unidade; C e Pascal compilam um arquivo por vez. Isso é parte da diferença entre as linguagens, não um erro de medição.
- Só mede o build de debug. O tempo do build otimizado e a velocidade do binário gerado entram depois.

## Licença

MIT
