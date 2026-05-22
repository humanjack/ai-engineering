# OpenAI Codex CLI — One Protocol, Five Frontends, Three Sandboxes

> **Repository:** [openai/codex](https://github.com/openai/codex)
> **Language:** Rust (`codex-rs/` workspace, ~120 crates)
> **License:** Apache 2.0
> **Distribution:** `codex` binary (also legacy npm shim in `codex-cli/`)

---

## TL;DR

- **One protocol, five frontends.** A single `Op` / `EventMsg` submission protocol ([`protocol/src/protocol.rs:404`](https://github.com/openai/codex/blob/main/codex-rs/protocol/src/protocol.rs)) connects the TUI, headless `exec`, IDE plugin, JSON-RPC `app-server`, and an inbound MCP server to the same agent core via `submission_loop` ([`handlers.rs:733`](https://github.com/openai/codex/blob/main/codex-rs/core/src/session/handlers.rs)).
- **Sandboxing is the differentiator.** Three layers per platform — Seatbelt + execpolicy + approval (macOS), bubblewrap + seccomp + Landlock + execpolicy (Linux), AppContainer + Job objects (Windows). `.git`, `.codex`, and `AGENTS.md` are **read-only even inside writable roots**.
- **Claude-Code-compatible hooks.** The same 8 events (`PreToolUse`, `PostToolUse`, `PreCompact`, `PostCompact`, `SessionStart`, `UserPromptSubmit`, `Stop`, `PermissionRequest`) over JSON-over-stdio. The engine type is literally named [`ClaudeHooksEngine`](https://github.com/openai/codex/blob/main/codex-rs/hooks/src/engine.rs).

> **Analogy:** Codex CLI is the agent for people who want a real sandbox. Most agents say "trust the model"; Codex makes the OS say "I will not let the model do that".

---

## 1. The Workspace at a Glance

```mermaid
flowchart TB
    subgraph Frontends["5 frontends, 1 protocol"]
        TUI[tui — ratatui terminal UI]
        Exec[exec — headless one-shot]
        App[app-server — JSON-RPC for IDE/desktop]
        McpS[mcp-server — Codex as MCP tool]
        IDE[IDE plugin]
    end

    subgraph Core["core/ — agent core"]
        Sub[submission_loop<br/>handlers.rs:733]
        Turn[run_turn<br/>turn.rs:141]
        Tools[ToolCallRuntime]
        Agents[AGENTS.md manager]
        Skills[SkillsManager]
        Compact[3 compaction modes]
    end

    subgraph Tools_["Tool handlers"]
        Shell[shell / local_shell]
        Exec_[exec_command + write_stdin]
        Patch[apply_patch]
        Plan[update_plan]
        Mcp[mcp]
        SubAg[agent_jobs / multi_agents]
    end

    subgraph Sandbox["Sandbox crates"]
        Seat[sandboxing — Seatbelt .sbpl]
        Linux[linux-sandbox — bwrap+seccomp+Landlock]
        Win[windows-sandbox-rs — AppContainer]
        Exec2[execpolicy — Starlark rules]
    end

    subgraph Provider["Provider"]
        Resp[OpenAI Responses API<br/>WS primary, HTTPS fallback]
        Other[Anthropic / Ollama / Bedrock]
    end

    Frontends --> Sub --> Turn --> Tools --> Tools_
    Tools_ -.shell/patch.-> Sandbox
    Turn --> Provider
    Turn --> Agents
    Turn --> Skills
    Turn --> Compact
```

---

## 2. The Submission Loop

Every frontend speaks the same `Op` / `EventMsg` protocol:

```mermaid
sequenceDiagram
    participant F as Frontend
    participant S as submission_loop
    participant T as Task (RegularTask/CompactTask/ReviewTask)
    participant R as run_turn
    participant Hooks as Hooks engine
    participant LLM as Provider

    F->>S: Submission { id, op: UserTurn{...} }
    S->>T: spawn Task
    T->>R: run_turn(...)
    R->>R: pre-compact if near limit
    R->>R: resolve skills + plugin mentions + MCP tools
    R->>Hooks: SessionStart, UserPromptSubmit
    loop until done
        R->>R: drain pending input
        R->>LLM: run_sampling_request (Responses API)
        LLM-->>R: streamed events (deltas, tool calls)
        alt ContextWindowExceeded
            R->>R: run_auto_compact mid-turn
        else needs_follow_up
            R->>R: continue loop
        else done
            R->>Hooks: Stop, AfterAgent
            alt Stop hook returns continuation_fragment
                R->>R: re-enter loop with new user message
            end
        end
    end
    R-->>F: EventMsg stream (deltas, plan updates, approvals, ...)
```

The full `EventMsg` enum is at [`protocol/src/protocol.rs:1273`](https://github.com/openai/codex/blob/main/codex-rs/protocol/src/protocol.rs). Five distinct re-entry points in `run_turn` make the lifecycle subtle but powerful.

---

## 3. The Three-Layer Sandbox — The Distinguishing Feature

Codex sandboxes the **shell child**, not the agent process. Defense in depth on every platform.

### Linux — three independent enforcement layers

```mermaid
flowchart TB
    Cmd[shell command]
    Helper[codex-linux-sandbox<br/>helper binary]
    Bwrap[bubblewrap mounts<br/>ro / + rw roots<br/>+ mask .git/.codex/AGENTS.md]
    Seccomp[seccomp filter<br/>Restricted or ProxyRouted]
    NNP[PR_SET_NO_NEW_PRIVS]
    Land[Landlock FS rules<br/>fallback]
    Child[child process]
    Cmd --> Helper --> Bwrap --> Seccomp --> NNP --> Land --> Child

    classDef sandbox fill:#fef3c7,stroke:#a16207
    class Helper,Bwrap,Seccomp,NNP,Land sandbox
```

Seccomp modes ([`linux-sandbox/src/landlock.rs:42`](https://github.com/openai/codex/blob/main/codex-rs/linux-sandbox/src/landlock.rs)):
- **Restricted** — deny `connect/accept/bind/listen` for non-`AF_UNIX`; always deny `ptrace`, `process_vm_readv/writev`, `io_uring_*`
- **ProxyRouted** — invert: only `AF_INET`/`AF_INET6` allowed (child reaches in-namespace TCP proxy)

### macOS — Seatbelt + composed policy

```bash
# sandboxing/src/seatbelt.rs:602::create_seatbelt_command_args
/usr/bin/sandbox-exec \
  -p <policy> \
  -D READABLE_ROOT_0=/path/to/root \
  -- <command>
```

The hard-coded `/usr/bin/sandbox-exec` is a real defense-in-depth choice — if `$PATH` is compromised, the system binary still runs.

Final policy = `seatbelt_base_policy.sbpl` (closed-by-default) + per-root `(allow file-read* / file-write* (subpath ...))` + optional `seatbelt_network_policy.sbpl` + `restricted_read_only_platform_defaults.sbpl`.

### Across all platforms

**`PROTECTED_METADATA_PATH_NAMES`** in [`protocol/src/permissions.rs`](https://github.com/openai/codex/blob/main/codex-rs/protocol/src/permissions.rs) — `.git`, `.codex`, `.agents`, `AGENTS.md`, etc. are read-only even inside writable roots. **The agent can't rewrite its own rules.**

### Plus a separate execpolicy

Starlark-based command auto-approval (not the sandbox; the *decision* to ask):

```python
prefix_rule(
    pattern = ["git", ["status", "diff", "log"]],
    decision = "allow",
    justification = "read-only git operations",
)
host_executable(name = "git", paths = ["/opt/homebrew/bin/git", "/usr/bin/git"])
```

Decision precedence: `forbidden > prompt > allow`. Three lines of defense before a destructive command executes: execpolicy → user approval → sandbox.

---

## 4. Tool Calling

All built-in tools in [`core/src/tools/handlers/`](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/handlers):

| Tool | What it does |
|---|---|
| `shell` / `local_shell` | Runs commands under the platform sandbox |
| `exec_command` + `write_stdin` | "Unified exec" — long-running interactive sessions with stdin streaming |
| `apply_patch` | `*** Begin Patch / *** End Patch` envelope, parsed by [`apply-patch/src/parser.rs`](https://github.com/openai/codex/blob/main/codex-rs/apply-patch/src/parser.rs) |
| `update_plan` | Emits `PlanUpdate` event; **disabled in Plan mode** |
| `view_image` | Inject an image into the next turn |
| `request_permissions` | Model can ask for additional sandbox permissions |
| `request_user_input` | Structured Q&A back to the user |
| `tool_search` | Discover tools dynamically — interesting context-conservation trick |
| `mcp` | Dispatch into a connected MCP server |
| `agent_jobs` / `multi_agents*` | Sub-agent orchestration |

The tool router is built per-turn by `built_tools()` ([`turn.rs:1160`](https://github.com/openai/codex/blob/main/codex-rs/core/src/session/turn.rs)). Parallel dispatch happens in `tools/parallel.rs::ToolCallRuntime`.

### Approval Model

```mermaid
flowchart LR
    A[shell command] --> B{execpolicy?}
    B -- forbidden --> Stop[reject]
    B -- allow --> C{AskForApproval policy?}
    B -- prompt --> Approve[ask user]
    C -- UnlessTrusted --> D{is_safe_command?}
    D -- yes --> Run[sandbox + run]
    D -- no --> Approve
    C -- OnRequest --> Run
    C -- Granular --> Splits[per-action booleans]
    C -- Never --> Stop
    Approve -- approved --> Run
    Approve -- denied --> Stop
```

---

## 5. Context Management — Mid-Turn Provider-Aware Compaction

Compaction can fire **mid-turn** when the model emits `ContextWindowExceeded`, then the loop resumes. Three implementations cooperate:

| Mode | Where | When |
|---|---|---|
| **Inline local** | `core/src/compact.rs:69` | Default fallback |
| **Remote v1** | `compact_remote.rs` | When provider supports `/responses/compact` |
| **Remote v2** | `compact_remote_v2.rs` | Newer variant |

Selection: `should_use_remote_compact_task(provider)` ([`compact.rs:65`](https://github.com/openai/codex/blob/main/codex-rs/core/src/compact.rs)).

**Re-injection policy** (the leaky-but-pragmatic part):
- `InitialContextInjection::BeforeLastUserMessage` — mid-turn (keeps the model's training assumption that the compaction summary appears just before the last user message)
- `DoNotInject` — pre-turn / manual

The hand-tuning reflects that compaction outputs have to land where the trained model expects them.

---

## 6. AGENTS.md — Hierarchical Project Memory

Codex's memory model ([`core/src/agents_md.rs`](https://github.com/openai/codex/blob/main/codex-rs/core/src/agents_md.rs)):

```mermaid
flowchart TD
    cwd[cwd]
    parent1[parent dir]
    root[project root marker .git]
    glob[~/.codex/AGENTS.md]
    over[AGENTS.override.md takes precedence]

    cwd --> parent1 --> root
    cwd -.collect each AGENTS.md.- AssembleConcat
    glob --> AssembleConcat
    AssembleConcat["Concat root-first<br/>separator: --- project-doc ---<br/>inject into developer message"]
```

Behaviors:
- Walk up from cwd to project root (default marker `.git`)
- Collect every `AGENTS.md` along the path
- `AGENTS.override.md` takes precedence over `AGENTS.md` in the same dir
- Global `~/.codex/AGENTS.md` loaded by `AgentsMdManager::load_global_instructions`
- Sub-dir `AGENTS.md` discovery during the turn is **left to the model** (system prompt instructs it to scan when working outside CWD)

---

## 7. Skills

Defined at [`core-skills/src/model.rs::SkillMetadata`](https://github.com/openai/codex/blob/main/codex-rs/core-skills/src):

```rust
pub struct SkillMetadata {
    pub name: String,
    pub description: String,
    pub interface: Option<SkillInterface>,
    pub dependencies: Option<SkillDependencies>,
    pub policy: Option<SkillPolicy>,
    pub scope: SkillScope,  // User | Repo | System | Admin
    pub plugin_id: Option<String>,
    ...
}
```

Two invocation modes:
- **Explicit** — user mentions `@skill-creator` (`collect_explicit_skill_mentions` at `turn.rs:225`)
- **Implicit** — a tool call hitting a skill's `scripts/` dir triggers the skill, gated by `policy.allow_implicit_invocation`

Bundled samples via `include_dir!`: `skill-creator`, `plugin-creator`, `skill-installer`, `openai-docs`, `imagegen`.

Skills are injected as **contextual user fragments** — not as system messages — so they don't break prompt caching.

---

## 8. MCP — Both Directions

```mermaid
flowchart LR
    Ext1[(External MCP server<br/>GitHub, browser, ...)]
    Ext2[(External MCP server)]
    Cx[Codex agent core]
    Other[(Claude / other agent)]

    Cx -- outbound client<br/>codex-mcp + rmcp --> Ext1
    Cx -- outbound client --> Ext2
    Other -- inbound MCP<br/>codex tool --> Cx
```

- **Outbound:** `codex-mcp` uses the `rmcp` crate. Tool names namespaced `mcp__<server>__<tool>`.
- **Inbound:** `mcp-server` exposes Codex as an MCP tool. The single tool is `codex`; exec/patch approvals route as MCP elicitations.

This makes Codex composable — Claude can spawn Codex as a sub-agent for terminal work and get streamed results back.

---

## 9. Hooks — Claude-Code-Compatible by Design

Engine type is literally named [`ClaudeHooksEngine`](https://github.com/openai/codex/blob/main/codex-rs/hooks/src/engine.rs). 8 events:

| Event | Fires |
|---|---|
| `PreToolUse` | Before a tool executes |
| `PostToolUse` | After a tool returns |
| `PermissionRequest` | When permission is needed |
| `PreCompact` / `PostCompact` | Around compaction |
| `SessionStart` | Once per session |
| `UserPromptSubmit` | After every user message |
| `Stop` | When the agent says it's done |

`Stop` hooks can demand continuation by returning `continuation_fragments` — letting hooks add custom looping/QA behavior on top of the model's "I'm done" signal. Brilliant primitive.

---

## 10. Sub-Agents — First-Class Coordination

```mermaid
flowchart LR
    Parent[Parent agent]
    Reg[Agent registry]
    Mailbox[Mailbox per agent]
    Goals[Goal state<br/>shared across turns]
    Awaiter[built-in: awaiter.toml]
    Explorer[built-in: explorer.toml]
    Delegate[codex_delegate]

    Parent -- agent_jobs / multi_agents --> Reg
    Reg --> Mailbox
    Parent -. goals.rs .- Goals
    Reg --> Awaiter
    Reg --> Explorer
    Parent -- delegate_to --> Delegate
```

More than "spawn another agent" — it's a coordination layer with mailboxes, `Op::InterAgentCommunication`, and persistent goal state.

---

## 11. Capabilities Matrix

| Capability | How Codex Does It | Code Reference |
|---|---|---|
| Harness | 5 frontends → 1 `Op`/`EventMsg` protocol | `core/src/session/handlers.rs:733` |
| Context mgmt | 3 compaction modes (local / remote v1 / remote v2), mid-turn capable | `core/src/compact.rs:50-94` |
| Tool calling | ~15 built-in handlers; parallel via `ToolCallRuntime` | `core/src/tools/handlers/` |
| Sandboxing | 3 layers per platform — strongest among coding-agent CLIs | `sandboxing/`, `linux-sandbox/`, `windows-sandbox-rs/` |
| Approval | `AskForApproval` enum w/ Granular variant; execpolicy gating | `protocol/src/protocol.rs:900` |
| Automations | Claude-Code-compatible hooks (8 events); built-in slash cmds | `hooks/src/engine.rs` |
| Skills | `SKILL.md` w/ explicit @ + implicit policy; injected as user fragments | `core-skills/`, `skills/` |
| Memory | AGENTS.md hierarchical + override + global + session rollouts | `core/src/agents_md.rs:43` |
| Sessions | JSONL rollouts under `~/.codex/sessions/`; `--resume <thread-id>` | `rollout/src/recorder.rs` |
| Planning | `update_plan` tool + Plan mode (tool disabled in Plan) | `core/src/tools/handlers/plan.rs` |
| Sub-agents | First-class — registry, mailboxes, goals, `multi_agents` parallel | `core/src/agent/` |
| MCP | Client (`codex-mcp/`) + Server (`mcp-server/`) | both dirs |
| Testing | ~86 integration tests + VT100 golden tests + insta snapshots | `core/tests/suite/`, `tui/tests/suite/` |

---

## 12. Testing

- **~86 integration test files** under `codex-rs/core/tests/suite/`
- **Sandbox integration tests** — `linux-sandbox/tests/suite/landlock.rs` actually spawns sandboxed children and asserts denials
- **TUI VT100 golden tests** — `tui/tests/suite/vt100_history.rs`, `vt100_live_commit.rs` (rendering correctness via terminal emulation)
- **Insta snapshots** — `core/src/session/snapshots/` captures prompt assembly so regressions in prompt construction surface in PR review
- **Mock infrastructure** — `core/tests/common/responses.rs` (mock Responses API)
- **What's missing** — no public evals/SWE-bench harness; assumed internal at OpenAI

---

## 13. Strengths & Tradeoffs

**Strengths**
- The strongest sandbox among coding-agent CLIs
- Claude-Code-compatible hooks → portable behavior
- One protocol, many frontends — TUI/exec/IDE/MCP all just clients
- First-class sub-agent infrastructure
- Mid-turn compaction with provider-aware re-injection
- Hard-coded `sandbox-exec` path → defense in depth even with PATH compromise

**Tradeoffs**
- `run_turn` is ~600 lines with 5 re-entry points — hard to reason about in isolation
- Sandbox spawn overhead per shell call
- Provider-aware compaction is leaky — assumptions tied to training data
- Rust workspace (~120 crates) has a real onboarding cost
- Memory crate (`memories/`) is in development; not yet a complete story

---

## 14. When to Choose Codex CLI

- You need a **real OS-enforced sandbox** for agent commands
- You want Claude-Code-compatible hooks (portable to/from Anthropic's CLI)
- You're integrating an agent into an IDE/desktop app and need a stable JSON-RPC server
- You want Codex to be callable **from** other agents (via inbound MCP)
- You're comfortable with a large Rust codebase

---

## 15. Deep Dive — Tool Use

Codex's tool system reads like a hardened production system because it is one. The themes: **explicit schemas**, **trait-based dispatch**, **OS-enforced sandboxing per tool call**, and **bidirectional MCP**.

### 15.1 · Tool definition is a struct, schema is JSON

The shape ([codex-rs/tools/src/tool_definition.rs:1-26](https://github.com/openai/codex/blob/main/codex-rs/tools/src/tool_definition.rs#L1)):

```rust
pub struct ToolDefinition {
    pub name: String,
    pub description: String,
    pub input_schema: JsonSchema,
    pub output_schema: Option<JsonValue>,
    pub defer_loading: bool,
}
```

Handlers implement the `ToolExecutor<ToolInvocation>` trait and produce a `ToolSpec` exposing this definition. `defer_loading` lets some tools register their schema lazily — useful for MCP tools that need a server connection before their schema is known.

### 15.2 · The ~15 built-ins, all in `spec_plan.rs`

The complete inventory lives in [`core/src/tools/spec_plan.rs`](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/spec_plan.rs):

| Tool | Handler | Notes |
|---|---|---|
| `exec_command`, `write_stdin` | `ExecCommandHandler` | Unified execution; sandbox-aware ([handlers/unified_exec/exec_command.rs:49](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/handlers/unified_exec/exec_command.rs#L49)) |
| `shell` | `ShellCommandHandler` | Legacy single-shot shell |
| `apply_patch` | `ApplyPatchHandler` | Codex-style streaming patch ([handlers/apply_patch.rs:59](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/handlers/apply_patch.rs#L59)) |
| `update_plan` | `PlanHandler` | Emits `PlanUpdate`; disabled in Plan mode ([handlers/plan.rs:79](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/handlers/plan.rs#L79)) |
| `request_user_input`, `request_permissions` | — | Interactive prompts |
| `list_available_plugins`, `request_plugin_install` | — | Plugin discovery |
| `view_image` | `ViewImageHandler` | Multi-modal input |
| `spawn_agent`, `send_message`, `wait_agent`, `close_agent`, `list_agents` | Multi-agent V2 | Registry + mailboxes ([spec_plan.rs:631-670](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/spec_plan.rs#L631)) |
| `spawn_agents_on_csv`, `report_agent_job_result` | Agent jobs | Batch spawning |
| MCP tools | `McpHandler` | Variable count, registered via inbound clients |

### 15.3 · Registry + router dispatch

`ToolRegistry` ([registry.rs:249](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/registry.rs#L249)) is a `HashMap<ToolName, Arc<dyn CoreToolRuntime>>`. Construction via `from_tools()` ([:258](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/registry.rs#L258)), lookup via `tool()` ([:285](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/registry.rs#L285)).

`ToolRouter::dispatch_tool_call_with_code_mode_result()` calls into `dispatch_any_with_terminal_outcome()` ([:326](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/registry.rs#L326)):

1. Find handler — `self.tool(&tool_name)` ([:363](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/registry.rs#L363))
2. Build pre-tool-use payload via `CoreToolRuntime::pre_tool_use_payload()` ([:65-71](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/registry.rs#L65))
3. Fire **PreToolUse** hooks ([:416](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/registry.rs#L416)) — can block via `FunctionCallError`
4. Run `tool.handle()` — the actual execution
5. Fire **PostToolUse** hooks ([:523+](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/registry.rs#L523))
6. Return `AnyToolResult`

### 15.4 · `apply_patch` parses streaming, applies whole

The Codex-style patch format is parsed by `StreamingPatchParser` from the `codex_apply_patch` crate. `ApplyPatchArgumentDiffConsumer` ([apply_patch.rs:56](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/handlers/apply_patch.rs#L56)) buffers delta chunks every 500 ms and emits `PatchApplyUpdatedEvent`s so the UI can render progress as the model streams the patch. Final hunks go to `ApplyPatchRuntime::apply()` which routes through the active filesystem sandbox.

### 15.5 · Three sandboxes per platform — the headline

Sandbox routing lives in `UnifiedExecRuntime::run()` ([runtimes/unified_exec.rs:250](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/runtimes/unified_exec.rs#L250)), with platform-specific wiring in `build_sandbox_command()` ([:340](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/runtimes/unified_exec.rs#L340)):

| Platform | Enforcement |
|---|---|
| Linux | bwrap + seccomp + Landlock (independent layers); Landlock policy from `effective_file_system_sandbox_policy()` ([apply_patch.rs:49](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/handlers/apply_patch.rs#L49)) |
| macOS | Seatbelt via `SandboxablePreference::Auto` ([:121](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/runtimes/unified_exec.rs#L121)); `.sbpl` policy injected inside exec-server |
| Windows | AppContainer; `disable_powershell_profile_for_elevated_windows_sandbox()` ([:276](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/runtimes/unified_exec.rs#L276)); `SandboxAttempt` carries level ([:280](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/runtimes/unified_exec.rs#L280)) |

On top of OS sandboxing sits the Starlark-based **execpolicy** ([hook input rewriting at registry.rs:416](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/registry.rs#L416)) which validates `(program, args)` against an allowlist before any sandbox even spins up. Approvals are cached per canonicalized command ([unified_exec.rs:131-140](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/runtimes/unified_exec.rs#L131)) so the same command isn't re-prompted within a session.

### 15.6 · Approval profiles gate the gate

Tool execution checks `approval_policy.value()` against the active permission profile ([exec_command.rs:186](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/handlers/unified_exec/exec_command.rs#L186)):

| Profile | workspace-write | read-only | on-request | never |
|---|---|---|---|---|
| Read | ✗ | ✓ | ✗ | ✗ |
| Edit | ✓ | ✓ | ✓ | ✗ |
| Execute | ✓ | ✓ | ✓ | ✓ |

`AskForApproval::OnRequest` flips control to the user. The PreToolUse hook can also block ([:426](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/registry.rs#L426)) — a separate, programmable veto channel.

### 15.7 · MCP, both directions

**Outbound** ([`codex-mcp/`](https://github.com/openai/codex/tree/main/codex-rs/codex-mcp/src)):
- `ConnectionManager` ([connection_manager.rs](https://github.com/openai/codex/blob/main/codex-rs/codex-mcp/src/connection_manager.rs)) keeps client lifecycles
- `ToolInfo` ([tools.rs:29](https://github.com/openai/codex/blob/main/codex-rs/codex-mcp/src/tools.rs#L29)) wraps MCP tools with Codex metadata
- `normalize_tools_for_model()` ([tools.rs:144](https://github.com/openai/codex/blob/main/codex-rs/codex-mcp/src/tools.rs#L144)) sanitizes names + dedupes across servers
- `tool_with_model_visible_input_schema()` ([tools.rs:117](https://github.com/openai/codex/blob/main/codex-rs/codex-mcp/src/tools.rs#L117)) masks sensitive parameters (file paths!) so the model can't trivially exfiltrate
- `supports_parallel_tool_calls` ([tools.rs:34](https://github.com/openai/codex/blob/main/codex-rs/codex-mcp/src/tools.rs#L34)) propagates per-tool

**Inbound** ([`mcp-server/`](https://github.com/openai/codex/tree/main/codex-rs/mcp-server/src)): exposes Codex itself as an MCP server, so other agents can call Codex tools.

### 15.8 · Sub-agents are first-class

Multi-agent V2 ([handlers/multi_agents_v2/](https://github.com/openai/codex/tree/main/codex-rs/core/src/tools/handlers/multi_agents_v2)):

```
spawn_agent  → SpawnAgentHandlerV2
send_message → SendMessageHandlerV2     # mailbox push
wait_agent   → WaitAgentHandlerV2       # blocks parent on UntilTerminal + timeout
close_agent  → CloseAgentHandlerV2
list_agents  → ListAgentsHandlerV2
```

`resolve_agent_target()` ([multi_agents_v2.rs:4](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/handlers/multi_agents_v2.rs#L4)) maps `AgentPath` to an active session. Messages flow as `CollabAgentInteractionBeginEvent` etc. — the same event protocol UIs consume, just routed agent-to-agent.

### 15.9 · Mid-turn compaction with provider-specific impls

`ContextWindowExceeded` triggers `run_inline_auto_compact_task()` ([compact.rs:69](https://github.com/openai/codex/blob/main/codex-rs/core/src/compact.rs#L69)) which injects the compaction summary `BeforeLastUserMessage` ([compact.rs:57](https://github.com/openai/codex/blob/main/codex-rs/core/src/compact.rs#L57)) and resumes. Pre-compact hook ([:140](https://github.com/openai/codex/blob/main/codex-rs/core/src/compact.rs#L140)) can block, post-compact ([:161](https://github.com/openai/codex/blob/main/codex-rs/core/src/compact.rs#L161)) gets fired after. Three implementations cover OpenAI (Responses API retry), Anthropic (inline), and other providers (pre-turn fallback).

### 15.10 · Output truncation is per-tool

`ExecCommandToolOutput::truncate_and_serialize()` enforces `DEFAULT_OUTPUT_BYTES_CAP` (from `codex_utils_pty`) or a per-tool `max_output_tokens` override ([exec_command.rs:259, 279](https://github.com/openai/codex/blob/main/codex-rs/core/src/tools/handlers/unified_exec/exec_command.rs#L259)). Token counting uses `approx_token_count()` — model-aware so the model's view stays under cap.

```mermaid
flowchart TD
    M[Model tool_call] --> D[ToolRouter.dispatch]
    D --> H1[execpolicy<br/>Starlark allowlist]
    H1 -- deny --> RM[FunctionCallError::RespondToModel]
    H1 -- allow --> H2[PreToolUse hook<br/>can block]
    H2 -- block --> RM
    H2 -- allow --> AP{Approval profile<br/>workspace-write / on-request / …}
    AP -- ask --> USR[User approves<br/>cached per command]
    AP -- never --> RM
    AP -- allow --> SB{Sandbox layer}
    SB --> LX[Linux: bwrap + seccomp + Landlock]
    SB --> MAC[macOS: Seatbelt .sbpl]
    SB --> WIN[Windows: AppContainer]
    LX --> EX[Execute]
    MAC --> EX
    WIN --> EX
    EX --> TR[Truncate output<br/>per-tool cap, token-aware]
    TR --> H3[PostToolUse hook]
    H3 --> M
```

---

## 16. Key Takeaways

1. **The sandbox is the lesson.** Three independent enforcement layers + metadata masking is the strongest current take on "untrust the model".
2. **One protocol unlocks many frontends.** TUI, exec, app-server, MCP-in all speak `Op`/`EventMsg` to the same `submission_loop` — every UI is just a different mouth.
3. **Hooks as continuation triggers.** `Stop` hooks can demand the agent keep working — turns hooks into a QA gate, not just an audit log.
4. **Mid-turn compaction with model-aware re-injection.** A leaky abstraction but pragmatically necessary.
5. **Skills as user fragments, not system messages.** Preserves prompt cache while still adding capability.

---

## Further Reading

- [openai/codex](https://github.com/openai/codex)
- [Codex docs (developers.openai.com)](https://developers.openai.com/codex)
- [Cross-agent comparison](comparison.md)
