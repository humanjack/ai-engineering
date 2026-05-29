# Adaptive Chunking — Architecture & Code Analysis

**Repository:** [ekimetrics/adaptive-chunking](https://github.com/ekimetrics/adaptive-chunking)
**Paper:** *"Adaptive Chunking: Optimizing Chunking-Method Selection for RAG"* — accepted at **LREC 2026** ([arXiv:2603.25333](https://arxiv.org/abs/2603.25333))
**Authors:** Paulo Roberto de Moura Junior, Jean Lelong, Annabelle Blangero — [Ekimetrics](https://www.ekimetrics.com/)
**License:** MIT (core) · Python ≥ 3.11 · ~8.8k LoC of Python
**Tagline:** *No single chunking method works best for every document — so evaluate several and pick the best one per document.*

> This is both a **research artifact** (reproduces every table/figure of an LREC 2026 paper from shipped data) and a **reusable library** (a `pip install`-able adaptive recursive splitter + five ground-truth-free quality metrics). This document analyzes the design, the algorithms under the hood, the workflow, code structure, reliability engineering, and impact.

---

## 1. The Core Idea

RAG quality is bottlenecked long before retrieval and generation: if a document is chopped into chunks that sever a table from its caption, a pronoun from its antecedent, or a claim from its supporting sentence, no retriever or LLM can recover the lost context. The standard fix — pick one chunking strategy (usually fixed-size recursive) and apply it everywhere — is a compromise. A page-break split is great for a slide-style ESG report and terrible for a flowing legal contract; a semantic splitter is the reverse.

Adaptive Chunking reframes chunking as a **per-document model-selection problem**:

```
for each document d:
    for each chunking method m in {page, sentence, recursive×3, semantic, llm_regex, ...}:
        chunks[d][m]  = m(d)
        score[d][m]   = weighted_mean( metric_i(chunks[d][m]) for i in 5 metrics )
    best_method[d]    = argmax_m score[d][m]      # ← different docs win with different methods
    output[d]         = chunks[d][ best_method[d] ]
```

The two crucial design decisions:

1. **The selection signal needs no ground truth.** All five quality metrics are *intrinsic* — they score a chunking purely from the text + cheap NLP signals (embeddings, coreference, the parser's own block boundaries). That means the method can be applied to a brand-new corpus in production with **no labeled QA pairs**.
2. **Both axes are pluggable.** A "chunking method" is any callable `str -> list[str]`; a "metric" is any callable `list[str] -> float`. The framework is a thin orchestration layer around those two contracts.

The official diagram (`docs/architecture.svg`) summarizes it as: *Corpus → Chunking Methods → Quality Metrics → Best Method Selection → Optimal chunks per document.* See `diagrams/adaptive-chunking/architecture.mmd` for the data-flow version with module names.

---

## 2. Key Results (from the paper, reproduced by the repo)

**Intrinsic metrics — Table 3** (mean %, all domains; Wilcoxon p < 0.001 vs every other method):

| Method | RC | ICC | DCC | BI | SC | **Mean** |
|--------|---:|----:|----:|---:|---:|--------:|
| **Adaptive Chunking** | 99.0 | 68.2 | 88.8 | 99.4 | 99.9 | **91.07** |
| LLM regex (GPT) | 98.0 | 70.9 | 82.4 | 98.1 | 99.6 | 89.80 |
| LangChain recursive | 96.1 | 65.6 | 88.8 | 95.0 | 97.7 | 88.62 |
| Semantic | 97.5 | 69.3 | 76.3 | 91.3 | 48.1 | 76.49 |
| Sentence | 86.3 | 78.4 | 72.5 | 61.9 | 67.2 | 73.26 |

**Extrinsic RAG validation — Table 5** (Wilcoxon p < 0.05 for retrieval completeness):

| Metric | **Adaptive** | LangChain recursive | Page split |
|--------|---:|---:|---:|
| Retrieval Completeness | **67.7** | 58.1 | 59.1 |
| Answer Correctness | **78.0** | 70.1 | 73.3 |
| Answered queries | **65/99** | 49/99 | 49/99 |

The honest read: on the *intrinsic* mean the win is modest (+2.45 pts over LangChain) — because the per-document argmax can only ever match the best fixed method on easy docs and beats it on hard ones. The *extrinsic* gain is where it pays off: **+9.6 pts retrieval completeness and 16 more answered queries (out of 99)** than either fixed baseline. Selecting chunking per document moved a real RAG needle.

Evaluation corpus: **33 documents, 3 domains (technical / legal / sustainability reporting), ~1.18M tokens** — the CLAIR corpus, shipped pre-parsed in `data/clair/`.

---

## 3. Repository Layout & Code Structure

```
adaptive-chunking/
├── data/clair/
│   ├── adi_parsed/          # 33 pre-parsed JSON docs (the parsed-doc contract)
│   └── mentions/            # pre-computed maverick-coref clusters → no GPU needed for RC
├── src/adaptive_chunking/
│   ├── __init__.py          #   7  — public API: just chunk_files
│   ├── pipeline.py          # 145  — chunk_files(): parse → split → repair → metadata
│   ├── splitters.py         # 618  — RecursiveSplitter + group/regex helpers  ← the core
│   ├── metrics.py           # 934  — the 5 intrinsic metrics + CoreferenceSolver
│   ├── parsing.py           #1111  — BaseParser ABC + Docling/PyMuPDF/Azure/Excel
│   ├── postprocessing.py    # 512  — gap invariant, oversized-split, tiny-merge, metadata
│   ├── compute_metrics.py   # 238  — scores all docs×methods, incremental + resumable
│   ├── split_documents.py   # 241  — runs all splitters over a directory (sync + async)
│   ├── extract_mentions.py  #  80  — coref orchestration for the RC metric
│   ├── chunking_utils.py    #  25  — tiktoken token counting
│   ├── jina_embedder.py     # 137  — Jina REST drop-in for SentenceTransformer
│   └── paper/               # paper-reproduction only (extra dependencies)
│       ├── replicate.py     # 889  — the 7-step CLI entry point
│       ├── splitters.py     # 577  — Semantic / Sentence / LongContext / LLMRegex baselines
│       ├── analysis.py      # 883  — adaptive selection + Tables 1–3 + Figure 1
│       ├── rag_eval.py      # 821  — RetrievalCompleteness LLM judge + DeepEval
│       ├── rag_utils.py     # 699  — Haystack hybrid-retrieval pipeline, QA generation
│       └── visualization.py # 838  — HTML split overlays
├── tests/                   # pytest: splitters, metrics, parsing, postprocessing
├── LLM.md                   # context file for coding assistants (architecture notes)
├── REPLICATE_GUIDELINES.md  # reproducibility notes + stability constraints
└── pyproject.toml           # extras: [coref] [parsing] [paper] [dev]
```

**Structural discipline worth noting:**

- **Core vs. paper split.** `pip install -e .` gives only the splitter + metrics (light deps: tiktoken, pandas, sentence-transformers, spacy, sklearn). The heavy machinery (torch 2.6, langchain, haystack, openai, deepeval, stanza, maverick) lives behind the `[paper]` extra. The library you'd embed in production is a small subset of the research code.
- **Lazy imports everywhere.** Heavy ML deps are imported *inside functions*, never at module top-level (e.g. `from sentence_transformers import util` inside `compute_semantic_dissimilarity`, `from maverick import Maverick` inside `CoreferenceSolver.__init__`). Importing `adaptive_chunking` stays cheap and doesn't pull a GPU stack.
- **Stable data contracts.** Chunks/mentions/metrics are persisted as **Parquet**; parsed documents as **JSON**. Stages communicate only through files, which is what makes the pipeline resumable and individually runnable.

---

## 4. The Data Model — one JSON contract that makes everything else possible

Every parser, regardless of backend, must emit the same shape (`BaseParser` docstring, `parsing.py:12`):

```jsonc
{
  "document_name": "report_x",
  "pages":   { "1": "## markdown of page 1 …", "2": "…" },   // insertion order == reading order
  "full_text": "concatenation of all pages, verbatim",
  "split_points": [142, 870, 1203, …],   // char offsets of structural block boundaries
  "titles":  [ { "title": "1. Intro", "start": 0, "end": 142, "level": 1 }, … ]
}
```

This contract is the linchpin:

- `full_text` is the **single source of truth**. Chunks are always substrings of it, which lets the system *locate* any chunk by string search and reason about boundaries in character space.
- `split_points` are the parser's own opinion of where real blocks (paragraphs, tables, lists) begin/end. **Block Integrity** scores a chunking against exactly these points — so "did you respect the document's structure?" is measured against the structure the parser actually extracted, not a guess.
- `titles` (with `start`/`end`/`level`) drive `titles_context`: when a chunk falls under a heading whose text isn't physically inside the chunk, the heading is attached as context metadata. This is a quiet but important retrieval booster.

---

## 5. The RecursiveSplitter Under the Hood (`splitters.py`)

This is the project's own chunker and the one that wins most often. It is a **split-then-merge** design (see `diagrams/adaptive-chunking/recursive-splitter.mmd`).

### Phase A — `_recursive_split`: descend a separator hierarchy

Given an ordered separator list, it tries the first separator; any resulting piece still larger than `chunk_size` is recursively re-split with the *next* separator, and so on. The paper configures a **14-level markdown-aware hierarchy** (`replicate.py:56`), from coarsest to finest:

```
H1…H6 headings  →  numbered/lettered list items  →  bullet markers (-, •, ▪, ◦, …)
→  blank lines (\n{2,})  →  single \n  →  sentence ends [.!?]  →  commas  →  spaces  →  ""
```

The terminal `""` separator is the clever part. When no semantic boundary can make a piece fit, it falls back to a **binary search** for the largest character prefix whose token count is ≤ `chunk_size` (`splitters.py:142`). This guarantees termination and — critically — never drops a character (it always advances by at least one). A naive "split every N chars" would mis-handle multi-byte tokens; binary search over the *real* token counter is exact.

Two robustness touches:
- Splitting keeps the separator attached (`attach_separator_to="start"` in the paper), so headings stay glued to the text beneath them.
- `_split_with_separator` is explicitly *"robust against patterns that contain capturing groups"* — it walks `re.finditer` matches rather than using `re.split`, sidestepping the classic Python footgun where capturing groups change `re.split`'s output.

### Phase B — two merge policies

After Phase A produces boundary-respecting pieces, one of two strategies reassembles them:

| `merging` mode | Behavior | Used by |
|---|---|---|
| `"to_chunk_size"` | Greedily packs pieces up to ~`chunk_size`, optionally with token overlap. Produces uniform, dense chunks. | The paper's `our_recurs_1100` / `our_recurs_600` |
| `"small_only"` | Keeps every semantic boundary intact; *only* merges pieces below `min_chunk_tokens` into a neighbour. Preserves structure at the cost of size uniformity. | The library default in `chunk_files` |

The **overlap reconstruction** (`_merge_splits`, `splitters.py:232`) is more careful than typical implementations. When starting a new chunk it backtracks over the *previous chunk's constituent parts* to build the overlap; if a single tail part is itself larger than `chunk_overlap`, it **recursively re-splits that part** to extract just enough overlap (enforcing a minimum of 50% of the requested overlap). This avoids both "no overlap because the last part was huge" and "overlap blows past the target."

> **A subtle but important note for users:** the library's `chunk_files(...)` default (`chunk_size=600, merging="small_only"`, plain `["\n\n","\n"," ",""]` separators) is **not** the configuration that produced the paper's headline `our_recurs` rows (`chunk_size=1100, merging="to_chunk_size"`, the 14-level markdown separators). The strong default is a reasonable general-purpose chunker; reproducing the paper requires the explicit paper config wired in `replicate.py`.

---

## 6. The Five Intrinsic Metrics (`metrics.py`) — what "quality" means here

All five return a score in `[0, 1]` where higher is better, and **none require ground-truth answers**. This is the heart of the contribution.

| Metric | Code | One-line definition | Signal |
|---|---|---|---|
| **SC** — Size Compliance | `compute_size_compliance` | Fraction of chunks within `[100, 1100]` tokens. | token counts only |
| **ICC** — Intrachunk Cohesion | `compute_intrachunk_cohesion` | Mean cosine sim between each chunk's *sentences* and the chunk's own embedding. | jina-embeddings-v3 |
| **DCC** — Contextual Coherence | `compute_contextual_coherence` | Mean cosine sim between each chunk and its surrounding ~3000-token window. | jina-embeddings-v3 |
| **BI** — Block Integrity | `compute_block_integrity` | Fraction of parser `split_points` blocks **not** cut by a chunk boundary (±5 char tolerance). | parser structure |
| **RC** — Reference Completeness | `compute_filtered_missing_ref_error` | 1 − fraction of entity↔pronoun coreference pairs split across a chunk boundary. | coreference (maverick) |

A few details that show real care:

- **ICC vs. DCC are opposing forces.** ICC rewards chunks that are internally homogeneous (don't mix topics); DCC rewards chunks that still resemble their neighbourhood (don't isolate). A splitter that fragments aggressively raises ICC but tanks DCC, and vice-versa — the weighted mean balances them. (`analysis.plot_metric_correlations` exists precisely to study these tensions — Figure 1.)
- **DCC's sliding window never double-counts text.** The window builder (`metrics.py:194`) tracks `current_end` and only adds the *unseen tail* of each overlapping chunk to the window, so overlap-heavy chunkings aren't unfairly inflated. It also skips degenerate single-chunk windows. This is the most intricate metric and the kind of edge-case handling that separates a benchmark you can trust from one you can't.
- **BI is measured in character space against the parser's own blocks**, with a 5-char tolerance so trivial whitespace differences don't count as "broken." This is why the parser's `split_points` matter so much.
- **RC operationalizes "don't strand a pronoun."** Coreference clusters are reduced to entity→pronoun pairs (`extract_entity_pronoun_pairs`), and a pair is "missing" if *any* chunk boundary falls between the entity and its pronoun. Counted at most once per pair. The README calls the raw quantity "Filtered Missing Reference Error"; the reported metric is its complement (completeness).

There are also unused-by-default metrics in the file (`compute_semantic_dissimilarity`, `compute_lexical_dissimilarity`, `compute_normalized_intrachunk_sim`) — research scaffolding that the pluggable design tolerates without bloating the default scoring set.

---

## 7. The Adaptive Selection Algorithm (`paper/analysis.py`)

This is where "adaptive" actually happens, and it's deliberately simple — see `diagrams/adaptive-chunking/adaptive-selection.mmd`.

`find_best_method` (`analysis.py:294`):

1. Pivot the per-document scores into a **metric × method** matrix.
2. For each method (column), compute a **weighted mean over metrics, skipping NaNs**: `Σ wᵢ·sᵢ / Σ wᵢ` over the metrics that actually have a score. The default weights are **uniform, 0.2 each** (`WEIGHTS = {m: 0.2 for m in METRICS}`).
3. `argmax` over methods (`idxmax`, which ignores NaN).

`output_best_chunks` (`analysis.py:167`) then pulls the winning method's chunks, in order, and writes one JSON per document. If a document has *no* usable metrics, it falls back to `default_method="page"`, then to the first available method — it never crashes or silently drops a document.

Two things make this robust rather than naive:
- **NaN-skipping is principled.** A method might legitimately have no ICC (e.g. all single-sentence chunks) or no RC (no coreference pairs found). Rather than penalize or crash, those metrics are simply excluded from *that method's* mean and the weights renormalize. This keeps comparisons fair across methods that produce structurally different outputs.
- **The weights are exposed.** Because selection is a weighted mean with externalized weights, a user who cares more about, say, table integrity for a financial corpus can re-weight BI upward without touching any other code. The "adaptive" policy is a one-line dictionary.

---

## 8. The Eight Chunking Methods & Baselines (`paper/splitters.py`)

The benchmark compares the framework's splitter against a representative spread of the field:

| Method | Implementation | Notes |
|---|---|---|
| `page` | page texts as-is | the parser's natural page boundaries |
| `sentence` | `SentenceSplitter` (Stanza, 5 sentences/chunk) | classic fixed-count baseline |
| `langch_recurs_default` | LangChain `RecursiveCharacterTextSplitter()` | the de-facto industry default |
| `langch_recurs_1100` | LangChain recursive w/ the 14-level markdown separators, 1100 tok | apples-to-apples vs. `our_recurs` |
| `our_recurs_1100` / `our_recurs_600` | this repo's `RecursiveSplitter` | the proposed method, two sizes |
| `semantic` | `SemanticChunkerWrapper` (LangChain SemanticChunker, Qwen3-Embedding-0.6B, gradient breakpoints) | embedding-breakpoint chunking |
| `llm_regex` | `LLMRegexSplitter` (GPT-4o) | LLM writes a per-document regex delimiter |

Notable engineering in the baselines:
- **`SemanticChunkerWrapper`** subclasses LangChain's `SemanticChunker` but adds a *whitespace-tolerant remap* of each chunk back to the source text and forces contiguity (`_map_chunks`) — because LangChain's semantic chunker is "destructive" (it normalizes whitespace), which would otherwise break the "chunks are verbatim substrings" invariant the metrics depend on.
- **`LLMRegexSplitter`** asks an LLM (few-shot prompted, temperature 0) to emit a single `<regex>…</regex>` delimiter, then splits with it. `extract_llm_regex` validates the pattern with `re.compile` and even attempts a **self-repair** (escaping stray hyphens inside character classes) before giving up and returning the whole document as one chunk. A clean example of defensive LLM-output handling.
- **`LongContextSemanticSplitter`** (experimental) embeds whole overlapping sentence-blocks with a long-context model and splits on cosine-dissimilarity peaks, with assertions that reconstruction is lossless (`assert reconstructed == text`).

---

## 9. Post-Processing & the Gap Invariant (`postprocessing.py`) — the reliability backbone

After any splitter runs, chunks pass through normalization, and the whole system rests on **one invariant that is asserted everywhere**:

> The ordered chunks must cover **every character** of `full_text` with **no gaps** (overlap is allowed).

`check_chunk_gaps` (`postprocessing.py:66`) verifies this by walking chunks, locating each in `full_text` (a backward `rfind` near the expected position, falling back to a forward `find`), checking no character was skipped, and confirming the last chunk reaches the end of the text. `repair_gaps_between_chunks` fixes any gap by prepending the missing text to the next chunk.

This invariant is checked with `assert ... == True` after **every** transformation in the pipeline — raw splitting, oversized-splitting, tiny-merging, async splitting (`split_documents.py`, `postprocessing.py`). And `pipeline.chunk_files` escalates a failure to a loud `RuntimeError("…This is a bug — please report it.")`. The payoff is large:

- Metrics like BI, ICC, DCC, RC all rely on `find_chunks_start_and_end` to map chunks back to character offsets. If a splitter ever lost or duplicated text, those offsets would be wrong and the scores meaningless. The invariant guarantees they aren't.
- It catches splitter bugs at chunk time, not three pipeline stages later when a metric silently produces garbage.

The two normalization passes (`replicate.py:272`):
1. **Split oversized** — anything over 1100 tokens is re-split with the recursive splitter. Applied to the structurally-driven methods (`page`, `sentence`, `semantic`, `llm_regex`) that can emit huge chunks.
2. **Merge tiny** — chunks under 100 tokens are merged into a neighbour (`merge_to="next"`, max 1150 tokens). Applied to all methods.

Importantly, **Table 3 deliberately mixes post-processing levels** (documented as CRITICAL in `LLM.md`): the proposed methods (`*`) are scored *after* post-processing; several baselines (`†`) are scored *raw*, to show them as they work out-of-the-box. The repo computes both (`metrics` → `results/`, `raw_metrics` → `results_raw/`) and `table3` prints them side-by-side with a delta against published values — an unusually honest reproducibility design.

---

## 10. Document Parsing (`parsing.py`) & Coreference (`metrics.py`)

**Parsing** is a clean `BaseParser` ABC with four backends behind the `[parsing]` extra:
- `DoclingParser` (default, open-source), `PyMuPDFParser` (lightweight), `AzureDIParser` (cloud Document Intelligence), `ExcelParser`.
- Each must implement `parse_docs_in_dir` and `convert_raw_results_to_markdown`, and all converge on the JSON contract from §4. The Azure parser is the most elaborate (~600 LoC): it walks the section tree depth-first, converts tables to size-bounded markdown via pandas→HTML→markdownify, and tracks global document order — exactly the structure-extraction quality that BI then rewards.

**Coreference** (the `CoreferenceSolver`, behind `[coref]`) is the most infrastructure-heavy metric input:
- Uses `maverick-coref` (`sapienzanlp/maverick-mes-ontonotes`) to find mention clusters, in **overlapping context windows** (it can't feed a whole document to the model at once).
- Token offsets are mapped back to character offsets; clusters sharing a mention are merged (`_merge_mention_clusters`); numeric-only and all-identical clusters are filtered out.
- The window-grouping code carries an explicit **infinite-loop fix** (`metrics.py:807`) forcing forward progress when overlap math would stall — a battle-scar comment that signals this was hardened against real failures.
- Because this needs a GPU and is slow, the repo **ships pre-computed mentions** in `data/clair/mentions/`, and the metrics step auto-discovers them (`_resolve_mentions_dir`). This single decision is what lets a CPU-only user reproduce the RC-dependent results.

---

## 11. The Reproduction Pipeline (`paper/replicate.py`)

One CLI threads everything together via 7 independently-runnable, file-coupled steps (see `diagrams/adaptive-chunking/replication-pipeline.mmd`):

```bash
python -m adaptive_chunking.paper.replicate \
    --data-dir data/clair/ --output-dir results/ --device cuda:0 \
    --steps chunking metrics raw_metrics analysis table3
```

| Step | Produces | Cost / notes |
|---|---|---|
| `chunking` | `chunks/{raw,no_oversizing,small_merged}` | GPU for semantic; OpenAI for llm_regex (both skippable) |
| `mentions` | `mentions/*.parquet` | GPU (maverick) — **pre-shipped, normally skipped** |
| `metrics` | `results/chunking_metrics.parquet` | **~9 h local / ~30 min with `JINA_API_KEY`** |
| `raw_metrics` | `results_raw/` | same cost; needed for the `†` Table 3 rows |
| `analysis` | Tables 1–2, Figure 1 (correlations) | cheap |
| `table3` | local-vs-published comparison + Δ | cheap |
| `rag` | Tables 4–5 | expensive: hundreds of OpenAI calls + GPU |

**Resumability is first-class.** `compute_metrics_per_origin` records already-computed `doc_name`s and skips them, and saves the Parquet incrementally **after each document** (`compute_metrics.py:69`, `:224`). A 9-hour run that dies at hour 7 resumes from document 26, not from zero. The chunking and post-processing stages similarly support `replace_all_results=False` to recompute only selected methods and merge with prior results.

**Embedder flexibility:** `_make_embedder` returns a Jina REST client if `JINA_API_KEY` is set, else loads `jinaai/jina-embeddings-v3` locally — the single switch behind the 9h→30min speedup. The `JinaEmbedder` wrapper mimics `SentenceTransformer.encode()` with concurrency capping (`max_concurrent=3`), retry jitter, and 20k-char truncation.

---

## 12. RAG Evaluation (`paper/rag_eval.py`, `rag_utils.py`) — the extrinsic proof

The intrinsic metrics are the *selector*; the RAG eval is the *validation that the selector helps a real pipeline* (see `diagrams/adaptive-chunking/rag-eval.mmd`). It compares three chunk sets — `best` (adaptive), `langch_recurs_default`, and `page` — through an identical retrieval+generation stack:

1. **QA generation** — GPT-4.1 generates 3 QA pairs per document → 99 queries.
2. **Indexing + hybrid retrieval (Haystack)** — dense (`Qwen/Qwen3-Embedding-4B`) **+** BM25, joined, then **reranked** with `Snowflake/snowflake-arctic-embed-l-v2.0` (top-k 10).
3. **Answer generation** — answer *only* from retrieved context, or explicitly say "I don't know."
4. **LLM-judge evaluation** — the custom **`RetrievalCompletenessMetric`** prompts an LLM fact-checker to rate, on a 0/1/2 scale (mapped to 0/0.5/1.0), how completely the retrieved context supports the reference answer — plus a standard Answer Correctness metric (DeepEval). "I don't know" answers are excluded from correctness (that's the "answered queries" count).

The retrieval-completeness judge is the conceptual bridge: it measures *whether the chunks even contained the answer*, which is precisely what better chunking should improve — and indeed it's where Adaptive wins most (67.7 vs ~58–59) with statistical significance.

---

## 13. Reliability & Engineering Quality

This is a research repo that is engineered better than most production code:

- **Coverage where it matters.** `tests/` exercises the splitter, metrics, parsing, and post-processing — the load-bearing core, not the paper glue.
- **The gap invariant** (§9) is asserted after every transformation, turning "the splitter silently ate a paragraph" from a debugging nightmare into an immediate, localized failure.
- **Resumability + incremental persistence** make multi-hour runs robust to interruption.
- **Lazy imports** keep the importable surface light and the dependency graph honest about what each feature costs.
- **Defensive LLM/regex handling** — pattern validation and self-repair in `extract_llm_regex`, graceful "return whole text" fallbacks.
- **Reproducibility realism** — `table3` prints *your* numbers next to the *published* numbers with a delta, instead of asking you to trust that they match. `LLM.md` pins exact model versions and warns that changing them changes results.
- **Honest baseline treatment** — the `*`/`†` post-processing split prevents the proposed method from looking better simply because baselines were normalized into uniformity.

Caveats / friction:
- **Heavy, version-pinned dependency stack** for full reproduction (torch 2.6.0, flash-attention-2 for the semantic chunker, stanza, maverick, haystack, deepeval). The core library avoids this; the paper extra does not.
- **Non-permissive optional licenses.** `[coref]` (maverick-coref, CC BY-NC-SA 4.0 — non-commercial) and `[parsing]` (pymupdf4llm, AGPL-3.0/Artifex) are copyleft. The README states these are being actively replaced so all metrics work under permissive licensing; today, fully-permissive use means losing the RC metric and the PyMuPDF backend.
- **Scale.** 33 documents and 99 queries is a real but small benchmark; the Wilcoxon tests are appropriate for that size, but the absolute query counts are modest.
- **Cost.** Embedding-based metrics are expensive without the Jina API; the RAG step is hundreds of paid LLM calls.

---

## 14. How Impactful Is It?

**Conceptually:** chunking is the most under-instrumented stage of RAG — teams tune retrievers and prompts obsessively while leaving chunking at "recursive, 512 tokens, 50 overlap" forever. This work reframes chunking as a *selectable, measurable* decision and supplies the missing measurement. The fact that selection needs **no ground truth** is the practically important bit: you can run it on a fresh corpus and let it choose, which a labeled-eval-dependent method could never do.

**Empirically:** the per-document argmax delivers a meaningful extrinsic gain (+9.6 pts retrieval completeness, +33% answered queries vs. the industry-default LangChain recursive) with statistical significance — on a multi-domain corpus, which is exactly the setting where one-size-fits-all chunking is weakest.

**As software:** the modular two-contract design (`str→list[str]` methods, `list[str]→float` metrics) means the *framework* outlives the specific paper. Practitioners can drop in their own splitter and their own metric and get per-document selection for free. The shipped pre-parsed corpus + pre-computed coreference mentions make the headline tables reproducible on a laptop — a low bar to clear that most papers don't.

**Where it lands:** peer-reviewed (LREC 2026), from an applied-AI consultancy (Ekimetrics) rather than a frontier lab, which shows in the bias toward reproducibility and deployability over novelty. The five intrinsic metrics — especially DCC's overlap-aware windowing and the coreference-based RC — are the most reusable ideas; they're a general-purpose, label-free toolkit for *grading any chunking*, independent of the selection wrapper.

**What's worth stealing:**
1. **Ground-truth-free chunking quality metrics** — usable as a standalone CI check ("did this pipeline change make chunking worse?").
2. **The gap invariant + character-space chunk localization** — a cheap, powerful safety net for any text-splitting system.
3. **Per-document method selection with externalized weights** — trivially portable to any setting with ≥2 candidate strategies.
4. **The `*`/`†` honest-baseline reproduction pattern and the local-vs-published delta table** — a reproducibility template more papers should copy.

---

## 15. TL;DR

Adaptive Chunking turns "which chunker?" from a fixed global guess into a per-document decision driven by five label-free quality metrics, and proves (with significance) that doing so improves downstream RAG retrieval and answer rates on a multi-domain corpus. The codebase is a clean split between a small, embeddable core (`RecursiveSplitter` + metrics) and a heavier, fully-reproducible research harness — held together by a strict "chunks cover all text, no gaps" invariant and resumable, file-coupled pipeline stages. The most durable contributions are the intrinsic metrics and the modular selection framework, both of which outlive the specific experiment.

*Diagrams accompanying this analysis: `diagrams/adaptive-chunking/{architecture, recursive-splitter, replication-pipeline, adaptive-selection, rag-eval}.mmd`.*
