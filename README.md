# make-release

Make a release by determining the next version, updating the version in the code/config, update sentry and push the release.

It builds on the command line tool for git flow:
https://nvie.com/posts/a-successful-git-branching-model/

## Requirements

* `git flow init` was run with `dev` and `main` as the development and production branches

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

## Tests

```
tests/next-version.sh
```

checks the versions `next` computes, in throwaway repositories. It needs only `git` and `bash`.

### Finish the release

Commit the change to the version file and any other release preparations.

```
make-release.sh finish
```

### Finalize the release

Push the release inclusing tags as well as finalize the release on sentry of a sentry slug is set

```
make-release.sh finalize
```
