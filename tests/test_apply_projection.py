import os
import shutil
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def copy_runtime_files(repo_dir: Path) -> None:
    shutil.copy2(REPO_ROOT / "ai-config.sh", repo_dir / "ai-config.sh")
    shutil.copytree(REPO_ROOT / "scripts", repo_dir / "scripts")
    os.chmod(repo_dir / "ai-config.sh", 0o755)


def run_ai_config(repo_dir: Path, home_dir: Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["HOME"] = str(home_dir)
    return subprocess.run(
        ["bash", "ai-config.sh", *args],
        cwd=repo_dir,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def test_apply_all_projects_claude_shared_content_without_sync(tmp_path: Path) -> None:
    repo_dir = tmp_path / "repo"
    home_dir = tmp_path / "home"
    repo_dir.mkdir()
    home_dir.mkdir()
    copy_runtime_files(repo_dir)

    write(repo_dir / "claude/CLAUDE.md", "shared instructions\n")
    write(repo_dir / "claude/mcp.json", '{"mcpServers":{"demo":{"command":"demo"}}}\n')
    write(
        repo_dir / "claude/settings.json",
        '{"extraKnownMarketplaces":{"demo":{"source":{"repo":"acme/demo"}}}}\n',
    )
    write(
        repo_dir / "claude/agents/shared-agent.md",
        "---\nname: shared-agent\ndescription: Shared agent\n---\nShared agent body.\n",
    )
    write(repo_dir / "claude/rules/common/shared.md", "shared rule\n")

    write(repo_dir / "codex/config.toml", 'model = "gpt-5"\n')
    write(repo_dir / "codex/rules/custom/private.md", "private codex rule\n")
    write(
        repo_dir / "codex/skills/private-skill/SKILL.md",
        "---\nname: private-skill\n---\nPrivate codex skill\n",
    )
    write(repo_dir / "agy/settings.json", '{"theme":"neon"}\n')

    write(
        home_dir / ".codex/config.toml",
        '[projects."/tmp/demo"]\ntrust_level = "trusted"\n',
    )

    result = run_ai_config(repo_dir, home_dir, "apply", "all")

    assert result.returncode == 0, result.stderr + result.stdout
    assert (home_dir / ".claude/CLAUDE.md").read_text(encoding="utf-8") == "shared instructions\n"
    assert (home_dir / ".codex/AGENTS.md").read_text(encoding="utf-8") == "shared instructions\n"
    assert (home_dir / ".gemini/antigravity-cli/mcp_config.json").read_text(encoding="utf-8") == (
        '{"mcpServers":{"demo":{"command":"demo"}}}\n'
    )
    assert (home_dir / ".gemini/antigravity-cli/settings.json").read_text(encoding="utf-8") == (
        '{"theme":"neon"}\n'
    )
    assert (
        home_dir / ".codex/skills/shared-agent/SKILL.md"
    ).read_text(encoding="utf-8").endswith("Shared agent body.\n")
    assert (
        home_dir / ".gemini/antigravity-cli/skills/shared-agent/SKILL.md"
    ).read_text(encoding="utf-8").endswith("Shared agent body.\n")
    assert (home_dir / ".codex/rules/common/shared.md").read_text(encoding="utf-8") == "shared rule\n"
    assert (
        home_dir / ".codex/rules/custom/private.md"
    ).read_text(encoding="utf-8") == "private codex rule\n"
    # Private skills pass through sanitize_skill_frontmatter, which synthesizes
    # description + metadata.short-description for strict parsers.
    private_skill = (home_dir / ".codex/skills/private-skill/SKILL.md").read_text(encoding="utf-8")
    assert "name: private-skill\n" in private_skill
    assert "short-description: " in private_skill
    assert private_skill.endswith("Private codex skill\n")

    codex_config = (home_dir / ".codex/config.toml").read_text(encoding="utf-8")
    assert 'model = "gpt-5"' in codex_config
    assert '[projects."/tmp/demo"]' in codex_config
    assert 'trust_level = "trusted"' in codex_config


def test_apply_codex_links_alternate_runtime_homes_to_canonical_config(tmp_path: Path) -> None:
    repo_dir = tmp_path / "repo"
    home_dir = tmp_path / "home"
    repo_dir.mkdir()
    home_dir.mkdir()
    copy_runtime_files(repo_dir)

    write(repo_dir / "claude/CLAUDE.md", "shared instructions\n")
    write(repo_dir / "codex/config.toml", 'model = "gpt-5"\n')
    write(repo_dir / "codex/rules/common/shared.md", "shared rule\n")
    write(
        repo_dir / "codex/skills/private-skill/SKILL.md",
        "---\nname: private-skill\n---\nPrivate codex skill\n",
    )
    (home_dir / ".codex-csl").mkdir()
    (home_dir / ".codex-set").mkdir()

    result = run_ai_config(repo_dir, home_dir, "apply", "codex")

    assert result.returncode == 0, result.stderr + result.stdout
    for runtime_home in (home_dir / ".codex-csl", home_dir / ".codex-set"):
        for rel_path in ("AGENTS.md", "config.toml", "rules", "skills"):
            linked_path = runtime_home / rel_path
            assert linked_path.is_symlink()
            assert os.readlink(linked_path) == str(home_dir / ".codex" / rel_path)
