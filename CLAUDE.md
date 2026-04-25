@AGENTS.md

# Claude Code Overlay

`AGENTS.md` is the primary repo contract for `betterkvm`.

Use these in order:
1. [AGENTS.md](AGENTS.md)
2. This file only as a thin tool-specific overlay

Guardrails:
- Prefer `just` entrypoints over ad hoc shell commands.
- Treat repo-local NixOS modules, preseed scripts, and host configs as higher priority than home-level defaults.
- Do not recurse across sibling repos unless the task explicitly asks for them.
- The `lab` repo is the house style authority for Nix patterns, justfile conventions, PBT testing, and MCP registry integration.
- PiKVM (Pi #1) is Arch Linux, not NixOS. Do not generate Nix config for it.
- Secrets management uses sops-nix with age keys. Never log or echo decrypted secret values.
