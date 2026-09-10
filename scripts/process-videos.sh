#!/bin/bash
set -euo pipefail

CONTENT_FILE="data/content.json"
TMP_DIR="/tmp/lidlt-process"
mkdir -p "$TMP_DIR"

IA_ACCESS="$IA_ACCESS_KEY"
IA_SECRET="$IA_SECRET_KEY"

FILTER_SEASON="${FILTER_SEASON:-}"
FILTER_CATEGORY="${FILTER_CATEGORY:-}"
DL_PAR="${DL_PAR:-8}"
UP_PAR="${UP_PAR:-6}"

UA="AppleCoreMedia/1.0.0.25F84 (Macintosh; U; Intel Mac OS X 14_8_8; en_us)"
ORIGIN="https://www.mediasetinfinity.es"
REFERER="https://www.mediasetinfinity.es/"
export UA ORIGIN REFERER IA_ACCESS IA_SECRET

PROCESSED=0
FAILED=0

echo "FILTER_SEASON='${FILTER_SEASON}' FILTER_CATEGORY='${FILTER_CATEGORY}'"

items=$(jq -r --arg season "$FILTER_SEASON" --arg category "$FILTER_CATEGORY" --argjson min 10 '
  [.content | to_entries[] | .key as $s |
    select(($s | tonumber) >= $min) |
    select($season == "" or $s == $season) |
    .value | to_entries[] | .key as $c |
    select($category == "" or $c == $category) |
    .value[] |
    select(.video | length > 0) |
    select([.video[].url | select(test("archive.org"))] | length == 0) |
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

  identifier="${contentId}"
  work_dir="${TMP_DIR}/${identifier}"
  rm -rf "$work_dir"; mkdir -p "$work_dir"

  echo ""
  echo "=== Procesando: ${title} (T${season} ${category} #${contentId}) ==="
  echo "HLS master: ${hls_url}"

  base_master="${hls_url%/*}"

  curl -s -A "$UA" -H "Origin: $ORIGIN" -H "Referer: $REFERER" "$hls_url" \
    | tr -d '\r' \
    | awk '
        /^#EXT-X-STREAM-INF:/ {
          inf=$0; gsub(/,?AUDIO="[^"]*"/,"",inf);
          getline u; if (u ~ /^#/ || u=="") next;
          print u "\t" inf;
        }' > "$work_dir/variants.txt"

  if [ ! -s "$work_dir/variants.txt" ]; then
    echo "ERROR: no se encontraron variantes en el master"; FAILED=$((FAILED + 1)); rm -rf "$work_dir"; continue
  fi

  : > "$work_dir/dl.txt"
  {
    echo "#EXTM3U"
    echo "#EXT-X-VERSION:4"
    echo "#EXT-X-INDEPENDENT-SEGMENTS"
  } > "$work_dir/master.m3u8"

  k=-1
  ep_error=0
  while IFS=$'\t' read -r vurl vinf; do
    k=$((k + 1))
    case "$vurl" in
      http*) vabs="$vurl" ;;
      *)     vabs="${base_master}/${vurl}" ;;
    esac
    vbase="${vabs%/*}"

    vpl=$(curl -s -A "$UA" -H "Origin: $ORIGIN" -H "Referer: $REFERER" "$vabs" | tr -d '\r')
    if [ -z "$vpl" ]; then echo "ERROR: variante $k vacía"; ep_error=1; break; fi
    if echo "$vpl" | grep -q "EXT-X-KEY"; then echo "ERROR: variante $k cifrada (EXT-X-KEY)"; ep_error=1; break; fi

    : > "$work_dir/v${k}.m3u8"
    i=0
    while IFS= read -r line; do
      case "$line" in
        "#"*|"") printf '%s\n' "$line" >> "$work_dir/v${k}.m3u8" ;;
        *)
          i=$((i + 1)); seg="v${k}_seg${i}.ts"
          case "$line" in http*) segu="$line" ;; *) segu="${vbase}/${line}" ;; esac
          printf '%s %s\n' "$segu" "$work_dir/$seg" >> "$work_dir/dl.txt"
          printf '%s\n' "$seg" >> "$work_dir/v${k}.m3u8" ;;
      esac
    done <<< "$vpl"

    if [ "$i" -eq 0 ]; then echo "ERROR: variante $k sin segmentos"; ep_error=1; break; fi

    printf '%s\n%s\n' "$vinf" "v${k}.m3u8" >> "$work_dir/master.m3u8"
    echo "  variante ${k}: ${i} segmentos"
  done < "$work_dir/variants.txt"

  if [ "$ep_error" -ne 0 ]; then FAILED=$((FAILED + 1)); rm -rf "$work_dir"; continue; fi

  nseg=$(wc -l < "$work_dir/dl.txt" | tr -d ' ')
  echo "Total segmentos (todas las calidades): ${nseg}. Descargando (paralelo x${DL_PAR})..."

  if ! xargs -P "$DL_PAR" -L 1 bash -c '
        curl -s --retry 3 --retry-delay 2 -f \
          -A "$UA" -H "Origin: $ORIGIN" -H "Referer: $REFERER" \
          -o "$2" "$1"
      ' _ < "$work_dir/dl.txt"; then
    echo "ERROR: falló alguna descarga de segmentos"; FAILED=$((FAILED + 1)); rm -rf "$work_dir"; continue
  fi

  empty=$(find "$work_dir" -name 'v*_seg*.ts' -empty | wc -l | tr -d ' ')
  if [ "$empty" -ne 0 ]; then
    echo "ERROR: ${empty} segmentos vacíos tras la descarga"; FAILED=$((FAILED + 1)); rm -rf "$work_dir"; continue
  fi
  total_size=$(du -sh "$work_dir" | cut -f1)
  echo "Descargado: ${total_size}."

  echo "Subiendo master.m3u8 (crea el item)..."
  code=$(curl -s --retry 3 --retry-delay 5 \
    -H "Authorization: LOW ${IA_ACCESS}:${IA_SECRET}" \
    -H "x-amz-auto-make-bucket: 1" \
    -H "x-archive-queue-derive: 0" \
    -H "x-archive-meta-mediatype: movies" \
    -H "x-archive-meta-title: ${title}" \
    -H "x-archive-meta-collection: opensource_movies" \
    -H "Content-Type: application/vnd.apple.mpegurl" \
    -T "$work_dir/master.m3u8" \
    "https://s3.us.archive.org/${identifier}/master.m3u8" \
    -o /tmp/ia_response.txt -w "%{http_code}")
  if [ "$code" != "200" ]; then
    echo "ERROR: IA respondió ${code} al crear el item"; cat /tmp/ia_response.txt 2>/dev/null
    FAILED=$((FAILED + 1)); rm -rf "$work_dir"; continue
  fi

  echo "Subiendo variantes + segmentos (paralelo x${UP_PAR})..."
  up_fail=$(find "$work_dir" \( -name 'v*.m3u8' -o -name 'v*_seg*.ts' \) \
    | ID="$identifier" xargs -P "$UP_PAR" -I{} bash -c '
        f="{}"; b=$(basename "$f")
        case "$b" in *.m3u8) ct="application/vnd.apple.mpegurl";; *) ct="video/mp2t";; esac
        c=$(curl -s --retry 3 --retry-delay 3 \
          -H "Authorization: LOW ${IA_ACCESS}:${IA_SECRET}" \
          -H "x-archive-queue-derive: 0" \
          -H "Content-Type: $ct" \
          -T "$f" "https://s3.us.archive.org/${ID}/$b" -o /dev/null -w "%{http_code}")
        [ "$c" = "200" ] || echo "x"
      ' | grep -c "x" || true)
  if [ "$up_fail" -ne 0 ]; then
    echo "ERROR: fallaron ${up_fail} subidas"; FAILED=$((FAILED + 1)); rm -rf "$work_dir"; continue
  fi

  archive_url="https://archive.org/download/${identifier}/master.m3u8"
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
           "label": "HLS",
           "type": "hls",
           "cast": true,
           "extension": false
         }]
       else . end
     )
     ' "$CONTENT_FILE" > "${CONTENT_FILE}.tmp" && mv "${CONTENT_FILE}.tmp" "$CONTENT_FILE"

  echo "JSON actualizado."
  PROCESSED=$((PROCESSED + 1))
  rm -rf "$work_dir"
  echo "=== Completado: ${title} ==="
done

echo ""
echo "=== Resumen ==="
echo "Procesados: ${PROCESSED}"
echo "Fallidos: ${FAILED}"
echo "Total: ${total}"
