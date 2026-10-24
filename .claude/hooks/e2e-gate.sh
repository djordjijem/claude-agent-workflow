#!/usr/bin/env bash
# Milestone gate for Claude Code. See "Review Handoff" in CLAUDE.md.
#
#   e2e-gate.sh run            Claude runs this at milestone end: typecheck, lint (new errors
#                              only), optional migration check, full test suite. Records a
#                              fingerprint of the code that passed.
#   e2e-gate.sh mark-edit      PostToolUse (Edit|Write|NotebookEdit): remembers that Claude
#                              edited code in the current turn.
#   e2e-gate.sh record-review  SubagentStop (reviewer agents): records that a reviewer finished.
#   e2e-gate.sh check          Stop hook (never executes repo code, only reads state):
#                              - turn edited code but ends without a milestone heading → block
#                              - "## Milestone N/M complete" / "## Review Summary" → all
#                                reviewers must have run since the milestone started, and the
#                                code must match the last green `run` → else block.
#                                "Status: BLOCKED" summaries pass through.
#
# Requires: bash, git, jq, sha1sum, realpath (GNU coreutils).
set -uo pipefail
umask 077

# ---- Config: adapt to your project ------------------------------------------------------
# Paths whose changes invalidate a green run.
watched=(src spec package.json package-lock.json tsconfig.json eslint.config.mjs)
# Edits under these paths count as "Claude changed code" and start the milestone flow.
code_paths_re='^(src|spec)/'
# Reviewer agents that must run every milestone (names from .claude/agents/*.md). Keep the
# SubagentStop matcher in settings.json in sync with this list.
reviewers=(code-reviewer security-auditor)
typecheck_cmd=(npx --no-install tsc --noEmit -p .)
test_cmd=(npm test)
# Lines from the test log quoted in the PASSED message (the agent copies them into its summary).
test_result_re='[0-9]+ (specs|tests), [0-9]+ failures|passed'
# Lint only files with these extensions. Empty disables the lint step.
lint_ext_re='\.(ts|tsx)$'
# Optional migration check: runs only when files under migration_paths changed.
# Example: migration_cmd='npx prisma validate && npx prisma migrate diff --exit-code ...'
migration_paths=()
migration_cmd=''
# Gitignored files that still affect test results (hashed into the fingerprint).
untracked_inputs_glob='env/*.env'
# ------------------------------------------------------------------------------------------

mode="${1:-}"

# Hook modes get JSON on stdin; use its cwd so worktree sessions gate their own checkout.
input=""
[[ "$mode" != "run" ]] && input=$(cat)
if [[ "$mode" == "run" ]]; then
  repo_dir=.
else
  repo_dir=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
  repo_dir="${repo_dir:-${CLAUDE_PROJECT_DIR:-.}}"
fi
if ! toplevel=$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null); then
  echo "e2e-gate: $repo_dir is not a git checkout, skipping" >&2
  exit 0
fi
cd "$toplevel" || exit 0
state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-e2e-gate/$(pwd | sha1sum | cut -c1-12)"
mkdir -p "$state_dir"
last_green="$state_dir/last-green"
log="$state_dir/last-run.log"

fingerprint() {
  {
    git diff HEAD -- "${watched[@]}"
    git ls-files -z -o --exclude-standard -- "${watched[@]}" | sort -z | xargs -0r sha1sum
    # shellcheck disable=SC2086 # the glob is meant to expand
    [[ -n "$untracked_inputs_glob" ]] && sha1sum $untracked_inputs_glob 2>/dev/null
  } | sha1sum | cut -d' ' -f1
}

# Files Claude edited during the current task (written by mark-edit, cleared when a
# Review Summary passes). The developer's own in-progress work is never linted.
edited_files="$state_dir/edited-files"

