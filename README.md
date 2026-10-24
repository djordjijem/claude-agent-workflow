# Claude Code workflow: review decisions, not diffs

My setup for letting Claude Code run multi-step tasks on its own while I review plans and
summaries instead of reading every line.

## The flow

```
 you                          agent                                     scripts (hooks)
 ───                          ─────                                     ───────────────
 task ──────────────────────▶ milestone plan
 approve plan ◀─────────────  (written to .claude/notes/plan-*.md)
                              for each milestone:
                                failing test → code → passing test     PostToolUse: log edited files
                                code-reviewer + security-auditor ────▶ SubagentStop: record reviewers ran
                                fix findings (regression test first)
                                e2e-gate.sh run ─────────────────────▶ typecheck, new lint errors,
                                                                       migrations, full suite → fingerprint
                                "## Milestone N/M complete" ─────────▶ Stop: blocked unless reviewers ran
                                                                       AND code == last green run
 read summary ◀───────────── "## Review Summary"
 manual QA, approve commit
```

## What runs and when

| Script | Trigger | What it does |
|---|---|---|
| `e2e-gate.sh mark-edit` | after **every** Edit/Write | logs which code files the agent touched in this task |
| `e2e-gate.sh record-review` | every time a reviewer agent finishes | stamps that `code-reviewer` / `security-auditor` ran |
| `e2e-gate.sh check` | **every** time the agent tries to end a turn | blocks it if it changed code without finishing the milestone, skipped a reviewer, or the code changed since the last green run |
| `e2e-gate.sh run` | agent runs it at the end of each milestone | typecheck → lint (only *new* errors in edited files) → optional migration check → full test suite; saves a fingerprint of the code that passed |
| `setup-worktree.sh` | start of a multi-milestone task (optional) | prepares an isolated git worktree so agent changes never mix with yours |

The Stop hook only reads state and never runs repo code. It blocks at most 3 times per turn,
then lets the agent stop with `Status: BLOCKED`, so a broken gate can't loop forever.

## What stays human

- Approving the plan
- Commits, pushes, new packages, the dev server (the agent never touches them)
- The "Needs developer approval" list in every summary: new code patterns, env vars or
  sensitive data, DB migrations
- Manual QA: the agent maintains `docs/qa/manual-tests-todo.md`, a human runs it

## Layout

```
CLAUDE.md                           workflow rules (template: fill in your project bits)
.claude/
  settings.json                     hook wiring
  hooks/e2e-gate.sh                 the gate + Stop/PostToolUse/SubagentStop hooks
  hooks/setup-worktree.sh           worktree prep
  agents/code-reviewer.md           correctness + conventions reviewer
  agents/security-auditor.md        security reviewer
  rules/ts-rules.md                 example path-scoped rule (no `any`)
  skills/                           planning, incremental implementation, docs/ADRs, context
  references/                       performance + security checklists
```

## Install into a project

1. Copy `CLAUDE.md` and `.claude/` into the repo root (merge with what you have).
2. Edit the config block at the top of `.claude/hooks/e2e-gate.sh`: watched paths, code
   paths, typecheck/test commands, optional migration command.
3. Keep the `SubagentStop` matcher in `settings.json` in sync with the `reviewers` list.
4. Fill in the project sections of `CLAUDE.md` (stack, structure, commands, conventions).
5. Requires `bash`, `git`, `jq` and GNU coreutils. The lint step assumes ESLint; set
   `lint_ext_re=''` to turn it off.

## Credits

The skills in `.claude/skills/`, the checklists in `.claude/references/` and the
`security-auditor` agent (lightly adapted) come from Addy Osmani's
[agent-skills](https://github.com/addyosmani/agent-skills), MIT licensed. 

The hooks, the `code-reviewer` agent and the `CLAUDE.md` workflow are my own.
