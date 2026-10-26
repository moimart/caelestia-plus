#!/bin/bash
# Removes the private files from every commit, before the repo goes public:
# the face video, the Home Assistant card config (lock-ha.json, with the
# home's address and entities) and the lock screen screenshot's old versions
# (they show those entities) and a widgets clip that ended on the lock screen,
# at every path they ever had. The screenshot's
# current version, with the cards blurred, is committed back afterwards, as
# is this script's (an older version named the address).
#
#   tools/purge-private-history.sh [--push]
#
# Works on a fresh clone in ~/.cache/caelestia-plus-purge and checks the
# result; --push then force-pushes it over origin's main and tags.
#
# Afterwards, don't `git subtree pull` from the old dotfiles repo again: its
# history still has these files and would bring them back.

set -euo pipefail

src=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
work=~/.cache/caelestia-plus-purge
private='face\.mp4$|lock-ha\.json$|docs/screenshots/lock\.jpg$|docs/screenshots/widgets\.webp$|tools/purge-private-history\.sh$'
keep=(shell/docs/screenshots/lock.jpg tools/purge-private-history.sh)
# The home's address, to check none is left (read here, never written down)
cards=~/code/caelestia-plus-private/personal/caelestia/lock-ha.json
address=$(python3 -c 'import json,sys,urllib.parse; print(urllib.parse.urlparse(json.load(open(sys.argv[1]))["url"]).hostname)' "$cards" 2>/dev/null || true)

rm -rf "$work"
git clone -q --no-local "$src" "$work"
cd "$work"
git fetch -q --tags "$src"

saved=$(mktemp -d)
for f in "${keep[@]}"; do
    mkdir -p "$saved/$(dirname "$f")"
    git show "HEAD:$f" > "$saved/$f"
done

echo "== Before: private files in history"
git log --all --format= --name-only | sort -u | grep -E "$private" || echo "(none)"

FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f --prune-empty \
    --index-filter "git ls-files -z | grep -zE '$private' | xargs -0r git rm -q --cached --ignore-unmatch" \
    --tag-name-filter cat -- --all >/dev/null

# Drop the backup refs and everything only they still reached
git for-each-ref --format='%(refname)' refs/original | xargs -r -n1 git update-ref -d
git reflog expire --expire=now --all
git gc -q --prune=now --aggressive

# The current versions back
for f in "${keep[@]}"; do
    mkdir -p "$(dirname "$f")"
    cp -p "$saved/$f" "$f"
    git add "$f"
done
git -c user.name="$(git -C "$src" config user.name)" -c user.email="$(git -C "$src" config user.email)" \
    commit -qm "The lock screen screenshot (Home Assistant cards blurred) and the history purge script"
rm -rf "$saved"

echo "== After: private files in history"
left=$(git log --all --format= --name-only | sort -u | grep -E "$private" | grep -vxF -f <(printf '%s\n' "${keep[@]}") || true)
# Only the newest commit may have the kept files
for f in "${keep[@]}"; do
    [ "$(git log --all --format=%h -- "$f" | wc -l)" = 1 ] || left="$left $f (older versions)"
done
addr=
[ -n "$address" ] && addr=$(git log --all -S"$address" --format=%h || true)
[ -n "$address" ] || echo "(couldn't read the home's address from $cards; not checked)"
if [ -n "$left" ] || [ -n "$addr" ]; then
    echo "still there: $left $addr" >&2
    exit 1
fi
echo "(none) - $(git rev-list --count HEAD) commits, $(du -sh .git | cut -f1)"

if [ "${1:-}" = --push ]; then
    url=$(git -C "$src" remote get-url origin)
    git push --force "$url" main
    git push --force --tags "$url"
    echo "Pushed. Re-clone your working copy (or reset it to origin/main): its old history still has the files."
fi
