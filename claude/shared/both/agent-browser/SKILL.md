# agent-browser

Headless browser automation. Use `agent-browser` CLI to control a browser for web automation tasks.

allowed-tools: Bash(agent-browser:*)

## Workflow

1. `agent-browser open <url>` — navigate to a page
2. `agent-browser snapshot -i` — get interactive elements with refs (e.g. @e1, @e2)
3. `agent-browser screenshot --annotate` — take labeled screenshot for visual reference
4. `agent-browser click @e1` / `agent-browser fill @e2 "text"` — interact with elements
5. Chain commands with `&&` — browser persists via daemon between calls

## Key Commands

```bash
agent-browser open <url>
agent-browser snapshot -i              # Interactive elements only (recommended first step)
agent-browser screenshot [path]        # Screenshot (--full for full page, --annotate for labels)
agent-browser click <sel|@ref>
agent-browser fill <sel|@ref> <text>
agent-browser type <sel|@ref> <text>
agent-browser press <key>              # Enter, Tab, Control+a, etc.
agent-browser wait <sel|ms>            # Wait for element or milliseconds
agent-browser eval <js>                # Run JavaScript
agent-browser get text <sel|@ref>      # Get element text
agent-browser find role button click --name Submit
```

## Tips

- Always run `snapshot -i` after navigation to discover element refs
- Use `--annotate` screenshots to visually identify elements
- Use `&&` chaining for multi-step flows in one shell call
- Use `--session-name <name>` to persist login state across runs
- Use `--auto-connect` to attach to an already-running Chrome
