# ReviewerNumberTwo

A macOS command-line tool for building a semantic research-paper corpus. Converts Markdown manuscripts into multi-provider embeddings, persists them to SQLite, and exposes semantic search, paper similarity, and embedding benchmarking.

Built on the [`Linguistics`](https://github.com/dyerlab/Linguistics) Swift package with GPU-accelerated transformer embeddings via MLX.

**Platform:** macOS 14.6+ · Apple Silicon (Metal required for MLX models)

---

## Overview

`ReviewerNumberTwo` takes a folder of Markdown files (converted from PDFs), embeds each section or paragraph using one or more embedding backends, and persists everything to a local SQLite database. The database is designed for direct consumption in R via `RSQLite`.

Once ingested, you can:

- **Search** the corpus with a free-text query using two-stage retrieval (embedding + cross-encoder reranking)
- **Find similar papers** to a given paper using section-level cosine similarity
- **Benchmark** embedding quality on scientific text and inspect corpus statistics

---

## Installation

**Requirements:** macOS 14.6+, Apple Silicon, Xcode 16+ (`swift build` cannot compile MLX Metal shaders)

```bash
# Clone and build
git clone <this-repo>
cd ReviewerNumberTwo
make install        # builds Release, installs to /usr/local/bin/reviewer

make uninstall      # removes the installed binary
```

---

## Workflow

### Step 1 — Convert PDFs to Markdown

PDFs are not processed by this tool. Use [`marker-pdf`](https://github.com/VikParuchuri/marker) via the `convert_pdfs.py` helper in the [`Linguistics`](https://github.com/dyerlab/Linguistics) repo:

```bash
pip install marker-pdf
python convert_pdfs.py /path/to/pdfs/ /path/to/markdown/ --workers 4
```

### Step 2 — Ingest

Embed the Markdown files and write them to a SQLite database:

```bash
# Embed all sections, default provider (BGE-Base)
reviewer ingest --input /path/to/markdown/ --db corpus.sqlite

# Embed only Introductions with three providers simultaneously
reviewer ingest --input /path/to/markdown/ --db intro.sqlite \
    --section Introduction \
    --providers fdl,nl,bgeBase

# Re-run safely — already-ingested documents are skipped automatically
reviewer ingest --input /path/to/markdown/ --db corpus.sqlite
```

### Step 3 — Analyse in R

Query the SQLite database directly. See [SQLite Schema](#sqlite-schema) below.

---

## Commands

### `ingest` — Embed and persist

```
reviewer ingest --input <dir> --db <path> [options]
```

| Option | Default | Description |
|---|---|---|
| `--input` | *(required)* | Directory of `.md` files |
| `--db` | *(required)* | SQLite database path (created if absent) |
| `--section` | *(all)* | Embed one section only: `Title` `Abstract` `Introduction` `Methods` `Results` `Discussion` `Other` |
| `--providers` | `bgeBase` | Comma-separated list of providers (see [Embedding Providers](#embedding-providers)) |
| `--granularity` | `sectionAndParagraphs` | `section` · `paragraph` · `sectionAndParagraphs` |

`--granularity sectionAndParagraphs` stores a full-section embedding at `sequence_index = 0` and individual paragraph embeddings at `sequence_index = 1…N`. This enables both document-level and passage-level analysis from a single ingest run.

---

### `search` — Semantic search

```
reviewer search --db <path> --query "<text>" [options]
```

| Option | Default | Description |
|---|---|---|
| `--db` | *(required)* | SQLite database |
| `--query` | *(required)* | Free-text query |
| `--top-k` | `10` | Results to return |
| `--provider` | `bgeBase` | Must match the provider used during ingest |

Two-stage pipeline: embedding retrieval over the top-50 candidates, then cross-encoder reranking (`BGE-Reranker-Base`) for precision.

```bash
reviewer search --db corpus.sqlite --query "gene flow in fragmented landscapes"
```

---

### `similar` — Paper-to-paper similarity

```
reviewer similar --db <path> --paper <id> [options]
```

| Option | Default | Description |
|---|---|---|
| `--db` | *(required)* | SQLite database |
| `--paper` | *(required)* | Filename (e.g. `Smith2001_ME.md`), filename prefix, or DOI |
| `--top-k` | `5` | Similar papers to return |
| `--provider` | `bgeBase` | Must match the provider used during ingest |

Scores each paper by the mean of the top-3 pairwise cosine similarities across all section-embedding pairs.

```bash
reviewer similar --db corpus.sqlite --paper Smith2001_ME.md
reviewer similar --db corpus.sqlite --paper 10.1111/j.1365-294X.2001.01215.x
```

---

### `benchmark` — Embedding quality + corpus statistics

```
reviewer benchmark --provider <name> [--db <path>]
```

Runs `EmbeddingBenchmark` from `Linguistics` on four test sets (Scientific, Retrieval, General, Paraphrase) reporting discrimination gap, accuracy, and threshold per set. When `--db` is provided, also prints document count, section distribution, and embedding dimensions for the corpus.

```bash
reviewer benchmark --provider bgeBase
reviewer benchmark --provider bgeBase --db corpus.sqlite
```

---

## Embedding Providers

| `--providers` token | Model | Dimensions | Download |
|---|---|---|---|
| `nl` | Apple NLEmbedding | ~300 | None — offline, CPU |
| `fdl` | Frequency-Dependent Linguistic | vocab-size | None — bag-of-words |
| `miniLM` | MiniLM-L6-v2 | 384 | ~90 MB |
| `bgeBase` | BGE-Base-en-v1.5 | 768 | ~400 MB · **default** |
| `bgeLarge` | BGE-Large-en-v1.5 | 1024 | ~1.2 GB |
| `mxbaiEmbedLarge` | mxbai-embed-large | 1024 | ~1.2 GB |
| `qwen3` | Qwen3-Embedding (4-bit) | 2048 | ~1 GB |
| `nomic` | Nomic-Embed-Text-v1.5 | 768 | ~300 MB |

MLX models download to `~/.cache/huggingface/hub/` on first use. All MLX models require Apple Silicon (Metal).

---

## SQLite Schema

The database is the primary output of this tool and is the interface consumed by downstream analysis (R, Python, etc.).

```sql
CREATE TABLE documents (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    corpus_uuid  TEXT NOT NULL,   -- stable UUID per manuscript
    title        TEXT,            -- paper title (first # heading)
    filename     TEXT,            -- source .md filename
    doi          TEXT,            -- DOI extracted from manuscript header
    created_at   TEXT             -- ISO-8601 ingest timestamp
);

CREATE TABLE embeddings (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    document_id    INTEGER REFERENCES documents(id),
    part           TEXT,          -- section: Introduction | Methods | Results | …
    granularity    TEXT,          -- section | paragraph | sectionAndParagraphs
    provider       TEXT,          -- see provider keys below
    dimensions     INTEGER,       -- vector length
    vector         BLOB,          -- little-endian Float32, length = dimensions × 4 bytes
    scaling        REAL,          -- provider scaling factor (usually 1.0)
    source_text    TEXT,          -- the text that was embedded
    sequence_index INTEGER,       -- see note below
    scheme         TEXT           -- optional analysis label
);
```

**`sequence_index` values:**

| Value | Meaning |
|---|---|
| `NULL` | Plain `section` or `paragraph` granularity |
| `0` | Full section text (`sectionAndParagraphs` only) |
| `1…N` | Ordered paragraphs within that section |

**Provider keys** stored in `embeddings.provider`:

`nl` · `fdl` · `miniLM` · `bgeBase` · `bgeLarge` · `mxbaiEmbedLarge` · `qwen3Embedding` · `nomicTextV1_5`

### Reading in R

```r
library(RSQLite)
library(dplyr)

con <- dbConnect(SQLite(), "corpus.sqlite")

# Join documents and embeddings
docs <- dbReadTable(con, "documents")
emb  <- dbReadTable(con, "embeddings")
df   <- left_join(emb, docs, by = c("document_id" = "id"))

# Deserialize a vector
dims <- df$dimensions[1]
vec  <- readBin(df$vector[[1]], what = "numeric", n = dims, size = 4, endian = "little")

# Filter to Introduction section, bgeBase provider, section-level rows only
intro <- df |>
  filter(part == "Introduction", provider == "bgeBase", sequence_index == 0)
```

### Typical ingest counts

For a 5-paragraph Introduction embedded with 3 providers (`fdl`, `nl`, `bgeBase`):

- 1 `documents` row per manuscript
- 18 `embeddings` rows: (1 section + 5 paragraphs) × 3 providers
  - `sequence_index` 0 = full Introduction, 1–5 = paragraphs

---

## Dependencies

| Package | Role |
|---|---|
| [`Linguistics`](https://github.com/dyerlab/Linguistics) | NLP primitives — loaders, embeddings, search, benchmarking |
| [`MatrixStuff`](../../Packages/MatrixStuff) | `Vector = [Double]`, `.normal` (L2), `.*` dot product |
| [`swift-argument-parser`](https://github.com/apple/swift-argument-parser) | CLI subcommand parsing |
