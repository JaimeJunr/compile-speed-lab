# Front-end paralelo e Cranelift do nightly em três projetos reais (note2, 2026-11-21)

Medido em 2026-11-21 na note2: Intel i5-1135G7, 4 núcleos, máquina parada, sem sccache.
Toolchain `rustc 1.102.0-nightly (c7d5ba59d 2026-11-20)`, LLVM 23.1.6 (`rodada1/env.txt`).

Desde `nightly-2026-11-14` o front-end paralelo vem ligado por padrão com 2 threads
([anúncio](https://blog.rust-lang.org/2026/11/16/enabling-parallel-frontend-on-nightly/)), e o time
pede relatos de uso real. Este teste mede esse padrão contra o front-end sequencial e contra 4 threads,
e o back-end Cranelift, numa máquina do tamanho de um runner padrão de CI.

## Projetos e configurações

| projeto | commit | linhas `.rs` | pacotes no lock | ponto de edição |
|---|---|---:|---:|---|
| context-engine | `d7e8591` | 15 mil | 293 | `src/shared/config.rs`, `config_path` |
| serverust | `8c15d3e` (main) | 26 mil | 431 | `serverust-core/src/config.rs`, `default` |
| Switchyard | `09c4d5c` | 79 mil | 328 | `crates/libsy/src/observability.rs` (crate base de 6 outras) |

`run.sh` define as configurações: `fe1` front-end sequencial (`-Zunstable-options --jobs-frontend=1`,
o comportamento do stable), `fe2` padrão do nightly (2 threads), `fe4` 4 threads, `cl2` Cranelift
(`CARGO_PROFILE_DEV_CODEGEN_BACKEND=cranelift`) com o front-end padrão. A contagem de threads entra por
`--config target.<triplo>.rustflags`, que se soma aos rustflags do Switchyard em vez de trocá-los.

- **Do zero** (`bench.sh`): `cargo check` e `cargo build` com o target apagado, 3 rodadas, configurações
  alternadas dentro de cada rodada para o aquecimento do notebook não favorecer nenhuma. RAM é o pico
  do maior processo (`/usr/bin/time %M`).
- **Uma linha mudada**: `edit-sync.sh` troca o número de um `black_box` no corpo de uma função não
  genérica e roda `sync`; `hyperfine` com 2 de aquecimento e 20 medidas de `cargo build`.

## Resultado

Rodada 1 (`rodada1/`), média de 3 do zero e mediana de 20 no rebuild:

| | context-engine | serverust | Switchyard |
|---|---:|---:|---:|
| check, sequencial | 24,4 s | 50,3 s | 39,2 s |
| check, 2 threads | 26,2 s (+7%) | 50,5 s (0%) | 41,5 s (+6%) |
| check, 4 threads | 25,8 s (+6%) | 50,0 s (−1%) | 41,5 s (+6%) |
| build, sequencial | 33,0 s | 67,2 s | 61,2 s |
| build, 2 threads | 36,9 s (+12%) | 72,8 s (+8%) | 68,0 s (+11%) |
| build, 4 threads | 35,0 s (+6%) | 72,9 s (+8%) | 66,2 s (+8%) |
| rebuild de uma linha, seq / 2 / 4 threads | 1,05 / 1,07 / 1,03 s | 0,82 / 0,83 / 0,84 s | 2,46 / 2,50 / 2,41 s |
| pico de RAM no check, seq → 4 threads | 500 → 527 MB | 781 → 838 MB | 409 → 417 MB |

Cranelift (rodada 1 para o context-engine, rodada 2 para os outros):

| | context-engine | serverust | Switchyard |
|---|---:|---:|---:|
| build do zero, LLVM 2 threads → Cranelift | 36,9 → 35,9 s (−3%) | 71,3 → 67,1 s (−6%) | 63,7 → 57,3 s (−10%) |
| rebuild de uma linha, LLVM → Cranelift | 1,07 → 1,05 s | 0,85 → 0,83 s | 2,46 → 2,44 s |

1. **Em 4 núcleos, o padrão novo do nightly deixa o build do zero mais lento.** Com 2 threads, o build
   ficou de 8% a 12% mais lento nos três projetos, e o check de 0% a 7%. Com 4 threads, o build ficou de
   6% a 8% mais lento. O pico de RAM sobe até 7%. Uma primeira rodada, cujos arquivos brutos se perderam numa sincronização,
   deu o mesmo sentido (por exemplo, check do context-engine 23,8 → 26,4 s).
2. **No rebuild de uma linha, o front-end paralelo não muda nada.** As diferenças ficam abaixo de 4%,
   dentro do ruído. É o ciclo em que o anúncio também espera pouco (3 a 5%).
3. **O Cranelift só ajuda no build do zero.** Ganha de 3% a 10%, mais nos projetos com mais código, e
   não encurta o rebuild de uma linha.
4. **O Cranelift quebra o link com `aws-lc-rs` anterior a 1.18.2**, que vem com o `rustls`: os símbolos
   `aws_lc_0_xx_0_*` ficam indefinidos. É o [aws-lc-rs#1231](https://github.com/aws/aws-lc-rs/issues/1231),
   corrigido em 1.18.2. O serverust (1.18.1) e o Switchyard (1.17.1) quebravam; na rodada 2 os dois
   rodaram com `cargo update -p aws-lc-rs` (1.19.0, `rodada2/lock-*.txt`), o mesmo lock nas duas colunas
   comparadas.

**Por que o paralelo não ganha aqui (provável, não verificado):** no build do zero o Cargo já ocupa os 4
núcleos com crates em paralelo, e as threads extras do front-end só disputam os mesmos núcleos. O
anúncio mede ganho maior por crate isolada, e o ganho de ponta a ponta que ele cita (15% no `cargo check`
do cargo) é com 8 núcleos e 8 threads. **Por que o Cranelift não ganha no rebuild:** falta saber onde vão
os 0,8 a 2,5 s; o próximo passo é o `-Zself-profile` desse rebuild.

## Armadilha de método

Sem o `sync` antes de cada medida, o rebuild do Switchyard oscilava entre 2,4 e 6 s com o mesmo tempo de
CPU (cerca de 4,8 s): a gravação pendente do `target/` de 1,3 GB caía dentro da medida. Nessa versão,
4 threads pareciam 46% mais rápidas que o sequencial; com o `sync`, a diferença sumiu.

## Limites

- Só 4 núcleos. Numa máquina de 8 ou 16 núcleos, o resultado pode virar, e é preciso medir antes de
  mudar o `cargo dev` (que usa 4 threads e Cranelift).
- Três rodadas do zero por configuração; os intervalos estão em `rodada1/clean.csv` e são de 1 a 6 s.
- `du.txt` traz o tamanho do `target/` por configuração: o front-end não muda nada; com Cranelift, o do
  context-engine fica um pouco maior (598 contra 576 MB).

Para refazer: `frota rodar --em note2-jaime --projeto <pasta com projects/ e estes scripts> --bg -- bash bench.sh`
e depois `bench2.sh`. Traga `results-fe*/` antes de sincronizar de novo: o `frota rodar` usa `rsync --delete`.
