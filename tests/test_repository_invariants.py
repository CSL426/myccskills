import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def repository_shell_scripts() -> list[str]:
    shell_scripts = sorted(
        path.relative_to(REPO_ROOT).as_posix()
        for path in REPO_ROOT.rglob("*.sh")
        if ".git" not in path.parts
    )
    assert shell_scripts
    return shell_scripts


def test_shell_scripts_are_forced_to_lf_by_gitattributes() -> None:
    shell_scripts = repository_shell_scripts()
    result = subprocess.run(
        ["git", "check-attr", "eol", "--", *shell_scripts],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    expected = [f"{script}: eol: lf" for script in shell_scripts]
    assert result.stdout.splitlines() == expected


def test_tracked_shell_scripts_do_not_contain_crlf() -> None:
    shell_scripts = repository_shell_scripts()

    for script in shell_scripts:
        assert b"\r\n" not in (REPO_ROOT / script).read_bytes(), (
            f"{script} contains CRLF"
        )


def test_root_instruction_files_are_identical_regular_files() -> None:
    instruction_files = [
        REPO_ROOT / name
        for name in ("CLAUDE.md", "AGENTS.md", "GEMINI.md")
    ]

    for instruction_file in instruction_files:
        assert instruction_file.is_file()
        assert not instruction_file.is_symlink(), f"{instruction_file.name} must not be a symlink"

    expected = instruction_files[0].read_bytes()
    for instruction_file in instruction_files[1:]:
        assert instruction_file.read_bytes() == expected
