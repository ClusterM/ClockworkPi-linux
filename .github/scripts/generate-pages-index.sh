#!/usr/bin/env bash
# Write pages/index.html with APT setup instructions.
# Usage: generate-pages-index.sh <pages-dir> <KERNELRELEASE>
set -euo pipefail

if [[ $# -ne 2 ]]; then
	echo "usage: $0 <pages-dir> <KERNELRELEASE>" >&2
	exit 2
fi

pages_dir="$(readlink -f "$1")"
kernelrelease="$2"
mkdir -p "$pages_dir"

owner="${GITHUB_REPOSITORY_OWNER:-ClusterM}"
repo="${GITHUB_REPOSITORY:-ClusterM/ClockworkPi-linux}"
repo_name="${repo#*/}"
base="https://${owner}.github.io/${repo_name}"
apt_base="${base}/apt"
run_url="${GITHUB_SERVER_URL:-https://github.com}/${repo}/actions/runs/${GITHUB_RUN_ID:-0}"
updated="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

python3 - "$pages_dir" "$kernelrelease" "$base" "$apt_base" "$repo" "$run_url" "$updated" <<'PY'
import html
import os
import sys
from pathlib import Path

pages_dir, kernel, base, apt_base, repo, run_url, updated = sys.argv[1:8]

doc = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ClockworkPi kernel APT</title>
  <style>
    body {{ font-family: system-ui, sans-serif; max-width: 46rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; }}
    code, pre {{ background: #f0f0f0; border-radius: 4px; }}
    code {{ padding: 0.12em 0.35em; }}
    pre {{ padding: 0.75rem 1rem; overflow-x: auto; }}
    a {{ color: #0969da; }}
  </style>
</head>
<body>
  <h1>Raspberry Pi Kernel for uConsole CM4/CM5</h1>
  <p><strong>Last updated:</strong> {html.escape(updated)}</p>
  <p><strong>Kernel release:</strong> <code>{html.escape(kernel)}</code></p>

  <h2>APT repository</h2>
  <p>Add the repository, then install the metapackage:</p>
  <pre>curl -fsSL {html.escape(apt_base)}/key.gpg \\
  | sudo gpg --dearmor -o /usr/share/keyrings/clockworkpi-linux.gpg
echo "deb [signed-by=/usr/share/keyrings/clockworkpi-linux.gpg arch=arm64] {html.escape(apt_base)} stable main" \\
  | sudo tee /etc/apt/sources.list.d/clockworkpi-linux.list
sudo apt update
sudo apt install linux-image-clockworkpi
sudo reboot</pre>

  <p>Later upgrades:</p>
  <pre>sudo apt update && sudo apt upgrade
sudo reboot</pre>

  <p>Repository base: <a href="{html.escape(apt_base)}/"><code>{html.escape(apt_base)}/</code></a></p>
  <p><strong>Source:</strong> <a href="https://github.com/{html.escape(repo)}">{html.escape(repo)}</a></p>
  <p><strong>Workflow run:</strong> <a href="{html.escape(run_url)}">{html.escape(run_url)}</a></p>
</body>
</html>
"""
Path(pages_dir, "index.html").write_text(doc, encoding="utf-8")
print(f"Wrote {pages_dir}/index.html")
PY
