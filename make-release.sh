#!/bin/bash

set -e;

# x.y.z for a release, x.y.z-rcN for a release candidate.
VERSION_REGEXP='([0-9]+)\.([0-9]+)\.([0-9]+)(-rc([0-9]+))?';

VERSION_FILENAMES=$(sed -n '1p' make-release)
SENTRY_ORG=$(sed -n '2p' make-release)
SENTRY_SLUG=$(sed -n '3p' make-release)
BUILD_COMMAND=$(sed -n '4p' make-release)
BUILD_PATH=$(sed -n '5p' make-release)

Help()
{
   # Display Help
   echo "Make a release."
   echo
   echo "Syntax: make-release.sh [-h] [major|minor|patch|hotfix|rc [major|minor|patch]|finish|finalize]"
   echo "       make-release.sh next <mode>   print the version <mode> would start, and change nothing"
   echo "options:"
   echo "-h   Output the help information"
   echo
}

# The version tags, newest first, by version: 1.10.0 after 1.9.0, and a
# release after its candidates (2.0.0 after 2.0.0-rc2). Tags in other forms
# are left out.
VersionTags()
{
    git -c versionsort.suffix=-rc tag --sort=-version:refname | grep -E "^$VERSION_REGEXP$" || true;
}

# Sets VERSION to the version MODE (major|minor|patch|hotfix|rc) starts. A
# release candidate takes the release it leads to as BUMP (major|minor|patch)
# for its first candidate, and counts on from the latest one without it.
# Bumps count from the last release, not from a candidate.
NextVersion()
{
    local MODE=$1 BUMP=$2 TAGS LAST_RELEASE LATEST;
    TAGS=$(VersionTags);
    LAST_RELEASE=$(echo "$TAGS" | grep -vE -- '-rc[0-9]+$' | head -n 1);
    LATEST=$(echo "$TAGS" | head -n 1);

    if [ "$MODE" = "rc" ] && [ -z "$BUMP" ];
    then
        if [[ ! $LATEST =~ ^$VERSION_REGEXP$ ]] || [ -z "${BASH_REMATCH[5]}" ];
        then
            echo "There is no release candidate to continue; start one with 'rc major', 'rc minor' or 'rc patch'." >&2;
            return 1;
        fi
        VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}-rc$((BASH_REMATCH[5] + 1))";
        return 0;
    fi

    if [[ ! $LAST_RELEASE =~ ^$VERSION_REGEXP$ ]];
    then
        echo "There is no release tag in the format x.y.z to count from." >&2;
        return 1;
    fi

    local -i MAJOR=${BASH_REMATCH[1]} MINOR=${BASH_REMATCH[2]} PATCH=${BASH_REMATCH[3]};

    case ${BUMP:-$MODE} in
        major) MAJOR+=1; MINOR=0; PATCH=0;;
        minor) MINOR+=1; PATCH=0;;
        patch|hotfix) PATCH+=1;;
        *) echo "Unknown release type '${BUMP:-$MODE}'." >&2; return 1;;
    esac

    VERSION="$MAJOR.$MINOR.$PATCH";

    if [ "$MODE" = "rc" ];
    then
        # Counts on from an earlier candidate for the same release.
        local -i RC=1;
        local PREV_RC;
        PREV_RC=$(echo "$TAGS" | grep -E "^${VERSION//./\\.}-rc[0-9]+$" | head -n 1);
        if [ -n "$PREV_RC" ];
        then
            RC=${PREV_RC##*-rc}+1;
        fi
        VERSION="$VERSION-rc$RC";
    fi
}

echo "Updating version files: $VERSION_FILENAMES";

if [ ! -z "$SENTRY_ORG" ]
then
    if [ ! -z "$SENTRY_SLUG" ]
    then
            echo "Updating sentry release for project '$SENTRY_SLUG' on '$SENTRY_ORG' organization.";

            if [ ! -z "$BUILD_COMMAND" ]
            then
                if [ ! -z "$BUILD_PATH" ]
                then
                        echo "Generating sourcemaps after building '$BUILD_COMMAND' into '$BUILD_PATH'.";
                fi
            elif [ ! -z "$BUILD_PATH" ]
            then
                echo "Please either add a build command into the 4th line or remove the build path '$BUILD_PATH' from the 5th line.";

                exit;
            else
                echo "Not updating sourcemaps to sentry since there is no build command and build path set.";
            fi

    fi
