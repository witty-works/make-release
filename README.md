# make-release

Make a release by determining the next version, updating the version in the code/config, update sentry and push the release.

It builds on the command line tool for git flow:
https://nvie.com/posts/a-successful-git-branching-model/

## Requirements

* `git flow init` was run with `dev` and `main` as the development and production branches
* the GitHub CLI `gh`, signed in with an account that can open and merge pull requests and push tags
* the repository allows merge commits for pull requests

## Configuration

Put this file into your PATH.

Note: Best is to create a symlink to make it easy to keep the file updated.

```
sudo ln -s [ABSOLUTE_PATH]/make-release/make-release.sh /usr/local/bin/make-release.sh
```

Add a "make-release" file into each repository where you want to use make-release.sh with the following contents:

* line 1 (version file name): The file name where the version number is tracked (comma separated list)
* line 2 (sentry organization): Name of the sentry organization, keep empty of sentry is not used
* line 3 (sentry slug): Name of the sentry slug (`sentry-cli projects -o [organization name] list`), keep empty of sentry is not used
* line 4 (build command): Command to run to build the project, keep empty if sourcemaps are not uploaded during tagging
* line 5 (build path): Relative path for where the build command geneerates the .map files

fe.

```
app/main.py
foo-bar
nlp-api
npm run build
./dist
```

## Usage

### Start the branch

This starts a branch, updates the version file and creates the sentry release if sentry slug is set

To start a major release

```
make-release.sh major
```

To start a minor release

```
make-release.sh minor
```

To start a patch release

```
make-release.sh patch
```

To start a hotfix, from `main`

```
make-release.sh hotfix
```

### Release candidates

A release candidate is tagged `x.y.z-rcN`. The first one names the release it leads to; each later one counts on:

```
make-release.sh rc major   # after 1.42.9: release/2.0.0-rc1
make-release.sh rc         # after 2.0.0-rc1: release/2.0.0-rc2
make-release.sh major      # after 2.0.0-rc2: release/2.0.0, the release itself
```

`finish` and `finalize` work as for a release. `major`, `minor`, `patch` and `hotfix` always count from the last release, not from a candidate.

To see which version a command would start, without changing anything:

```
make-release.sh next rc major
```

The tags are sorted by version, with a release after its candidates, whatever `tag.sort` is set to. Tags in other forms (`v3`, `1.42.9.1`) are left out.

### Finish the release

Commit the change to the version file and any other release preparations, then, on the release or hotfix branch:

```
make-release.sh finish
```

This pushes the branch and opens a pull request into `main`; it merges nothing itself. `main` can then require a pull request and passing checks, for administrators too, without needing a second person to approve: the pull request needs no approval, only the checks.

Merge the pull request on GitHub once the checks pass, **with a merge commit**. A squash or rebase merge leaves the release's commits off `main`, and `finalize` refuses it.

### Finalize the release

Still on the release or hotfix branch:

```
make-release.sh finalize
```

This checks that the pull request is merged, tags the merge commit (the editor opens for the tag message, for instance to add the milestone URL), pushes the tag, merges the tag into `dev` and pushes `dev`, and deletes the local branch. If a sentry slug is set, it also finalizes the release on sentry.

If merging into `dev` conflicts, `finalize` stops after pushing the tag: resolve the conflict, commit, push `dev`, and finalize the sentry release by hand.

## Tests

```
tests/next-version.sh
tests/finish-finalize.sh
```

`next-version.sh` checks the versions `next` computes, and `finish-finalize.sh` runs `finish` and `finalize` against a throwaway origin with a stand-in for `gh`. Both use throwaway repositories and need only `git` and `bash`.
