# Global orchestration policy

These rules apply to every project unless a project-level `AGENTS.md` overrides them.

## Task board

For every non-trivial request, create or update a shared task board at:

```text
<project>/.opencode/plans/current.md
```

The Orchestrator owns this file. Subagents must not edit it. Create the directory when missing.

### Board isolation (hard rule)

- Each repository has one **board area**, always in the **main worktree**:
  `<main-repo-root>/.opencode/plans/`.
- The default/legacy board is `<main-repo-root>/.opencode/plans/current.md`.
- Every **unrelated feature or task sequence** gets its own board:
  `<main-repo-root>/.opencode/plans/boards/<slug>.md`.
- Never append a new unrelated feature to another feature's board. If the task does not belong to the existing board's feature, create a new board file.
- Resolve the main root with `git rev-parse --git-common-dir`; if the result ends in `.git`, the main root is its parent. Do not guess.
- Worktrees are execution lanes, not separate boards. A task running in a worktree stays on its project board with its worktree/branch in the table.
- Never create or update a board inside a worktree, another project, a temporary directory, or a different repository.
- Only the Orchestrator may write project boards. Subagents and reviewers must report board changes to the Orchestrator; they must not edit a board directly.
- Before writing, compare the target path with the project's board area. If it is outside `.opencode/plans/current.md` or `.opencode/plans/boards/*.md`, stop and report the mismatch instead of writing.
- Each board header must identify its scope:
  `**Proje:** <main-root>`, `**Board:** <slug>`, `**Oturum:** <session-id>`.
- The live panel is project-scoped and shows each board file separately. Never merge two projects or two task sequences into one table.

Use this structure:

```md
# Güncel Görevler

**Proje:** <main-repo-root>
**Board:** <slug>
**Oturum:** ses_...
**Özellik:** ...

| ID | Görev | Ajan | Durum | Worktree / Branch |
|---|---|---|---|---|
| T1 | Kısa görev adı | explorer | bitti | - |
| T2 | Kısa görev adı | fixer | çalışıyor | worktrees/slug / agent/slug |

## Detaylar

### T2 — Kısa görev adı
- **Kapsam:** ...
- **Dosyalar:** ...
- **Doğrulama:** ...
- **Not:** ...
```

Write the board in **Turkish**. Code identifiers, file paths, and commands may stay in their original language.

Keep the table compact:

- `Görev` is a short title, not a paragraph.
- Put files, verification, and notes in the per-task details below.
- Do not paste code, logs, or long diffs into the board.
- Use Turkish status labels: `bekliyor`, `çalışıyor`, `incelemede`, `engellendi`, `bitti`, `birleşti`.
- Keep the full worktree path in the details; show a short path in the table.

Update the board when a task is queued, dispatched, completed, blocked, reviewed, or integrated. Keep it short enough that the user can scan it.

### Board lifecycle (cleanup)

- Boards are **ephemeral working state**, not history. Keep only active task sequences in `.opencode/plans/boards/`.
- When every task is `bitti`/`birleşti` and the final report has been delivered (or the work is explicitly abandoned), move the board to:
  `<main-repo-root>/.opencode/plans/archive/<YYYY-MM>/boards/<slug>.md`
  in the same turn. Create `<YYYY-MM>/README.md` with one line per archived board.
- Keep `.opencode/plans/current.md` as a short active-board index/status page. Do **not** append completed feature histories to it; replace stale status text when the active set changes.
- Durable documents (ADR, contract, gap analysis) may stay in `.opencode/plans/`. Completed implementation plans/contracts should be archived with their board.
- Archive, do not delete, unless the user explicitly asks for deletion.
- If there is no active board, say so in `current.md` and leave `boards/` empty.

## Parallel work

- Maximum **2 active writers** per repository.
- One writer owns one file set. Never assign overlapping write scopes to parallel writers.
- Every independent write task gets its own worktree and branch:
  - Worktree: `.slim/worktrees/<slug>` (use the project's configured worktree location if different)
  - Branch: `agent/<slug>`
- Read-only tasks (exploration, review, research) may run in parallel without worktrees.
- Non-trivial code changes belong to `fixer` or `designer`. The Orchestrator coordinates and reviews; it may make only trivial single-file edits itself.
- Do not spawn a subagent or worktree just to look busy.
- If worktrees are unavailable, allow only one writer at a time.

## Integration and merge

- Use an integration branch named `integration/agents` unless the project defines another one.
- Merge completed task branches into the integration branch only after:
  1. the task report is reviewed,
  2. the diff is inspected,
  3. the project's relevant checks pass.
- Merge in dependency order. Re-run affected checks after each merge.
- Stop on conflicts or failing checks and report them; do not force-resolve or discard work.
- **Never merge into `main`/`master` without explicit user approval.**
- Never force-push, delete unmerged branches, or remove a dirty worktree without explicit confirmation.
- Standing approval: create/remove clean task worktrees and merge verified task branches into `integration/agents` without asking. Ask only for `main`/`master`, destructive actions, conflicts, and dirty worktrees.

## Review gate

Use the available read-only reviewers when their scope matches:

- **Arbiter** — merge readiness, correctness, architecture, contracts.
- **Proctor** — behavior and regression test sufficiency.
- **Paladin** — security, auth, payments, uploads, secrets, trust boundaries.
- **Hunter** — swallowed errors, misleading fallbacks, weak diagnostics, retry exhaustion.

Reviewers must not edit files. Send their findings back to the owning writer, then re-run the affected checks.

## Worktree setup

For a new worktree, ensure the environment is usable before assigning a writer:

- copy required local env files without committing secrets,
- install dependencies or link the main checkout's dependency directory when safe,
- verify the project's test/build command works in the worktree.

Do not commit generated artifacts, local env files, or dependency directories.

## User communication

- The user only needs to state the outcome. Apply the board, worktree, delegation, review, and integration policy automatically; do not require the user to specify those steps.
- The task board is the single source of truth for parallel work.
- Keep the user-facing summary short: what is running, what is blocked, what needs approval.
- Ask the user only for blockers, destructive actions, budget/scope decisions, and main-branch merges.
- At the end, report the board state, changed files, checks, reviewer verdicts, and the integration branch.
