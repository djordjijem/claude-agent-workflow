# <Project name>

<One line: what this service is and its stack.>

## Code Style

- <your conventions: typing rules, naming, response shapes, max function size…>
- Library-first: prefer established packages over custom utils.
- **NEVER add, remove, upgrade or downgrade packages without the developer's explicit
  approval.** Propose it instead: package, version, why, alternatives considered,
  downloads/maintenance, and license. Then wait for a yes. Restoring the existing lockfile
  (`npm ci`) is fine. This applies even when the change is needed for a task the developer
  already approved: approving the task doesn't approve its package changes.

## Structure

```
src/        - <layers>
spec/       - tests
```

## Commands

```bash
<dev server>      # the developer runs this, never the agent
<test command>    # run tests once
```

## Git Workflow

- **NEVER commit without the developer's explicit approval.** Not at the end of a task, not
  "one commit per step", not because a plan said to. Finish the work, leave it uncommitted,
  and say what changed. This applies to commit, push, amend, rebase and anything else that
  rewrites history.
- Never `git add -A` / `git add .`; stage only the files you touched. The working tree
  usually has unrelated in-progress work in it.
- Never use `--no-verify`. If a hook fails, report it instead of bypassing it.
- Commit format: `type(scope): description`

## Dev Server

- **NEVER start or stop the dev server yourself.** The developer runs it manually. If you
  need it running to verify something, ask and wait.

## MANDATORY: Test-Driven Development

Every code change follows TDD:
1. Write a failing test first
2. Run it, verify it FAILS (not errors)
3. Write minimal code to pass
4. Run it, verify it PASSES
5. Refactor if needed

A test that passes immediately is the wrong test; rewrite it.

## Post-Change Checklists

After significant changes (features, endpoints, refactors, dependency upgrades), run both:

### Performance
- [ ] No N+1 queries
- [ ] Queries use proper indexes
- [ ] No unpaginated reads of large tables
- [ ] No loading full records when only IDs/counts are needed
- [ ] No synchronous blocking work in request handlers
- [ ] Bulk operations instead of loops

### Security
- [ ] User input validated before use
- [ ] No raw string interpolation in queries
- [ ] Authorization and tenant scoping enforced
- [ ] No secrets hardcoded or logged
- [ ] No sensitive data in API responses
- [ ] No new critical/high vulnerabilities from the dependency audit

## Review Handoff (MANDATORY at the end of every task that changes code)

A task is not done until the gate passes and the Review Summary is posted.

### Milestones (the developer approves the plan and reviews the end result, nothing in between)

- Before touching code, post a numbered milestone plan: each milestone is one coherent,
  testable slice (e.g. "1/3 migration + model", "2/3 data access + routes", "3/3 auth + docs").
  For multi-milestone tasks, wait for the developer's OK on the plan. That is the ONLY
  mid-task check-in. A small fix is a single milestone (1/1) and needs no plan approval.
- If the task needs package changes, list them in the plan so they're approved with it. A
  package need discovered mid-task is a BLOCKED stop.
- **Plan file:** write the approved plan to `.claude/notes/plan-<task-slug>.md` (goal, each
  milestone with its files and acceptance criteria). Mark milestones `[x]` as they finish.
  Long runs get their context summarised, so re-read this file after a summary and before
  each milestone; it's the source of truth for where you are.
- **Worktree (optional):** for multi-milestone tasks, work in a git worktree so changes never
  mix with the developer's in-progress work, then run `.claude/hooks/setup-worktree.sh` in it.
- After approval, run ALL milestones back to back. Don't stop or ask between them.
- During a milestone (TDD loop) run only the relevant spec files, not the full suite.
- Edit code with the Edit/Write tools, not shell commands: the hooks track edits through them.
- End of each milestone, in this order:
  1. **Automated review.** Launch BOTH agents in parallel: `code-reviewer` and
     `security-auditor`. Give them the explicit list of files changed in THIS milestone and
     the milestone goal, and tell them not to review anything else.
  2. **Fix** findings by severity:

     | security-auditor | code-reviewer | Action |
     |---|---|---|
     | Critical, High | 🔴 Critical Issues | must fix |
     | Medium | 🟡 Improvements | fix if cheap, else list as unresolved |
     | Low, Info | 🟢 Suggestions | ignore unless trivial |

     Treat findings as claims: verify before changing code; if one is wrong, note why and
     skip it. A real bug gets a **failing regression test first**, then the fix. At most 2
     review→fix rounds per milestone; anything still open goes in the summary.
  3. **Gate.** Run `bash .claude/hooks/e2e-gate.sh run` (typecheck, no NEW lint errors in
     edited files, migration check, full suite). Run it last: any later code change
     invalidates it.
  4. Post `## Milestone N/M complete: <name>` with changed files, findings fixed/skipped, and
     the gate's result lines. Then continue straight into the next milestone.
