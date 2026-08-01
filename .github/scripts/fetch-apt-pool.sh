#!/usr/bin/env bash
# Download an existing GitHub Pages APT pool into <dest-apt-dir> for reuse.
# Usage: fetch-apt-pool.sh <apt-base-url> <dest-apt-dir>
# Example: fetch-apt-pool.sh https://clusterm.github.io/ClockworkPi-linux/apt ./prev-apt

set -euo pipefail

if [[ $# -ne 2 ]]; then
	echo "usage: $0 <apt-base-url> <dest-apt-dir>" >&2
	exit 2
fi

base="${1%/}"
dest="$(mkdir -p "$2" && readlink -f "$2")"
packages_url="${base}/dists/stable/main/binary-arm64/Packages"

tmp="$(mktemp)"
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT

if ! curl -fsSL "$packages_url" -o "$tmp"; then
	echo "No previous Packages index at $packages_url (fresh repo)"
	exit 0
fi

echo "Fetching previous APT pool from $base"
mkdir -p "$dest"

# Keep the index for Replaces discovery even if individual debs are pruned later.
mkdir -p "$dest/dists/stable/main/binary-arm64"
cp "$tmp" "$dest/dists/stable/main/binary-arm64/Packages"

# Filenames in Packages are relative to the apt root (e.g. pool/main/...)
while IFS= read -r rel; do
	[[ -z "$rel" ]] && continue
	out="$dest/$rel"
	mkdir -p "$(dirname "$out")"
	if curl -fsSL "$base/$rel" -o "$out"; then
		echo "  got $rel"
	else
		echo "  warn: failed to fetch $rel" >&2
		rm -f "$out"
	fi
done < <(awk '/^Filename: / {print $2}' "$tmp")

echo "Previous pool staged at $dest"
