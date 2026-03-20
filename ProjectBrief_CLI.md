# Literature CLI — Project Brief

## What This Is

A macOS command-line tool (and/or small Xcode app target) that uses the `Linguistics` Swift package to build a personal research-paper corpus, embed it with GPU transformer models, persist it to SQLite, and expose semantic search and analysis over it.

The immediate corpus is a collection of population genetics / molecular ecology papers (Dyer, Verrelli, Miles, Smouse, et al., 2001–2025).

---

## Dependency

```swift
.package(url: "https://github.com/dyerlab/Linguistics", from: "1.0.0")
```

The `Linguistics` package provides all NLP primitives — do not re-implement anything it already exposes:

- `ManuscriptLoader` — PDF-converted Markdown → `Corpus`
- `AcademicProgramLoader` — CSV course catalogs → `[Corpus]`
- `MLXEmbeddingService` / `NLEmbeddingService` / `FDLEmbeddingService` — embedding backends
- `MLXCrossEncoderReranker` / `EmbeddingReranker` — reranking
- `CorpusStore` — SQLite persistence (read/write `[Corpus]`)
- `MultiProviderEmbedder` — run multiple providers in one pass
- `EmbeddingBenchmark` / `ThresholdCalibrator` — evaluation utilities
- `String` extensions — sentiment, ARI, tokenization, lemmatization

---

## PDF Pipeline

PDFs are **not** embedded in this project's bundle. The workflow is:

1. **Convert** PDFs to Markdown using `convert_pdfs.py` (in the `Linguistics` repo root):
   ```bash
   pip install marker-pdf
   python convert_pdfs.py <pdf_dir> <markdown_output_dir> [--workers N]
   ```
2. **Load & embed** the resulting `.md` files via `ManuscriptLoader.loadAll(...)` using whichever `EmbeddingProviderOption` is selected.
3. **Persist** the resulting `[Corpus]` to SQLite via `CorpusStore`.

The `Linguistics` package keeps 2–3 sample PDFs (converted to Markdown) in `Tests/` for `ManuscriptLoader` unit tests. All other PDFs live here.

---

## Core Goals

### 1. Corpus Ingestion
- Accept a directory of Markdown files (pre-converted from PDF) and a provider option as arguments
- Embed at section or paragraph granularity (configurable)
- Write output to a SQLite database at a user-specified path
- Support incremental updates (skip already-embedded documents by DOI or filename)

### 2. Semantic Search
- Given a free-text query, retrieve the top-K most relevant passages across all papers
- Two-stage pipeline: fast NLEmbedding or MiniLM retrieval → cross-encoder reranker
- Output: ranked list with paper title, section, score, and source text snippet

### 3. Paper-to-Paper Similarity
- Given a paper (by filename or DOI), find the most similar papers in the corpus
- Compare at section level (e.g., Methods-to-Methods, Abstract-to-Abstract) or whole-document

### 4. Corpus Analysis
- Summarize the corpus: paper count, section distribution, embedding dimensions stored
- Optionally run `EmbeddingBenchmark` against a provider to validate quality on this domain

---

## Architecture Decisions (Already Made)

| Decision | Choice |
|----------|--------|
| Library | `Linguistics` SPM package (not bundled here) |
| Embedding storage | SQLite via `CorpusStore` |
| Default embedding model | `MLXEmbeddingService(.bgeBase)` — 768d, good quality/speed balance |
| Reranker | `MLXCrossEncoderReranker(.bgeRerankerBase)` for search result refinement |
| Granularity | `.paragraph` for search; `.section` for paper-level similarity |
| PDF conversion | External Python script (`marker-pdf`) — not part of this binary |
| Platform | macOS 14+, Apple Silicon (Metal required for MLX) |

---

## What to Build First

1. **`ingest` command** — takes `--input <markdown-dir>` `--db <sqlite-path>` `--provider <nl|miniLM|bgeBase|...>` `--granularity <section|paragraph>`
2. **`search` command** — takes `--db <sqlite-path>` `--query "..."` `--top-k 10`
3. **`similar` command** — takes `--db <sqlite-path>` `--paper <filename-or-doi>` `--top-k 5`

Use `ArgumentParser` (Swift standard for CLI argument parsing).

---

## Notes for New Session

- Run Xcode (not `swift test`) for any MLX work — Metal shader compilation requires it
- `FDLEmbeddingService` vectors are **not** L2-normalized — call `.normal` before cosine comparisons
- `NLEmbedding` returns ~300 dimensions on macOS 26 (not 512 as documented for earlier OS versions)
- Model weights download to `~/.cache/huggingface/hub/` on first use — not bundled
- All `Linguistics` public types are `Sendable`; `MLXEmbeddingService` and `MLXCrossEncoderReranker` are `actor`s
