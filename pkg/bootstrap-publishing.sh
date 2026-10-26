#!/bin/bash
# One-time setup for publishing the caelestia-plus pacman repo. Run it
# yourself (it creates a public repo and stores secrets):
#
#   bash ~/code/caelestia-plus/pkg/bootstrap-publishing.sh
#
# 1. creates the public repo moimart/caelestia-plus-packages and pushes the
#    README and signing key prepared in ~/code/caelestia-plus-packages
# 2. turns on GitHub Pages for its gh-pages branch
# 3. adds the CI deploy key to it, with write access
# 4. stores the signing key and the deploy key as secrets in
#    moimart/caelestia-plus, so its Packages workflow can sign and publish
# 5. starts that workflow
#
# The keys are in ~/.local/share/caelestia-plus/signing/ (keep a backup).

set -euo pipefail

keys=~/.local/share/caelestia-plus/signing
packages=moimart/caelestia-plus-packages
source=moimart/caelestia-plus

step() { printf '\n== %s\n' "$*"; }

step "Creating $packages (public)"
if gh repo view "$packages" >/dev/null 2>&1; then
    echo "already exists"
else
    gh repo create "$packages" --public \
        --description "pacman repo for caelestia-plus (built by CI, served by GitHub Pages)"
fi
cd ~/code/caelestia-plus-packages
git remote get-url origin >/dev/null 2>&1 || git remote add origin "git@github.com:$packages.git"
git push -u origin main

step "Seeding the gh-pages branch (CI replaces it on every build)"
if ! git ls-remote --exit-code origin gh-pages >/dev/null 2>&1; then
    tmp=$(mktemp -d)
    cp README.md caelestia-plus.asc "$tmp/"
    touch "$tmp/.nojekyll"
    git -C "$tmp" init -q -b gh-pages
    git -C "$tmp" add -A
    git -C "$tmp" commit -qm "Placeholder until the first CI build"
    git -C "$tmp" push -q "git@github.com:$packages.git" gh-pages
    rm -rf "$tmp"
fi

step "Turning on GitHub Pages (gh-pages branch)"
gh api "repos/$packages/pages" >/dev/null 2>&1 \
    || gh api -X POST "repos/$packages/pages" -f 'source[branch]=gh-pages' -f 'source[path]=/' >/dev/null
gh api "repos/$packages/pages" --jq '"Pages: " + .html_url'

step "Adding the CI deploy key to $packages (write access)"
gh repo deploy-key list -R "$packages" | grep -q "caelestia-plus CI" \
    || gh repo deploy-key add "$keys/deploy_key.pub" -R "$packages" --allow-write --title "caelestia-plus CI"

step "Storing the secrets in $source"
gh secret set PACKAGE_SIGNING_KEY -R "$source" < "$keys/private.asc"
gh secret set PACKAGES_DEPLOY_KEY -R "$source" < "$keys/deploy_key"
gh secret list -R "$source"

step "Starting the Packages workflow"
gh workflow run packages.yml -R "$source"
echo "Follow it with: gh run watch -R $source"
