#!/usr/bin/env bash

if [ "$1" == "" ]; then
  exit 1
fi

PLUGIN_PATH="$(echo "$1" | tr -s '::' '/')"
if [ "$PLUGIN_PATH" == "" ]; then
  exit 1
fi

STATIC_DIR="$2"
if [ "$STATIC_DIR" == "" ]; then
  exit 1
fi

STATIC_PATH="$PLUGIN_PATH/$STATIC_DIR"
if [ ! -d "$STATIC_PATH" ]; then
  echo "Directory $PLUGIN_PATH/$STATIC_DIR not found."
  exit 1
fi

staticapi_template_file="templates/staticapi.json"
if [ ! -f "$staticapi_template_file" ]; then
  echo "Template file $staticapi_template_file not found."
  exit 1
fi

spec_body=$(cat "$staticapi_template_file")
json_fragments=()
while IFS= read -r -d '' file; do
  if [ -f "$file" ]; then
    path_name="${file//$PLUGIN_PATH/}"
    echo "Creating $path_name"

    endpoint_spec=$(echo "{\"$path_name\": $spec_body}" | jq .)
    json_fragments+=("$endpoint_spec")
  fi
done < <(find "$STATIC_PATH" -type f -print0)

json_output="$(printf "%s,\n" "${json_fragments[@]}" | sed '$ s/,$//')"
echo -e "$json_output" >"$PLUGIN_PATH/staticapi.json"

echo "staticapi.json has been created at $PLUGIN_PATH"
