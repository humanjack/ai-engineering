# LangChain Deep Agents — Architecture & Code Analysis

**Repository:** [langchain-ai/deepagents](https://github.com/langchain-ai/deepagents)
**Version:** 0.4.9 | **License:** MIT | **Python:** ≥3.11
**Tagline:** An opinionated, ready-to-run agent harness built on LangChain & LangGraph

---

## 1. What Is Deep Agents?

Deep Agents is LangChain's official "agent harness" — a batteries-included framework that gives you a fully working agent out of the box, inspired directly by Claude Code. Instead of wiring up prompts, tools, and context management yourself, `create_deep_agent()` returns a compiled LangGraph graph with planning, filesystem access, sub-agents, and auto-summarization baked in.

```python
from deepagents import create_deep_agent

agent = create_deep_agent()
result = agent.invoke({
    "messages": [{"role": "user", "content": "Research LangGraph and write a summary"}]
})
```

The agent can plan via a todo list, read/write files, run shell commands in a sandbox, spawn sub-agents for parallel work, and manage its own context window — all with zero configuration.

---

## 2. Core Features

| Feature | Description |
|---|---|
| **Planning** | `write_todos` tool for task breakdown and progress tracking |
| **Filesystem** | `read_file`, `write_file`, `edit_file`, `ls`, `glob`, `grep` tools |
| **Shell Execution** | `execute` tool for sandboxed shell commands |
| **Sub-agents** | `task` tool to spawn ephemeral agents with isolated context |
| **Auto-summarization** | Automatic conversation compaction when tokens exceed threshold |
| **Large result eviction** | Oversized tool outputs saved to filesystem, replaced with preview |
| **Skills system** | Progressive-disclosure skill loading from SKILL.md files |
| **Memory / AGENTS.md** | Load persistent context from AGENTS.md files into system prompt |
| **MCP support** | Via langchain-mcp-adapters |
| **Provider agnostic** | Any LLM with tool-calling support (default: Claude Sonnet 4.6) |
| **Human-in-the-loop** | Interrupt-on-config for tool approval flows |
| **ACP server** | Agent Communication Protocol for IDE/editor integration |

---

## 3. Monorepo Structure

```
deepagents/
├── libs/
│   ├── deepagents/          # Core SDK (the `deepagents` PyPI package)
│   │   ├── deepagents/
│   │   │   ├── graph.py              # create_deep_agent() — main entry point
│   │   │   ├── base_prompt.md        # Base system prompt
│   │   │   ├── middleware/           # All middleware implementations
│   │   │   │   ├── filesystem.py     # File tools + large result eviction
│   │   │   │   ├── subagents.py      # Sub-agent spawning via `task` tool
│   │   │   │   ├── summarization.py  # Auto-compaction + compact_conversation tool
│   │   │   │   ├── memory.py         # AGENTS.md memory loading
│   │   │   │   ├── skills.py         # SKILL.md progressive-disclosure loading
│   │   │   │   ├── patch_tool_calls.py # Fix dangling tool calls
│   │   │   │   └── _utils.py         # System message helpers
│   │   │   └── backends/             # Pluggable storage backends
│   │   │       ├── protocol.py       # BackendProtocol + SandboxBackendProtocol
│   │   │       ├── state.py          # StateBackend (ephemeral, in LangGraph state)
│   │   │       ├── filesystem.py     # FilesystemBackend (real disk)
│   │   │       ├── local_shell.py    # LocalShellBackend (execution support)
│   │   │       ├── store.py          # StoreBackend (LangGraph BaseStore)
│   │   │       ├── composite.py      # CompositeBackend (route paths to backends)
│   │   │       └── sandbox.py        # Remote sandbox interface
│   │   └── pyproject.toml
│   ├── cli/                 # Terminal UI (deepagents-cli, uses Textual)
│   ├── acp/                 # Agent Communication Protocol server
│   ├── harbor/              # Eval/benchmark framework
│   └── partners/            # Integration packages
│       ├── runloop/         # Runloop sandbox
│       ├── daytona/         # Daytona sandbox
│       └── modal/           # Modal sandbox
├── examples/                # Example agents
│   ├── deep_research/       # Multi-step research agent
│   ├── text-to-sql-agent/   # SQL agent with skills
│   └── content-builder-agent/
└── AGENTS.md                # Development guidelines
```

---

## 4. Core Dependencies & Their Roles

### Primary Dependencies

| Library | Role |
|---|---|
| **langchain-core** (≥1.2.18) | Message types (`HumanMessage`, `AIMessage`, `ToolMessage`, `SystemMessage`), tool abstractions (`BaseTool`, `StructuredTool`), `BaseChatModel` interface, content block types |
| **langchain** (≥1.2.11) | `create_agent()` — the underlying LangGraph agent builder; middleware system (`AgentMiddleware`, `HumanInTheLoopMiddleware`, `TodoListMiddleware`); `init_chat_model()` for provider-agnostic model initialization; `ToolRuntime` for tool context |
| **langgraph** (implicit via langchain) | Graph compilation (`CompiledStateGraph`), state management, checkpointers for persistence, `BaseStore` for long-term storage, `Command` for state updates from tools, `Runtime` context, streaming support |
| **langchain-anthropic** (≥1.3.4) | `ChatAnthropic` (default model), `AnthropicPromptCachingMiddleware` for efficient prompt caching |
| **langchain-google-genai** (≥4.2.0) | Google Gemini model support |

### How LangChain & LangGraph Work Together

```
┌─────────────────────────────────────────────────┐
│              create_deep_agent()                  │
│                                                   │
│  ┌─────────────────────────────────────────────┐ │
│  │           langchain.create_agent()           │ │
│  │                                              │ │
│  │  ┌───────────────────────────────────────┐  │ │
│  │  │         LangGraph StateGraph          │  │ │
│  │  │                                       │  │ │
│  │  │  model_node ←→ tool_node (loop)       │  │ │
│  │  │      ↑                                │  │ │
│  │  │  middleware stack wraps each call      │  │ │
│  │  └───────────────────────────────────────┘  │ │
│  └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

- **LangChain** provides the agent creation API, middleware framework, and tool abstractions
- **LangGraph** provides the underlying graph runtime — state machine, checkpointing, streaming, and the `Command` primitive for tools that update state
- **Deep Agents** layers on top with opinionated middleware (filesystem, sub-agents, summarization, skills, memory) and a curated system prompt

---

## 5. Architecture: The Middleware Stack

Deep Agents' architecture is fundamentally a **middleware stack** that wraps model calls and tool calls. Each middleware can:
- Inject instructions into the system prompt (`wrap_model_call`)
- Add tools to the agent
- Modify messages before they reach the model
- Intercept tool results after execution (`wrap_tool_call`)
- Run initialization logic before the agent loop (`before_agent`)

### Default Middleware Order (Main Agent)

```
1. TodoListMiddleware          — Adds write_todos tool for planning
2. MemoryMiddleware*           — Loads AGENTS.md into system prompt
3. SkillsMiddleware*           — Loads SKILL.md metadata for progressive disclosure
4. FilesystemMiddleware        — Adds ls/read/write/edit/glob/grep/execute tools
5. SubAgentMiddleware          — Adds task tool for spawning sub-agents
6. SummarizationMiddleware     — Auto-compacts conversation when tokens exceed threshold
7. AnthropicPromptCachingMiddleware — Optimizes prompt caching for Anthropic models
8. PatchToolCallsMiddleware    — Fixes dangling tool calls from interrupted responses
9. [User middleware]*          — Any additional middleware passed by the developer
10. HumanInTheLoopMiddleware*  — Pauses at configured tool calls for approval
```
*Optional, added conditionally

### How a Request Flows

```
User message
    │
    ▼
before_agent() hooks run (load memory, skills, patch tool calls)
    │
    ▼
┌─────────────────────────────┐
│    LangGraph Agent Loop     │
│                             │
│  ┌───────────────────────┐  │
│  │  wrap_model_call()    │  │  ← Each middleware wraps the model call
│  │  (outer → inner)      │  │    - Inject system prompt sections
│  │                       │  │    - Modify messages (summarization)
│  │  → LLM invocation     │  │    - Truncate old tool args
│  │  ← AI response        │  │
│  └───────────────────────┘  │
│           │                 │
│     Tool calls?             │
│       yes │                 │
│           ▼                 │
│  ┌───────────────────────┐  │
│  │  wrap_tool_call()     │  │  ← Intercept tool results
│  │  (outer → inner)      │  │    - Evict large results to filesystem
│  │                       │  │
│  │  → Tool execution     │  │
│  │  ← Tool result        │  │
│  └───────────────────────┘  │
│           │                 │
│     Loop back to model      │
└─────────────────────────────┘
    │
    ▼
Final response to user
```

---

## 6. Context Engineering

Deep Agents implements context engineering through multiple coordinated mechanisms:

### 6.1 System Prompt Composition

The system prompt is built dynamically by stacking middleware contributions:

```
Base Agent Prompt (hardcoded behavioral instructions)
    + User's custom system_prompt (prepended)
    + Memory content (AGENTS.md files, wrapped in <agent_memory> tags)
    + Skills listing (progressive disclosure — names + descriptions only)
    + Filesystem instructions (tool usage guidance)
    + Execution instructions (if sandbox available)
    + Sub-agent instructions (task tool documentation with examples)
    + Summarization instructions (compact_conversation tool guidance)
```

Each middleware uses `append_to_system_message()` to add its section. For Anthropic models, `SystemMessage` supports `content_blocks` (a list of content blocks), and each middleware appends a new text block — this enables **prompt caching** where stable prefix blocks are cached and only new blocks trigger recomputation.

### 6.2 Auto-Summarization (Context Window Management)

The `SummarizationMiddleware` automatically compacts conversations when they get too long:

**Trigger:** Configurable as tokens, messages, or fraction of model's max context
- Default: 85% of model's `max_input_tokens` (from model profile)
- Fallback: 170,000 tokens for models without profile info

**Process:**
1. Count current token usage
2. If threshold exceeded → determine cutoff index (keep last 10% of context)
3. Offload old messages to filesystem at `/conversation_history/{thread_id}.md`
4. Generate LLM-powered summary of evicted messages
5. Replace old messages with: summary message + reference to offloaded file + recent messages

**Tool Argument Truncation:** Before full summarization, a lighter-weight optimization truncates large `write_file`/`edit_file` arguments in older messages (keeps first 20 chars + truncation notice).

**Manual Compaction:** The `SummarizationToolMiddleware` exposes a `compact_conversation` tool that lets the agent (or the model itself) trigger compaction on demand. This is useful when switching tasks — the model can proactively compact irrelevant context.

### 6.3 Large Tool Result Eviction

When any tool returns a result exceeding ~20,000 tokens (configurable):
1. Content is written to `/large_tool_results/{tool_call_id}` in the backend
2. The inline result is replaced with a preview (head + tail, ~10 lines) and a file reference
3. The agent can `read_file` the full output in paginated chunks

Excluded from eviction: `ls`, `glob`, `grep` (self-truncating), `read_file` (would cause re-read loops), `edit_file`/`write_file` (tiny outputs).

### 6.4 Memory (AGENTS.md)

The `MemoryMiddleware` loads AGENTS.md files at agent startup and injects their content into the system prompt within `<agent_memory>` tags. The system prompt includes detailed guidelines for when and how the agent should update its own memory by editing these files.

Key design:
- Memory is loaded once per session (cached in state as `memory_contents`)
- Agent can edit its own memory files using `edit_file` tool
- Guidelines distinguish what to remember vs. what's transient
- Security: never store credentials

### 6.5 Skills (Progressive Disclosure)

Skills follow the [Agent Skills specification](https://agentskills.io/specification):
- Each skill = directory with `SKILL.md` (YAML frontmatter + markdown instructions)
- At startup, only metadata (name, description, path) is loaded into the system prompt
- The agent reads the full SKILL.md content on-demand when it decides a skill is relevant
- Sources can be layered: base → user → project (later overrides earlier)

---

## 7. Agent Harness: create_deep_agent()

The `create_deep_agent()` function is the main entry point. It:

1. **Resolves the model** — string `"provider:model"` format or pre-configured `BaseChatModel`; defaults to `claude-sonnet-4-6`
2. **Builds the general-purpose sub-agent** — with its own full middleware stack
3. **Processes custom sub-agents** — fills in default model, tools, and middleware
4. **Assembles the main middleware stack** — in the order described above
5. **Composes the system prompt** — user prompt + base agent prompt
6. **Calls `langchain.create_agent()`** — which builds the LangGraph graph
7. **Sets recursion limit to 1000** — allowing deep agent loops

```python
agent = create_deep_agent(
    model="openai:gpt-4o",           # Any provider:model string
    tools=[my_tool],                   # Additional custom tools
    system_prompt="You are a researcher.",
    middleware=[my_middleware],         # Extra middleware
    subagents=[{                       # Custom sub-agents
        "name": "analyst",
        "description": "Data analysis",
        "system_prompt": "You analyze data.",
        "tools": [pandas_tool],
    }],
    skills=["/skills/user/"],          # Skill directories
    memory=["/AGENTS.md"],             # Memory files
    backend=my_sandbox,                # Storage + execution backend
    checkpointer=MemorySaver(),        # For persistence
    interrupt_on={"execute": True},    # Human approval for shell commands
)
```

### Key Design Decisions

- **"Trust the LLM" security model** — The agent can do anything its tools allow. Enforce boundaries at the tool/sandbox level, not by expecting the model to self-police.
- **Sub-agents get the same middleware stack** — Each sub-agent automatically gets TodoList, Filesystem, Summarization, PromptCaching, and PatchToolCalls middleware.
- **Backend abstraction** — All file operations go through `BackendProtocol`, making storage pluggable (in-memory state, local filesystem, remote sandbox, LangGraph store, or composite routing).

---

## 8. Sub-Agent System

The `SubAgentMiddleware` adds a `task` tool that spawns ephemeral sub-agents:

### How It Works

1. Main agent decides to delegate → calls `task(description="...", subagent_type="general-purpose")`
2. A new agent is created with its own middleware stack and isolated message history
3. Sub-agent receives only the task description as a `HumanMessage` (clean context)
4. Sub-agent works autonomously using all available tools
5. Sub-agent's final message is returned as a `ToolMessage` to the main agent
6. Sub-agent state is discarded (ephemeral)

### Key Properties

- **Context isolation** — Sub-agents don't see the main conversation, only their task
- **Parallel execution** — Multiple `task` calls in one response run concurrently
- **State passthrough** — Non-excluded state keys pass through to sub-agents
- **Custom sub-agents** — Define specialized agents with different models, tools, or prompts
- **Pre-compiled agents** — Pass any LangGraph `Runnable` as a `CompiledSubAgent`

### Default: General-Purpose Sub-Agent

Every Deep Agent gets a "general-purpose" sub-agent with the same tools as the main agent. The system prompt includes detailed examples of when to use sub-agents (complex research, isolated analysis) vs. when not to (trivial tasks).

---

## 9. Backend System (Storage & Execution)

### Backend Protocol

All file operations go through `BackendProtocol`:

```python
class BackendProtocol:
    def read(path, offset, limit) -> str           # Read with line numbers
    def write(path, content) -> WriteResult         # Create/overwrite file
    def edit(path, old, new) -> EditResult          # Find-and-replace edit
    def ls_info(path) -> list[FileInfo]             # List directory
    def glob_info(pattern, path) -> list[FileInfo]  # Glob search
    def grep_raw(pattern, path, glob) -> list[Match]  # Text search
    def download_files(paths) -> list[FileDownloadResponse]  # Batch download
    def upload_files(uploads) -> list[FileUploadResponse]    # Batch upload
```

For shell execution, `SandboxBackendProtocol` extends this with:
```python
class SandboxBackendProtocol(BackendProtocol):
    def execute(command, timeout) -> ExecuteResult
```

### Available Backends

| Backend | Storage | Execution | Use Case |
|---|---|---|---|
| `StateBackend` | LangGraph state (ephemeral) | ✗ | Default, testing, stateless agents |
| `FilesystemBackend` | Local disk | ✗ | Persistent file access |
| `LocalShellBackend` | Local disk | ✓ (local shell) | Development, trusted environments |
| `StoreBackend` | LangGraph BaseStore | ✗ | Persistent across sessions |
| `CompositeBackend` | Routes paths → backends | Depends | Hybrid (e.g., ephemeral + persistent `/memories/`) |
| Partner sandboxes | Remote | ✓ (sandboxed) | Production (Runloop, Daytona, Modal) |

---

## 10. CLI (deepagents-cli)

The CLI is a full terminal UI built with **Textual** (Python TUI framework):

- Interactive chat interface with streaming responses
- Thread/session management with persistence
- Model selector (switch models mid-conversation)
- MCP server integration and trust management
- Skill management (create, load, view)
- Sandbox integration (Runloop, Daytona, Modal)
- Non-interactive mode for scripting
- ACP mode for IDE integration

---

## 11. ACP (Agent Communication Protocol)

The `deepagents-acp` package wraps a Deep Agent as an ACP server, enabling:
- IDE/editor integration (e.g., VS Code, JetBrains)
- Standardized agent communication
- Tool call streaming with diffs
- Session management
- Permission handling

---

## 12. Implementation Patterns Worth Noting

### Middleware as the Universal Extension Point
Everything in Deep Agents is a middleware. Want to add memory? Middleware. Skills? Middleware. Sub-agents? Middleware. This makes the system highly composable — you can remove any capability by simply not including its middleware.

### Command Pattern for State Updates
Tools return `Command(update={...})` to modify LangGraph state atomically. This enables tools to update files, messages, and metadata in a single transaction.

### Prompt Caching Awareness
The `AnthropicPromptCachingMiddleware` is always in the stack (with `unsupported_model_behavior="ignore"` for non-Anthropic models). For Anthropic, system prompt sections are structured as separate content blocks so the stable prefix is cached.

### Backend Factory Pattern
Backends can be passed as either instances or factory functions (`lambda runtime: StateBackend(runtime)`). This enables lazy initialization and access to runtime context (state, store, config).

### Defensive Summarization
Summarization uses a two-phase approach: first try the normal model call, and if it raises `ContextOverflowError`, fall back to summarization. This means the agent gracefully handles unexpected context growth.

---

## 13. Quick Start Recipes

### Minimal Agent
```python
from deepagents import create_deep_agent
agent = create_deep_agent()  # Uses Claude Sonnet 4.6
```

### Custom Model + Tools
```python
from deepagents import create_deep_agent
from langchain.chat_models import init_chat_model

agent = create_deep_agent(
    model="openai:gpt-4o",
    tools=[my_search_tool, my_db_tool],
    system_prompt="You are a data analyst.",
)
```

### With Persistent Storage
```python
from deepagents import create_deep_agent
from deepagents.backends import CompositeBackend, StateBackend, StoreBackend
from langgraph.checkpoint.memory import MemorySaver

backend = CompositeBackend(
    default=StateBackend(),
    routes={"/memories/": StoreBackend()}
)
agent = create_deep_agent(
    backend=backend,
    checkpointer=MemorySaver(),
    memory=["/AGENTS.md"],
)
```

### With Custom Sub-Agents
```python
agent = create_deep_agent(
    subagents=[{
        "name": "code-reviewer",
        "description": "Reviews code for bugs and style issues",
        "system_prompt": "You are an expert code reviewer...",
        "model": "anthropic:claude-sonnet-4-6",
        "tools": [read_file_tool, grep_tool],
    }],
)
```

---

## 14. Key Takeaways for AI Engineering

1. **Middleware-first architecture** makes agent capabilities composable and removable
2. **Context engineering is multi-layered**: prompt composition + auto-summarization + large result eviction + arg truncation + progressive skill disclosure
3. **Sub-agents solve context pollution** — isolate complex tasks so the main thread stays clean
4. **Backend abstraction** decouples storage from logic — same agent code works locally or in remote sandboxes
5. **The "trust the LLM" model** pushes security to the infrastructure layer (sandboxes, tool permissions) rather than prompt engineering
6. **Memory is file-based and self-maintaining** — the agent can edit its own AGENTS.md files, creating a feedback loop for learning
7. **Built on LangGraph primitives** — inherits streaming, persistence, checkpointing, and the full LangGraph ecosystem
