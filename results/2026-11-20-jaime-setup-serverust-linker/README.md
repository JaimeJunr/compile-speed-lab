# lld contra wild no serverust (2026-11-20)

serverust em `d869782` (workspace de 13 crates, 61 binários de teste), rustc 1.94.1 fixado pelo projeto.
Ciclo medido: trocar um número numa função privada de `serverust-core` (`edit.sh`) e rodar
`cargo test --workspace --no-run`, que recompila os dependentes e religa todos os testes.
Cinco execuções por linker, com a fila `heavy-run` (4 núcleos) e a máquina com outras cargas.

| linker | tempo, cada execução (s) | instruções (bi) |
|---|---|---|
| lld (padrão desde o Rust 1.90) | 15.36, 17.46, 17.87, 20.32, 23.97 | 32.1 a 34.0 |
| wild via clang | 13.11, 14.60, 17.56, 19.95, 21.08 | 35.8 a 37.6 |

O script original roda num clone em `~/.cache/rust-lab`; `medir-linker.sh` é o que foi usado.
