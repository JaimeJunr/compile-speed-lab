#!/usr/bin/env python3
"""Audita a configuração de compilação de um projeto Rust e aponta o que deixa o build lento.

    ./doctor.py <projeto> [<projeto>...]

Só lê arquivos. Cada recomendação diz de onde vem: medição deste laboratório ou documentação.
"""

import re
import sys
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# Tamanho do crate do cenário 50x200 do lab, onde mudar uma linha ainda custa 40% do check.
BIG_CRATE_LINES = 60_000
# Primeira stable em que o x86_64 Linux liga com lld por padrão.
LLD_DEFAULT_VERSION = (1, 90)
SKIP_DIRS = {"target", ".git", "node_modules", "work"}

TomlTable = dict[str, Any]


@dataclass
class Finding:
    check: str
    status: str  # ok, melhorar ou info
    detail: str
    fix: str = ""
    evidence: str = ""


@dataclass
class ProjectFacts:
    root: Path
    manifest: TomlTable
    cargo_config: TomlTable
    toolchain: str | None
    workflows: list[str]
    crate_lines: dict[str, int] = field(default_factory=dict)


def read_toml(path: Path) -> TomlTable:
    return tomllib.loads(path.read_text()) if path.is_file() else {}


def read_toolchain(root: Path) -> str | None:
    toml_file = root / "rust-toolchain.toml"
    if toml_file.is_file():
        return read_toml(toml_file).get("toolchain", {}).get("channel")
    plain = root / "rust-toolchain"
    return plain.read_text().strip() if plain.is_file() else None


def read_workflows(root: Path) -> list[str]:
    folder = root / ".github" / "workflows"
    if not folder.is_dir():
        return []
    return [p.read_text() for p in sorted(folder.iterdir()) if p.suffix in (".yml", ".yaml")]


def package_dirs(root: Path) -> list[Path]:
    found: list[Path] = []
    for manifest in root.rglob("Cargo.toml"):
        if SKIP_DIRS.isdisjoint(manifest.relative_to(root).parts) and "package" in read_toml(manifest):
            found.append(manifest.parent)
    return found


def count_crate_lines(root: Path) -> dict[str, int]:
    """Linhas de .rs por pacote, sem contar membros aninhados dentro do diretório de outro."""
    dirs = package_dirs(root)
    lines: dict[str, int] = {}
    for pkg in dirs:
        nested = [d for d in dirs if d != pkg and d.is_relative_to(pkg)]
        total = 0
        for src in pkg.rglob("*.rs"):
            rel = src.relative_to(pkg).parts
            if SKIP_DIRS.isdisjoint(rel) and not any(src.is_relative_to(n) for n in nested):
                total += len(src.read_text(errors="replace").splitlines())
        lines[str(pkg.relative_to(root)) or "."] = total
    return lines


def load_facts(root: Path) -> ProjectFacts:
    manifest_path = root / "Cargo.toml"
    if not manifest_path.is_file():
        raise ValueError(f"projeto inválido: {root} não tem Cargo.toml, esperado a raiz de um crate ou workspace")
    return ProjectFacts(root, read_toml(manifest_path), read_toml(root / ".cargo" / "config.toml"),
                        read_toolchain(root), read_workflows(root), count_crate_lines(root))


def check_ci_incremental(facts: ProjectFacts) -> Finding:
    if not facts.workflows:
        return Finding("ci-incremental", "info", "sem workflow do GitHub Actions")
    text = "\n".join(facts.workflows)
    if "Swatinem/rust-cache" in text or re.search(r"CARGO_INCREMENTAL:\s*[\"']?0", text):
        return Finding("ci-incremental", "ok", "incremental desligado no CI (rust-cache ou CARGO_INCREMENTAL=0)")
    return Finding("ci-incremental", "melhorar", "CI compila do zero com o incremental ligado",
                   "`CARGO_INCREMENTAL: 0` no `env` do workflow",
                   "lab: incremental custa +22% no `cargo check` limpo")


