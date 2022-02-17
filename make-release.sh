#!/bin/bash

set -e;

VERSION_REGEXP='([0-9]+)\.([0-9]+)\.([0-9]+)';

VERSION_FILENAME=$(sed -n '1p' make-release)
SENTRY_ORG=$(sed -n '2p' make-release)
SENTRY_SLUG=$(sed -n '3p' make-release)

echo "Updating '$VERSION_FILENAME'.";

if [ ! -z "$SENTRY_ORG" ]
then
    if [ ! -z "$SENTRY_SLUG" ]
    then
            echo "Updating sentry release for project '$SENTRY_SLUG' on '$SENTRY_ORG' organization.";
    fi
elif [ ! -z "$SENTRY_SLUG" ]
then
    echo "Please either add a sentry org into the 2nd line or remove the sentry project '$SENTRY_SLUG' from the 3rd line.";

    exit;
else
    echo "Not updating sentry since there is no sentry organization on the 2nd line and a slug on the 3rd line";
fi

case $1 in
    major|minor|patch|hotfix)
        MODE=$1;
        echo "Preparing $MODE updating dev/main";
        git checkout dev;
        git pull --rebase;
        git checkout main;
        git pull --rebase;

        PREV_VERSION=$(git tag | head -n 1);

        REGEXP="^$VERSION_REGEXP+$";
        if [[ ! $PREV_VERSION =~ $REGEXP ]];
        then
            echo "Previous version should be in the format x.y.z and not '$PREV_VERSION'.";

            exit;
        fi

        declare -i MAJOR;
        declare -i MINOR;
        declare -i PATCH;

        case $MODE in
            major)
                TYPE='release';
                MAJOR=${BASH_REMATCH[1]}+1;
                MINOR=0;
                PATCH=0;
            ;;
            minor)
                TYPE='release';
                MAJOR=${BASH_REMATCH[1]};
                MINOR=${BASH_REMATCH[2]}+1;
                PATCH=0;
            ;;
            patch)
                TYPE='release';
                MAJOR=${BASH_REMATCH[1]};
                MINOR=${BASH_REMATCH[2]};
                PATCH=${BASH_REMATCH[3]}+1;
            ;;
            hotfix)
                TYPE='hotfix';
                MAJOR=${BASH_REMATCH[1]};
                MINOR=${BASH_REMATCH[2]};
                PATCH=${BASH_REMATCH[3]}+1;
            ;;
        esac

        VERSION="$MAJOR.$MINOR.$PATCH";

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

        sed "s/$PREV_VERSION/$VERSION/" $VERSION_FILENAME > "${VERSION_FILENAME}.bak"
        mv "${VERSION_FILENAME}.bak" $VERSION_FILENAME
    ;;

    finish)
        BRANCH=$(git branch --show-current);
        REGEXP="^(release|hotfix)/($VERSION_REGEXP)+$";

        if [[ ! $BRANCH =~ $REGEXP ]];
        then
            echo "Please make sure you are currently on release or hotfix branch, ie. a branch named 'release|hotfix/x.y.x'";

            exit;
        fi

        TYPE=${BASH_REMATCH[1]};
        VERSION=${BASH_REMATCH[2]};

        set -x

        git flow $TYPE finish $VERSION;
    ;;

    finalize)
        VERSION=$(git tag | head -n 1);
        PREV_VERSION=$(git tag | head -n 2 | tail -1);

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
        echo "./make-release.sh [major|minor|patch|hotfix|finish|finalize]";
   ;;
esac
