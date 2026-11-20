#!/bin/sh
# Xcode Cloud post-clone hook: fetch the Git LFS objects (snapshot reference images).
# Without this the checkout contains LFS pointer text files instead of PNGs.
set -eu

cd "${CI_PRIMARY_REPOSITORY_PATH:-$(git rev-parse --show-toplevel)}"

if ! command -v git-lfs >/dev/null 2>&1; then
    brew install git-lfs
fi

git lfs install --local
git lfs pull

# Fail early with a clear message if any reference image is still a pointer file.
if grep -rl "^version https://git-lfs" Snapshots >/dev/null 2>&1; then
    echo "error: Snapshots still contains Git LFS pointer files after 'git lfs pull'." >&2
    exit 1
fi
