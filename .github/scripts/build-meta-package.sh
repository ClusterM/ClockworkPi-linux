#!/usr/bin/env bash
# Build a tiny metapackage linux-image-clockworkpi that Depends on the
# versioned linux-image-<KERNELRELEASE> so apt upgrade pulls new kernels.
#
# Usage:
#   build-meta-package.sh <KERNELRELEASE> <debian-version> <out-dir>
# Example:
#   build-meta-package.sh 7.2.0-clockworkpi 1.42 ./debs

set -euo pipefail

if [[ $# -ne 3 ]]; then
	echo "usage: $0 <KERNELRELEASE> <debian-version> <out-dir>" >&2
	exit 2
fi

kernelrelease="$1"
debver="$2"
out_dir="$(readlink -f "$3")"
mkdir -p "$out_dir"

pkg_name="linux-image-clockworkpi"
arch="arm64"
depends="linux-image-${kernelrelease}"

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

mkdir -p "$work/${pkg_name}/DEBIAN"
cat >"$work/${pkg_name}/DEBIAN/control" <<EOF
Package: ${pkg_name}
Version: ${debver}
Section: kernel
Priority: optional
Architecture: ${arch}
Depends: ${depends}
Maintainer: ClockworkPi-linux CI <noreply@users.noreply.github.com>
Description: ClockworkPi / uConsole Raspberry Pi kernel (metapackage)
 This metapackage always depends on the latest ClockworkPi linux-image
 build published by the project's APT repository. Installing or upgrading
 it pulls in the matching versioned kernel package, which installs modules
 and the default firmware boot images (kernel_2712.img / kernel8.img).
EOF

dpkg-deb --root-owner-group -b "$work/${pkg_name}" \
	"$out_dir/${pkg_name}_${debver}_${arch}.deb"
echo "Built $out_dir/${pkg_name}_${debver}_${arch}.deb (Depends: ${depends})"
