# Agent Ergonomics Kit

A reusable kit for standardizing AI agent documentation and Codex sub-agent coordination across repositories.

## What This Kit Provides

- **AGENTS.md** - Canonical, tool-agnostic agent guidelines
- **CLAUDE.md** - Shim that imports modular docs for Claude Code
- **Modular docs** - Skills, sandbox, auth, MCP, Codex, inference-speed
- **MCP server definitions** - Following mcp-local-spec approach
- **Codex orchestration** - Dual-path (MCP + CLI) with queue, watchdog, diagnostics
- **CI integration** - Verify scripts to prevent drift

## Quick Start

### Apply to a Repository

```bash
# Clone this kit
git clone https://github.com/YOUR_ORG/agent-ergonomics.git

# Apply to your target repo
./scripts/apply.sh /path/to/your/repo

# In your repo, bootstrap and verify
cd /path/to/your/repo
./scripts/agent/bootstrap.sh
./scripts/agent/verify.sh
```

### Test Codex Integration

```bash
# In target repo
./scripts/codex/diagnose.sh
```

## Verification

- In the kit repo, run `./scripts/verify.sh` (template-level checks).
- In a target repo, run `./scripts/agent/verify.sh` (repo-level conformance).

## Kit Structure

```
agent-ergonomics/
├── README.md                    # This file
├── templates/
│   ├── AGENTS.md               # Canonical agent guidelines template
│   ├── CLAUDE.md               # Shim template (exact format required)
│   └── .agent/
│       ├── skills.md           # Working style and repo commands
│       ├── sandbox.md          # Safety guidelines
│       ├── auth.md             # Authentication patterns
│       ├── mcp.md              # MCP configuration
│       ├── codex.md            # Codex sub-agent contract
│       ├── inference_speed.md  # Workflow optimization
│       └── mcp/servers/        # MCP server definitions
│           ├── codex.md
│           ├── filesystem.md
│           ├── github.md
│           └── shell.md
├── scripts/
│   ├── apply.sh               # Apply kit to target repo
│   ├── verify.sh              # Verify target repo conforms
│   ├── agent/
│   │   ├── bootstrap.sh       # Bootstrap target repo
│   │   └── verify.sh          # Verify (copied to target)
│   ├── codex/
│   │   ├── run.sh             # Router (auto-selects MCP/CLI)
│   │   ├── run_cli.sh         # CLI execution path
│   │   ├── run_mcp.sh         # MCP execution path
│   │   ├── status.sh          # Job status viewer
│   │   ├── cancel.sh          # Cancel running job
│   │   ├── watchdog.sh        # Monitor for timeouts
│   │   ├── enqueue.sh         # Add to queue
│   │   ├── worker.sh          # Process queue
│   │   ├── worker_status.sh   # Queue status
│   │   ├── diagnose.sh        # Diagnostic tool
│   │   └── print_recommended_config.sh
│   ├── mcp/
│   │   └── install.sh         # Install MCP servers to ~/.mcp/
│   └── docs/
│       └── list.sh            # List documentation
└── docs/
    ├── README.md              # Docs index
    ├── agent_setup.md         # Setup guide
    ├── codex_cli.md           # Codex CLI usage
    ├── codex_config_recommended.md  # Config recommendations
    └── codex_postmortem.md    # Troubleshooting template
```

## Key Concepts

### AGENTS.md vs CLAUDE.md

- **AGENTS.md** is the canonical document, readable by any agent
- **CLAUDE.md** is a strict shim that imports modular docs via `@` syntax
- This separation keeps Claude-specific features isolated

### Dual-Path Codex Execution

The kit supports both MCP and CLI paths for Codex:

```bash
# Auto-select (prefers MCP if available)
./scripts/codex/run.sh "task"

# Force CLI
CODEX_MODE=cli ./scripts/codex/run.sh "task"

# Force MCP
CODEX_MODE=mcp ./scripts/codex/run.sh "task"
```

### Task Queue

For non-blocking task delegation:

```bash
./scripts/codex/enqueue.sh "task 1"
./scripts/codex/enqueue.sh "task 2"
./scripts/codex/worker.sh --daemon &
```

### Watchdog

Monitor running jobs for stalls:

```bash
./scripts/codex/watchdog.sh --daemon &
```

Automatically detects:
- No start acknowledgment (60s)
- No heartbeat (5min)
- Stale jobs (10min) - triggers auto-split suggestion

## Inference-Speed Principles

This kit implements learnings from "Shipping at Inference-Speed":

1. **Queue work, don't block** - Use the task queue
2. **Keep prompts short** - Iterate, don't mega-prompt
3. **CLI-first verification** - Every change should be testable
4. **Engineer for agents** - Predictable structure, docs in docs/
5. **Treat compaction as review** - Write summaries that survive
6. **Auto-split large tasks** - Watchdog suggests splitting

## Contributing

1. Make changes to templates/scripts
2. Test by applying to a test repo
3. Run `./scripts/verify.sh /path/to/test/repo`
4. Submit PR

## License

MIT
