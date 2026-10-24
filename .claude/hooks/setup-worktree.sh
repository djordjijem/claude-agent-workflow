#!/usr/bin/env bash
# Prepares a git worktree (e.g. one made by Claude's EnterWorktree under .claude/worktrees/)
# to build and test: links node_modules and copies gitignored env files from the main
# checkout. Run from inside the worktree.
set -euo pipefail

# ---- Config: exact list of gitignored files the worktree needs (never globs) ----
secrets=(env/development.env env/test.env)
exclude_patterns=('env/*.env')
# ---------------------------------------------------------------------------------

worktree=$(git rev-parse --show-toplevel)
main=$(git worktree list --porcelain | sed -n 's/^worktree //p' | head -n 1)
[[ -n "$main" && -d "$main/.git" ]] || { echo "Can't find the main checkout."; exit 1; }
[[ "$worktree" == "$main" ]] && { echo "Run this inside a worktree, not the main checkout."; exit 1; }

# Shared node_modules is fine while package.json matches. If the task changes
# dependencies, replace the link with a real `npm ci` in the worktree.
[[ -L "$worktree/node_modules" || -e "$worktree/node_modules" ]] ||
  ln -s "$main/node_modules" "$worktree/node_modules"

# The worktree's branch may have an older .gitignore, so make sure the secrets we copy can
# never be committed from it: add them to the repo-wide exclude file (shared by all worktrees).
exclude="$(git rev-parse --git-common-dir)/info/exclude"
mkdir -p "$(dirname "$exclude")"
for pattern in "${exclude_patterns[@]}"; do
  grep -qxF "$pattern" "$exclude" 2>/dev/null || echo "$pattern" >>"$exclude"
done

# Exact allowlist (never globs: a future prod-*.env must not leak into a worktree).
for file in "${secrets[@]}"; do
  [[ -f "$main/$file" && ! -e "$worktree/$file" ]] || continue
  dir=$(dirname "$file")
  if [[ -L "$worktree/$dir" ]]; then
    echo "refusing to copy $file: $dir is a symlink in the worktree"
    exit 1
  fi
  if ! git -C "$worktree" check-ignore -q "$file"; then
    echo "refusing to copy $file: it isn't gitignored in the worktree"
    exit 1
  fi
  mkdir -p "$worktree/$dir"
  install -m 600 "$main/$file" "$worktree/$file"
  echo "copied $file"
done
echo "Worktree ready: $worktree"
echo "Note: the worktree uses the same test DB as the main checkout. Don't run test"
echo "suites in both at the same time."
