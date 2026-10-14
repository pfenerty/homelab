# Agent Instructions

See [`CLAUDE.md`](CLAUDE.md) for repository layout, cluster operations and secret handling.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->

## Cross-Repo Planning

`homelab` hosts the Tekton/PAC CI that runs pipelines defined with `tektonic` for `apko-cicd`, `ocidex`, the `tektonic-ci` repos and this repo. Cross-cutting initiatives are tracked in `~/code/common/` (issue prefix: `plan`).

- `bd list` here shows only this repo's issues. For every repo at once, use the hub: `cd ~/code/common && bin/hub sync && bd ready` (or `bd blocked`, `bd list`)
- Cross-repo epics (work spanning 2+ repos) live in the hub: `cd ~/code/common && bin/hub sync`, `bd create --type=epic ...`, then `bd dep add plan-xyz <issue-id-in-this-repo>`. See `~/code/common/CLAUDE.md`
- When a local issue is part of a cross-repo initiative, also note it here: `bd update <id> --append-notes "Parent epic: plan-xyz"` (`--notes` would replace existing notes)
- File issues in the repo where the change lands; don't add a tracking copy in a consumer repo
- homelab issues in this chain typically involve: PAC Repository CRDs, namespace setup, SOPS-encrypted secrets for CI credentials
