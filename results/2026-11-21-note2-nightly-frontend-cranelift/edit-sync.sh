#!/usr/bin/env bash
# Como edit.sh, mas descarrega o cache de escrita antes da medida: no Switchyard a gravação
# pendente do target/ (1,3 GB) fazia o rebuild oscilar entre 2,4 e 6 s com o mesmo tempo de CPU.
set -euo pipefail
"$(dirname "$0")/edit.sh" "$1"
sync