# Blocks only on NEW lint errors in Claude-edited files that still exist: new files must be
# clean, modified files must not have more errors than their HEAD version. This lets the gate
# work in codebases with a backlog of old lint errors.
lint_gate() {
  local files=() file before after failed=0 report
  [[ -n "$lint_ext_re" && -f "$edited_files" ]] || return 0
  while IFS= read -r file; do
    [[ "$file" =~ $lint_ext_re && -f "$file" ]] && files+=("$file")
  done < <(sort -u "$edited_files")
  ((${#files[@]} == 0)) && return 0

  report=$(npx --no-install eslint -f json -- "${files[@]}" 2>/dev/null)
  if ! jq -e 'type == "array"' <<<"$report" >/dev/null 2>&1; then
    echo "  eslint failed to run: npx eslint ${files[*]}"
    return 1
  fi
  for file in "${files[@]}"; do
    after=$(jq --arg f "$PWD/$file" '[.[] | select(.filePath == $f) | .errorCount] | add // 0' \
      <<<"$report")
    before=0
    if git cat-file -e "HEAD:$file" 2>/dev/null; then
      # eslint exits 1 when the file has errors; with pipefail that would fail the whole
      # pipeline, so its exit code is ignored and jq decides whether the output is valid.
      before=$({ git show "HEAD:$file" | npx --no-install eslint -f json --stdin --stdin-filename "$file" \
        2>/dev/null || true; } | jq -e '[.[].errorCount] | add // 0' 2>/dev/null) || {
        echo "  eslint failed to run on HEAD:$file"
        return 1
      }
    fi
    ((after > before)) || continue
    echo "  $file: $before → $after lint errors"
    jq -r --arg f "$PWD/$file" '.[] | select(.filePath == $f) | .messages[]
      | select(.severity == 2) | "    \(.line):\(.column) \(.message) (\(.ruleId))"' \
      <<<"$report" | head -n 15
    failed=1
  done
  return $failed
}

# Migration checks, only when migration files changed. Worth having when tests can't catch a
# broken migration (e.g. the ORM auto-creates tables in the test DB).
migration_gate() {
  local changed
  [[ -n "$migration_cmd" && ${#migration_paths[@]} -gt 0 ]] || return 0
  changed=$({
    git diff HEAD --name-only -- "${migration_paths[@]}"
    git ls-files -o --exclude-standard -- "${migration_paths[@]}"
  })
  [[ -z "$changed" ]] && return 0
  if ! bash -c "$migration_cmd" >>"$log" 2>&1; then
    echo "  migration check failed:"
    tail -n 20 "$log" | redact
    return 1
  fi
}

# Log tails get echoed into Claude's transcript: mask anything secret-looking.
redact() {
  sed -E 's/((password|passwd|token|secret|api[_-]?key)[^:=]{0,20}[:=]["'\'' ]*)[^,"'\'' ]+/\1<redacted>/Ig'
}

# Runs the whole gate. Returns 0 on success and records the green fingerprint.
run_gate() {
  local current lint_output migration_output
  current=$(fingerprint)
  : >"$log"

  if ! "${typecheck_cmd[@]}" >"$log" 2>&1; then
    echo "E2E gate: typecheck FAILED."
    tail -n 40 "$log" | redact
    return 1
  fi
  if ! lint_output=$(lint_gate); then
    echo "E2E gate: NEW lint errors in changed files:"
    echo "$lint_output"
    return 1
  fi
  if ! migration_output=$(migration_gate); then
    echo "E2E gate: migration checks FAILED:"
    echo "$migration_output"
    return 1
  fi
  if ! "${test_cmd[@]}" >"$log" 2>&1; then
    echo "E2E gate: full test suite FAILED. Full log: $log"
    tail -n 60 "$log" | redact
    return 1
  fi
  echo "$current" >"$last_green"
  echo "E2E gate: PASSED (typecheck clean, no new lint errors, migrations ok)"
  grep -E "$test_result_re" "$log" | tail -n 5
  return 0
}

if [[ "$mode" == "run" ]]; then
  run_gate
  exit $?
fi

session_id=$(jq -r '.session_id // "default"' <<<"$input")
session_dir="$state_dir/sessions/$session_id"
mkdir -p "$session_dir"

case "$mode" in
mark-edit)
  file=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")
  [[ -n "$file" && "$file" != *$'\n'* ]] || exit 0
  file=$(realpath -m --relative-to="$PWD" -- "$file")
  [[ "$file" =~ $code_paths_re && "$file" != *..* ]] || exit 0
  echo "$file" >>"$edited_files"
  turn=$(jq -r '.prompt_id // empty' <<<"$input")
  [[ -n "$turn" ]] && echo "$turn" >"$session_dir/edited-turn"
  # Start of a task: reviews must happen after this point.
  [[ -f "$session_dir/task-start" ]] || date +%s >"$session_dir/task-start"
  exit 0
  ;;
record-review)
  agent=$(jq -r '.agent_type // ""' <<<"$input")
  for reviewer in "${reviewers[@]}"; do
    [[ "$agent" == "$reviewer" ]] && date +%s >"$session_dir/reviewed-$agent"
  done
  exit 0
  ;;
check) ;;
*)
  echo "usage: e2e-gate.sh run|check|mark-edit|record-review" >&2
  exit 0
  ;;
esac

# ---- Stop hook ----
prompt_id=$(jq -r '.prompt_id // empty' <<<"$input")
last_message=$(jq -r '.last_assistant_message // ""' <<<"$input")

# Loop protection: block at most max_blocks times per turn, then let Claude stop. The
# blocks are a real gate (every Stop is re-verified), not a one-shot reminder.
max_blocks=3
blocks_file="$session_dir/blocks-${prompt_id:-none}"
block() {
  local count
  count=$(($(cat "$blocks_file" 2>/dev/null || echo 0) + 1))
  echo "$count" >"$blocks_file"
  if ((count > max_blocks)); then
    echo "e2e-gate: blocked $max_blocks times this turn, letting the turn end. The task is NOT
verified: the summary must say Status: BLOCKED." >&2
    exit 0
  fi
  echo "$1" >&2
  exit 2
}

has_heading=0
grep -qE '^#+ *(Milestone [0-9]+(/[0-9]+)? complete|Review Summary)' <<<"$last_message" &&
  has_heading=1

if ((has_heading == 0)); then
  [[ -n "$prompt_id" && -f "$session_dir/edited-turn" &&
    "$(cat "$session_dir/edited-turn")" == "$prompt_id" ]] || exit 0
  block "You edited code this turn but didn't finish the milestone flow. Finish the
current milestone (reviews, gate) and end with '## Milestone N/M complete: <name>' or
'## Review Summary', or end with '## Review Summary' and 'Status: BLOCKED (<reason>)'."
fi

grep -qE '^\**Status:?\** *BLOCKED' <<<"$last_message" && exit 0

if [[ -f "$session_dir/task-start" ]]; then
  task_start=$(cat "$session_dir/task-start")
  missing=()
  for agent in "${reviewers[@]}"; do
    reviewed="$session_dir/reviewed-$agent"
    [[ -f "$reviewed" && "$(cat "$reviewed")" -ge "$task_start" ]] || missing+=("$agent")
  done
  ((${#missing[@]} == 0)) || block "Milestone claimed complete, but these reviewers haven't run
since the task started (or since the last milestone that passed): ${missing[*]}. Run them on the
milestone's changed files, fix findings, re-run the gate, then post the heading again."
fi

# The hook only compares state; the gate itself runs via `bash .claude/hooks/e2e-gate.sh run`
# so the typecheck/tests go through Claude Code's normal Bash permissions.
if [[ ! -f "$last_green" || "$(cat "$last_green")" != "$(fingerprint)" ]]; then
  block "Milestone claimed complete, but there's no green gate run for the current code (it
changed after the last passing run, or the gate was never run / failed). Run
'bash .claude/hooks/e2e-gate.sh run', fix any failure, then post the heading again. If it
can't pass, report Status: BLOCKED."
fi

# Passed. A finished task clears its state; a passed milestone resets the review baseline
# so the next milestone needs its own reviews.
rm -f "$session_dir"/reviewed-* "$session_dir"/blocks-*
if grep -qE '^#+ *Review Summary' <<<"$last_message"; then
  rm -f "$session_dir/task-start" "$session_dir/edited-turn" "$edited_files"
else
  date +%s >"$session_dir/task-start"
fi
exit 0
