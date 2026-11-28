#!/bin/bash
# Checks `make-release.sh finish` and `finalize` against a throwaway origin,
# with a stand-in for the GitHub CLI: finish opens a pull request into main
# instead of merging, and finalize tags the merge and brings it into dev.
# Needs only git and bash.
#
#   tests/finish-finalize.sh

set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/make-release.sh"
FAILED=0
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $1"; FAILED=1; }

git() { command git -c user.name=t -c user.email=t@example.invalid -c init.defaultBranch=main "$@"; }
export -f git

# The stand-in `gh`: `pr create` records its arguments; `pr view` answers
# with the state and merge commit the test wrote to $WORK/pr.
mkdir "$WORK/bin"
cat > "$WORK/bin/gh" <<'GH'
#!/bin/bash
case "$1 $2" in
    "pr create") printf '%s\n' "$@" > "$GH_LOG"; echo "https://github.example/pr/1";;
    "pr view") cat "$GH_PR";;
    "repo view") echo "example-gh/example-repo";;
    *) echo "unexpected gh $*" >&2; exit 1;;
esac
GH
chmod +x "$WORK/bin/gh"
# The stand-in `sentry-cli` records each call.
printf '#!/bin/bash\necho "$*" >> "$SENTRY_LOG"\n' > "$WORK/bin/sentry-cli"
chmod +x "$WORK/bin/sentry-cli"
export SENTRY_LOG="$WORK/sentry.log"
export PATH="$WORK/bin:$PATH" GH_LOG="$WORK/gh.log" GH_PR="$WORK/pr" GIT_EDITOR=true

# An origin with main and dev at 1.42.9, and a clone on release/2.0.0-rc1.
git init -q --bare "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/clone" 2>/dev/null
cd "$WORK/clone"
# A Sentry organisation and project whose names differ from GitHub's.
printf '\nexample-sentry-org\nexample-project\n' > make-release
git add make-release && git commit -q -m init
git tag -a 1.42.9 -m 1.42.9
git branch dev
git push -q origin main dev --tags
git checkout -q -b release/2.0.0-rc1 dev
git commit -q --allow-empty -m "Prepare 2.0.0-rc1"

# finish refuses uncommitted changes.
echo change >> make-release
"$SCRIPT" finish > "$WORK/out" 2>&1 && fail "finish ran with uncommitted changes"
command git checkout -q make-release

# finish pushes the branch and opens a pull request into main; it merges
# nothing.
"$SCRIPT" finish > "$WORK/out" 2>&1 || { fail "finish exited non-zero: $(tail -n 3 "$WORK/out")"; }
git ls-remote --exit-code origin refs/heads/release/2.0.0-rc1 > /dev/null || fail "finish did not push the branch"
grep -qx -- '--base' "$GH_LOG" && grep -qx main "$GH_LOG" || fail "finish did not open a pull request into main"
[ "$(git rev-parse origin/main)" = "$(git rev-parse main)" ] || fail "finish changed main"
git rev-parse -q --verify refs/tags/2.0.0-rc1 > /dev/null && fail "finish created the tag"

# finalize waits for the merge.
echo "OPEN " > "$GH_PR"
"$SCRIPT" finalize > "$WORK/out" 2>&1 && fail "finalize ran before the pull request was merged"
git rev-parse -q --verify refs/tags/2.0.0-rc1 > /dev/null && fail "finalize tagged an unmerged release"

# finalize refuses a squash merge: the release's commits are not on main.
git clone -q "$WORK/origin.git" "$WORK/github" 2>/dev/null
(
    cd "$WORK/github"
    git checkout -q -b squashed origin/main
    git merge -q --squash origin/release/2.0.0-rc1 > /dev/null 2>&1
    git commit -q --allow-empty -m "Squashed 2.0.0-rc1"
    echo "MERGED $(git rev-parse HEAD)" > "$GH_PR"
    git push -q origin squashed
)
"$SCRIPT" finalize > "$WORK/out" 2>&1 && fail "finalize accepted a squash merge"
grep -q "merge commit" "$WORK/out" || fail "finalize did not say a merge commit is needed: $(tail -n 2 "$WORK/out")"

# The pull request is merged with a merge commit on GitHub.
(
    cd "$WORK/github"
    git checkout -q main
    git merge -q --no-ff -m "Merge pull request #1 from release/2.0.0-rc1" origin/release/2.0.0-rc1
    echo "MERGED $(git rev-parse HEAD)" > "$GH_PR"
    git push -q origin main
)
# Meanwhile dev moved on.
(
    cd "$WORK/github"
    git checkout -q -b dev origin/dev
    git commit -q --allow-empty -m "Work on dev"
    git push -q origin dev
)
MERGE=$(cut -d' ' -f2 "$GH_PR")

"$SCRIPT" finalize > "$WORK/out" 2>&1 || fail "finalize exited non-zero: $(tail -n 3 "$WORK/out")"
[ "$(git ls-remote origin refs/tags/2.0.0-rc1^{} | cut -f1)" = "$MERGE" ] || fail "the pushed tag is not on the merge commit"
[ "$(git cat-file -t 2.0.0-rc1 2>/dev/null)" = tag ] || fail "the tag is not annotated"
git fetch -q origin
git merge-base --is-ancestor "$MERGE" origin/dev || fail "dev does not contain the release"
git log --format=%s origin/dev | grep -qx "Work on dev" || fail "dev lost its own work"
[ "$(git branch --show-current)" = dev ] || fail "finalize did not leave the clone on dev"

if [ "$FAILED" = 0 ]; then echo "All finish/finalize checks passed."; fi
exit "$FAILED"
