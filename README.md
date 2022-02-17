# make-release

Make a release by determining the next version, updating the version in the code/config, update sentry and push the release.

It builds on the command line tool for git flow:
https://nvie.com/posts/a-successful-git-branching-model/

## Requirements

* `git flow init` was run with `dev` and `main` as the development and production branches
* run `git config --global tag.sort -version:refname`

## Configuration

Put this file into your PATH.

Note: Best is to create a symlink to make it easy to keep the file updated.

```
sudo ln -s [ABSOLUTE_PATH]/make-release/make-release.sh /usr/local/bin/make-release.sh
```

Add a "make-release" file into each repository where you want to use make-release.sh with the following contents:

* line 1 (version file name): The file name where the version number is tracked
* line 2 (sentry organization): Name of the sentry organization, keep empty of sentry is not used
* line 3 (sentry slug): Name of the sentry slug (`sentry-cli projects -o [organization name] list`), keep empty of sentry is not used

fe.

```
app/main.py
foo-bar
nlp-api
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
