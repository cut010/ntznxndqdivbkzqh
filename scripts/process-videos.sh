#!/bin/bash
set -euo pipefail

CONTENT_FILE="data/content.json"
TMP_DIR="/tmp/lidlt-process"
mkdir -p "$TMP_DIR"

IA_ACCESS="$IA_ACCESS_KEY"
IA_SECRET="$IA_SECRET_KEY"

FILTER_SEASON="${FILTER_SEASON:-}"
FILTER_CATEGORY="${FILTER_CATEGORY:-}"

PROCESSED=0
FAILED=0

echo "FILTER_SEASON='${FILTER_SEASON}' FILTER_CATEGORY='${FILTER_CATEGORY}'"

MIN_SEASON="${FILTER_SEASON:-10}"
items=$(jq -r --arg season "$FILTER_SEASON" --arg category "$FILTER_CATEGORY" --argjson min 10 '
  [.content | to_entries[] | .key as $s |
    select(($s | tonumber) >= $min) |
    select($season == "" or $s == $season) |
    .value | to_entries[] | .key as $c |
    select($category == "" or $c == $category) |
    .value[] |
    select(.video | length > 0) |
    select(.video | map(select(.type == "mp4")) | length == 0) |
    {season: $s, category: $c, contentId: .contentId, title: .title, hls: (.video[0].url)}
  ] | .[] | @base64
' "$CONTENT_FILE" || true)

if [ -z "$items" ]; then
  echo "No hay videos pendientes."
  exit 0
fi

total=$(echo "$items" | wc -l | tr -d ' ')
echo "Videos a procesar: $total"

for item_b64 in $items; do
  data=$(echo "$item_b64" | base64 -d)
  season=$(echo "$data" | jq -r '.season')
  category=$(echo "$data" | jq -r '.category')
  contentId=$(echo "$data" | jq -r '.contentId')
  title=$(echo "$data" | jq -r '.title')
  hls_url=$(echo "$data" | jq -r '.hls')

  identifier="lidlt-t${season}-${category}-${contentId}"
  filename="${identifier}.mp4"
  output_path="${TMP_DIR}/${filename}"

  echo ""
  echo "=== Procesando: ${title} (T${season} ${category} #${contentId}) ==="
  echo "HLS: ${hls_url}"

  echo "Descargando..."

  UA="AppleCoreMedia/1.0.0.25F84 (Macintosh; U; Intel Mac OS X 14_8_8; en_us)"

  master=$(curl -s \
    -A "$UA" \
    -H "Origin: https://www.mediasetinfinity.es" \
    -H "Referer: https://www.mediasetinfinity.es/" \
    "$hls_url")
  variant=$(echo "$master" | tr -d '\r' | awk '
    /^#EXT-X-STREAM-INF:/ {
      h=0; bw=0;
      if (match($0,/RESOLUTION=[0-9]+x[0-9]+/)) { s=substr($0,RSTART,RLENGTH); sub(/RESOLUTION=[0-9]+x/,"",s); h=s+0; }
      if (match($0,/BANDWIDTH=[0-9]+/))         { s=substr($0,RSTART,RLENGTH); sub(/BANDWIDTH=/,"",s);        bw=s+0; }
      getline u;
      if (u ~ /^#/ || u=="") next;
      n++; H[n]=h; B[n]=bw; U[n]=u;
    }
    END {
      best=0;
      for (i=1;i<=n;i++) if (H[i]>=1080 && (best==0 || B[i]<B[best])) best=i;
      if (best==0) for (i=1;i<=n;i++) if (best==0 || H[i]>H[best]) best=i;
      if (best>0) print U[best];
    }')
  if [ -n "$variant" ]; then
    case "$variant" in
      http*) stream_url="$variant" ;;
      *)     stream_url="${hls_url%/*}/${variant}" ;;
    esac
    echo "Variante: ${stream_url}"
  else
    stream_url="$hls_url"
  fi


  if ! ffmpeg \
    -user_agent "$UA" \
    -headers $'Origin: https://www.mediasetinfinity.es\r\nReferer: https://www.mediasetinfinity.es/\r\n' \
    -multiple_requests 1 \
    -fflags +genpts \
    -i "$stream_url" \
    -map 0:v:0 -map 0:a:0 \
    -c:v libx264 -preset veryfast -crf 20 -fps_mode cfr -pix_fmt yuv420p \
    -c:a aac -b:a 128k -af aresample=async=1 \
    -movflags +faststart -y "$output_path" 2>/tmp/ffmpeg.log; then
    echo "ERROR: ffmpeg fallo para ${title}"
    tail -5 /tmp/ffmpeg.log
    FAILED=$((FAILED + 1))
    rm -f "$output_path"
    continue
  fi

  filesize=$(du -h "$output_path" | cut -f1)
  echo "Descargado: ${filesize}"

  echo "Subiendo a Archive.org..."
  http_code=$(curl -s --retry 3 --retry-delay 5 \
    -H "Authorization: LOW ${IA_ACCESS}:${IA_SECRET}" \
    -H "x-archive-meta-mediatype: movies" \
    -H "x-archive-meta-title: ${title}" \
    -H "x-archive-meta-collection: opensource_movies" \
    -H "x-amz-auto-make-bucket: 1" \
    -T "$output_path" \
    "https://s3.us.archive.org/${identifier}/${filename}" \
    -o /tmp/ia_response.txt -w "%{http_code}")

  if [ "$http_code" != "200" ]; then
    echo "ERROR: Archive.org respondio ${http_code} para ${title}"
    cat /tmp/ia_response.txt 2>/dev/null
    FAILED=$((FAILED + 1))
    rm -f "$output_path"
    continue
  fi

  archive_url="https://archive.org/download/${identifier}/${filename}"
  echo "Subido: ${archive_url}"

  jq --arg season "$season" \
     --arg category "$category" \
     --arg contentId "$contentId" \
     --arg url "$archive_url" \
     '
     .content[$season][$category] |= map(
       if .contentId == $contentId then
         .video += [{
           "url": $url,
           "label": "MP4",
           "type": "mp4",
           "cast": true,
           "extension": false
         }]
       else . end
     )
     ' "$CONTENT_FILE" > "${CONTENT_FILE}.tmp" && mv "${CONTENT_FILE}.tmp" "$CONTENT_FILE"

  echo "JSON actualizado."
  PROCESSED=$((PROCESSED + 1))

  rm -f "$output_path"
  echo "=== Completado: ${title} ==="
done

echo ""
echo "=== Resumen ==="
echo "Procesados: ${PROCESSED}"
echo "Fallidos: ${FAILED}"
echo "Total: ${total}"
