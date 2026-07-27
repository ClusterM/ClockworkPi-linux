#!/usr/bin/env bash
# Inject ClockworkPi firmware hooks into a linux-image_*.deb as
# /etc/kernel/{postinst,postrm}.d/* so they run on the target via the
# package's maintainer script (run-parts on /etc/kernel).
#
# Usage: inject-kernel-hooks.sh <linux-image_*.deb> <hooks-dir>
# hooks-dir must contain postinst.d/ and/or postrm.d/.

set -euo pipefail

if [[ $# -ne 2 ]]; then
	echo "usage: $0 <linux-image.deb> <hooks-dir>" >&2
	exit 2
fi

deb="$(readlink -f "$1")"
hooks="$(readlink -f "$2")"

if [[ ! -f "$deb" ]]; then
	echo "error: deb not found: $deb" >&2
	exit 1
fi
if [[ ! -d "$hooks" ]]; then
	echo "error: hooks dir not found: $hooks" >&2
	exit 1
fi

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

dpkg-deb -R "$deb" "$work/pkg"

mkdir -p "$work/pkg/etc/kernel/postinst.d" "$work/pkg/etc/kernel/postrm.d"

if [[ -d "$hooks/postinst.d" ]]; then
	cp -a "$hooks"/postinst.d/* "$work/pkg/etc/kernel/postinst.d/"
	chmod 755 "$work/pkg/etc/kernel/postinst.d"/*
fi
if [[ -d "$hooks/postrm.d" ]]; then
	cp -a "$hooks"/postrm.d/* "$work/pkg/etc/kernel/postrm.d/"
	chmod 755 "$work/pkg/etc/kernel/postrm.d"/*
fi

# Rebuild in place (same filename)
dpkg-deb --root-owner-group -b "$work/pkg" "$work/out.deb"
mv -f "$work/out.deb" "$deb"
echo "Injected firmware hooks into $(basename "$deb")"
