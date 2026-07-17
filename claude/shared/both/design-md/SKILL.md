---
name: design-md
description: Apply real-world design systems (Stripe, Linear, Notion, etc.) to frontend work. Use when the user asks to build UI in a specific brand's style, or wants design style recommendations. Fetches curated DESIGN.md files via the getdesign CLI.
---

# design-md

Apply curated design systems from 58+ real-world brands to frontend development using the `getdesign` CLI.

allowed-tools: Bash(npx getdesign*), Read, Glob

## Determine Mode

1. **User named a brand** (e.g., "use stripe style", "apply linear design", `/design-md notion`) → go to **Direct Mode**
2. **User described a vibe or use case** (e.g., "something clean for a medical app", "dark techy dashboard") → go to **Recommendation Mode**
3. **User said `/design-md`** with no argument → go to **Recommendation Mode**

## Direct Mode

```bash
npx getdesign add <brand> --out ./DESIGN.md --force
```

If the command fails (brand not found), run `npx getdesign list` and show available brands.

After download, read `./DESIGN.md` and proceed to **Apply Design**.

## Recommendation Mode

```bash
npx getdesign list
```

From the output, recommend **2-3 brands** that match the user's description. For each, give:
- Brand name
- The one-line description from `getdesign list`
- Why it fits the user's needs

After the user picks one, continue with **Direct Mode**.

## Apply Design

1. **Read the full DESIGN.md** into context.
2. **Extract key tokens** relevant to the current task:
   - Color palette (primary, accent, neutral, surface, border)
   - Typography (font family, size scale, weight, line-height, letter-spacing)
   - Spacing and border-radius conventions
   - Shadow system
   - Component patterns (buttons, cards, inputs, navigation)
3. **Implement the UI** using exact values from the DESIGN.md — real hex codes, real font names, real spacing values. Do not approximate.
4. If `frontend-design` skill is available, follow its quality principles (avoid AI slop, bold aesthetic choices, production-grade code). The DESIGN.md provides the design direction; `frontend-design` provides implementation quality standards.

## Mix-and-Match

When users request combinations (e.g., "Stripe colors + Linear layout"):

```bash
npx getdesign add stripe --out ./stripe-design.md --force
npx getdesign add linear --out ./linear-design.md --force
```

Read both files. Use the specified aspects from each (colors from one, layout/typography from the other).

## Cleanup

After implementation is complete, remind the user:
> "DESIGN.md is still in your project root. You can delete it or add it to .gitignore if you don't want it committed."
