command:
  - sh
  - -c
  - |
    ############################################################
    # Grafana dashboard uploader (NO jq, curlimages/curl)
    #
    # Directory layout:
    #   /git/dashboard/<orgId>/<folder>/*.json
    #
    # Example:
    #   /git/dashboard/1/sre/cpu.json
    #   /git/dashboard/2/platform/latency.json
    #
    # Limitations:
    # - Folder names MUST be URL-safe (no space / no unicode)
    # - dashboard.json top-level "id" should ideally be null
    ############################################################

    set -eu

    # ---- required env ----
    : "${GRAFANA_URL:?need GRAFANA_URL}"
    : "${GRAFANA_TOKEN:?need GRAFANA_TOKEN}"

    DASH_ROOT="/git/dashboard"

    AUTH="Authorization: Bearer ${GRAFANA_TOKEN}"
    CT="Content-Type: application/json"

    ############################################################
    # Wait until Grafana is ready
    ############################################################
    echo "[wait] grafana health check"
    for i in $(seq 1 60); do
      if curl -fsS "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
        echo "[ok] grafana is ready"
        break
      fi
      sleep 2
      [ "$i" -eq 60 ] && { echo "[err] grafana not ready"; exit 1; }
    done

    ############################################################
    # Extract first "uid":"xxxx" from JSON (HACK)
    # Used only for folder API responses
    ############################################################
    extract_uid() {
      tr '\n' ' ' \
      | sed -n 's/.*"uid"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n 1
    }

    ############################################################
    # Get folder UID by name (empty if not exists)
    ############################################################
    get_folder_uid() {
      org="$1"
      name="$2"

      curl -fsS \
        "${GRAFANA_URL}/api/search?type=dash-folder&query=${name}" \
        -H "$AUTH" \
        -H "X-Grafana-Org-Id: ${org}" 2>/dev/null \
      | extract_uid || true
    }

    ############################################################
    # Create Grafana folder and return UID
    ############################################################
    create_folder_uid() {
      org="$1"
      name="$2"

      curl -fsS -X POST \
        "${GRAFANA_URL}/api/folders" \
        -H "$AUTH" \
        -H "$CT" \
        -H "X-Grafana-Org-Id: ${org}" \
        -d "{\"title\":\"${name}\"}" \
      | extract_uid
    }

    ############################################################
    # Replace ONLY the first `"id": <number>` with `"id": null`
    # (avoid breaking panel IDs)
    ############################################################
    normalize_dashboard_id() {
      file="$1"
      awk '
        BEGIN{done=0}
        {
          if(done==0 && match($0, /"id"[[:space:]]*:[[:space:]]*[0-9]+/)){
            sub(/"id"[[:space:]]*:[[:space:]]*[0-9]+/, "\"id\": null")
            done=1
          }
          print
        }
      ' "$file"
    }

    ############################################################
    # Upload dashboard JSON to Grafana
    ############################################################
    upload_dashboard() {
      org="$1"
      folder_uid="$2"
      json="$3"

      tmp="/tmp/payload.json"

      # Build Grafana API payload manually
      echo -n '{"dashboard":' > "$tmp"
      normalize_dashboard_id "$json" >> "$tmp"
      echo -n ',"folderUid":"' >> "$tmp"
      echo -n "$folder_uid" >> "$tmp"
      echo -n '","overwrite":true}' >> "$tmp"

      curl -fsS -X POST \
        "${GRAFANA_URL}/api/dashboards/db" \
        -H "$AUTH" \
        -H "$CT" \
        -H "X-Grafana-Org-Id: ${org}" \
        --data-binary @"$tmp" >/dev/null

      rm -f "$tmp"
    }

    ############################################################
    # Main loop
    ############################################################
    for org in 1 2 3 4 5 6 7; do
      ORG_DIR="${DASH_ROOT}/${org}"
      [ -d "$ORG_DIR" ] || continue

      echo "===== ORG ${org}"

      for folder_dir in "${ORG_DIR}"/*; do
        [ -d "$folder_dir" ] || continue
        folder="$(basename "$folder_dir")"

        echo "[ORG ${org}] folder=${folder}"

        uid="$(get_folder_uid "$org" "$folder")"
        if [ -z "$uid" ]; then
          uid="$(create_folder_uid "$org" "$folder")"
          [ -n "$uid" ] || { echo "[err] failed to create folder ${folder}"; exit 1; }
          echo "  created folder uid=${uid}"
        else
          echo "  existing folder uid=${uid}"
        fi

        for json in "${folder_dir}"/*.json; do
          [ -f "$json" ] || continue
          echo "    upload $(basename "$json")"
          upload_dashboard "$org" "$uid" "$json"
        done
      done
    done

    echo "[done] all dashboards uploaded"