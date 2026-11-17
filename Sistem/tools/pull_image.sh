#!/usr/bin/env bash
# Usage: pull_image.sh <repo> <tag> <outdir>
# Downloads a Docker Hub image (linux/arm64) without Docker and extracts its layers into outdir.
set -euo pipefail
REPO="$1"; TAG="$2"; OUT="$3"
mkdir -p "$OUT"
TOKEN=$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${REPO}:pull" | python3 -I -c 'import sys,json;print(json.load(sys.stdin)["token"])')
ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'
IDX=$(curl -fsSL -H "Authorization: Bearer $TOKEN" -H "Accept: $ACCEPT" "https://registry-1.docker.io/v2/${REPO}/manifests/${TAG}")
DIGEST=$(printf '%s' "$IDX" | python3 -I -c '
import sys,json
d=json.load(sys.stdin)
if "manifests" in d:
    for m in d["manifests"]:
        p=m.get("platform",{})
        if p.get("os")=="linux" and p.get("architecture")=="arm64":
            print(m["digest"]);break
    else:
        for m in d["manifests"]:
            p=m.get("platform",{})
            if p.get("os")=="linux" and p.get("architecture")=="amd64":
                print(m["digest"]);break
else:
    print("SELF")')
if [ "$DIGEST" = "SELF" ]; then MAN="$IDX"; else
MAN=$(curl -fsSL -H "Authorization: Bearer $TOKEN" -H "Accept: $ACCEPT" "https://registry-1.docker.io/v2/${REPO}/manifests/${DIGEST}"); fi
printf '%s' "$MAN" > "$OUT/.manifest.json"
for L in $(printf '%s' "$MAN" | python3 -I -c 'import sys,json;[print(l["digest"]) for l in json.load(sys.stdin)["layers"]]'); do
  echo "layer $L" >&2
  curl -fsSL -H "Authorization: Bearer $TOKEN" "https://registry-1.docker.io/v2/${REPO}/blobs/${L}" | tar -xz -C "$OUT" 2>/dev/null || true
done
CFG=$(printf '%s' "$MAN" | python3 -I -c 'import sys,json;print(json.load(sys.stdin)["config"]["digest"])')
curl -fsSL -H "Authorization: Bearer $TOKEN" "https://registry-1.docker.io/v2/${REPO}/blobs/${CFG}" > "$OUT/.config.json"
echo "done $REPO:$TAG -> $OUT" >&2
