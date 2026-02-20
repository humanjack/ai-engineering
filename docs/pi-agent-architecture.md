# Pi Agent — Architecture & Workflow Analysis

> Source: [Blog post by Armin Ronacher](https://lucumr.pocoo.org/2026/1/31/pi/) + [github.com/badlogic/pi-mono](https://github.com/badlogic/pi-mono)
> Author of Pi: Mario Zechner ([@badlogic](https://github.com/badlogic))

---

## 1. What Is Pi?

Pi is a **minimal terminal coding agent** — the engine that powers [OpenClaw](https://openclaw.ai). It's intentionally small: the shortest system prompt of any coding agent, only **4 built-in tools** (Read, Write, Edit, Bash), and a powerful extension system that lets the agent extend *itself* at runtime.

Philosophy: **"If you want the agent to do something new, ask it to build it."** No MCP, no downloaded plugins by default — the agent writes its own tools.

---

## 2. Monorepo Structure

```
pi-mono/
├── packages/
│   ├── ai/              → @mariozechner/pi-ai         (unified multi-provider LLM API)
│   ├── agent/           → @mariozechner/pi-agent-core  (agent runtime, tools, state)
│   ├── coding-agent/    → @mariozechner/pi-coding-agent (interactive CLI)
│   ├── tui/             → @mariozechner/pi-tui         (terminal UI library)
│   ├── web-ui/          → @mariozechner/pi-web-ui      (web chat components)
│   ├── mom/             → @mariozechner/pi-mom         (Slack bot delegate)
│   └── pods/            → @mariozechner/pi-pods        (vLLM GPU pod manager)
├── .pi/                 → project-level Pi config
├── AGENTS.md            → dev rules (for humans & agents)
└── scripts/
```

---

## 3. Layered Architecture

```
┌─────────────────────────────────────────────────────┐
│                   User Interfaces                    │
│  coding-agent (TUI)  │  mom (Slack)  │  web-ui      │
│  OpenClaw (Telegram/  │               │              │
│  Discord/etc.)        │               │              │
├─────────────────────────────────────────────────────┤
│                  agent-core (Runtime)                 │
│  AgentMessage tree  │  Tool executor  │  Events      │
│  Steering/follow-up │  State machine  │  Branching   │
├─────────────────────────────────────────────────────┤
│                     pi-ai (LLM SDK)                  │
│  Unified stream/complete API across 20+ providers    │
│  Token/cost tracking │ Context serialization         │
│  Cross-provider handoffs │ OAuth support             │
├─────────────────────────────────────────────────────┤
│                   LLM Providers                      │
│  Anthropic │ OpenAI │ Google │ Mistral │ xAI │ ...   │
└─────────────────────────────────────────────────────┘
```

### Layer 1: `pi-ai` — Unified LLM API
- Single `stream()` / `complete()` interface for all providers
- `Context` object: `{ systemPrompt, messages[], tools[] }` — serializable, transferable between models mid-session
- Automatic model discovery per provider (only tool-capable models)
- Built-in token counting, cost tracking, usage stats
- TypeBox schemas for type-safe tool definitions
- Cross-provider handoff: switch models mid-conversation without losing context

### Layer 2: `agent-core` — Agent Runtime
- **AgentMessage**: Superset of LLM messages — includes custom app-specific types via TS declaration merging
- **Message flow**: `AgentMessage[] → transformContext() → convertToLlm() → Message[] → LLM`
- **Event-driven**: `agent_start → turn_start → message_start → message_update (streaming) → message_end → tool_execution_start/end → turn_end → agent_end`
- **Steering**: Interrupt the agent mid-tool-execution with new instructions (remaining tools get skipped)
- **Follow-up queue**: Stack messages to run after agent finishes current work
- **Custom message types**: Extensions can inject non-LLM messages (UI-only, metadata, state) that get filtered before the LLM call

### Layer 3: `coding-agent` — The CLI
- 4 core tools: **Read**, **Write**, **Edit**, **Bash**
- 4 extension points: **Extensions** (TypeScript), **Skills** (markdown), **Prompt Templates**, **Themes**
- Runs in 4 modes: interactive TUI, print/JSON, RPC (process integration), SDK (embedding)
- Loads `AGENTS.md` / `CLAUDE.md` from cwd + parent dirs + global config

---

## 4. Session Model (Tree-Based)

Sessions are **JSONL files with a tree structure** — each entry has `id` and `parentId`.

```
Session File (.jsonl)
├── msg-1 (user: "Fix the login bug")
│   └── msg-2 (assistant: tool calls...)
│       ├── msg-3 (tool result)
│       │   └── msg-4 (assistant: "Done, here's what I changed")
│       │       ├── msg-5 (user: "Actually, also fix the logout") ← branch A
│       │       └── msg-6 (user: "/review")                      ← branch B (side-quest)
│       │           └── msg-7 (assistant: review findings)
```

Key features:
- **Branching** (`/tree`): Navigate to any point, continue from there. All history preserved in one file.
- **Forking** (`/fork`): Create a new session file from a branch point
- **Compaction**: When context gets too long, older messages get summarized. Full history stays in JSONL; `/tree` can revisit.
- **Side-quests**: Branch off to fix a broken tool or review code without polluting the main context. Rewind back, and Pi summarizes the side-branch.

---

## 5. Extension System

Extensions are TypeScript modules with access to the `ExtensionAPI`:

```typescript
export default function (pi: ExtensionAPI) {
  pi.registerTool({ name: "deploy", ... });      // Custom tools
  pi.registerCommand("stats", { ... });           // Slash commands
  pi.on("tool_call", async (event, ctx) => { });  // Event hooks
  // Custom TUI components: spinners, tables, pickers, overlays
}
```

What extensions can do:
- Register/replace tools (including built-in ones)
- Add slash commands and keyboard shortcuts
- Render custom TUI components (proven capable: someone ran Doom in it)
- Implement sub-agents, plan mode, permission gates
- Custom compaction/summarization logic
- Persist state into sessions (survives reload)
- Hot-reload: agent writes code → reloads → tests → iterates

### Extensions vs Skills vs Prompt Templates

| Mechanism | Format | Loaded | Purpose |
|-----------|--------|--------|---------|
| **Extension** | TypeScript | At startup, hot-reloadable | Tools, commands, UI, event hooks |
| **Skill** | Markdown (SKILL.md) | On-demand via `/skill:name` | Domain knowledge, workflows |
| **Prompt Template** | Markdown | On `/name` | Reusable prompts with `{{vars}}` |
| **Theme** | JSON/TS | Auto hot-reload | Visual customization |

All four can be bundled into **Pi Packages** and shared via npm or git.

---

## 6. Workflow: How a Prompt Flows Through Pi

```
User types "Read config.json and fix the port"
        │
        ▼
┌─ coding-agent (TUI) ─────────────────────────────┐
│  1. Editor captures input                          │
│  2. Extensions get pre-prompt hooks                │
│  3. Message added to session tree                  │
└───────────────────────────────────────────────────┘
        │
        ▼
┌─ agent-core ──────────────────────────────────────┐
│  4. transformContext() — prune/compact if needed    │
│  5. convertToLlm() — filter custom msgs, map types │
│  6. Stream to LLM via pi-ai                        │
│  7. LLM returns tool_call: read("config.json")     │
│  8. Execute tool → return result                   │
│  9. LLM returns tool_call: edit(...)               │
│ 10. Execute tool → return result                   │
│ 11. LLM returns text: "Fixed the port to 8080"    │
│ 12. Emit agent_end with all new messages           │
└───────────────────────────────────────────────────┘
        │
        ▼
┌─ Session file ────────────────────────────────────┐
│ 13. All messages appended to JSONL tree            │
│ 14. Extension state persisted alongside            │
└───────────────────────────────────────────────────┘
```

During step 8-10, the user can **steer** (interrupt with new instructions) or **queue follow-ups**.

---

## 7. How OpenClaw Uses Pi

OpenClaw is a real-world **SDK integration** of Pi. It strips the TUI and connects the agent runtime to messaging channels (Telegram, Discord, Slack, etc.):

```
Telegram/Discord/etc.
        │
        ▼
   OpenClaw Gateway
        │
        ▼
   pi-agent-core (SDK mode)
        │
        ▼
   pi-ai → LLM providers
```

OpenClaw adds: channel routing, heartbeats, cron, multi-session, sub-agents, node control, memory files. But the core loop — user message → agent → tools → response — is Pi.

---

## 8. Design Principles

1. **Minimal core, maximal extensibility**: 4 tools, short system prompt. Everything else is extensions.
2. **Self-extending agent**: Instead of downloading plugins, ask the agent to build what you need. It has docs + examples to reference.
3. **No MCP by design**: Tools live in bash/code, not protocol servers. (MCP can be bridged via `mcporter` CLI if needed.)
4. **Provider-agnostic sessions**: Sessions can contain messages from different providers. No deep lock-in to any provider's features.
5. **Tree-based sessions**: Branching enables side-quests, reviews, and experiments without context pollution.
6. **Software building software**: The agent maintains its own functionality — skills, extensions, CLIs. It's clay, not concrete.

---

## 9. Notable Community Extensions

| Extension | What It Does |
|-----------|-------------|
| `/answer` | Extracts questions from agent's response into structured input |
| `/todos` | Local issue tracker as markdown files in `.pi/todos` |
| `/review` | Branch into fresh context for code review, bring fixes back |
| `/control` | Send prompts from one Pi agent to another (simple multi-agent) |
| `/files` | List changed files, quick-look, diff in VS Code |
| `pi-subagents` | Nico's sub-agent orchestration extension |
| `pi-interactive-shell` | Run interactive CLIs in observable TUI overlay |

---

## 10. Key Takeaways for AI Engineering

- **Minimalism wins**: Pi proves you don't need a massive tool surface. Read/Write/Edit/Bash + a good extension system covers virtually everything.
- **Sessions as trees**: This is a powerful UX pattern. Side-quests, branching reviews, and rewind-to-fix without losing context.
- **Agent self-extension with hot-reload**: The write-reload-test loop for extensions is a game-changer. The agent debugs its own tools.
- **Unified LLM layer matters**: `pi-ai` handles 20+ providers with one interface, making model switching trivial. Cross-provider handoff mid-session is a differentiator.
- **Extensions > Plugins**: Giving the agent the ability to write TypeScript extensions (with TUI components, tools, event hooks) is more powerful than any plugin marketplace.
