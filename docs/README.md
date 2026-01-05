# Agent Ergonomics Documentation

This kit provides standardized agent documentation and Codex sub-agent coordination for any repository.

## Contents

| Document | Purpose |
|----------|---------|
| [agent_setup.md](agent_setup.md) | How to apply the kit to a repository |
| [codex_cli.md](codex_cli.md) | Codex CLI installation and usage |
| [codex_config_recommended.md](codex_config_recommended.md) | Recommended Codex configuration |
| [codex_postmortem.md](codex_postmortem.md) | Troubleshooting template for Codex issues |

## Quick Start

```bash
# Apply kit to a target repository
./scripts/apply.sh /path/to/your/repo

# In the target repo, bootstrap
cd /path/to/your/repo
./scripts/agent/bootstrap.sh

# Verify setup
./scripts/agent/verify.sh

# Test Codex integration
./scripts/codex/diagnose.sh
```

## What Gets Installed

When you apply this kit to a repository:

```
target-repo/
├── AGENTS.md              # Canonical agent guidelines (customize this!)
├── CLAUDE.md              # Shim that imports modular docs
├── .agent/
│   ├── skills.md          # Working style and repo commands
│   ├── sandbox.md         # Safety guidelines
│   ├── auth.md            # Authentication patterns
│   ├── mcp.md             # MCP configuration
│   ├── codex.md           # Codex sub-agent contract
│   ├── inference_speed.md # Workflow optimization
│   ├── queue/             # Task queue storage
│   ├── runs/              # Codex run logs
│   └── mcp/servers/       # MCP server definitions
├── scripts/
│   ├── agent/             # Bootstrap and verify scripts
│   ├── codex/             # Codex orchestration scripts
│   ├── mcp/               # MCP installation scripts
│   └── docs/              # Documentation utilities
└── docs/
    └── (documentation)
```

## Key Concepts

### AGENTS.md vs CLAUDE.md

- **AGENTS.md** is the canonical, tool-agnostic document describing how agents work in the repo
- **CLAUDE.md** is a shim that imports AGENTS.md and additional modular docs via `@` syntax

This separation ensures:
- Claude-specific features (like `@` imports) don't pollute the main doc
- Other agents can read AGENTS.md directly
- Modular docs can be updated independently

### Codex Integration

The kit provides dual-path Codex execution:

1. **MCP Path**: Uses MCP protocol for integration with Claude
2. **CLI Path**: Uses `codex exec` for direct execution

Scripts automatically route to the available path.

### Queue System

For non-blocking task delegation:

```bash
# Add tasks without waiting
./scripts/codex/enqueue.sh "task 1"
./scripts/codex/enqueue.sh "task 2"

# Process queue in background
./scripts/codex/worker.sh --daemon &
```
