#!/usr/bin/env bash
# DEPRECATED: firmware hooks must not be injected into versioned linux-image-*.deb
# packages. Those packages are co-installable across KERNELRELEASE values, but
# dpkg rejects two packages owning the same /etc/kernel/*.d path.
#
# Hooks are shipped by linux-image-clockworkpi (see build-meta-package.sh).
#
# This script remains only so old workflow revisions fail loudly if revived.

set -euo pipefail

echo "error: inject-kernel-hooks.sh is deprecated." >&2
echo "Ship firmware hooks via build-meta-package.sh (linux-image-clockworkpi)." >&2
exit 1