elif [ ! -z "$SENTRY_SLUG" ]
then
    echo "Please either add a sentry org into the 2nd line or remove the sentry project '$SENTRY_SLUG' from the 3rd line.";

    exit;
else
    echo "Not updating sentry since there is no sentry organization set.";
fi

while getopts "hr:" opt; do
    case ${opt} in
    h )
        Help
        exit 1
        ;;
    esac
done

case $1 in
    next)
        NextVersion "$2" "${3:-}";
        echo "$VERSION";
    ;;

    major|minor|patch|hotfix|rc)
        MODE=$1;
        # Fails before anything is checked out or started.
        NextVersion "$MODE" "${2:-}";
        echo "Preparing '$MODE' updating dev/main";
        git checkout dev;
        git pull --rebase;
        git checkout main;
        git pull --rebase;

        # Again, with the tags the pull brought.
        NextVersion "$MODE" "${2:-}";

        # The version the version files hold: the latest tag, a release
        # candidate included.
        PREV_VERSION=$(VersionTags | head -n 1);

        if [ "$MODE" = "hotfix" ];
        then
            TYPE='hotfix';
        else
            TYPE='release';
        fi

        set -x

        git flow $TYPE start $VERSION;

        set +x
        if [ ! -z "$SENTRY_SLUG" ]
        then
            set -x
            sentry-cli releases -o $SENTRY_ORG new -p $SENTRY_SLUG $VERSION;
            set +x
        fi
        set -x

        # hyphen (-) is set as delimiter
        IFS=','

        # str is read into an array as tokens separated by IFS
        read -ra values <<< "$VERSION_FILENAMES"

        #echo each of the value to output
        for VERSION_FILENAME in "${values[@]}"; do
            sed "s/$PREV_VERSION/$VERSION/" $VERSION_FILENAME > "${VERSION_FILENAME}.bak"
            mv "${VERSION_FILENAME}.bak" $VERSION_FILENAME
        done

        # reset IFS to default value
        IFS=' '
    ;;

    finish)
        BRANCH=$(git branch --show-current);
        REGEXP="^(release|hotfix)/($VERSION_REGEXP)$";

        if [[ ! $BRANCH =~ $REGEXP ]];
        then
            echo "Please make sure you are currently on release or hotfix branch, ie. a branch named 'release|hotfix/x.y.z[-rcN]' f.e. release/1.22.3 or release/2.0.0-rc1";

            exit;
        fi

        TYPE=${BASH_REMATCH[1]};
        VERSION=${BASH_REMATCH[2]};

        if [ ! -z "$BUILD_COMMAND" ]
        then
            set -x
            eval "$BUILD_COMMAND"
            sentry-cli sourcemaps inject --org $SENTRY_ORG --project $SENTRY_SLUG $BUILD_PATH
            sentry-cli sourcemaps upload --org $SENTRY_ORG --project $SENTRY_SLUG $BUILD_PATH --release $VERSION
            set +x
        fi

        set -x

        git flow $TYPE finish $VERSION;
    ;;

    finalize)
        VERSION=$(VersionTags | head -n 1);
        PREV_VERSION=$(VersionTags | sed -n '2p');

        set -x

        git push origin main dev --tags;

        set +x
        if [ ! -z "$SENTRY_SLUG" ]
        then
            set -x
            sentry-cli releases -o $SENTRY_ORG finalize $VERSION;
            sentry-cli releases -o $SENTRY_ORG set-commits $VERSION --commit "$SENTRY_ORG/$SENTRY_SLUG@$PREV_VERSION..$VERSION";
            set +x
        fi
    ;;

    *)
        Help
   ;;
esac
