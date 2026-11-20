"""Testes do doctor: cada checagem com um projeto que passa e um que precisa melhorar."""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import doctor  # noqa: E402


def make_project(files: dict[str, str]) -> Path:
    root = Path(tempfile.mkdtemp(prefix="doctor-"))
    for rel, text in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    return root


def status_of(root: Path, check: str) -> str:
    findings = doctor.diagnose(doctor.load_facts(root))
    return next(f.status for f in findings if f.check == check)


PKG = '[package]\nname = "x"\nversion = "0.1.0"\nedition = "2021"\n'
LINE_TABLES = '\n[profile.dev]\ndebug = "line-tables-only"\n\n[profile.dev.package."*"]\ndebug = false\n'


class CiIncrementalTest(unittest.TestCase):
    def test_rust_cache_already_disables_incremental(self) -> None:
        root = make_project({"Cargo.toml": PKG,
                             ".github/workflows/ci.yml": "steps:\n  - uses: Swatinem/rust-cache@v2\n"})
        self.assertEqual(status_of(root, "ci-incremental"), "ok")

    def test_ci_without_cache_or_env_needs_fix(self) -> None:
        root = make_project({"Cargo.toml": PKG, ".github/workflows/ci.yml": "run: cargo test\n"})
        self.assertEqual(status_of(root, "ci-incremental"), "melhorar")

    def test_actions_cache_of_target_counts_as_cache(self) -> None:
        workflow = "- uses: actions/cache@v4\n  with:\n    path: |\n      ~/.cargo/registry/cache\n      target\n"
        root = make_project({"Cargo.toml": PKG, ".github/workflows/ci.yml": workflow})
        self.assertEqual(status_of(root, "ci-cache"), "ok")

    def test_no_ci_is_only_info(self) -> None:
        root = make_project({"Cargo.toml": PKG})
        self.assertEqual(status_of(root, "ci-incremental"), "info")


class DevDebuginfoTest(unittest.TestCase):
    def test_default_full_debuginfo_needs_fix(self) -> None:
        root = make_project({"Cargo.toml": PKG})
        self.assertEqual(status_of(root, "dev-debuginfo"), "melhorar")

    def test_explicit_debug_true_needs_fix(self) -> None:
        root = make_project({"Cargo.toml": PKG + "\n[profile.dev]\ndebug = true\n"})
        self.assertEqual(status_of(root, "dev-debuginfo"), "melhorar")

    def test_line_tables_with_deps_off_is_ok(self) -> None:
        root = make_project({"Cargo.toml": PKG + LINE_TABLES})
        self.assertEqual(status_of(root, "dev-debuginfo"), "ok")

    def test_debug_zero_also_covers_dependencies(self) -> None:
        root = make_project({"Cargo.toml": PKG + "\n[profile.dev]\ndebug = 0\n"})
        self.assertEqual(status_of(root, "dev-debuginfo"), "ok")

    def test_line_tables_without_deps_override_is_only_info(self) -> None:
        root = make_project({"Cargo.toml": PKG + '\n[profile.dev]\ndebug = "line-tables-only"\n'})
        self.assertEqual(status_of(root, "dev-debuginfo"), "info")

    def test_setting_in_cargo_config_counts(self) -> None:
        root = make_project({"Cargo.toml": PKG, ".cargo/config.toml": LINE_TABLES})
        self.assertEqual(status_of(root, "dev-debuginfo"), "ok")


class ToolchainTest(unittest.TestCase):
    def test_pin_before_lld_default_needs_fix(self) -> None:
        root = make_project({"Cargo.toml": PKG, "rust-toolchain.toml": '[toolchain]\nchannel = "1.85.0"\n'})
        self.assertEqual(status_of(root, "toolchain"), "melhorar")

    def test_recent_pin_is_ok(self) -> None:
        root = make_project({"Cargo.toml": PKG, "rust-toolchain.toml": '[toolchain]\nchannel = "1.94.1"\n'})
        self.assertEqual(status_of(root, "toolchain"), "ok")

    def test_stable_channel_is_ok(self) -> None:
        root = make_project({"Cargo.toml": PKG, "rust-toolchain": "stable\n"})
        self.assertEqual(status_of(root, "toolchain"), "ok")


class BigCrateTest(unittest.TestCase):
    def test_crate_above_threshold_needs_fix(self) -> None:
        big = "fn f() {}\n" * (doctor.BIG_CRATE_LINES + 1)
        root = make_project({"Cargo.toml": PKG, "src/main.rs": big})
        self.assertEqual(status_of(root, "crate-grande"), "melhorar")

    def test_nested_member_lines_are_not_counted_in_parent(self) -> None:
        big = "fn f() {}\n" * (doctor.BIG_CRATE_LINES // 2 + 1)
        root = make_project({"Cargo.toml": PKG + '\n[workspace]\nmembers = ["a"]\n', "src/main.rs": big,
                             "a/Cargo.toml": PKG.replace('"x"', '"a"'), "a/src/lib.rs": big})
        self.assertEqual(status_of(root, "crate-grande"), "ok")


class RenderTest(unittest.TestCase):
    def test_report_lists_every_check(self) -> None:
        root = make_project({"Cargo.toml": PKG})
        report = doctor.render(root, doctor.diagnose(doctor.load_facts(root)))
        for check in ("ci-incremental", "ci-cache", "dev-debuginfo", "toolchain", "crate-grande"):
            self.assertIn(check, report)

    def test_missing_manifest_is_reported_with_path(self) -> None:
        root = make_project({"README.md": "x"})
        with self.assertRaisesRegex(ValueError, "Cargo.toml"):
            doctor.load_facts(root)


if __name__ == "__main__":
    unittest.main()