def check_ci_cache(facts: ProjectFacts) -> Finding:
    if not facts.workflows:
        return Finding("ci-cache", "info", "sem workflow do GitHub Actions")
    text = "\n".join(facts.workflows)
    caches_target = "actions/cache" in text and re.search(r"^\s*target\s*$", text, re.MULTILINE)
    if "Swatinem/rust-cache" in text or "sccache" in text or caches_target:
        return Finding("ci-cache", "ok", "CI guarda as dependências compiladas entre execuções")
    return Finding("ci-cache", "melhorar", "CI recompila todas as dependências a cada execução",
                   "`- uses: Swatinem/rust-cache@v2` depois de instalar a toolchain",
                   "documentação do rust-cache")


def dev_profile(facts: ProjectFacts) -> TomlTable:
    # Perfil em .cargo/config.toml vence o do Cargo.toml.
    merged: TomlTable = dict(facts.manifest.get("profile", {}).get("dev", {}))
    merged.update(facts.cargo_config.get("profile", {}).get("dev", {}))
    return merged


NO_DEBUGINFO = (False, 0, "none")


def check_dev_debuginfo(facts: ProjectFacts) -> Finding:
    profile = dev_profile(facts)
    debug = profile.get("debug", True)
    # Sem override de pacote, as dependências herdam o debug do [profile.dev].
    deps_debug = profile.get("package", {}).get("*", {}).get("debug", debug)
    fix = '`[profile.dev] debug = "line-tables-only"` e `[profile.dev.package."*"] debug = false`'
    evidence = "Cargo book (profiles); não medido no lab"
    if debug in (True, 2, "full"):
        return Finding("dev-debuginfo", "melhorar", "build de dev gera debuginfo completo", fix, evidence)
    if deps_debug not in NO_DEBUGINFO:
        return Finding("dev-debuginfo", "info", f"debug = {debug!r}, e as dependências também",
                       '`[profile.dev.package."*"] debug = false`', evidence)
    return Finding("dev-debuginfo", "ok", f"debug = {debug!r}, dependências sem debuginfo")


def parse_version(channel: str) -> tuple[int, int] | None:
    match = re.fullmatch(r"(\d+)\.(\d+)(\.\d+)?", channel)
    return (int(match[1]), int(match[2])) if match else None


def check_toolchain(facts: ProjectFacts) -> Finding:
    if facts.toolchain is None:
        return Finding("toolchain", "ok", "sem toolchain fixa: usa a stable instalada")
    version = parse_version(facts.toolchain)
    if version is not None and version < LLD_DEFAULT_VERSION:
        return Finding("toolchain", "melhorar", f"toolchain fixa em {facts.toolchain}, anterior ao lld padrão",
                       "subir para 1.90 ou mais nova", "release notes do Rust 1.90 (lld padrão no x86_64 Linux)")
    return Finding("toolchain", "ok", f"toolchain {facts.toolchain}")


def check_big_crate(facts: ProjectFacts) -> Finding:
    if not facts.crate_lines:
        return Finding("crate-grande", "info", "nenhum pacote encontrado")
    name, lines = max(facts.crate_lines.items(), key=lambda item: item[1])
    detail = f"maior crate: `{name}` com {lines} linhas ({len(facts.crate_lines)} crates)"
    if lines > BIG_CRATE_LINES:
        return Finding("crate-grande", "melhorar", detail, "dividir em crates menores, com a parte que muda menos embaixo",
                       "lab: num crate de 60 mil linhas, mudar uma linha custa 40% do `cargo check` inteiro")
    return Finding("crate-grande", "ok", detail)


CHECKS = (check_ci_incremental, check_ci_cache, check_dev_debuginfo, check_toolchain, check_big_crate)


def diagnose(facts: ProjectFacts) -> list[Finding]:
    return [check(facts) for check in CHECKS]


def render(root: Path, findings: list[Finding]) -> str:
    rows = [f"## {root.name}", "", "| checagem | situação | o que achou | como resolver | de onde vem |",
            "|---|---|---|---|---|"]
    rows += [f"| {f.check} | {f.status} | {f.detail} | {f.fix} | {f.evidence} |" for f in findings]
    return "\n".join(rows) + "\n"


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 64
    worst = 0
    for arg in argv:
        root = Path(arg).resolve()
        findings = diagnose(load_facts(root))
        print(render(root, findings))
        if any(f.status == "melhorar" for f in findings):
            worst = 1
    return worst


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
