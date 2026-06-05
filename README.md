# Factory Desktop

Factory Desktop is a local-first macOS SwiftUI app for managing projects, tasks, worktrees, local Ollama planning runs, Codex handoffs, and review logs across local repositories.

This v0.1 intentionally does **not** perform autonomous file editing. Factory owns state, run logs, handoffs, and safe command execution; humans approve implementation and commits.

## v0.1 Features

- Three-column SwiftUI desktop UI:
  - sidebar for projects and tasks
  - center task detail, controlled workflow, and run log
  - right inspector for project context, git status, changed files, and actions
- SQLite storage at `~/.factory/factory.db`
- Automatic migrations with pre-migration DB backups in `~/.factory/snapshots/`
- Project registry with name, path, type, default branch, test commands, and metadata
- Task CRUD with statuses: `inbox`, `planning`, `approved`, `running`, `needs_review`, `done`, `blocked`
- Git status and diff stat display
- Local and Codex worktree creation:
  - local branch: `factory/<id>-<slug>`
  - codex branch: `codex/<id>-<slug>`
  - worktrees under `~/.factory/worktrees/<project>/<task>-local|codex`
- Ollama planner integration against `http://localhost:11434/api/generate`
- Planner model selector with `qwen3.5:4b` as the default
- Prompt/output logs under `~/.factory/runs/`
- Codex handoff markdown generation
- Terminal and VS Code open buttons
- Review-note generation
- CommandRunner allowlist and blocked-command safety checks
- Explicit confirmation before committing; commit is refused on `main`, `master`, or the configured default branch

## Build and Run

```bash
swift build
swift run FactoryDesktop
```

Run tests:

```bash
swift test
```

## GitHub Remote

This repo is intended to publish to:

```bash
https://github.com/dany-sh/factory-desktop.git
```

## First Self-Use Flow

1. Launch Factory Desktop.
2. Click **Register This App**.
3. If this folder has not been initialized as a git repo yet, run `git init` outside Factory first.
4. Create a task such as `Improve source controls UI`.
5. Click **Create Local Worktree**.
6. Click **Plan Locally** with Ollama running.
7. Review the planner output in the run log.
8. Click **Send to Codex**.
9. Terminal opens in the Codex worktree; run `codex` and use the generated handoff.
10. Refresh git status and generate a review note before any human-approved commit.

## Local Model Policy

- Factory planning: `qwen3.5:4b` at 64k
- Debug/code planning: `codegeex4:9b` at 64k
- Task JSON: `gemma4:e2b` at 64k
- Structured extraction: `granite4.1:3b` at 64k max
- Fallback code reasoning: `qwen2.5-coder:7b` at 64k/128k
- Long-context reading: `gemma4:latest` or `gemma4:e4b`

Hard caps:

- Do not use `qwen3.5:9b` above 128k.
- Do not use `granite4.1:3b` above 64k.
- Do not use 256k globally.
- Use 64k by default.

## Safety Model

Allowed shell entry points:

- `git status`
- `git diff`
- `git diff --stat`
- `git log`
- `git branch`
- `git worktree`
- `git switch`
- `git checkout`
- `git add`
- `git commit`
- `xcodebuild`
- `swift test`
- `npm run lint`
- `npm run test`
- `python -m pytest`
- `open`
- `code`

Blocked command fragments:

- `rm -rf`
- `sudo`
- `git reset --hard`
- `git push --force`
- `chmod -R 777`
- `killall`
- `pkill`
- `curl | sh`
