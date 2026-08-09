#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/package-deb.sh PLUGIN_CLASS RELEASE_FILENAME VERSION MIN_KOHA_VERSION MAX_KOHA_VERSION [OUTPUT_DIR]

Build an unsigned Architecture: all Debian package for a Koha plugin.

Required environment:
  DEB_MAINTAINER       Debian maintainer, e.g. "Jane Doe <jane@example.org>"

Optional environment:
  DEB_PACKAGE_NAME     Binary package name (default: koha-plugin-RELEASE_FILENAME)
  DEB_REVISION         Debian revision (default: 1)
  DEB_DEPENDENCIES     Additional comma-separated runtime dependencies
  DEB_BUILDER_IMAGE    Builder image (default: debian:bookworm-slim)
  CONTAINER_BINARY     docker or podman (auto-detected)
  DEB_NATIVE_BUILD     Set to 1 to use local dpkg-buildpackage
  DEB_GENERATE_ONLY    Set to 1 to generate the source tree without building
  PLUGIN_DESCRIPTION  One-line package description
  PLUGIN_AUTHOR       Copyright holder used in debian/copyright
EOF
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

[ "$#" -ge 5 ] && [ "$#" -le 6 ] || {
    usage >&2
    exit 1
}

PLUGIN_CLASS=$1
RELEASE_FILENAME=$2
PLUGIN_VERSION=$3
MIN_KOHA_VERSION=$4
MAX_KOHA_VERSION=$5
OUTPUT_DIR=${6:-dist/debian}

