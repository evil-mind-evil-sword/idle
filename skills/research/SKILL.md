---
name: research
description: Get documented research on external libraries, APIs, or codebases using the librarian agent
---

# Research Skill

Get durable, documented research on external code and libraries.

## When to Use

Use this skill when you need:
- Documented research that persists beyond the conversation
- Investigation of external libraries, APIs, or frameworks
- Research that other agents should be able to discover via jwz

**Don't use for**: Quick questions where you don't need a durable artifact. Just ask naturally and the librarian agent will be auto-discovered.

## Workflow

Invoke the librarian agent:

```
Task(subagent_type="idle:librarian", prompt="Research: <topic>")
```

The librarian agent will:
1. Search external sources (GitHub, docs, web)
2. Evaluate source credibility (CRAAP method)
3. Synthesize findings with inline citations
4. Write artifact to `.claude/plugins/idle/librarian/<topic>.md`
5. Post notification to jwz for discoverability

## Artifact Output

Research is saved to:
```
.claude/plugins/idle/librarian/<topic>.md
```

## jwz Integration

The librarian posts a notification for discoverability:

```bash
jwz post "issue:<issue-id>" --role librarian \
  -m "[librarian] RESEARCH: <topic>
Path: .claude/plugins/idle/librarian/<topic>.md
Summary: <one-line key finding>
Confidence: HIGH|MEDIUM|LOW
Sources: <count>"
```

Other agents can discover research via:
```bash
jwz search "RESEARCH:"
jwz read "issue:<id>" | grep "Path:"
```

## Output Structure

The librarian returns:

```markdown
# Research: [Topic]

**Status**: FOUND | NOT_FOUND | PARTIAL
**Confidence**: HIGH | MEDIUM | LOW
**Summary**: One-line answer

## Sources (with credibility)
1. [Source](URL) - [Authority] - [Date]

## Findings
[Detailed explanation with citations]

## Conflicts/Uncertainties
[Any disagreements between sources]
```
