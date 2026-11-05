#!/bin/bash
# Upload a video to revolvetrading.com/v/<slug> (chunked, resumable).
#
#   upload-video.sh FILE [TITLE]
#
# Machine-readable stdout, one event per line, for VideoUpload.qml:
#   progress <0-100>
#   url <https://revolvetrading.com/v/...>
#   error <message>
#
# Config: ~/.config/revolve-video.env (mode 600)
#   REVOLVE_VIDEO_URL=https://revolvetrading.com
#   REVOLVE_VIDEO_TOKEN=<NUXT_VIDEO_UPLOAD_TOKEN from Coolify>
set -uo pipefail

fail() { echo "error $*"; exit 1; }

file="${1:-}"
title="${2:-}"
[[ -f "$file" ]] || fail "No such file: $file"

env_file="${REVOLVE_VIDEO_ENV:-$HOME/.config/revolve-video.env}"
# shellcheck source=/dev/null
[[ -f "$env_file" ]] && source "$env_file"
base="${REVOLVE_VIDEO_URL:-https://revolvetrading.com}"
token="${REVOLVE_VIDEO_TOKEN:-}"
[[ -n "$token" ]] || fail "REVOLVE_VIDEO_TOKEN not set in $env_file"

auth=(-H "Authorization: Bearer $token")
size=$(stat -c %s "$file")
name=$(basename "$file")

# api METHOD PATH [curl args...] -> body on stdout, non-zero on HTTP error
api() {
    local method="$1" path="$2"
    shift 2
    local out code
    out=$(curl -sS -X "$method" "${auth[@]}" -w '\n%{http_code}' "$@" "$base$path") || return 1
    code="${out##*$'\n'}"
    out="${out%$'\n'*}"
    printf '%s' "$out"
    [[ "$code" =~ ^2 ]]
}

init=$(api POST /api/upload/videos -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg f "$name" --argjson s "$size" --arg t "$title" \
        '{filename: $f, size: $s} + (if $t == "" then {} else {title: $t} end)')") \
    || fail "Upload rejected: $(jq -r '.statusMessage // .message // .' <<< "$init" 2>/dev/null)"
slug=$(jq -r .slug <<< "$init")
chunk=$(jq -r .chunkSize <<< "$init")
[[ -n "$slug" && "$slug" != null ]] || fail "Bad init response"

offset=0
retries=0
echo "progress 0"
while (( offset < size )); do
    count=$(( size - offset < chunk ? size - offset : chunk ))
    if res=$(dd if="$file" bs=4M iflag=skip_bytes,count_bytes skip="$offset" count="$count" status=none |
        api PUT "/api/upload/videos/$slug?offset=$offset" \
            -H 'Content-Type: application/octet-stream' --data-binary @-); then
        offset=$(jq -r .offset <<< "$res")
        retries=0
        echo "progress $(( offset * 100 / size ))"
    else
        (( ++retries > 5 )) && fail "Chunk at $offset failed: $res"
        sleep "$retries"
        # Resume from whatever the server actually has.
        state=$(api GET "/api/upload/videos/$slug") || continue
        offset=$(jq -r .offset <<< "$state")
    fi
done

done_json=$(api POST "/api/upload/videos/$slug/complete") \
    || fail "Finish failed: $(jq -r '.statusMessage // .' <<< "$done_json" 2>/dev/null)"
echo "url $(jq -r .url <<< "$done_json")"
