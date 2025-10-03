#!/usr/bin/env bash
#
# git-bump-minor-and-tag.sh
#
# 1) Auto-stash current changes (if any)
# 2) Checkout main
# 3) Auto-pop the stash (if created)
# 4) git add/commit -m "updated submodule" (only if there are changes)
# 5) Find latest tag, bump MINOR (SemVer), reset PATCH to 0
# 6) Push branch and tag, then checkout the new tag
#
# Notes:
# - Expects tags like v1.2.3 or 1.2.3. If no tags exist, starts from v0.0.0 -> v0.1.0
# - Pushes to 'origin' and branch 'main' by default (override with env vars)
#   GIT_REMOTE=upstream GIT_BRANCH=master ./git-bump-minor-and-tag.sh
#

set -euo pipefail

GIT_REMOTE="${GIT_REMOTE:-origin}"
GIT_BRANCH="${GIT_BRANCH:-main}"

echo "==> Ensuring we’re in a Git repo..."
git rev-parse --is-inside-work-tree >/dev/null

current_branch="$(git symbolic-ref --short -q HEAD || echo 'DETACHED')"
echo "==> Current branch: $current_branch"

echo "==> Fetching latest from $GIT_REMOTE (including tags)..."
git fetch "$GIT_REMOTE" --tags --prune

# 1) Auto-stash current changes (if any)
echo "==> Checking for local modifications to stash..."
if ! git diff-index --quiet HEAD -- || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  stash_msg="auto-stash $(date '+%Y-%m-%d %H:%M:%S')"
  git stash push -u -m "$stash_msg"
  made_stash=1
  echo "==> Stashed changes: $stash_msg"
else
  made_stash=0
  echo "==> No changes to stash."
fi

# 2) Checkout main (or configured branch)
echo "==> Checking out $GIT_BRANCH..."
git checkout "$GIT_BRANCH"

# Make sure branch is up to date (optional but sensible)
echo "==> Rebase branch on $GIT_REMOTE/$GIT_BRANCH (fast-forward only)..."
git pull --rebase --ff-only "$GIT_REMOTE" "$GIT_BRANCH" || {
  echo "!! Could not fast-forward $GIT_BRANCH. Resolve manually and re-run."
  exit 1
}

# 3) Auto-pop stash (if it was created)
if [ "$made_stash" -eq 1 ]; then
  echo "==> Popping the stash back onto $GIT_BRANCH..."
  if ! git stash pop; then
    echo "!! Stash pop had conflicts. Resolve them, commit, then re-run from step 5."
    exit 1
  fi
else
  echo "==> No stash to pop."
fi

# 4) Auto git add & commit (only if there are changes)
echo "==> Adding changes..."
git add -A

if ! git diff --cached --quiet; then
  echo "==> Committing: \"updated submodule\""
  git commit -m "updated submodule"
else
  echo "==> No changes to commit."
fi

# 5) Determine latest tag and bump MINOR
echo "==> Determining latest tag..."
latest_tag="$(git tag --list | sort -V | tail -n 1 || true)"
if [ -z "$latest_tag" ]; then
  echo "==> No existing tags; defaulting to v0.0.0"
  latest_tag="v0.0.0"
fi
echo "==> Latest tag found: $latest_tag"

# Normalize: strip leading 'v' if present, parse M.m.p
tag_no_v="${latest_tag#v}"

# Accept formats like X.Y.Z (strict semver). If not semver, abort to be safe.
if [[ ! "$tag_no_v" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "!! Latest tag '$latest_tag' is not SemVer (X.Y.Z or vX.Y.Z). Aborting."
  exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
# patch="${BASH_REMATCH[3]}"  # not needed; reset to 0

new_minor=$((minor + 1))
new_tag="v${major}.${new_minor}.0"

echo "==> New tag will be: $new_tag"

# Create an annotated tag
git tag -a "$new_tag" -m "Release $new_tag"

# 6) Push branch and tag, then checkout the new tag
echo "==> Pushing branch '$GIT_BRANCH' to $GIT_REMOTE..."
git push "$GIT_REMOTE" "$GIT_BRANCH"

echo "==> Pushing tag '$new_tag' to $GIT_REMOTE..."
git push "$GIT_REMOTE" "$new_tag"

echo "==> Checking out the new tag (detached HEAD): $new_tag"
git checkout "$new_tag"

echo "✅ Done."