#!/usr/bin/env bash
# Troca o número da linha "// LAB-EDIT" do arquivo: mudança de corpo sem mexer em interface.
set -euo pipefail
sed -i -E "s#[0-9]+( } // LAB-EDIT)\$#$((RANDOM + 1))\1#" "$1"
