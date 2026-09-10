#!/bin/bash
set -euo pipefail

CONTENT_FILE="data/content.json"
PLAYER_SRC="scripts/player.html"
TMP_DIR="/tmp/lidlt-process"
mkdir -p "$TMP_DIR"

[ -f "$PLAYER_SRC" ] || { echo "Falta $PLAYER_SRC"; exit 1; }

IA_ACCESS="$IA_ACCESS_KEY"
IA_SECRET="$IA_SECRET_KEY"

FILTER_SEASON="${FILTER_SEASON:-}"
FILTER_CATEGORY="${FILTER_CATEGORY:-}"
DL_PAR="${DL_PAR:-8}"

UA="AppleCoreMedia/1.0.0.25F84 (Macintosh; U; Intel Mac OS X 14_8_8; en_us)"
ORIGIN="https://www.mediasetinfinity.es"
REFERER="https://www.mediasetinfinity.es/"
export UA ORIGIN REFERER

PROCESSED=0
FAILED=0

ia_put() {
  curl -s --retry 5 --retry-delay 5 --retry-all-errors \
    -H "Authorization: LOW ${IA_ACCESS}:${IA_SECRET}" \
    -H "x-archive-queue-derive: 0" \
    -H "Content-Type: $3" \
    "${@:4}" \
    -T "$1" "$2" -o /tmp/ia_response.txt -w "%{http_code}"
}

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

  {
    echo "#EXTM3U"
    echo "#EXT-X-VERSION:4"
    echo "#EXT-X-INDEPENDENT-SEGMENTS"
  } > "$work_dir/master.m3u8"
  k=-1
  while IFS=$'\t' read -r vurl vinf; do
    k=$((k + 1))
    printf '%s\n%s\n' "$vinf" "v${k}.m3u8" >> "$work_dir/master.m3u8"
  done < "$work_dir/variants.txt"

  echo "Subiendo master.m3u8 (crea el item)..."
  code=$(ia_put "$work_dir/master.m3u8" "https://s3.us.archive.org/${identifier}/master.m3u8" \
    "application/vnd.apple.mpegurl" \
    -H "x-amz-auto-make-bucket: 1" \
    -H "x-archive-meta-mediatype: movies" \
    -H "x-archive-meta-title: ${title}" \
    -H "x-archive-meta-collection: opensource_movies")
  if [ "$code" != "200" ]; then
    echo "ERROR: IA respondió ${code} al crear el item"; cat /tmp/ia_response.txt 2>/dev/null
    FAILED=$((FAILED + 1)); rm -rf "$work_dir"; continue
  fi

  echo "Subiendo player.html..."
  code=$(ia_put "$PLAYER_SRC" "https://s3.us.archive.org/${identifier}/player.html" "text/html")
  if [ "$code" != "200" ]; then
    echo "ERROR: IA ${code} subiendo player.html"; cat /tmp/ia_response.txt 2>/dev/null
    FAILED=$((FAILED + 1)); rm -rf "$work_dir"; continue
  fi

  ep_error=0
  k=-1
  while IFS=$'\t' read -r vurl vinf; do
    k=$((k + 1))
    case "$vurl" in
      http*) vabs="$vurl" ;;
      *)     vabs="${base_master}/${vurl}" ;;
    esac
    vbase="${vabs%/*}"

    curl -s -A "$UA" -H "Origin: $ORIGIN" -H "Referer: $REFERER" "$vabs" | tr -d '\r' > "$work_dir/src_${k}.m3u8"
    if [ ! -s "$work_dir/src_${k}.m3u8" ]; then echo "ERROR: variante $k vacía"; ep_error=1; break; fi
    if grep -q "EXT-X-KEY" "$work_dir/src_${k}.m3u8"; then echo "ERROR: variante $k cifrada (EXT-X-KEY)"; ep_error=1; break; fi

    : > "$work_dir/dl_${k}.txt"
    i=0
    while IFS= read -r line; do
      case "$line" in
        "#"*|"") : ;;
        *)
          i=$((i + 1))
          case "$line" in http*) segu="$line" ;; *) segu="${vbase}/${line}" ;; esac
          printf '%s %s\n' "$segu" "$work_dir/tmp_${k}_${i}.ts" >> "$work_dir/dl_${k}.txt"
          ;;
      esac
    done < "$work_dir/src_${k}.m3u8"
    nseg=$i
    if [ "$nseg" -eq 0 ]; then echo "ERROR: variante $k sin segmentos"; ep_error=1; break; fi

    echo "  variante ${k}: ${nseg} segmentos, descargando (x${DL_PAR})..."
    if ! xargs -P "$DL_PAR" -L 1 bash -c '
          curl -s --retry 3 --retry-delay 2 -f \
            -A "$UA" -H "Origin: $ORIGIN" -H "Referer: $REFERER" \
            -o "$2" "$1"
        ' _ < "$work_dir/dl_${k}.txt"; then
      echo "ERROR: falló descarga en variante $k"; ep_error=1; break
    fi

    : > "$work_dir/v${k}.ts"
    : > "$work_dir/v${k}.m3u8"
    i=0; off=0
    while IFS= read -r line; do
      case "$line" in
        "#"*|"") printf '%s\n' "$line" >> "$work_dir/v${k}.m3u8" ;;
        *)
          i=$((i + 1)); tmp="$work_dir/tmp_${k}_${i}.ts"
          if [ ! -s "$tmp" ]; then echo "ERROR: segmento vacío $tmp"; ep_error=1; break; fi
          sz=$(wc -c < "$tmp" | tr -d '[:space:]')
          cat "$tmp" >> "$work_dir/v${k}.ts"
          printf '#EXT-X-BYTERANGE:%s@%s\nv%s.ts\n' "$sz" "$off" "$k" >> "$work_dir/v${k}.m3u8"
          off=$((off + sz))
          rm -f "$tmp"
          ;;
      esac
    done < "$work_dir/src_${k}.m3u8"
    if [ "$ep_error" -ne 0 ]; then break; fi

    vsize=$(wc -c < "$work_dir/v${k}.ts")
    echo "  variante ${k}: v${k}.ts = $((vsize / 1024 / 1024)) MB, subiendo..."
    code=$(ia_put "$work_dir/v${k}.ts" "https://s3.us.archive.org/${identifier}/v${k}.ts" "video/mp2t")
    if [ "$code" != "200" ]; then echo "ERROR: IA ${code} subiendo v${k}.ts"; cat /tmp/ia_response.txt 2>/dev/null; ep_error=1; break; fi
    code=$(ia_put "$work_dir/v${k}.m3u8" "https://s3.us.archive.org/${identifier}/v${k}.m3u8" "application/vnd.apple.mpegurl")
    if [ "$code" != "200" ]; then echo "ERROR: IA ${code} subiendo v${k}.m3u8"; cat /tmp/ia_response.txt 2>/dev/null; ep_error=1; break; fi

    rm -f "$work_dir/v${k}.ts"
  done < "$work_dir/variants.txt"

  if [ "$ep_error" -ne 0 ]; then FAILED=$((FAILED + 1)); rm -rf "$work_dir"; continue; fi

  hls_url_ia="https://archive.org/download/${identifier}/master.m3u8"
  embed_url="https://archive.org/download/${identifier}/player.html"
  echo "HLS:   ${hls_url_ia}"
  echo "Embed: ${embed_url}"

  jq --arg season "$season" \
     --arg category "$category" \
     --arg contentId "$contentId" \
     --arg hls "$hls_url_ia" \
     --arg embed "$embed_url" \
     '
     .content[$season][$category] |= map(
       if .contentId == $contentId then
         .video += [
           { "url": $hls,   "label": "HLS",   "type": "hls",   "cast": true,  "extension": false },
           { "url": $embed, "label": "Web",   "type": "embed", "cast": false, "extension": false }
         ]
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
