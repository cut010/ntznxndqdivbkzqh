#!/bin/bash
set -euo pipefail

CONTENT_FILE="data/content.json"
TMP_DIR="/tmp/lidlt-process"
mkdir -p "$TMP_DIR"

IA_ACCESS="$IA_ACCESS_KEY"
IA_SECRET="$IA_SECRET_KEY"

PROCESSED=0
FAILED=0

# Detectar episodios nuevos comparando con el commit anterior
NEW_IDS_FILE="${TMP_DIR}/new_ids.txt"

# Buscar el ultimo commit que NO sea del bot
COMPARE_REF=$(git log --oneline --format="%H %s" | grep -v "auto: mp4 procesados" | head -2 | tail -1 | cut -d' ' -f1)

if [ -z "$COMPARE_REF" ]; then
  echo "No hay commit anterior para comparar."
  exit 0
fi

echo "Comparando con: $(git log --oneline -1 "$COMPARE_REF")"

git show "${COMPARE_REF}:${CONTENT_FILE}" > "${TMP_DIR}/old_content.json" 2>/dev/null || echo '{"content":{}}' > "${TMP_DIR}/old_content.json"

jq -r '.content | to_entries[] | .value | to_entries[] | .value[] | .contentId' "${TMP_DIR}/old_content.json" | sort > "${TMP_DIR}/old_ids.txt"
jq -r '.content | to_entries[] | .value | to_entries[] | .value[] | .contentId' "$CONTENT_FILE" | sort > "${TMP_DIR}/current_ids.txt"

comm -13 "${TMP_DIR}/old_ids.txt" "${TMP_DIR}/current_ids.txt" > "$NEW_IDS_FILE"

if [ ! -s "$NEW_IDS_FILE" ]; then
  echo "No hay episodios nuevos."
  exit 0
fi

new_count=$(wc -l < "$NEW_IDS_FILE" | tr -d ' ')
echo "Episodios nuevos detectados: ${new_count}"
cat "$NEW_IDS_FILE"
echo ""

items=$(jq -r --slurpfile ids <(jq -R '.' "$NEW_IDS_FILE" | jq -s '.') '
  [.content | to_entries[] | .key as $season |
    .value | to_entries[] | .key as $category |
    .value[] |
    select(.contentId as $cid | $ids[0] | index($cid)) |
    select(.video | length > 0) |
    select(.video | map(select(.type == "mp4")) | length == 0) |
    {season: $season, category: $category, contentId: .contentId, title: .title, hls: (.video[0].url)}
  ] | .[] | @base64
' "$CONTENT_FILE" || true)

if [ -z "$items" ]; then
  echo "Los episodios nuevos ya tienen MP4 o no tienen video."
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
  if ! ffmpeg \
    -headers $'Origin: https://www.mediasetinfinity.es\r\nReferer: https://www.mediasetinfinity.es/\r\n' \
    -i "$hls_url" -c copy -bsf:a aac_adtstoasc -movflags +faststart -y "$output_path" 2>/tmp/ffmpeg.log; then
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
