#!/usr/bin/env bash
# Build a signed APT repository tree under <pages-dir>/apt from a set of .debs.
#
# Env:
#   APT_GPG_PRIVATE_KEY   armored private key (required)
#   APT_GPG_PASSPHRASE    optional passphrase
#   APT_KEEP_VERSIONS     how many versioned image/headers builds to keep (default 3)
#   APT_ORIGIN            Origin/Label (default ClockworkPi-linux)
#   APT_SUITE             suite name (default stable)
#
# Usage:
#   publish-apt-repo.sh <pages-dir> <debs-dir> [previous-apt-dir]

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
	echo "usage: $0 <pages-dir> <debs-dir> [previous-apt-dir]" >&2
	exit 2
fi

pages_dir="$(readlink -f "$1")"
debs_dir="$(readlink -f "$2")"
prev_apt="${3:-}"
if [[ -n "$prev_apt" ]]; then
	prev_apt="$(readlink -f "$prev_apt")"
fi

keep="${APT_KEEP_VERSIONS:-3}"
origin="${APT_ORIGIN:-ClockworkPi-linux}"
suite="${APT_SUITE:-stable}"
codename="$suite"
component="main"
arch="arm64"

if [[ -z "${APT_GPG_PRIVATE_KEY:-}" ]]; then
	echo "error: APT_GPG_PRIVATE_KEY is not set; refusing to publish an unsigned repo" >&2
	exit 1
fi

if [[ ! -d "$debs_dir" ]]; then
	echo "error: debs dir not found: $debs_dir" >&2
	exit 1
fi

apt_root="$pages_dir/apt"
pool_dir="$apt_root/pool/${component}"
dist_bin="$apt_root/dists/${suite}/${component}/binary-${arch}"
mkdir -p "$pool_dir" "$dist_bin"

if [[ -n "$prev_apt" && -d "$prev_apt/pool" ]]; then
	echo "Merging previous pool from $prev_apt"
	cp -a "$prev_apt"/pool/. "$apt_root/pool/"
fi

shopt -s nullglob
for deb in "$debs_dir"/*.deb; do
	base="$(basename "$deb")"
	pkg="$(dpkg-deb -f "$deb" Package)"
	letter="$(printf '%s' "$pkg" | cut -c1)"
	dest="$pool_dir/${letter}/${pkg}"
	mkdir -p "$dest"
	cp -f "$deb" "$dest/$base"
	echo "Staged $base"
done

# Prune: keep newest N versioned image/headers package names; only newest meta.
python3 - "$pool_dir" "$keep" <<'PY'
import subprocess
import sys
from functools import cmp_to_key
from pathlib import Path

pool = Path(sys.argv[1])
keep = int(sys.argv[2])

def deb_fields(path: Path):
    out = subprocess.check_output(
        ["dpkg-deb", "-f", str(path), "Package", "Version"],
        text=True,
    )
    fields = {}
    for line in out.splitlines():
        if ": " in line:
            k, v = line.split(": ", 1)
            fields[k] = v
    return fields

def dpkg_cmp(a, b):
    if a == b:
        return 0
    if subprocess.call(["dpkg", "--compare-versions", a, "gt", b]) == 0:
        return 1
    return -1

entries = []
for deb in pool.rglob("*.deb"):
    try:
        f = deb_fields(deb)
    except subprocess.CalledProcessError:
        continue
    entries.append(
        {
            "path": deb,
            "package": f["Package"],
            "version": f["Version"],
            "mtime": deb.stat().st_mtime,
        }
    )

def prune(group, retain_count):
    # Newest by Debian Version, then mtime
    ordered = sorted(
        group,
        key=cmp_to_key(lambda a, b: (
            dpkg_cmp(a["version"], b["version"])
            or (1 if a["mtime"] > b["mtime"] else -1 if a["mtime"] < b["mtime"] else 0)
        )),
    )
    for e in ordered[:-retain_count]:
        print(f"Pruning {e['path'].name} ({e['package']} {e['version']})")
        e["path"].unlink(missing_ok=True)

meta = [e for e in entries if e["package"] == "linux-image-clockworkpi"]
images = [
    e for e in entries
    if e["package"].startswith("linux-image-") and e["package"] != "linux-image-clockworkpi"
]
headers = [e for e in entries if e["package"].startswith("linux-headers-")]
other = [
    e for e in entries
    if e not in meta and e not in images and e not in headers
]

if meta:
    prune(meta, 1)
if images:
    prune(images, keep)
if headers:
    prune(headers, keep)
# leave other packages alone

import os
for dirpath, dirnames, filenames in os.walk(pool, topdown=False):
    p = Path(dirpath)
    if p == pool:
        continue
    try:
        next(p.iterdir())
    except StopIteration:
        p.rmdir()
PY

(
	cd "$apt_root"
	dpkg-scanpackages -m "pool/${component}" /dev/null \
		>"dists/${suite}/${component}/binary-${arch}/Packages"
)
gzip -fnk "$dist_bin/Packages"

release_dir="$apt_root/dists/${suite}"
cat >"$release_dir/Release" <<EOF
Origin: ${origin}
Label: ${origin}
Suite: ${suite}
Codename: ${codename}
Architectures: ${arch}
Components: ${component}
Description: ClockworkPi / uConsole Raspberry Pi kernel packages
Date: $(date -Ru)
EOF

(
	cd "$release_dir"
	{
		echo "MD5Sum:"
		for f in $(find "${component}" -type f | sort); do
			printf ' %s %16d %s\n' "$(md5sum "$f" | awk '{print $1}')" "$(stat -c%s "$f")" "$f"
		done
		echo "SHA256:"
		for f in $(find "${component}" -type f | sort); do
			printf ' %s %16d %s\n' "$(sha256sum "$f" | awk '{print $1}')" "$(stat -c%s "$f")" "$f"
		done
	} >>Release
)

gnupg_home="$(mktemp -d)"
chmod 700 "$gnupg_home"
cleanup_gpg() { rm -rf "$gnupg_home"; }
trap cleanup_gpg EXIT
export GNUPGHOME="$gnupg_home"

printenv APT_GPG_PRIVATE_KEY | gpg --batch --import
key_id="$(gpg --batch --list-secret-keys --with-colons | awk -F: '/^sec:/ {print $5; exit}')"
if [[ -z "$key_id" ]]; then
	echo "error: failed to import APT_GPG_PRIVATE_KEY" >&2
	exit 1
fi

gpg_sign=(gpg --batch --yes --armor)
if [[ -n "${APT_GPG_PASSPHRASE:-}" ]]; then
	gpg_sign+=(--pinentry-mode loopback --passphrase "$APT_GPG_PASSPHRASE")
fi

"${gpg_sign[@]}" --export "$key_id" >"$apt_root/key.gpg"

rm -f "$release_dir/InRelease" "$release_dir/Release.gpg"
"${gpg_sign[@]}" --clearsign -u "$key_id" \
	-o "$release_dir/InRelease" "$release_dir/Release"
"${gpg_sign[@]}" --detach-sign -u "$key_id" \
	-o "$release_dir/Release.gpg" "$release_dir/Release"

echo "APT repository ready at $apt_root"
find "$apt_root" -type f | sort
