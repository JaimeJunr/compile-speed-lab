#!/usr/bin/env bash
# Troca o número do black_box na linha "// LAB-EDIT": mudança de corpo, sem mexer em interface.
set -euo pipefail
sed -i -E "s#black_box\([0-9]+\); // LAB-EDIT#black_box($((RANDOM + 1))); // LAB-EDIT#" "$1"
grep -q "LAB-EDIT" "$1"
