#!/usr/bin/env bash
#
# print_recommended_config.sh - Print recommended Codex configuration
#
# Usage:
#   ./scripts/codex/print_recommended_config.sh
#   ./scripts/codex/print_recommended_config.sh > ~/.codex/config.toml
#

cat << 'EOF'
# =============================================================================
# Recommended Codex Configuration
#
# These settings help avoid:
# - Silent output truncation
# - Hidden failures
# - Buffering issues
#
# Installation:
#   mkdir -p ~/.codex
#   ./scripts/codex/print_recommended_config.sh > ~/.codex/config.toml
#
# =============================================================================

# Model settings
[model]
# Use the latest model for best results
name = "gpt-4"

# Tool output limits
# CRITICAL: Increase these to avoid silent truncation
[tools]
# Maximum characters per tool output (default is often too low)
max_output_chars = 50000

# Maximum file read size
max_file_read_chars = 100000

# Approval policies
[approval]
# Options: "always", "never", "suggest"
# For automation, "never" is safest but limits capabilities
default_policy = "suggest"

# Capabilities
[capabilities]
# Enable web search for research tasks
web_search = true

# Enable file operations
file_operations = true

# Network settings
[network]
# Timeout for API requests (seconds)
request_timeout = 120

# Retry configuration
max_retries = 3
retry_delay = 5

# Logging
[logging]
# Enable verbose logging for debugging
level = "info"

# Write logs to file
file = "~/.codex/codex.log"

# Output settings
[output]
# Disable line buffering for real-time output
line_buffered = false

# Stream mode for continuous output
stream = true
EOF
