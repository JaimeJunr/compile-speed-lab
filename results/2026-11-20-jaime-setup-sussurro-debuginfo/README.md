# debuginfo completo contra line-tables-only no Sussurro (2026-11-20)

Sussurro em `cc0b2b8` (um crate, dependências pesadas como whisper.cpp e Tauri), rustc 1.100.0.
Ciclo medido: trocar um número numa função privada de `src/paths.rs` (`edit.sh`) e rodar
`cargo test --no-run`. `slim.toml` é a config passada com `--config` na variante reduzida.
Cinco execuções por variante, com a fila `heavy-run` (4 núcleos). O clone precisou de um
`ui/dist/index.html` vazio, porque o Tauri exige a pasta do front no build.

| variante | tempo, cada execução (s) | instruções (bi) | RAM pico | `target/` |
|---|---|---:|---:|---:|
| debug completo (padrão do Cargo) | 2.51, 3.19, 5.35, 5.90, 8.45 | 8.8 | 1.2 GiB | 3.0 GB |
| `debug = "line-tables-only"`, dependências com `debug = false` | 1.67, 1.67, 1.69, 1.70, 2.20 | 4.2 | 0.48 GiB | 1.5 GB |
