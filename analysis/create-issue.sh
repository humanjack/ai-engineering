#!/bin/bash
# Run this script locally where you have `gh` authenticated to create the issue:
#   chmod +x create-issue.sh && ./create-issue.sh

gh issue create \
  --repo humanjack/ai-engineering \
  --title "Analysis: jennifer509/nunet-news-digest - Architecture, Security & Reliability Review" \
  --body "$(cat <<'ISSUE_BODY'
# Repository Analysis: jennifer509/nunet-news-digest

> **AI-Powered News Digest on NuNet Decentralised Compute**
> Repository: https://github.com/jennifer509/nunet-news-digest
> Full analysis with Mermaid diagrams: [`analysis/nunet-news-digest-repo-analysis.md`](https://github.com/humanjack/ai-engineering/blob/claude/analyze-repo-architecture-KrmSt/analysis/nunet-news-digest-repo-analysis.md)

---

## Executive Summary

**nunet-news-digest** is a single-file Python application (~460 lines) that automates AI-powered news aggregation. It fetches articles from 11 RSS feeds, scores them for relevance against 40+ keywords, synthesizes structured briefings via Google Gemini API, and delivers results to Telegram. Containerized in a 6-line Dockerfile and deployed on NuNet decentralized compute.

| Metric | Value |
|--------|-------|
| Language | Python 3.11 |
| Total Files | 6 |
| Main Script | ~460 lines |
| Dependencies | 1 (aiogram>=3.4) |
| RSS Sources | 11 feeds |
| Relevance Keywords | 40+ |

---

## 1. Feature Analysis

```mermaid
mindmap
  root((nunet-news-digest))
    Data Ingestion
      11 RSS/Atom Feeds
        AI/ML Sources
          TechCrunch AI
          The Verge AI
          Ars Technica
          Google AI Blog
        Crypto/DePIN Sources
          CoinTelegraph
          The Block
          Decrypt
        Infrastructure Sources
          Hacker News
          InfoQ
          Kubernetes Blog
          Docker Blog
      HTML Stripping
      Dual Format Parser
    Intelligence Layer
      40+ Keyword Scoring
      Title Deduplication
      Top-N Filtering
      Configurable Thresholds
    AI Synthesis
      Gemini API Integration
      Multi-model Fallback
      Structured Prompt Engineering
      4 Output Sections
    Delivery
      Telegram Bot
        HTML Formatting
        Message Chunking
        Topic Threading
      Local Markdown Backup
    Operations
      CLI Interface
      Docker Container
      NuNet Deployment
      Scheduled Execution
```

### Core Features (12 total)

| # | Feature | Description |
|---|---------|-------------|
| 1 | Multi-source RSS Aggregation | 11 RSS/Atom feeds across AI, Crypto/DePIN, Infrastructure |
| 2 | Dual Format Parsing | RSS 2.0 and Atom with HTML stripping |
| 3 | Keyword Relevance Scoring | 40+ domain-specific keywords |
| 4 | Title-based Deduplication | Normalized title comparison |
| 5 | AI Synthesis via Gemini | Structured digest with 4 sections |
| 6 | Gemini Model Fallback | 3-model cascade (2.5-flash -> 2.0-flash -> 1.5-flash) |
| 7 | Telegram Delivery | HTML formatting + auto chunk splitting |
| 8 | Topic Threading | Optional Telegram forum topic routing |
| 9 | Local Markdown Backup | Dated archive with metadata |
| 10 | Three Operation Modes | Single run, dry-run, scheduled |
| 11 | Dockerized Deployment | Minimal 6-line Dockerfile |
| 12 | NuNet Decentralized Deploy | YAML manifest + JSON sidecar |

---

## 2. Design Architecture

```mermaid
graph TB
    subgraph "External Data Sources"
        RSS1["TechCrunch AI"]
        RSS2["The Verge AI"]
        RSS3["Hacker News"]
        RSS4["CoinTelegraph"]
        RSS5["7 More Feeds..."]
    end

    subgraph "NuNet Decentralized Compute Node"
        subgraph "Docker Container: python:3.11-slim"
            FETCH["fetch_all_feeds&#40;&#41;<br/>Sequential RSS fetcher"]
            SCORE["score_relevance&#40;&#41;<br/>40+ keyword matcher"]
            FILTER["filter_and_rank&#40;&#41;<br/>Dedup + Top-N"]
            SYNTH["synthesize_digest&#40;&#41;<br/>Gemini REST API"]
            DELIVER["send_to_telegram&#40;&#41;<br/>aiogram bot"]
            SAVE["Local file save"]
        end
    end

    subgraph "External APIs"
        GEMINI["Google Gemini API"]
        TGAPI["Telegram Bot API"]
    end

    RSS1 --> FETCH
    RSS2 --> FETCH
    RSS3 --> FETCH
    RSS4 --> FETCH
    RSS5 --> FETCH
    FETCH --> SCORE --> FILTER --> SYNTH
    SYNTH --> GEMINI
    GEMINI --> SYNTH
    SYNTH --> DELIVER --> TGAPI
    SYNTH --> SAVE

    style FETCH fill:#4a90d9,color:#fff
    style SYNTH fill:#e67e22,color:#fff
    style DELIVER fill:#27ae60,color:#fff
    style GEMINI fill:#f39c12,color:#fff
    style TGAPI fill:#0088cc,color:#fff
```

### Deployment Architecture

```mermaid
graph TB
    subgraph "Development"
        DEV["Developer Machine"]
        CLI["CLI Testing<br/>--dry-run"]
    end

    subgraph "Docker Hub"
        IMG["jenb97/news-digest:latest"]
    end

    subgraph "NuNet P2P Network"
        APPLIANCE["NuNet Appliance Dashboard"]
        YAML["news-digest.yaml"]
        SIDECAR["sidecar.json"]
        subgraph "Peer Node"
            CONTAINER["Docker Container<br/>0.5-4 CPU, 0.5-8 GiB RAM"]
        end
    end

    DEV -->|"docker build + push"| IMG
    DEV --> CLI
    IMG -->|"pulled by"| CONTAINER
    APPLIANCE -->|"configures"| YAML
    SIDECAR -->|"defines UI for"| APPLIANCE
    YAML -->|"deploys to"| CONTAINER

    style IMG fill:#2496ed,color:#fff
    style APPLIANCE fill:#9b59b6,color:#fff
    style CONTAINER fill:#27ae60,color:#fff
```

---

## 3. Workflow Analysis

```mermaid
flowchart TD
    START([Start]) --> ARGS["Parse CLI Args"]
    ARGS --> MODE{Mode?}

    MODE -->|schedule| SLEEP["Sleep until SCHEDULE_HOUR UTC"]
    SLEEP --> RUN
    MODE -->|single| RUN["run_digest&#40;&#41;"]

    RUN --> FETCH["Fetch 11 feeds<br/>0.5s delay each"]
    FETCH --> CHECK{Articles?}
    CHECK -->|No| EXIT["Exit"]
    CHECK -->|Yes| FILTER["Score + Filter + Dedup<br/>Top 25 articles"]
    FILTER --> RELEVANT{Relevant?}
    RELEVANT -->|No| LOWER["Lower threshold<br/>min_score=0"]
    LOWER --> SYNTH
    RELEVANT -->|Yes| SYNTH["Gemini Synthesis<br/>3-model fallback"]
    SYNTH --> SAVE["Save markdown"]
    SAVE --> DRY{Dry run?}
    DRY -->|Yes| PRINT["Print to console"]
    DRY -->|No| TG["Send to Telegram<br/>Chunked HTML"]
    TG --> DONE([Done])
    PRINT --> DONE

    style FETCH fill:#4a90d9,color:#fff
    style SYNTH fill:#e67e22,color:#fff
    style TG fill:#27ae60,color:#fff
```

### Data Flow

```mermaid
flowchart LR
    RSS["11 RSS Feeds<br/>~250+ articles/day"] -->|"HTTP GET"| ARTICLES["Raw Articles"]
    ARTICLES -->|"keyword match"| SCORED["Scored Articles"]
    SCORED -->|"sort + dedup"| FILTERED["Top 25"]
    FILTERED -->|"prompt template"| PROMPT["Gemini Prompt"]
    PROMPT -->|"REST API"| DIGEST["Structured Digest"]
    DIGEST -->|"HTML chunks"| TELEGRAM["Telegram"]
    DIGEST -->|"file write"| ARCHIVE["Local Archive"]
```

---

## 4. Security Analysis

```mermaid
graph TB
    subgraph "CRITICAL"
        S1["SSL Verification Disabled<br/>for RSS Feeds - MITM risk"]
        S2["API Key in URL Query Param<br/>Visible in logs/proxies"]
        S3["Docker Runs as Root<br/>No USER directive"]
    end
    subgraph "HIGH"
        S4["RSS Content to Prompt Injection<br/>Unsanitized feed content"]
        S5["SSL Fallback Disables Verify<br/>for Gemini API calls"]
        S6["Unpinned Dependency<br/>aiogram no upper bound"]
    end
    subgraph "MEDIUM"
        S7["Placeholder Secrets in YAML"]
        S8["No Secret Rotation"]
    end
    style S1 fill:#c0392b,color:#fff
    style S2 fill:#c0392b,color:#fff
    style S3 fill:#c0392b,color:#fff
    style S4 fill:#e67e22,color:#fff
    style S5 fill:#e67e22,color:#fff
    style S6 fill:#e67e22,color:#fff
```

| # | Severity | Finding | Recommendation |
|---|----------|---------|----------------|
| 1 | **CRITICAL** | SSL verification disabled for RSS feeds (`CERT_NONE`) | Enable SSL verification; add `certifi` |
| 2 | **CRITICAL** | Gemini API key exposed in URL query parameter | Use `x-goog-api-key` HTTP header |
| 3 | **CRITICAL** | Container runs as root (no USER directive) | Add `RUN useradd -r appuser && USER appuser` |
| 4 | **HIGH** | Unsanitized RSS content in Gemini prompt (injection risk) | Sanitize/escape feed content |
| 5 | **HIGH** | SSL fallback disables verification for Gemini API | Include `certifi` in requirements.txt |
| 6 | **HIGH** | Unpinned dependency (`aiogram>=3.4`) | Pin exact version: `aiogram==3.4.1` |
| 7 | **MEDIUM** | Placeholder secrets in YAML config | Use NuNet secret injection |
| 8 | **MEDIUM** | No secret rotation mechanism | Implement key rotation strategy |

---

## 5. Reliability Analysis

```mermaid
graph TB
    subgraph "Existing Resilience - Good"
        P1["Gemini 3-Model Fallback"]
        P2["Adaptive Score Threshold"]
        P3["Console Fallback on TG Fail"]
        P4["Polite 0.5s Feed Delays"]
    end
    subgraph "Missing Resilience - Gaps"
        M1["No Retry Logic<br/>for RSS/Telegram"]
        M2["No Health Checks"]
        M3["No Container Restart Policy"]
        M4["No Persistent Storage"]
        M5["Sleep-based Scheduler<br/>Drift prone"]
        M6["No Monitoring/Alerting"]
    end
    style P1 fill:#27ae60,color:#fff
    style P2 fill:#27ae60,color:#fff
    style P3 fill:#27ae60,color:#fff
    style P4 fill:#27ae60,color:#fff
    style M1 fill:#e74c3c,color:#fff
    style M2 fill:#e74c3c,color:#fff
    style M3 fill:#e74c3c,color:#fff
    style M4 fill:#e74c3c,color:#fff
    style M5 fill:#e74c3c,color:#fff
    style M6 fill:#e74c3c,color:#fff
```

| # | Impact | Finding | Recommendation |
|---|--------|---------|----------------|
| 1 | **HIGH** | No retry on RSS fetch failures | Add exponential backoff (3 attempts) |
| 2 | **HIGH** | No retry on Telegram delivery | Add retry with backoff |
| 3 | **HIGH** | No container restart policy | Add `restart: always` |
| 4 | **HIGH** | No health checks | Add Docker HEALTHCHECK |
| 5 | **MEDIUM** | Sleep-based scheduler drifts | Use APScheduler or cron |
| 6 | **MEDIUM** | Sequential feed fetching (~6s min) | Use asyncio.gather() |
| 7 | **MEDIUM** | No graceful shutdown handling | Add signal handlers |
| 8 | **MEDIUM** | Output not persisted across restarts | Mount Docker volume |

---

## Summary Scorecard

| Dimension | Score | Assessment |
|-----------|-------|------------|
| **Features** | 8/10 | Excellent feature set for scope |
| **Architecture** | 7/10 | Clean single-file design appropriate for complexity |
| **Workflow** | 7/10 | Clear pipeline with smart adaptive fallbacks |
| **Security** | 3/10 | Critical: disabled SSL, exposed API keys, root container |
| **Reliability** | 4/10 | Good model fallback but missing retries, health checks, monitoring |

### Top 5 Immediate Actions

| # | Action | Category | Effort |
|---|--------|----------|--------|
| 1 | Enable SSL verification + add `certifi` | Security | Low |
| 2 | Move Gemini API key to HTTP header | Security | Low |
| 3 | Add `USER appuser` to Dockerfile | Security | Low |
| 4 | Pin `aiogram` to exact version | Security | Low |
| 5 | Add retry logic with exponential backoff | Reliability | Medium |

---

> **Overall**: A well-conceived and cleanly implemented prototype with excellent product thinking. Security posture needs critical fixes before production. Reliability improvements would significantly increase operational confidence.

https://claude.ai/code/session_01DUDp56fcTtcsDaGqN2K5XN
ISSUE_BODY
)"
