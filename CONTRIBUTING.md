# Contributing to trivial

Thank you for your interest in contributing to trivial!

## Development Setup

1. Clone the repository:
   ```shell
   git clone https://github.com/femtomc/trivial.git
   cd trivial
   ```

2. Install dependencies:
   ```shell
   ./install.sh
   ```

3. Run Claude Code with the plugin:
   ```shell
   claude --plugin-dir .
   ```

4. Test that agents and commands are available:
   ```shell
   /trivial:dev:plan What should I work on?
   ```

## Adding a New Agent

1. Create a new file in `agents/`:
   ```
   agents/your-agent.md
   ```

2. Add YAML frontmatter:
   ```yaml
   ---
   name: your-agent
   description: When to use this agent (shown in agent picker)
   model: haiku | opus
   tools: Read, Grep, Glob, Bash
   ---
   ```

3. Write the agent instructions:
   - **Role**: What the agent does
   - **Constraints**: What the agent MUST NOT do
   - **Workflow**: How the agent operates
   - **Output Format**: Expected response structure

4. The agent becomes available as `trivial:your-agent`

See `agents/explorer.md` for a simple example or `agents/oracle.md` for a complex one.

## Adding a New Command

1. Create a new file in `commands/<category>/`:
   ```
   commands/dev/your-command.md
   commands/loop/your-command.md
   ```

2. Add YAML frontmatter:
   ```yaml
   ---
   description: What the command does
   ---
   ```

3. Write the command specification:
   - **Usage**: How to invoke
   - **Workflow**: Step-by-step execution
   - **Output**: Completion signals (for loop commands)

4. The command becomes available as `/trivial:<category>:your-command`

See `commands/dev/fmt.md` for a simple example or `commands/loop/grind.md` for a complex one.

## Code Style

- Agent/command files are Markdown with YAML frontmatter
- Use clear, imperative language in instructions
- Be explicit about constraints (what the agent MUST NOT do)
- Include concrete examples in workflows

## Messaging Guidelines

Agents communicate via zawinski messaging (`jwz` CLI):

- **Messages** are for quick status updates and notes
- **Artifacts** (`.claude/plugins/trivial/{agent}/`) are for polished outputs

### Topic Naming

| Pattern | Purpose |
|---------|---------|
| `project:<name>` | Project-wide announcements |
| `issue:<id>` | Per-issue discussion |
| `agent:<name>` | Direct agent communication |

### Message Format

```
[agent] ACTION: description

Examples:
[oracle] STARTED: Analyzing auth feature
[oracle] FINDING: Race condition in handler.go:45
[reviewer] BLOCKING: Security issue in token validation
```

## Testing

trivial doesn't have automated tests. Manual testing workflow:

1. Load the plugin with `claude --plugin-dir`
2. Invoke your agent/command
3. Verify it behaves as documented
4. Test edge cases (missing dependencies, errors)

## Pull Request Process

1. Fork the repository
2. Create a branch for your change
3. Add/modify agents or commands
4. Test manually
5. Submit a PR with:
   - Clear description of what you added/changed
   - Any new dependencies required
   - Example usage

## Architecture

For a deeper understanding of how trivial works, see [docs/architecture.md](docs/architecture.md).