SOURCE_DIR=$(pwd)
ASSET_ROOT=${KOHA_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
TEMPLATE_DIR="$ASSET_ROOT/templates/debian"
RENDERER="$ASSET_ROOT/scripts/render-debian.pl"

DEB_MAINTAINER=${DEB_MAINTAINER:-${PLUGIN_DEBIAN_MAINTAINER:-}}
DEB_REVISION=${DEB_REVISION:-${PLUGIN_DEBIAN_REVISION:-1}}
DEB_DEPENDENCIES=${DEB_DEPENDENCIES:-${PLUGIN_DEBIAN_DEPENDENCIES:-}}
DEFAULT_PACKAGE_NAME=$RELEASE_FILENAME
if [[ "$DEFAULT_PACKAGE_NAME" != koha-plugin-* ]]; then
    DEFAULT_PACKAGE_NAME="koha-plugin-${DEFAULT_PACKAGE_NAME}"
fi
DEB_PACKAGE_NAME=${DEB_PACKAGE_NAME:-${PLUGIN_DEBIAN_PACKAGE_NAME:-$DEFAULT_PACKAGE_NAME}}
DEB_BUILDER_IMAGE=${DEB_BUILDER_IMAGE:-debian:bookworm-slim}
PLUGIN_DESCRIPTION=${PLUGIN_DESCRIPTION:-Koha plugin ${RELEASE_FILENAME}}
PLUGIN_AUTHOR=${PLUGIN_AUTHOR:-$DEB_MAINTAINER}

[ -x "$RENDERER" ] || fail "template renderer not found or not executable: $RENDERER"
[ -d "$TEMPLATE_DIR" ] || fail "Debian templates not found: $TEMPLATE_DIR"

[[ "$PLUGIN_CLASS" =~ ^Koha::Plugin::[A-Za-z][A-Za-z0-9]*::[A-Za-z][A-Za-z0-9]*::[A-Za-z][A-Za-z0-9]*$ ]] \
    || fail 'plugin class must use Koha::Plugin::<TLD>::<ORG>::<PROJECT>'
[[ "$RELEASE_FILENAME" =~ ^[a-zA-Z0-9_-]+$ ]] \
    || fail 'release filename may contain only letters, numbers, underscores, and hyphens'
[[ "$PLUGIN_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail 'plugin version must use X.Y.Z'
[[ "$DEB_PACKAGE_NAME" =~ ^[a-z0-9][a-z0-9+.-]+$ ]] \
    || fail 'Debian package name contains invalid characters'
[[ "$DEB_REVISION" =~ ^[0-9]+([.+~][a-zA-Z0-9]+)*$ ]] \
    || fail 'Debian revision contains invalid characters'
[[ "$DEB_MAINTAINER" =~ ^[^\<\>]+\ \<[^\<\>@[:space:]]+@[^\<\>[:space:]]+\>$ ]] \
    || fail 'DEB_MAINTAINER must use "Name <email@example.org>"'
[[ "$MIN_KOHA_VERSION" =~ ^[0-9]{2}\.[0-9]{2}([.][0-9]+)*$ ]] \
    || fail 'minimum Koha version must begin with YY.MM'
if [ -n "$MAX_KOHA_VERSION" ]; then
    [[ "$MAX_KOHA_VERSION" =~ ^[0-9]{2}\.[0-9]{2}([.][0-9]+)*$ ]] \
        || fail 'maximum Koha version must begin with YY.MM'
fi

for one_line_value in "$DEB_DEPENDENCIES" "$PLUGIN_DESCRIPTION" "$PLUGIN_AUTHOR" "$SOURCE_DIR"; do
    [[ "$one_line_value" != *$'\n'* && "$one_line_value" != *$'\r'* ]] \
        || fail 'Debian metadata values must be on one line'
done

CLASS_PATH=${PLUGIN_CLASS//:://}
MODULE_PATH="${CLASS_PATH}.pm"
MODULE_RELATIVE_PATH=$MODULE_PATH
[ -f "$SOURCE_DIR/$MODULE_PATH" ] || fail "plugin module not found: $MODULE_PATH"
[ -d "$SOURCE_DIR/Koha" ] || fail 'Koha directory not found'

koha_lower_bound() {
    local value=$1
    local year month patch remainder
    IFS=. read -r year month patch remainder <<<"$value"
    if [ -n "${patch:-}" ]; then
        printf '%s.%s.%s' "$year" "$month" "$patch"
    else
        printf '%s.%s' "$year" "$month"
    fi
}

koha_exclusive_upper_bound() {
    local value=$1
    local year month remainder
    IFS=. read -r year month remainder <<<"$value"
    year=$((10#$year))
    month=$((10#$month + 1))
    if [ "$month" -gt 12 ]; then
        year=$((year + 1))
        month=1
    fi
    printf '%02d.%02d' "$year" "$month"
}

MIN_DEB_VERSION=$(koha_lower_bound "$MIN_KOHA_VERSION")
KOHA_DEPENDS="koha-common (>= ${MIN_DEB_VERSION})"
if [ -n "$MAX_KOHA_VERSION" ]; then
    MAX_DEB_VERSION=$(koha_exclusive_upper_bound "$MAX_KOHA_VERSION")
    KOHA_DEPENDS="${KOHA_DEPENDS}, koha-common (<< ${MAX_DEB_VERSION})"
fi
if [ -n "$DEB_DEPENDENCIES" ]; then
    KOHA_DEPENDS="${KOHA_DEPENDS}, ${DEB_DEPENDENCIES}"
fi

PACKAGE_VERSION="${PLUGIN_VERSION}-${DEB_REVISION}"
BUILD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/koha-plugin-deb.XXXXXX")
WORK_DIR="$BUILD_ROOT/${DEB_PACKAGE_NAME}-${PLUGIN_VERSION}"
trap 'rm -rf "$BUILD_ROOT"' EXIT

mkdir -p "$WORK_DIR/debian/source" "$WORK_DIR/debian/tests"
cp -R "$SOURCE_DIR/Koha" "$WORK_DIR/Koha"

export DEB_TEMPLATE_PACKAGE_NAME=$DEB_PACKAGE_NAME
export DEB_TEMPLATE_PACKAGE_VERSION=$PACKAGE_VERSION
export DEB_TEMPLATE_PLUGIN_VERSION=$PLUGIN_VERSION
export DEB_TEMPLATE_PLUGIN_CLASS=$PLUGIN_CLASS
export DEB_TEMPLATE_MODULE_PATH=$MODULE_PATH
export DEB_TEMPLATE_MODULE_RELATIVE_PATH=$MODULE_RELATIVE_PATH
export DEB_TEMPLATE_MAINTAINER=$DEB_MAINTAINER
export DEB_TEMPLATE_AUTHOR=$PLUGIN_AUTHOR
export DEB_TEMPLATE_COPYRIGHT_YEAR
DEB_TEMPLATE_COPYRIGHT_YEAR=$(date -u +%Y)
export DEB_TEMPLATE_DESCRIPTION=$PLUGIN_DESCRIPTION
export DEB_TEMPLATE_DEPENDS=$KOHA_DEPENDS
export DEB_TEMPLATE_CHANGELOG_DATE
DEB_TEMPLATE_CHANGELOG_DATE=$(LC_ALL=C date -R)

render() {
    local template=$1
    local output=$2
    "$RENDERER" "$TEMPLATE_DIR/$template" "$WORK_DIR/$output"
}

render control debian/control
render changelog debian/changelog
render copyright debian/copyright
render postinst debian/postinst
render prerm debian/prerm
render configure-instance debian/configure-instance
render unregister debian/unregister
render install debian/install
render tests-smoke debian/tests/smoke
render lintian-overrides "debian/${DEB_PACKAGE_NAME}.lintian-overrides"

cp "$TEMPLATE_DIR/rules" "$WORK_DIR/debian/rules"
cp "$TEMPLATE_DIR/source-format" "$WORK_DIR/debian/source/format"
cp "$TEMPLATE_DIR/tests-control" "$WORK_DIR/debian/tests/control"
chmod 0755 "$WORK_DIR/debian/rules" "$WORK_DIR/debian/postinst" \
    "$WORK_DIR/debian/prerm" "$WORK_DIR/debian/configure-instance" \
    "$WORK_DIR/debian/unregister" "$WORK_DIR/debian/tests/smoke"

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)

if [ "${DEB_GENERATE_ONLY:-0}" = '1' ]; then
    rm -rf "$OUTPUT_DIR/source"
    cp -R "$WORK_DIR" "$OUTPUT_DIR/source"
    printf 'Generated Debian source tree: %s/source\n' "$OUTPUT_DIR"
    exit 0
fi

build_native() {
    command -v dpkg-buildpackage >/dev/null 2>&1 \
        || fail 'dpkg-buildpackage not found; use a container builder'
    command -v lintian >/dev/null 2>&1 \
        || fail 'lintian not found; install it or use a container builder'
    (
        cd "$WORK_DIR"
        dpkg-buildpackage -us -uc -b
    )
    find "$BUILD_ROOT" -maxdepth 1 -type f \
        \( -name '*.deb' -o -name '*.changes' -o -name '*.buildinfo' \) \
        -exec cp {} "$OUTPUT_DIR/" \;
    lintian "$OUTPUT_DIR"/*.changes | tee "$OUTPUT_DIR/lintian.log"
}

build_container() {
    local runtime=$1
    "$runtime" run --rm \
        -e DEBIAN_FRONTEND=noninteractive \
        -e HOST_UID="$(id -u)" \
        -e HOST_GID="$(id -g)" \
        -v "$BUILD_ROOT:/build" \
        -v "$OUTPUT_DIR:/out" \
        "$DEB_BUILDER_IMAGE" \
        sh -ec '
            apt-get update
            apt-get install -y --no-install-recommends build-essential debhelper dpkg-dev lintian
            cd "/build/'"${DEB_PACKAGE_NAME}-${PLUGIN_VERSION}"'"
            dpkg-buildpackage -us -uc -b
            # The disposable builder intentionally runs as root so it can install
            # its toolchain; --allow-root suppresses the generic root warning.
            lintian --allow-root /build/*.changes | tee /out/lintian.log
            find /build -maxdepth 1 -type f \
                \( -name "*.deb" -o -name "*.changes" -o -name "*.buildinfo" \) \
                -exec cp {} /out/ \;
            chown -R "$HOST_UID:$HOST_GID" /out
        '
}

if [ "${DEB_NATIVE_BUILD:-0}" = '1' ]; then
    build_native
else
    CONTAINER_BINARY=${CONTAINER_BINARY:-}
    if [ -z "$CONTAINER_BINARY" ]; then
        if command -v docker >/dev/null 2>&1; then
            CONTAINER_BINARY=docker
        elif command -v podman >/dev/null 2>&1; then
            CONTAINER_BINARY=podman
        else
            fail 'docker or podman is required; alternatively set DEB_NATIVE_BUILD=1'
        fi
    fi
    case "$CONTAINER_BINARY" in
        docker|podman) ;;
        *) fail 'CONTAINER_BINARY must be docker or podman' ;;
    esac
    build_container "$CONTAINER_BINARY"
fi

if command -v sha256sum >/dev/null 2>&1; then
    ( cd "$OUTPUT_DIR" && sha256sum ./*.deb >SHA256SUMS )
else
    ( cd "$OUTPUT_DIR" && shasum -a 256 ./*.deb >SHA256SUMS )
fi

printf 'Debian artifacts written to %s\n' "$OUTPUT_DIR"
