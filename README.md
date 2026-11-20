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
| `incr` | mudar o corpo de uma função, num arquivo só, e compilar de novo (o ciclo do dia a dia) |

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
./tests/edit_test.sh       # a edição de "mudou 1 linha" mexe em um arquivo só?
```

Rode numa máquina parada: outras cargas mudam os números. `RUNS_CLEAN` e `RUNS_INCR` ajustam quantas vezes cada cenário roda.

## Primeira rodada (2026-11-20)

10 mil funções (`50x200`), notebook com 16 threads limitado a 4 núcleos pela fila de build, **com outras cargas rodando**: o tempo de relógio tem ruído alto (a variante `rust-llvm` foi de 2,6 s a 11,7 s no mesmo cenário). As instruções de CPU são o número mais estável. Dados brutos em [`results/2026-11-20-jaime-setup-50x200`](results/2026-11-20-jaime-setup-50x200).

**Erro desta rodada:** o `_edit` mudava a linha marcada em todos os 50 arquivos, não em um só. A coluna "mudou 50 linhas" mede isso: uma linha em cada arquivo. O `lab.sh` já edita um arquivo só, e a rodada precisa ser refeita.

| variante | limpo (s) | sem mudança (s) | mudou 50 linhas, 1 por arquivo (s) | RAM pico, limpo (MiB) | instruções, limpo (bi) |
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
2. ~~Num crate único, o build incremental quase não poupa trabalho.~~ Errada: a edição mexia nos 50 arquivos. Com um arquivo só, numa máquina parada, o incremental poupa 60% (ver "Onde vai o tempo do `cargo check`").
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

## Onde vai o tempo do `cargo check` (2026-11-20)

Cenário `50x200` (crate único, 10 mil funções), rustc 1.100.0. Dados brutos em [`results/2026-11-20-jaime-setup-check-profile`](results/2026-11-20-jaime-setup-check-profile) e [`results/2026-11-20-note2-incremental`](results/2026-11-20-note2-incremental).

**Por fase** (`-Ztime-passes`, 2,34 s no total, numa máquina com outras cargas):

| fase | s | % |
|---|---:|---:|
| `MIR_checking` (borrowck e as checagens feitas em cada função) | 0.72 | 31 |
| `type_check_crate` (inferência e checagem de tipos) | 0.48 | 21 |
| `expand_crate` (inclui ler e analisar os 50 arquivos de `mod mJ;`) | 0.35 | 15 |
| `misc_checking_1` e `misc_checking_3` | 0.14 | 6 |
| `coherence_checking` | 0.10 | 4 |
| `resolve_crate` (resolução de nomes) | 0.09 | 4 |
| `lint_checking` | 0.06 | 2 |
| gravar o cache incremental | 0.04 | 2 |
| resto (inicialização e fases pequenas) | 0.36 | 15 |

**Por consulta** (`-Zself-profile`): o perfil infla o total para 10,3 s de CPU, então vale a proporção, não o tempo. As maiores são `typeck` (12%), `mir_built` (8%), a gravação do grafo de dependências do incremental (8%, 515 mil nós) e `mir_borrowck` (8%). Depois vem uma fila de checagens de 0,7% a 2% cada (`thir_body`, `check_unsafety`, `check_liveness`, `check_match`, `check_transmutes`, `opaque_types_defined_by`, `check_coroutine_obligations`, `has_ffi_unwind_calls`), todas chamadas 10.051 vezes: uma por função. O hashing dos resultados para o incremental soma 1,8 s dos 10,3 s, cerca de 3 µs por consulta por função.

**Com e sem incremental** (note2 parada, mediana de 7 execuções):

| | incremental | sem incremental |
|---|---:|---:|
| build limpo | 1.58 s | 1.29 s |
| mudou 1 linha, 1 arquivo | 0.52 s | 1.29 s |
| tamanho de `target/` | 35 MB | 60 KB |

O que isso mostra:

1. **O custo cresce com o número de funções, não com a dificuldade delas.** As funções são triviais e cada uma passa por umas 25 consultas. Cada consulta paga um custo fixo (nó no grafo de dependências, hash do resultado), mesmo quando não tem nada a checar.
2. **O incremental custa 22% no build limpo e poupa 60% quando muda uma linha.** Na máquina de desenvolvimento vale a pena. No CI, que sempre compila do zero, `CARGO_INCREMENTAL=0` corta perto de um quinto do `cargo check` e não grava 35 MB de cache.
3. **Mesmo com o incremental, uma linha mudada custa 40% do build inteiro** (0,52 contra 1,29 s), enquanto o C recompila só o arquivo. Hipótese não verificada: expansão, leitura dos arquivos e resolução de nomes refazem o crate inteiro, e o grafo de 515 mil nós precisa ser carregado e conferido. Próximo passo: perfil do rebuild incremental.
4. **Candidato a otimização no rustc: `check_coroutine_obligations`.** Desde [rust-lang/rust#152327](https://github.com/rust-lang/rust/pull/152327) (fev/2026), o `mir_borrowck` a chama em toda função; antes ela só rodava para coroutines (`async`). A função ([check.rs](https://github.com/rust-lang/rust/blob/main/compiler/rustc_hir_analysis/src/check/check.rs)) monta um contexto de inferência antes de olhar a lista de predicados pendentes, que é vazia em qualquer função sem `async`. Um retorno antecipado com a lista vazia parece equivalente: sem obrigação não há erro nem tipo opaco a conferir. Não foi testado com a suíte do rustc. O ganho é pequeno (0,8% do perfil neste cenário), mas a mudança é de poucas linhas e um primeiro PR barato. `check_transmutes` já percorre uma lista vazia sem custo; o que pesa nela é só a consulta existir.

## Projetos reais (2026-11-20)

Medido em clones de projetos de verdade, no ciclo "mudei uma função, recompila os testes" (`cargo test --no-run`), cinco execuções cada, na fila `heavy-run` com outras cargas na máquina.

**Debuginfo, no Sussurro** (um crate, dependências pesadas). Dados em [`results/2026-11-20-jaime-setup-sussurro-debuginfo`](results/2026-11-20-jaime-setup-sussurro-debuginfo).

| | debug completo (padrão) | `line-tables-only`, dependências sem debug |
|---|---:|---:|
| tempo (mediana) | 5.35 s | 1.69 s |
| instruções | 8.8 bi | 4.2 bi |
| RAM pico | 1.2 GiB | 0.48 GiB |
| `target/` | 3.0 GB | 1.5 GB |

O build de dev padrão gera debuginfo completo do projeto e de todas as dependências, e escrever e ligar isso custa metade do ciclo. Com `line-tables-only` o backtrace continua com arquivo e linha; o que se perde é inspecionar variáveis no depurador. Para isso, um perfil separado com `debug = true`.

```toml
[profile.dev]
debug = "line-tables-only"

