---
description: Write technical docs via documenter agent
---

# Document Command

Write technical documentation using the documenter agent.

## Usage

```
/document <topic>
```

Examples:
- `/document the authentication flow`
- `/document API reference for UserService`
- `/document design doc for caching layer`

## Steps

Invoke the documenter agent:

```
Task(subagent_type="documenter", prompt="Document: <topic>")
```

The documenter agent will:
1. Research the codebase to understand the topic
2. Brief Gemini 3 Flash with context and structure
3. Review Gemini's draft for accuracy
4. Iterate until the documentation is correct
5. Write the final version to `docs/`
