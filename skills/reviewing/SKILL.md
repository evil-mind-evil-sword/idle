---
name: reviewing
description: Get second opinions from external models (Codex, Gemini) for adversarial review, tie-breaking, and multi-model consensus. Use when validating critical decisions or when stuck.
---

# Reviewing Skill

Multi-model second opinions via OpenAI Codex CLI and Google Gemini CLI.

## When to Use

- Validating critical findings (security, correctness, soundness)
- Breaking ties when uncertain
- Cross-checking complex reasoning
- Architecture decisions with high stakes

**Don't use for**: Simple questions. Just think harder.

## Priority Order

| Priority | Tool | When |
|----------|------|------|
| **1st** | Codex | Primary second opinion (different architecture from Claude) |
| **2nd** | Gemini | Tie-breaker, or when Codex unavailable |
| **3rd** | `claude -p` | Fallback (fresh context, same architecture) |

## Codex (OpenAI)

OpenAI's CLI for code and reasoning tasks.

### Invocation

```bash
codex exec -s read-only -m gpt-5.2 -c reasoning=xhigh "<prompt>"
```

| Flag | Purpose |
|------|---------|
| `-s read-only` | **Required** - sandbox mode, no modifications |
| `-m gpt-5.2` | Best model for thorough review |
| `-c reasoning=xhigh` | Maximum reasoning effort |

### Models

| Model | Use Case |
|-------|----------|
| `gpt-5.2` | **Default** - thorough review, high-stakes |
| `o3` | Complex multi-step reasoning |
| `o4-mini` | Quick opinions, low-stakes |

### Reasoning Levels

```bash
-c reasoning=xhigh   # Critical: security, correctness proofs
-c reasoning=high    # Standard: code review, design tradeoffs
# (omit)             # Quick opinions
```

## Gemini (Google)

Google's CLI for research and long-context analysis.

### Invocation

```bash
gemini -s -m gemini-2.5-pro "<prompt>"
```

| Flag | Purpose |
|------|---------|
| `-s` | **Required** - sandbox mode |
| `-m gemini-2.5-pro` | Best model for research/long-context |

### Models

| Model | Use Case |
|-------|----------|
| `gemini-2.5-pro` | **Default** - research, long context (>100k tokens) |
| `gemini-3-pro` | Latest capabilities (when available) |

### Strengths

- Long context windows (large codebase analysis)
- Research and fact-checking
- Tie-breaking between Claude and Codex

## Prompt Pattern

Always request a `---SUMMARY---` marker for reliable extraction:

```bash
codex exec -s read-only -m gpt-5.2 -c reasoning=xhigh "
<context and question>

End with:
---SUMMARY---
AGREE/DISAGREE with <topic>
Confidence: HIGH/MEDIUM/LOW
Key insight: <one sentence>
"
```

### Output Extraction

```bash
# Run and capture
codex exec -s read-only -m gpt-5.2 -c reasoning=xhigh "..." > /tmp/opinion.log 2>&1

# Extract summary
sed -n '/---SUMMARY---/,$ p' /tmp/opinion.log
```

## Common Patterns

### Second Opinion

```bash
codex exec -s read-only -m gpt-5.2 -c reasoning=xhigh "
Problem: <describe>
Current hypothesis: <what you think>

Do you agree? What would you change?

---SUMMARY---
AGREE/DISAGREE
Confidence: HIGH/MEDIUM/LOW
Key insight: <summary>
"
```

### Tie-Breaker (Gemini)

```bash
gemini -s -m gemini-2.5-pro "
Analysis A (Claude): <view>
Analysis B (Codex): <view>

They disagree on: <the issue>

Which is correct?

---SUMMARY---
FAVOR: A/B/NEITHER
Reasoning: <why>
"
```

### Multi-Model Consensus

For high-stakes decisions, query both:

```bash
# Get Codex opinion
codex exec -s read-only -m gpt-5.2 -c reasoning=xhigh "..." > /tmp/codex.log 2>&1

# Get Gemini opinion
gemini -s -m gemini-2.5-pro "..." > /tmp/gemini.log 2>&1

# Compare summaries
sed -n '/---SUMMARY---/,$ p' /tmp/codex.log
sed -n '/---SUMMARY---/,$ p' /tmp/gemini.log
```

## Recording Findings

Post to jwz for discovery:

```bash
# Single model
jwz post "issue:<id>" --role alice \
  -m "[alice] SECOND_OPINION: codex on <topic>
Model: gpt-5.2 (reasoning=xhigh)
Agreement: AGREE|DISAGREE|PARTIAL
Key insight: <summary>"

# Multi-model consensus
jwz post "issue:<id>" --role alice \
  -m "[alice] CONSENSUS: <topic>
Models: codex, gemini
Agreement: FULL|PARTIAL|SPLIT
Synthesis: <reconciled view>"
```

## Timeouts

```bash
# Codex with xhigh reasoning can take time
timeout 180 codex exec -s read-only -m gpt-5.2 -c reasoning=xhigh "..."

# Gemini
timeout 120 gemini -s -m gemini-2.5-pro "..."
```

## Fallback Chain

```bash
if command -v codex >/dev/null 2>&1; then
    codex exec -s read-only -m gpt-5.2 -c reasoning=xhigh "..."
elif command -v gemini >/dev/null 2>&1; then
    gemini -s -m gemini-2.5-pro "..."
else
    claude -p "..."
fi
```
