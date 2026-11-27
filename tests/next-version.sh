#!/bin/bash
# Checks the versions `make-release.sh next` computes, in a throwaway
# repository with the given tags. Needs only git and bash.
#
#   tests/next-version.sh

set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/make-release.sh"
FAILED=0

# expect "<tags, oldest first>" "<arguments>" "<expected version or ERROR>"
expect() {
    local repo
    repo=$(mktemp -d)
    (
        cd "$repo"
        git init -q
        git -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
        for tag in $1; do git tag "$tag"; done
        printf '\n\n\n' > make-release
        # Not the global setting the README asks for: the script must sort
        # on its own.
        git config tag.sort refname
        "$SCRIPT" next $2 2>&1 | tail -n 1
    ) > "$repo.out"
    local got
    got=$(cat "$repo.out")
    rm -rf "$repo" "$repo.out"
    if [ "$3" = ERROR ]; then
        if [[ "$got" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
            echo "FAIL: [$1] next $2: expected an error, got '$got'"; FAILED=1
        fi
    elif [ "$got" != "$3" ]; then
        echo "FAIL: [$1] next $2: expected '$3', got '$got'"; FAILED=1
    fi
}

expect "1.42.8 1.42.9" "major" "2.0.0"
expect "1.42.8 1.42.9" "minor" "1.43.0"
expect "1.42.8 1.42.9" "patch" "1.42.10"
expect "1.42.8 1.42.9" "hotfix" "1.42.10"
# A first release candidate names the release it leads to.
expect "1.42.9" "rc major" "2.0.0-rc1"
expect "1.42.9" "rc minor" "1.43.0-rc1"
expect "1.42.9" "rc patch" "1.42.10-rc1"
# The next one counts on.
expect "1.42.9 2.0.0-rc1" "rc" "2.0.0-rc2"
expect "1.42.9 2.0.0-rc1 2.0.0-rc2" "rc" "2.0.0-rc3"
expect "1.42.9 2.0.0-rc1" "rc major" "2.0.0-rc2"
# After candidates, the release itself; bumps count from the last release.
expect "1.42.9 2.0.0-rc1 2.0.0-rc2" "major" "2.0.0"
expect "1.42.9 2.0.0-rc1 2.0.0" "patch" "2.0.1"
expect "1.42.9 2.0.0-rc1 2.0.0" "rc minor" "2.1.0-rc1"
# Version order, not text order: 10 after 9, a release after its candidates.
expect "1.9.0 1.10.0" "patch" "1.10.1"
expect "2.0.0-rc9 2.0.0-rc10" "rc" "2.0.0-rc11"
# Without a candidate to continue, rc needs to know which release.
expect "1.42.9" "rc" "ERROR"
expect "1.42.9 2.0.0-rc1 2.0.0" "rc" "ERROR"
# Tags in other forms are left out.
expect "1.42.9 1.42.9.1 v3 latest" "patch" "1.42.10"

if [ "$FAILED" = 0 ]; then echo "All next-version checks passed."; fi
exit "$FAILED"
