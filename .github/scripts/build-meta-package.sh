#!/usr/bin/env bash
# Build linux-image-clockworkpi metapackage that Depends on linux-image-<KERNELRELEASE>
# and ships shared /etc/kernel/{postinst,postrm}.d firmware hooks.
#
# Hooks belong here (stable package name), not in each versioned linux-image-*.deb:
# those packages must be co-installable, and dpkg forbids two packages owning the
# same path without Replaces. Putting the hooks in every image package caused:
#   trying to overwrite '/etc/kernel/postinst.d/zz-clockworkpi-rpi-firmware',
#   which is also in package linux-image-<older-release>
#
# Usage:
#   build-meta-package.sh <KERNELRELEASE> <debian-version> <out-dir> [hooks-dir] [prev-apt-dir]
# Example:
#   build-meta-package.sh 7.2.0-clockworkpi 1.42 ./debs .github/kernel-hooks ./prev-apt

set -euo pipefail

if [[ $# -lt 3 || $# -gt 5 ]]; then
	echo "usage: $0 <KERNELRELEASE> <debian-version> <out-dir> [hooks-dir] [prev-apt-dir]" >&2
	exit 2
fi

kernelrelease="$1"
debver="$2"
out_dir="$(readlink -f "$3")"
hooks_dir="${4:-}"
prev_apt="${5:-}"
mkdir -p "$out_dir"

pkg_name="linux-image-clockworkpi"
arch="arm64"
depends="linux-image-${kernelrelease}"

if [[ -n "$hooks_dir" ]]; then
	hooks_dir="$(readlink -f "$hooks_dir")"
	if [[ ! -d "$hooks_dir" ]]; then
		echo "error: hooks dir not found: $hooks_dir" >&2
		exit 1
	fi
fi
if [[ -n "$prev_apt" ]]; then
	prev_apt="$(readlink -f "$prev_apt")"
fi

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

mkdir -p "$work/${pkg_name}/DEBIAN"

# Take over hook paths previously shipped inside versioned linux-image-* packages.
# Replaces without Conflicts allows overwriting those files while keeping old
# kernels installed for rollback.
replaces=""
if [[ -n "$prev_apt" && -d "$prev_apt" ]]; then
	replaces="$(
		{
			find "$prev_apt" -type f -name 'linux-image-*.deb' -print0 2>/dev/null \
				| while IFS= read -r -d '' deb; do
					dpkg-deb -f "$deb" Package
				done
		} | awk -v meta="$pkg_name" '$0 != meta && $0 ~ /^linux-image-/ { print }' \
			| LC_ALL=C sort -u \
			| paste -sd, - || true
	)"
fi

control_extra=""
if [[ -n "$replaces" ]]; then
	control_extra="Replaces: ${replaces}"
fi

cat >"$work/${pkg_name}/DEBIAN/control" <<EOF
Package: ${pkg_name}
Version: ${debver}
Section: kernel
Priority: optional
Architecture: ${arch}
Depends: ${depends}
${control_extra}
Maintainer: ClockworkPi-linux CI <noreply@users.noreply.github.com>
Description: ClockworkPi / uConsole Raspberry Pi kernel (metapackage)
 This metapackage always depends on the latest ClockworkPi linux-image
 build published by the project's APT repository. Installing or upgrading
 it pulls in the matching versioned kernel package and installs shared
 firmware boot hooks (kernel_2712.img / kernel8.img via /etc/kernel hooks).
EOF
# Drop empty line if Replaces was omitted
sed -i '/^$/d' "$work/${pkg_name}/DEBIAN/control"

if [[ -n "$hooks_dir" ]]; then
	mkdir -p "$work/${pkg_name}/etc/kernel/postinst.d" \
		"$work/${pkg_name}/etc/kernel/postrm.d"
	if [[ -d "$hooks_dir/postinst.d" ]]; then
		cp -a "$hooks_dir"/postinst.d/* "$work/${pkg_name}/etc/kernel/postinst.d/"
		chmod 755 "$work/${pkg_name}/etc/kernel/postinst.d"/*
	fi
	if [[ -d "$hooks_dir/postrm.d" ]]; then
		cp -a "$hooks_dir"/postrm.d/* "$work/${pkg_name}/etc/kernel/postrm.d/"
		chmod 755 "$work/${pkg_name}/etc/kernel/postrm.d"/*
	fi
fi

dpkg-deb --root-owner-group -b "$work/${pkg_name}" \
	"$out_dir/${pkg_name}_${debver}_${arch}.deb"
echo "Built $out_dir/${pkg_name}_${debver}_${arch}.deb (Depends: ${depends}${replaces:+; Replaces: ${replaces}})"