[profile.dev.package."*"]
debug = false
```

**Linker, no serverust** (13 crates, 61 binários de teste). Dados em [`results/2026-11-20-jaime-setup-serverust-linker`](results/2026-11-20-jaime-setup-serverust-linker). O wild não ganhou do lld, o padrão desde o Rust 1.90: mediana de 17,6 s contra 17,9 s, dentro do ruído de ±3 s, e 11% mais instruções. Neste ciclo o tempo vai em recompilar os dependentes, não em ligar.

## Doctor

`./doctor.py <projeto>...` lê `Cargo.toml`, `.cargo/config.toml`, `rust-toolchain` e os workflows do GitHub Actions e aponta o que deixa o build lento: CI com incremental ligado ou sem cache, debuginfo completo no dev, toolchain anterior ao lld padrão e crate grande demais. Cada item diz de onde vem a recomendação: medição deste laboratório ou documentação. Só lê arquivos. Os testes ficam em `tests/test_doctor.py` (`python3 -m unittest tests/test_doctor.py`).

Uma armadilha que o doctor evita: `[profile]` em `.cargo/config.toml`, inclusive o global em `~/.cargo/config.toml`, vence o do `Cargo.toml`. Por isso o ajuste de debuginfo vai no `Cargo.toml` de cada projeto, e não na config da máquina, onde passaria por cima de escolhas feitas de propósito.

## Objetivo e frentes

Deixar o ciclo de compilação dos projetos Rust o mais perto possível de Go, Pascal e C, sem trocar de linguagem. São três frentes, que se alimentam:

1. **Medir** (este laboratório): o mesmo programa em várias linguagens e técnicas, e medições em clones de projetos reais. Cada técnica nova da comunidade vira uma coluna.
2. **Aplicar** (o doctor): o que a medição prova vira checagem, e o doctor aponta em cada projeto o que falta. Uma recomendação só entra com evidência: medição daqui ou documentação citada.
3. **Contribuir com o Rust**: levar ao compilador e às ferramentas o que as medições mostram. Primeiro candidato: o retorno antecipado em `check_coroutine_obligations`.

### O que já existe

- [cargo-wizard](https://github.com/kobzol/cargo-wizard), de Jakub Beránek (Kobzol), que trabalha no desempenho do compilador. **Aplica** modelos de perfil (compilação rápida, binário rápido, binário pequeno) por um diálogo ou com `cargo wizard apply`. Não audita o CI, não compara projetos nem traz medição. Ativo: v0.2.3 em 2026-04.
- [cargo-kit](https://docs.rs/crate/cargo-kit): aplica modelos parecidos, com bem menos uso.
- O doctor ocupa o espaço que esses dois deixam: só lê, olha CI e toolchain além do perfil, roda em vários projetos de uma vez e diz de onde vem cada recomendação. Um caminho natural é propor ao cargo-wizard um modo de auditoria (`cargo wizard check`), em vez de manter uma ferramenta paralela.

### Decisões

- **O linker fica no padrão (lld).** No serverust o wild não ganhou: 17,6 contra 17,9 s, dentro do ruído, com 11% mais instruções.
- **O debuginfo é ajustado em cada `Cargo.toml`, não em `~/.cargo/config.toml`.** O `[profile]` da config vence o do manifesto e passaria por cima de escolhas feitas de propósito.
- **No CI, o `Swatinem/rust-cache` já desliga o incremental.** Não é preciso `CARGO_INCREMENTAL=0` à parte quando ele está presente.
- **A config global da máquina continua com sccache.** O Cranelift fica opcional pelo `cargo dev` (`~/.local/bin/cargo-dev`), que precisa de nightly.

### Próximos passos

- Aplicar o debuginfo reduzido nos projetos que o doctor aponta. O Sussurro está em andamento; Switchyard, jira-hours, wasm-server-rust, homestead-kitchen e os projetos da empresa ainda não começaram.
- Refazer a primeira rodada com a edição em um arquivo só, numa máquina parada.
- Perfil (`-Zself-profile`) do rebuild incremental, para ver onde vão os 0,52 s de uma linha mudada.
- Testar no Go a edição numa função `//go:noinline`, para confirmar se o inlining é o que faz ele recompilar os dependentes.
- Cenário com genéricos e traits, onde a monomorfização pesa.
- Abrir no rustc o PR do retorno antecipado em `check_coroutine_obligations`, com a suíte do compilador.
- Propor o modo de auditoria ao cargo-wizard, levando as checagens e a evidência do doctor.
- Um modelo de projeto novo (camada 2) já com o perfil de dev ajustado, ou adotar um modelo pronto se existir.

## Limites conhecidos

- O código sintético mede a escala do compilador, não um projeto real: não tem genéricos, traits, macros nem dependências externas, que são justamente onde o Rust mais gasta. Próximos cenários: genéricos com muitas instanciações e um workspace com várias crates.
- Rust, Go, Odin, Zig e V compilam o programa como uma unidade; C e Pascal compilam um arquivo por vez. Isso é parte da diferença entre as linguagens, não um erro de medição.
- Só mede o build de debug. O tempo do build otimizado e a velocidade do binário gerado entram depois.

## Licença

MIT
