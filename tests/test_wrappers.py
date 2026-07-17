import os
import subprocess
import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
pytestmark = pytest.mark.skipif(os.name == "nt", reason="Unix shell wrapper contract")


def test_shell_wrapper_runs_from_outside_repo(tmp_path: Path) -> None:
    result = subprocess.run(
        [str(REPO_ROOT / "ai-config.sh"), "help"],
        cwd=tmp_path,
        env=os.environ.copy(),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr + result.stdout
    assert "./ai-config.sh <command> [tool]" in result.stdout


def test_shell_wrapper_preserves_python_exit_code(tmp_path: Path) -> None:
    result = subprocess.run(
        [str(REPO_ROOT / "ai-config.sh"), "explode"],
        cwd=tmp_path,
        env=os.environ.copy(),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    assert "Unknown command" in result.stderr + result.stdout


def test_shell_wrapper_falls_back_from_old_python3(tmp_path: Path) -> None:
    binaries = tmp_path / "bin"
    binaries.mkdir()
    (binaries / "bash").symlink_to("/bin/bash")
    (binaries / "dirname").symlink_to("/usr/bin/dirname")
    (binaries / "python").symlink_to(sys.executable)
    old_python = binaries / "python3"
    old_python.write_text("#!/bin/bash\nexit 1\n")
    old_python.chmod(0o755)
    env = os.environ.copy()
    env["PATH"] = str(binaries)

    result = subprocess.run(
        [str(REPO_ROOT / "ai-config.sh"), "help"],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr + result.stdout


def test_shell_wrapper_reports_missing_python(tmp_path: Path) -> None:
    binaries = tmp_path / "bin"
    binaries.mkdir()
    (binaries / "bash").symlink_to("/bin/bash")
    (binaries / "dirname").symlink_to("/usr/bin/dirname")
    env = os.environ.copy()
    env["PATH"] = str(binaries)

    result = subprocess.run(
        [str(REPO_ROOT / "ai-config.sh"), "help"],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    assert "requires Python 3.11 or newer" in result.stderr


def test_shell_wrapper_works_through_path_symlink(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    link = bin_dir / "ai-config"
    link.symlink_to(REPO_ROOT / "ai-config.sh")

    result = subprocess.run(
        [str(link), "help"],
        cwd=tmp_path,
        env=os.environ.copy(),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr + result.stdout
    assert "./ai-config.sh <command> [tool]" in result.stdout


def test_installer_bootstraps_into_isolated_home(tmp_path: Path) -> None:
    home = tmp_path / "home"
    home.mkdir()
    env = os.environ.copy()
    env["HOME"] = str(home)
    env["AI_CONFIG_VENV"] = str(home / ".venvs" / "ai-config")

    result = subprocess.run(
        ["bash", str(REPO_ROOT / "install.sh")],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0 and "pip install" in result.stderr + result.stdout:
        pytest.skip("pip could not build editable install (offline environment)")
    assert result.returncode == 0, result.stderr + result.stdout
    # Running from inside the checkout: installs THIS repo, no clone
    assert "Using this checkout" in result.stdout

    shim = home / ".local" / "bin" / "ai-config"
    assert shim.is_symlink()

    run = subprocess.run(
        [str(shim), "help"],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert run.returncode == 0, run.stderr + run.stdout
    assert "<command> [tool]" in run.stdout
