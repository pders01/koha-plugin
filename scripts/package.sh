#!/usr/bin/env bash

if [ "$1" == "" ]; then
  exit 1
fi

PLUGIN_PATH="${1//::/'/'}"
if [ "$PLUGIN_PATH" == "" ]; then
  exit 1
fi

if [ "$2" == "" ]; then
  exit 1
fi

if [ "$3" = "" ]; then
  exit 1
fi

echo "$PLUGIN_PATH"
mkdir -p dist
cp -r Koha dist/.
(
  cd dist || exit 1
  zip -r ../"${2}-${3}".kpz ./Koha
)
rm -rf dist
