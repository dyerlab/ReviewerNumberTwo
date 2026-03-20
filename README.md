# ReviewerNumberTwo

> A command-line tool to parse the linguistic structure of Markdown (or PDF-converted-to-Markdown) research papers into a SQLite corpus for semantic search, paper similarity analysis, and downstream analysis in R.

Built on the [`Linguistics`](https://github.com/dyerlab/Linguistics) Swift package with GPU-accelerated transformer embeddings via MLX.

**Platform:** macOS 14.6+ · Apple Silicon (Metal required for MLX models)

---

## Overview

`ReviewerNumberTwo` takes a folder of PDFs (pre-converted to Markdown), embeds each section or paragraph using one of several embedding backends, and persists everything to a local SQLite database. Once ingested, you can:

- **Search** the corpus with a free-text query using two-stage retrieval (embedding + cross-encoder reranking)
- **Find similar papers** to a given paper using section-level cosine similarity
- **Benchmark** embedding quality on scientific text and inspect corpus statistics

The default corpus is a collection of population genetics / molecular ecology papers (Dyer, Verrelli, Miles, Smouse, et al., 2001–2025), but the tool works for any domain with Markdown source files.

---

## Installation

### Requirements

- macOS 14.6+, Apple Silicon (Metal required for MLX models)
- Xcode 16+ — required for building; `swift build` cannot compile MLX Metal shaders
- Python + `marker-pdf` for the initial PDF → Markdown conversion step

### Build & Install

1. Open `ReviewerNumberTwo.xcodeproj` in Xcode.
2. Add the following Swift Package dependencies via **File › Add Package Dependencies…**:
   - `https://github.com/apple/swift-argument-parser` (≥ 1.3.0)
   - Local package: `../../Packages/MatrixStuff`
3. Add all source files under `Commands/` and `Support/` to the **ReviewerNumberTwo** target if Xcode did not pick them up automatically.
4. Build a Release binary and install it to `/usr/local/bin/reviewer`:

```bash
make install
```

To remove it later:

```bash
make uninstall
```

---

## PDF Pipeline

PDFs are not processed by this binary. Convert them first using [`convert_pdfs.py`](https://github.com/dyerlab/Linguistics) from the Linguistics repo:

```bash
pip install marker-pdf
python convert_pdfs.py ReviewerNumberTwo/Data/PDFs/ /path/to/markdown/ --workers 4
```

Then pass the output directory to `ingest`. Sample PDFs are in `ReviewerNumberTwo/Data/PDFs/` (23 papers, not yet converted).

---

## Commands

### `ingest` — Embed and persist a Markdown directory

```bash
reviewer ingest --input <markdown-dir> --db <sqlite-path> [--provider bgeBase] [--granularity paragraph]
```

| Option | Default | Description |
|---|---|---|
| `--input` | *(required)* | Directory of `.md` files to embed |
| `--db` | *(required)* | Path to SQLite database (created if absent) |
| `--provider` | `bgeBase` | Embedding backend — see [Embedding Providers](#embedding-providers) |
| `--granularity` | `paragraph` | `paragraph` (best for search) or `section` (best for similarity) |

Supports **incremental updates** — documents already in the database (matched by DOI or filename) are skipped automatically.

```bash
# Embed all papers at paragraph granularity
reviewer ingest --input /path/to/markdown/ --db corpus.db

# Add new papers later — existing ones are skipped
reviewer ingest --input /path/to/new_papers/ --db corpus.db
```

---

### `search` — Semantic search with cross-encoder reranking

```bash
reviewer search --db <sqlite-path> --query "<text>" [--top-k 10] [--provider bgeBase]
```

| Option | Default | Description |
|---|---|---|
| `--db` | *(required)* | Path to SQLite database |
| `--query` | *(required)* | Free-text search query |
| `--top-k` | `10` | Number of results to return |
| `--provider` | `bgeBase` | Must match the provider used during `ingest` |

Uses a two-stage pipeline: embedding retrieval over the top-50 candidates, followed by cross-encoder reranking (`BGE-Reranker-Base`) for precision. Output includes paper title, section, reranker score, and a text snippet.

```bash
reviewer search --db corpus.db --query "gene flow in fragmented landscapes" --top-k 10
```

---

### `similar` — Paper-to-paper similarity

```bash
reviewer similar --db <sqlite-path> --paper <filename-or-doi> [--top-k 5] [--provider bgeBase]
```

| Option | Default | Description |
|---|---|---|
| `--db` | *(required)* | Path to SQLite database |
| `--paper` | *(required)* | Target paper by filename (e.g. `2001_Dyer_Sork_ME.md`) or DOI |
| `--top-k` | `5` | Number of similar papers to return |
| `--provider` | `bgeBase` | Must match the provider used during `ingest` |

Scores each paper by the mean of the top-3 pairwise cosine similarities across all section-embedding pairs, capturing topical overlap without requiring identical section structures across papers.

```bash
reviewer similar --db corpus.db --paper 2001_Dyer_Sork_ME.md --top-k 5
```

---

### `benchmark` — Evaluate embedding quality + corpus statistics

```bash
reviewer benchmark [--provider bgeBase] [--db <sqlite-path>]
```

| Option | Default | Description |
|---|---|---|
| `--provider` | `bgeBase` | Embedding backend to evaluate |
| `--db` | *(optional)* | When provided, prints corpus statistics before the benchmark |

Runs `EmbeddingBenchmark` from `Linguistics` on four test sets — Scientific, Retrieval, General, and Paraphrase — reporting discrimination gap, accuracy, and threshold for each. When `--db` is provided, also prints document count, section distribution, embedding dimensions, and a per-provider embedding breakdown.

```bash
# Quality benchmark only
reviewer benchmark --provider bgeBase

# Benchmark + corpus statistics
reviewer benchmark --provider bgeBase --db corpus.db
```

---

## Embedding Providers

| Flag | Model | Dimensions | Download | Notes |
|---|---|---|---|---|
| `nl` | Apple NLEmbedding | ~300 (macOS 26) | None | Instant, offline, CPU only |
| `fdl` | Frequency-Dependent Linguistic | Vocab size | None | Bag-of-words; not pre-normalized |
| `miniLM` | MiniLM-L6 | 384 | ~90 MB | Fast, lightweight |
| `bgeBase` | BGE-Base-en-v1.5 | 768 | ~400 MB | **Default** — good quality/speed balance |
| `bgeLarge` | BGE-Large-en-v1.5 | 1024 | ~1.2 GB | Higher accuracy |
| `mxbaiEmbedLarge` | mxbai-embed-large | 1024 | ~1.2 GB | Retrieval-optimized |
| `qwen3` | Qwen3-Embedding | 2048 | ~1 GB | 4-bit quantized |
| `nomic` | Nomic-Embed-Text-v1.5 | 768 | ~300 MB | Matryoshka embeddings |

MLX models download to `~/.cache/huggingface/hub/` on first use. GPU (Metal / Apple Silicon) is required for all MLX models.

> **FDL note:** FDL vectors are raw frequency counts and are not L2-normalized. The tool normalizes them automatically before cosine comparisons using `vector.normal` from `MatrixStuff`.

> **NLEmbedding note:** Returns ~300 dimensions on macOS 26, not 512 as documented for earlier OS versions.

---

## Architecture

`ReviewerNumberTwo` is a thin CLI wrapper around the [`Linguistics`](https://github.com/dyerlab/Linguistics) Swift package. All NLP primitives come from `Linguistics`; this tool adds only the command-line interface.

```
PDF files
    │
    ▼  (external: convert_pdfs.py / marker-pdf)
Markdown files
    │
    ▼  ManuscriptLoader.loadAll(from:granularity:using:as:)
[Corpus]  ──────────────────────────────────►  CorpusStore (SQLite)
                                                     │
                                        ┌────────────┼────────────┐
                                        ▼            ▼            ▼
                                     search       similar     benchmark
                                  (embed +      (cosine,    (EmbeddingBenchmark
                                  rerank)       top-3 pool)  + corpus stats)
```

The SQLite schema stores vector BLOBs as little-endian `Float32` arrays, making the database directly readable in R:

```r
readBin(blob_col[[1]], "numeric", n = dims, size = 4, endian = "little")
```

**Key types from `Linguistics`:**

| Type | Role |
|---|---|
| `ManuscriptLoader` | Markdown → `Corpus` (extracts title, DOI, sections, embeddings) |
| `CorpusStore` | SQLite read/write for `[Corpus]` |
| `MLXEmbeddingService` | GPU transformer embeddings (Swift actor) |
| `NLEmbeddingService` | Apple on-device word-vector embeddings |
| `FDLEmbeddingService` | Corpus frequency-count vectors |
| `MLXCrossEncoderReranker` | Cross-encoder reranking (Swift actor) |
| `EmbeddingBenchmark` | Quality evaluation with 10 built-in test sets |

---

## Dependencies

| Package | Role |
|---|---|
| [`Linguistics`](https://github.com/dyerlab/Linguistics) | NLP primitives — embeddings, loaders, search, benchmarking |
| [`MatrixStuff`](../../Packages/MatrixStuff) | `Vector = [Double]`, `.normal` normalization, `.*` dot product |
| [`swift-argument-parser`](https://github.com/apple/swift-argument-parser) | CLI subcommand parsing |
