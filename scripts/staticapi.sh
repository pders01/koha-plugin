#!/usr/bin/env bash

if [ "$1" == "" ]; then
  exit 1
fi

PLUGIN_PATH="${1//::/'/'}"
if [ "$PLUGIN_PATH" == "" ]; then
  exit 1
fi

shift
STATIC_DIRS=("$@")

if [ ${#STATIC_DIRS[@]} -eq 0 ]; then
  echo "Error: At least one static directory must be specified"
  exit 1
fi

# Resolve template path: KOHA_PLUGIN_ROOT (set by CLI/PAR) or script's own directory
TOOL_ROOT="${KOHA_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
staticapi_template_file="${TOOL_ROOT}/templates/staticapi.json"
if [ ! -f "$staticapi_template_file" ]; then
  echo "Error: Template file not found at $staticapi_template_file"
  exit 1
fi

spec_body=$(cat "$staticapi_template_file")
json_fragments=()

for STATIC_DIR in "${STATIC_DIRS[@]}"; do
  STATIC_PATH="$PLUGIN_PATH/$STATIC_DIR"

  if [ ! -d "$STATIC_PATH" ]; then
    echo "Warning: Directory $STATIC_PATH not found, skipping"
    continue
  fi

  echo "Processing directory: $STATIC_DIR"

  while IFS= read -r -d '' file; do
    if [ -f "$file" ]; then
      # Strip plugin path AND static dir name — Koha prepends /static/ automatically
      path_name="${file//$STATIC_PATH/}"
      echo "  Creating $path_name"
      json_fragments+=("$path_name")
    fi
  done < <(find "$STATIC_PATH" -type f -print0)
done

if [ ${#json_fragments[@]} -eq 0 ]; then
  echo "Error: No files found in specified directories"
  exit 1
fi

{
  echo "{"
  for i in "${!json_fragments[@]}"; do
    path="${json_fragments[$i]}"
    path_json=$(printf '%s' "$path" | jq -R .)
    echo "  $path_json: $spec_body"
    if [ "$i" -lt $((${#json_fragments[@]} - 1)) ]; then
      echo ","
    fi
  done
  echo "}"
} | jq . >"$PLUGIN_PATH/staticapi.json"

echo "staticapi.json has been created at $PLUGIN_PATH"
