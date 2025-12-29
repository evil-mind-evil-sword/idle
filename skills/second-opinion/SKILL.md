---
name: second-opinion
description: Get a formal multi-model analysis on architecture, tricky bugs, or design decisions using the oracle agent
---

# Second Opinion Skill

Get a formal, documented second opinion on hard problems.

## When to Use

Use this skill when:
- Stuck on a tricky bug that resists simple fixes
- Facing architectural decisions with non-obvious tradeoffs
- Need documented reasoning that other agents can reference
- Want multi-model consensus (oracle consults Codex/Claude)

**Don't use for**: Quick questions where you don't need formal analysis. Just describe your problem naturally and the oracle agent will be auto-discovered.

## Workflow

Invoke the oracle agent:

```
Task(subagent_type="idle:oracle", prompt="Second opinion needed: <problem description>")
```

The oracle agent will:
1. Generate ranked hypotheses (3-5 possibilities)
2. Document assumptions and checks performed
3. Consult a second model (Codex or Claude) for diverse perspective
4. Iterate until convergence or clear disagreement
5. Post analysis summary to jwz

## Multi-Model Consensus

The oracle uses a different model architecture to break self-bias:

1. **Codex** (preferred) - OpenAI model, maximum architectural diversity
2. **Claude -p** (fallback) - Fresh context, still breaks self-bias loop

The dialogue continues until models converge or disagreement is clearly understood.

## jwz Integration

The oracle posts analysis summaries for discoverability:

```bash
# For bug analysis
jwz post "issue:<issue-id>" --role oracle \
  -m "[oracle] ANALYSIS: <topic>
Status: RESOLVED|NEEDS_INPUT|UNRESOLVED
Confidence: HIGH|MEDIUM|LOW
Summary: <one-line recommendation>
Key finding: <most important insight>"

# For design decisions
jwz post "issue:<issue-id>" --role oracle \
  -m "[oracle] DECISION: <topic>
Recommendation: <chosen approach>
Alternatives considered: <count>
Tradeoffs: <key tradeoff summary>"
```

Other agents can discover analyses via:
```bash
jwz search "ANALYSIS:"
jwz search "DECISION:"
```

## Output Structure

The oracle returns:

```markdown
## Result

**Status**: RESOLVED | NEEDS_INPUT | UNRESOLVED
**Confidence**: HIGH (85%+) | MEDIUM (60-75%) | LOW (<50%)
**Summary**: One-line recommendation

## Problem
[Restatement]

## Hypotheses (ranked by probability)
1. (60%) [Most likely] - Evidence: [X]
2. (25%) [Alternative] - Evidence: [Y]

## Second Opinion
[What the other model thinks]

## Recommendation
[Synthesized recommendation]

## Would Change Conclusion If
[What evidence would overturn this]
```

## Confidence Levels

| Level | Criteria |
|-------|----------|
| **HIGH (85%+)** | Multiple evidence sources, verified against code, models agree |
| **MEDIUM (60-75%)** | Single strong source OR multiple weak sources agree |
| **LOW (<50%)** | Hypothesis fits but unverified, circumstantial evidence |
