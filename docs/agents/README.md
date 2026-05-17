# AI Agent Architecture Series

Educational deep-dives on six open-source AI agents — grounded in source code, illustrated with diagrams, and synthesized into a comparison guide.

## The Agents

| # | Agent | One-line | Doc |
|---|---|---|---|
| 1 | **Pi** | Minimal self-extending coding agent — 4 tools + hot-reloadable TypeScript extensions | [pi.md](pi.md) |
| 2 | **OpenClaw** | Multi-channel productization of Pi — Gateway daemon + 22+ messaging surfaces | [openclaw.md](openclaw.md) |
| 3 | **Hermes Agent** | Maximalist Python harness with a self-improving skill curator | [hermes.md](hermes.md) |
| 4 | **OpenCode** | LSP-native coding agent — edits wait for diagnostics; tree-sitter bash perms | [opencode.md](opencode.md) |
| 5 | **Deep Agents** | LangChain's opinionated middleware-composable harness | [deepagents.md](deepagents.md) |
| 6 | **Codex CLI** | OpenAI's Rust agent — one protocol, five frontends, three-layer OS sandboxes | [codex.md](codex.md) |

→ **[Cross-agent comparison](comparison.md)** — matrices, decision tree, design philosophies side-by-side.

## Interactive Web Pages

Each agent has a dedicated HTML page with rendered Mermaid diagrams, tabbed sections, and inline code references. Open from `site/`:

- [`site/index.html`](../../site/index.html) — landing page
- `site/pi.html` · `site/openclaw.html` · `site/hermes.html` · `site/opencode.html` · `site/deepagents.html` · `site/codex.html`
- [`site/comparison.html`](../../site/comparison.html) — cross-agent matrix

## Diagrams

Source `.mmd` files live under `diagrams/<agent>/` so they can be embedded elsewhere or re-rendered.

## Capabilities Covered (per agent)

1. Harness / runtime architecture
2. Context management (compaction, caching)
3. Tool calling (definition, dispatch, sandboxing)
4. Automations (hooks, slash commands, cron)
5. Skills / plugins
6. Memory (file-based, vector, etc.)
7. Planning / execution loops
8. Testing & evaluation

## Series Tracking

- [Umbrella issue #51](https://github.com/humanjack/ai-engineering/issues/51)
- Sub-issues: [#52 Pi](https://github.com/humanjack/ai-engineering/issues/52), [#54 Deep Agents](https://github.com/humanjack/ai-engineering/issues/54), [#56 OpenClaw](https://github.com/humanjack/ai-engineering/issues/56), [#58 Hermes](https://github.com/humanjack/ai-engineering/issues/58), [#60 OpenCode](https://github.com/humanjack/ai-engineering/issues/60), [#62 Codex CLI](https://github.com/humanjack/ai-engineering/issues/62)
