# cargo check com e sem incremental (note2, 2026-11-20)

Cenário `50x200` (crate único), rustc/cargo 1.100.0, note2 parada (load 0,02 antes e 0,30 depois).
`perf` bloqueado na máquina (`perf_event_paranoid=4`), por isso só tempo de relógio.
Sete execuções de cada modo, alternadas; a mediana está no README principal.

Build limpo (`cargo clean` antes de cada execução), em segundos:

| execução | incremental | sem incremental |
|---:|---:|---:|
| 1 | 1.838 | 1.293 |
| 2 | 1.593 | 1.275 |
| 3 | 1.568 | 1.283 |
| 4 | 1.580 | 1.314 |
| 5 | 1.580 | 1.286 |
| 6 | 1.597 | 1.297 |
| 7 | 1.573 | 1.296 |

Mudou uma linha em `src/m0.rs` (um arquivo só), em segundos:

| execução | incremental | sem incremental |
|---:|---:|---:|
| 1 | 0.527 | 1.302 |
| 2 | 0.517 | 1.291 |
| 3 | 0.508 | 1.287 |
| 4 | 0.515 | 1.302 |
| 5 | 0.510 | 1.288 |
| 6 | 0.519 | 1.294 |
| 7 | 0.521 | 1.307 |

Disco: `target` com incremental 35 MB (34 MB em `debug/incremental`), sem incremental 60 KB.

Comando de cada execução:

```bash
CARGO_INCREMENTAL=$inc CARGO_TARGET_DIR=/tmp/csl-inc$inc cargo check -q
```
