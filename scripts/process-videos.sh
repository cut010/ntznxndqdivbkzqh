#!/bin/bash
set -euo pipefail

CONTENT_FILE="data/content.json"
TMP_DIR="/tmp/lidlt-process"
mkdir -p "$TMP_DIR"

IA_ACCESS="$IA_ACCESS_KEY"
IA_SECRET="$IA_SECRET_KEY"

PROCESSED=0
FAILED=0

items=$(jq -r '
  [.content | to_entries[] | .key as $season |
    .value | to_entries[] | .key as $category |
    .value[] |
    select(.video | length > 0) |
    select(.video | map(select(.type == "mp4")) | length == 0) |
    {season: $season, category: $category, contentId: .contentId, title: .title, hls: (.video[0].url)}
  ] | .[] | @base64
' "$CONTENT_FILE")

if [ -z "$items" ]; then
  echo "No hay videos pendientes de procesar."
  exit 0
fi

total=$(echo "$items" | wc -l | tr -d ' ')
echo "Videos pendientes: $total"

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

  # Descargar HLS a MP4
  echo "Descargando..."
  if ! ffmpeg -i "$hls_url" -c copy -bsf:a aac_adtstoasc -movflags +faststart -y "$output_path" 2>/tmp/ffmpeg.log; then
    echo "ERROR: ffmpeg fallo para ${title}"
    cat /tmp/ffmpeg.log | tail -5
    FAILED=$((FAILED + 1))
    rm -f "$output_path"
    continue
  fi

  filesize=$(du -h "$output_path" | cut -f1)
  echo "Descargado: ${filesize}"

  # Subir a Archive.org
  echo "Subiendo a Archive.org..."
  if ! curl -s --retry 3 --retry-delay 5 \
    -H "Authorization: LOW ${IA_ACCESS}:${IA_SECRET}" \
    -H "x-archive-meta-mediatype: movies" \
    -H "x-archive-meta-title: ${title}" \
    -H "x-archive-meta-collection: opensource_movies" \
    -H "x-amz-auto-make-bucket: 1" \
    -T "$output_path" \
    "https://s3.us.archive.org/${identifier}/${filename}" \
    -o /tmp/ia_response.txt -w "%{http_code}" | grep -q "200"; then
    echo "ERROR: Subida a Archive.org fallo para ${title}"
    cat /tmp/ia_response.txt 2>/dev/null
    FAILED=$((FAILED + 1))
    rm -f "$output_path"
    continue
  fi

  archive_url="https://archive.org/download/${identifier}/${filename}"
  echo "Subido: ${archive_url}"

  # Actualizar content.json
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

  # Limpiar
  rm -f "$output_path"
  echo "=== Completado: ${title} ==="
done

echo ""
echo "=== Resumen ==="
echo "Procesados: ${PROCESSED}"
echo "Fallidos: ${FAILED}"
echo "Total: ${total}"
