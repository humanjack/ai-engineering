# Deep Agents — LangChain's Opinionated Agent Harness

> **Repository:** [langchain-ai/deepagents](https://github.com/langchain-ai/deepagents)
> **Language:** Python (≥3.11) · **License:** MIT
> **Built on:** LangChain + LangGraph
> **Tagline:** "Batteries-included agent harness inspired by Claude Code"

---

## TL;DR

- **Middleware stack, not a monolith.** Every capability — planning, filesystem, sub-agents, summarization, memory, skills — is a middleware that wraps the model call and the tool call. You compose your agent by selecting middleware.
- **Built on LangGraph primitives.** Streaming, checkpointing, persistence, and the `Command` pattern for atomic state updates come for free.
- **Batteries-included by design.** `create_deep_agent()` with zero args returns a working agent that can plan, read/write files, spawn sub-agents, and auto-compact its own context.

> **Analogy:** Pi gives you Lego bricks. Deep Agents gives you the Death Star kit. Both can build the same thing — Deep Agents just shipped most of it pre-assembled.

---

## 1. Why It Exists

LangChain noticed that everyone building serious agents was reimplementing the same five things: a todo list, file tools, shell execution, sub-agents, and context compaction. Rather than ship them as one-off recipes, they extracted the patterns into a **middleware framework** layered on top of LangGraph.

The result: you can `from deepagents import create_deep_agent` and have a working "Claude Code-shaped" agent in two lines, then peel back layers as your needs deviate from the default.

---

## 2. Two-Line Quickstart

```python
from deepagents import create_deep_agent

agent = create_deep_agent()
result = agent.invoke({
    "messages": [{"role": "user", "content": "Research LangGraph and write a summary"}]
})
```

That agent already has: planning (`write_todos`), filesystem (`read_file`/`write_file`/`edit_file`/`ls`/`glob`/`grep`), shell (`execute`), sub-agents (`task`), auto-summarization, Anthropic prompt caching, and AGENTS.md memory loading.

---

## 3. The Layered Stack

```mermaid
flowchart TB
    subgraph App["create_deep_agent()"]
        Cfg[Config & defaults]
        Sub[Sub-agent factory]
        MW[Middleware composer]
    end

    subgraph LC["LangChain create_agent()"]
        Builder[Graph builder]
        ToolReg[Tool registry]
        Inject[init_chat_model]
    end

    subgraph LG["LangGraph runtime"]
        SG[StateGraph]
        Model[model_node]
        Tool[tool_node]
        Ckpt[Checkpointer]
        Store[BaseStore]
    end

    subgraph Backend["BackendProtocol"]
        State[StateBackend]
        FS[FilesystemBackend]
        Shell[LocalShellBackend]
        Remote[Runloop / Daytona / Modal]
    end

    App --> LC --> LG
    LG -.uses.-> Backend
    Tool -.commands.-> SG

    classDef app fill:#fef3c7,stroke:#a16207
    classDef lc fill:#dcfce7,stroke:#15803d
    classDef lg fill:#e0f2fe,stroke:#0369a1
    classDef be fill:#fce7f3,stroke:#be185d
    class Cfg,Sub,MW app
    class Builder,ToolReg,Inject lc
    class SG,Model,Tool,Ckpt,Store lg
    class State,FS,Shell,Remote be
```

- **Deep Agents** = curated middleware + opinionated system prompt
- **LangChain `create_agent`** = the underlying agent builder + middleware framework
- **LangGraph** = the state machine, persistence, streaming
- **BackendProtocol** = pluggable storage + execution

---

## 4. The Middleware Stack

A Deep Agent is a **stack of middleware**, in this default order:

```mermaid
flowchart TD
    M1[1 · TodoListMiddleware<br/>write_todos tool]
    M2[2 · MemoryMiddleware*<br/>AGENTS.md → system prompt]
    M3[3 · SkillsMiddleware*<br/>SKILL.md metadata]
    M4[4 · FilesystemMiddleware<br/>ls / read / write / edit / glob / grep / execute]
    M5[5 · SubAgentMiddleware<br/>task tool]
    M6[6 · SummarizationMiddleware<br/>auto-compact + compact_conversation tool]
    M7[7 · AnthropicPromptCachingMiddleware<br/>content-block caching]
    M8[8 · PatchToolCallsMiddleware<br/>fix dangling tool calls]
    M9[9 · User middleware*]
    M10[10 · HumanInTheLoopMiddleware*<br/>approval flows]
    M1 --> M2 --> M3 --> M4 --> M5 --> M6 --> M7 --> M8 --> M9 --> M10
```

\* = optional, added conditionally based on `create_deep_agent()` args.

Each middleware can override any subset of these hooks:

| Hook | Fires | Used For |
|---|---|---|
| `before_agent(state)` | Once at start | Load memory, skills, patch state |
| `wrap_model_call(handler, request)` | Every model call | Inject system prompt, modify messages, summarize |
| `wrap_tool_call(handler, request)` | Every tool call | Evict large results, log, guard |

Source: [libs/deepagents/deepagents/middleware/](https://github.com/langchain-ai/deepagents/tree/main/libs/deepagents/deepagents/middleware)

---

## 5. A Request's Journey

```mermaid
sequenceDiagram
    participant U as User
    participant DA as create_deep_agent
    participant MW as Middleware Stack
    participant M as Model (Claude)
    participant T as Tool (write_file)
    participant BE as Backend

    U->>DA: invoke({messages: ["Research X and save report"]})
    DA->>MW: before_agent hooks
    MW->>MW: MemoryMiddleware loads AGENTS.md
    MW->>MW: SkillsMiddleware loads SKILL.md metadata
    loop until no tool calls
        MW->>M: wrap_model_call(messages, tools, system)
        Note over MW: AnthropicCachingMW: split system into content blocks<br/>SummarizationMW: compact if > 85% context
        M-->>MW: assistant + toolCall(write_todos)
        MW->>T: wrap_tool_call(write_todos)
        T->>BE: state.todos = [...]
        T-->>MW: ToolMessage(ok)
        M-->>MW: assistant + toolCall(write_file)
        MW->>T: wrap_tool_call(write_file)
        T->>BE: state.files[path] = content
        T-->>MW: ToolMessage(ok)
        Note over MW: If result > 20k tokens:<br/>FilesystemMW evicts to /large_tool_results/
        M-->>MW: assistant text "Done"
    end
    MW-->>U: final state with messages, files, todos
```

---

## 6. Context Engineering — How Deep Agents Manages 200k Tokens

Five mechanisms cooperate:

### 6.1 · Stacked System Prompt with Caching
Each middleware appends a content block to `SystemMessage.content_blocks`. For Anthropic, stable prefix blocks are **prompt-cached** — only new blocks recompute. This drops cost ~80% on long sessions.

### 6.2 · Auto-Summarization
`SummarizationMiddleware` triggers when usage > 85% of `max_input_tokens`:
1. Compute cutoff index (keep last 10% of context)
2. Offload old messages to `/conversation_history/{thread_id}.md`
3. LLM-generated summary replaces evicted messages
4. Reference to offloaded file is included for retrieval

### 6.3 · Tool-Arg Truncation
Before full summarization, large `write_file`/`edit_file` args in older messages get truncated to "first 20 chars + …truncated".

### 6.4 · Large Result Eviction
Tool results > 20k tokens get written to `/large_tool_results/{tool_call_id}` and the inline result is replaced with head + tail preview + file reference. Agent reads in paginated chunks. Excluded: `ls`, `glob`, `grep`, `read_file`, `edit_file`, `write_file`.

### 6.5 · Skills Progressive Disclosure
Only skill `name` + `description` + `path` go in the system prompt. The agent reads the full `SKILL.md` only when it decides a skill is relevant.

---

## 7. Sub-Agents

`task(description, subagent_type)` spawns an **ephemeral** sub-agent:

```mermaid
flowchart LR
    Main[Main agent<br/>full history] -- task(...) --> Sub[Sub-agent<br/>empty history + only the task]
    Sub -- tools --> SubTools[Read/Write/etc.]
    Sub -- final message --> Main
    Note[State discarded after return]
    Sub -.-> Note
```

Properties:
- **Context isolation** — sub-agent sees only its task description
- **Parallel execution** — multiple `task` calls in one assistant turn run concurrently
- **Same middleware stack** — sub-agents inherit TodoList, Filesystem, Summarization, PromptCaching, PatchToolCalls
- **Custom personas** — define `subagents=[{name, description, system_prompt, model, tools}]`

The default `general-purpose` sub-agent has all the main agent's tools.

---

## 8. Backend Abstraction

All file operations route through `BackendProtocol`:

```python
class BackendProtocol:
    def read(path, offset, limit) -> str
    def write(path, content) -> WriteResult
    def edit(path, old, new) -> EditResult
    def ls_info(path) -> list[FileInfo]
    def glob_info(pattern, path) -> list[FileInfo]
    def grep_raw(pattern, path, glob) -> list[Match]
    def download_files(paths)
    def upload_files(uploads)

class SandboxBackendProtocol(BackendProtocol):
    def execute(command, timeout) -> ExecuteResult
```

Available backends:

| Backend | Storage | Execution | Use Case |
|---|---|---|---|
| `StateBackend` | LangGraph state (ephemeral) | ✗ | Default, tests, stateless agents |
| `FilesystemBackend` | Local disk | ✗ | Persistent local files |
| `LocalShellBackend` | Local disk | ✓ local shell | Development |
| `StoreBackend` | LangGraph `BaseStore` | ✗ | Cross-session persistence |
| `CompositeBackend` | Routes paths → backends | mixed | Hybrid (e.g. `/memories/` → store) |
| Runloop / Daytona / Modal | Remote | ✓ sandboxed | Production |

---

## 9. Custom Configuration

```python
from deepagents import create_deep_agent
from deepagents.backends import CompositeBackend, StateBackend, StoreBackend
from langgraph.checkpoint.memory import MemorySaver

backend = CompositeBackend(
    default=StateBackend(),
    routes={"/memories/": StoreBackend()},
)

agent = create_deep_agent(
    model="openai:gpt-4o",
    tools=[my_search_tool],
    system_prompt="You are a researcher.",
    subagents=[{
        "name": "code-reviewer",
        "description": "Reviews PRs for bugs",
        "system_prompt": "You are a senior code reviewer...",
        "model": "anthropic:claude-sonnet-4-6",
        "tools": [read_file_tool, grep_tool],
    }],
    skills=["/skills/user/"],
    memory=["/AGENTS.md"],
    backend=backend,
    checkpointer=MemorySaver(),
    interrupt_on={"execute": True},   # human approval for shell
)
```

---

## 10. Testing & Evaluation

Deep Agents ships a sister package — **harbor** — for benchmarking:

- `libs/harbor/` — eval framework with task suites
- Provider-specific test matrices (Claude vs GPT vs Gemini)
- Reproducible benchmarks against published agent task suites
- Used by LangChain to compare middleware tweaks

Internal tests: `libs/deepagents/tests/` covers middleware ordering, summarization triggers, sub-agent isolation, prompt caching segmentation. The CLI and ACP packages have integration tests against a stub model.

---

## 11. Capabilities Matrix

| Capability | How Deep Agents Does It | Code Reference |
|---|---|---|
| Harness / runtime | LangGraph StateGraph + middleware stack | `libs/deepagents/deepagents/graph.py` |
| Context management | System-prompt composition + auto-summarization + arg truncation + result eviction | `middleware/summarization.py`, `middleware/filesystem.py` |
| Tool calling | `BaseTool`/`StructuredTool` + `Command` for state updates | `middleware/filesystem.py` |
| Automations | `interrupt_on` + middleware composition + custom hooks | `middleware/__init__.py` |
| Skills | `SKILL.md` progressive disclosure | `middleware/skills.py` |
| Memory | `AGENTS.md` loaded into system prompt; agent edits via `edit_file` | `middleware/memory.py` |
| Planning | `write_todos` tool + `TodoListMiddleware` | `middleware/__init__.py` |
| Sub-agents | `task` tool, ephemeral isolated agents | `middleware/subagents.py` |
| Testing | Unit tests + `harbor` eval framework | `libs/harbor/` |

---

## 12. Strengths & Tradeoffs

**Strengths**
- Best-in-class context management — many small techniques cooperating
- Composability via middleware (you can remove any capability)
- LangGraph gives you persistence + streaming + checkpointing for free
- Real benchmarking (`harbor`) baked into the org
- Drop-in agent in 2 lines

**Tradeoffs**
- LangChain/LangGraph dependency surface is large
- Middleware ordering matters and isn't trivially discoverable
- Python-first; Node bindings exist but lag
- Heavier abstraction than Pi or OpenCode — more concepts to internalize
- Tied to LangGraph's state model (you commit to that mental shape)

---

## 13. When to Choose Deep Agents

- You're already in the LangChain ecosystem
- You want a production-grade agent with **persistence + streaming + checkpointing**
- You need to compose specialized sub-agents (research, analysis, code-review)
- You want a real eval harness (`harbor`) to A/B middleware tweaks
- You're targeting remote sandboxes (Runloop/Daytona/Modal) for execution

---

## 14. Deep Dive — Tool Use

Deep Agents inherits LangChain's `BaseTool` and `create_agent` foundations, but the interesting part is *what middleware does around tool calls*: result eviction, summarization, filtering, and sub-agent dispatch all run through `wrap_tool_call()`.

### 14.1 · `wrap_tool_call` is the contract

The universal middleware hook ([middleware/filesystem.py:18-20](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/middleware/filesystem.py#L18)):

```python
def wrap_tool_call(
    self,
    request: ToolCallRequest,
    handler: Callable[[ToolCallRequest], ToolMessage | Command],
) -> ToolMessage | Command:
```

Linear composition: `M1.wrap_tool_call → M2.wrap_tool_call → … → actual execute`. Each middleware can short-circuit (skip the handler), mutate the request, or post-process the result.

`wrap_model_call` is the symmetric hook on the model side. Together they cover every interception point a harness might want — no separate ToolNode, no separate router.

### 14.2 · The ~11 built-ins, grouped by middleware

| Middleware | Tools | Source |
|---|---|---|
| `FilesystemMiddleware` | `ls`, `read_file`, `write_file`, `edit_file`, `glob`, `grep`, `execute` (if backend supports it) | [filesystem.py:336-445](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/middleware/filesystem.py#L336) |
| `SubAgentMiddleware` | `task` | [subagents.py:200-250](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/middleware/subagents.py#L200) |
| `AsyncSubAgentMiddleware` | `launch_task`, `get_task_result`, `list_tasks`, `cancel_task` | [async_subagents.py:150-350](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/middleware/async_subagents.py#L150) |
| LangChain `TodoListMiddleware` | `write_todos` | imported, not in this repo |
| `_ToolExclusionMiddleware` | (filter) | runs at tail, drops tools listed in `HarnessProfile.excluded_tools` |

Tools are injected into `ModelRequest.tools` via `wrap_model_call`, **then filtered**. This means user `tools=[…]` and middleware-provided tools merge transparently from the agent's perspective.

### 14.3 · Backend-routed file ops

Every file tool delegates to a `BackendProtocol` ([backends/protocol.py:100-500](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/backends/protocol.py#L100)):

```python
class BackendProtocol(ABC):
    async def aread(self, path) -> ReadResult
    async def awrite(self, path, content) -> WriteResult
    async def als(self, path) -> list[FileInfo]
    async def aexecute(self, command, timeout=None) -> ExecuteResult   # SandboxBackendProtocol only
```

Concrete backends:
- **StateBackend** — in-memory dict, default ([graph.py:520](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/graph.py#L520))
- **FilesystemBackend** — real disk
- **CompositeBackend** — path-prefix routing, e.g. `/sandbox/* → Runloop`, `/ → FileSystem` ([backends/composite.py](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/backends/composite.py))
- **SandboxBackendProtocol** — marker interface enabling `execute` (Runloop, Daytona, Modal)

The same `write_file` call hits a real VM, a remote dev environment, or a Python dict depending on the backend bound at agent construction — tools never know.

### 14.4 · The 20 K eviction trick

The most-cited Deep Agents pattern. When `wrap_tool_call` sees a tool result over `_tool_token_limit_before_evict` (~20 K tokens), `_offload_tool_message_content()` ([_message_eviction.py:119-142](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/middleware/_message_eviction.py#L119)) writes the full text to `/large_tool_results/{sanitized_tool_call_id}` via the same backend, and replaces the message with:

> *Tool result was too large. The full content has been saved to `/large_tool_results/<id>`.*
> *Preview (first 5 lines + … + last 5 lines):*
> *…*

The agent can still inspect the result through `read_file(file_path="/large_tool_results/<id>", offset=…, limit=…)`. Storage and tool I/O share the same backend — eviction in Runloop goes to a Runloop file, eviction in StateBackend goes to a dict entry. Same code path.

`_create_content_preview()` ([:37-63](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/middleware/_message_eviction.py#L37)) builds the head/tail with line numbers and caps individual lines at 1000 chars.

### 14.5 · Context overflow → summarize, not error

`_DeepAgentsSummarizationMiddleware` ([summarization.py](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/middleware/summarization.py)) catches `ContextOverflowError` and calls `_clip_overflow_tail()` ([_overflow_clip.py:1-150](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/middleware/_overflow_clip.py)) which trims the trailing `ToolMessage` batch by either:

- truncating large `read_file` results in place (head + tail with path reference), or
- offloading other large results to `/large_tool_results/` (same mechanism as §14.4)

Then it re-invokes the model with a "summarize this conversation" prompt. Tool-arg truncation isn't an explicit middleware — Pydantic validation rejects oversized inputs at the schema layer, and overflow triggers reactively.

### 14.6 · Sub-agents are declarative

A subagent is a TypedDict ([subagents.py:27-115](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/middleware/subagents.py#L27)):

```python
{
    "name": "research",
    "description": "Researches and summarizes topics",
    "system_prompt": "You are a research expert...",
    "model": "openai:gpt-5.5",       # optional; inherits parent
    "tools": [...],                   # optional; inherits parent tools
    "middleware": [...],              # optional custom stack
    "skills": [...],                  # optional skill paths
    "permissions": [...],
}
```

At construction time, `create_deep_agent` builds a fresh middleware stack for each subagent ([graph.py:548-611](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/graph.py#L548)) — TodoList → Filesystem → Summarization → PatchToolCalls → (optional Skills + user middleware) → profile → exclusion → prompt-caching. The subagent is compiled via `create_agent()` and exposed through the `task` tool.

Subagents are **ephemeral and parallelizable** — each `task()` call gets a fresh context window. No state shared with the parent except the return value.

### 14.7 · Skills are not tools

`SkillsMiddleware` ([skills.py:99-150](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/middleware/skills.py#L99)) appends markdown skill content to the system prompt as progressive disclosure — the model decides when to use them. Layered sources mean later definitions override earlier ones with the same skill name. Paths use POSIX conventions so the same skill file works under any backend.

### 14.8 · Model + tool schema = LangChain's problem

`resolve_model()` ([_models.py:15-36](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/_models.py#L15)) takes `"provider:model"` strings and routes through `init_chat_model()`. Provider profiles ([profiles/provider/provider_profiles.py](https://github.com/langchain-ai/deepagents/blob/main/libs/deepagents/deepagents/profiles/provider/provider_profiles.py)) apply provider-specific defaults (Responses API, OpenRouter app attribution, etc.). Schema translation is **entirely LangChain's responsibility** — Deep Agents never sees provider-specific tool JSON.

```mermaid
flowchart TD
    M[Model returns tool_call] --> R[Middleware stack<br/>wrap_tool_call chain]
    R --> M1[TodoList]
    M1 --> M2[Filesystem]
    M2 --> M3[Summarization]
    M3 --> M4[SubAgent]
    M4 --> M5[User middleware]
    M5 --> M6[Exclusion]
    M6 --> T[Tool execute<br/>via backend]
    T --> BACKEND{Backend}
    BACKEND --> ST[StateBackend dict]
    BACKEND --> FS[Local filesystem]
    BACKEND --> RL[Runloop / Daytona / Modal]
    ST --> RES[Result]
    FS --> RES
    RL --> RES
    RES --> CHECK{>20k tokens?}
    CHECK -- yes --> EV[Offload to /large_tool_results/&lt;id&gt;<br/>via same backend]
    CHECK -- no --> M
    EV --> M
```

---

## 15. Key Takeaways

1. **Middleware as the universal extension point** — every capability composes via the same hooks
2. **Context engineering is multi-layered** — five techniques cooperating beats any single trick
3. **Sub-agents solve context pollution** — isolate the messy work, keep the main thread clean
4. **Backend abstraction** — same agent code runs locally, in LangGraph state, or in a remote sandbox
5. **"Trust the LLM" security** — enforce at the sandbox layer, not the prompt layer

---

## Further Reading

- [Deep Agents repo](https://github.com/langchain-ai/deepagents)
- [LangGraph docs](https://langchain-ai.github.io/langgraph/)
- This repo's full analysis: [research/deepagents-analysis.md](../../research/deepagents-analysis.md)
- [Cross-agent comparison](comparison.md)
