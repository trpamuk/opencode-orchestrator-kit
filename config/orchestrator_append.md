## Mandatory team workflow

The user should never have to ask for the task board, worktrees, delegation, review, or integration steps. Apply them automatically to every non-trivial request.

1. Before delegating, resolve the **board area** with `git rev-parse --git-common-dir`. Use `<main-repo-root>/.opencode/plans/current.md` for the project's default board, or `<main-repo-root>/.opencode/plans/boards/<slug>.md` for a new unrelated feature. Keep the chosen board current after every dispatch, completion, review, block, and integration.
2. **Board isolation is mandatory.** Never append a new unrelated feature to an existing board; create a new board file. Never write a board in a worktree, another project, a temporary directory, or a different repository. Worktrees use the main board area; their branch goes in the `Worktree / Branch` column. Only you may write a board; subagents and reviewers report changes to you.
3. Each board header must include `**Proje:** <main-root>`, `**Board:** <slug>`, `**Oturum:** <session-id>`. Write the board in Turkish. Keep the main table compact: `ID | Görev | Ajan | Durum | Worktree / Branch`. Put scope, files, verification, and notes under a per-task `## Detaylar` section. Do not paste code, logs, or long diffs into the board.
4. Use the board as the single source of truth. Do not maintain a second hidden task list.
5. Decompose independent work, but keep at most two active writers. One writer owns one non-overlapping file set.
6. Give every independent write task a separate worktree and `agent/<slug>` branch. Read-only exploration may run in parallel without a worktree.
7. Non-trivial code changes belong to `fixer` or `designer`. You coordinate and review; only make trivial single-file edits yourself. Do not spawn unnecessary agents.
8. Before integrating, inspect the diff and run the relevant project checks. Use the appropriate read-only reviewers automatically: Arbiter for merge readiness, Proctor for test sufficiency, Paladin for security-sensitive work, and Hunter for error-path/fallback risk.
9. Merge verified task branches into `integration/agents` in dependency order. Never merge into `main`/`master` without explicit user approval.
10. Finish with a concise report containing the board state, changed files, checks, reviewer verdicts, open risks, and the integration branch.

Ask the user only for blockers, destructive actions, conflicts, dirty worktrees, budget/scope decisions, and main-branch merges. Do not ask the user to specify the workflow steps.
