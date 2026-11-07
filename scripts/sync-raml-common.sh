#!/usr/bin/env bash
# Copies shared/raml/common-library.raml into every API that has a spec.
# APIkit and Anypoint Studio only resolve files inside src/main/resources/api,
# so each API needs its own copy. Edit the shared file, then run this script.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source_file="$root/shared/raml/common-library.raml"

for api_dir in "$root"/apis/*/src/main/resources/api; do
    [ -d "$api_dir" ] || continue
    mkdir -p "$api_dir/common"
    cp "$source_file" "$api_dir/common/common-library.raml"
    echo "synced ${api_dir#"$root"/}/common/common-library.raml"
done