- The last milestone ends with `## Review Summary` instead.
- Only stop early when truly blocked: the gate still fails after a genuine fix attempt, a
  requirement is ambiguous in a way that changes the design, or the next step needs something
  forbidden (commit, server restart, prod access, package changes). Report `Status: BLOCKED`.
- The Stop hook (`e2e-gate.sh check`) enforces this:
  - A turn that edited code must end with one of the two headings.
  - On a heading, both reviewers must have run since the milestone started, and the code must
    match the last green gate run. Otherwise the turn is blocked.
  - `Status: BLOCKED` summaries pass through. Never use the headings for anything else.

### E2E tests

- Every new feature and every behaviour change needs an end-to-end spec: real HTTP calls
  against the app and a test DB (auth → request → response shape → resulting DB state), plus
  negative cases (wrong role, wrong tenant).
- Pass = the gate prints `E2E gate: PASSED`. Quote its result lines in the milestone message.
- Any failure = BLOCKED. If a failure looks pre-existing and unrelated, name the spec and
  show why, but the status stays BLOCKED until the developer decides.

### Review Summary (post as the final message)

```
## Review Summary
Status: READY FOR REVIEW | BLOCKED (<reason>)
Where: main checkout | worktree <path> on branch <branch>
Plan: .claude/notes/plan-<task-slug>.md

Changed files
- path/to/file.ts — one line on why

E2E
- Specs added/updated: <file> → "it(...)" names
- Gate: <result lines>

Checklists: Performance ✅/❌ · Security ✅/❌ (name any failed item)

Automated review (per milestone)
- M1: code-reviewer → N fixed, N skipped (why) · security-auditor → N fixed, N skipped (why)
- Unresolved review findings: <file:line + finding, or "None">

Big picture
<table of added/changed/removed items + ASCII diagram if the flow changed>

Feature README: <path, created | updated>
Manual QA: <N added / N updated / N removed in docs/qa/manual-tests-todo.md, or "none">

### ⚠ Needs developer approval
- New code patterns: <file:line + what is new, or "None">
- Env vars / sensitive data: <file:line + what, or "None">
- DB changes / migrations: <file:line + what, or "None">
```

Every approval category is always listed; write "None" instead of omitting it.

- **New code patterns:** any abstraction, helper style, dependency, middleware,
  error-handling approach or file layout that doesn't already exist in the codebase.
- **Env vars / sensitive data:** any new env var read, config/secret file change, credentials,
  PII, anything newly logged or newly returned in an API response. Names only, never values.
- **DB changes / migrations:** model changes, migrations, seed data, raw SQL, indexes,
  constraints, cascade rules.

### Big picture

- A table: `| Item | Kind (endpoint, function, model, table, column, migration, env var) |
  Added/Changed/Removed | Notes |`.
- When flow or structure changed, an ASCII diagram of the request path, marking new parts
  `[NEW]` and changed ones `[CHANGED]`.

### Feature README

- Every feature or behaviour change is documented in a `README.md` in the feature's folder,
  or `docs/features/<feature>.md` when it's spread across shared layers.
- Contents: what it does and why, how it fits in the system, endpoints/env vars/tables
  (names only), and a dated `## Changelog` entry, newest first. Never rewrite old entries.

### Manual QA list (every task, small or large)

- `docs/qa/manual-tests-todo.md`: open tests that still need a human run.
- `docs/qa/manual-tests-covered.md`: tests that were run and passed (date, who, env).
- Every behaviour change adds or updates tests in the open list. Format:
  `- [ ] **<AREA>-<NN>** <steps> → <expected>`, grouped in `##` sections by feature.
  IDs are stable; never reuse a number. Rewrite or delete tests that a change makes wrong.
