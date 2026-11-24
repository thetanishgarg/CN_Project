#!/bin/bash
# Rebuild EVIDENCE.html, EVIDENCE.pdf, the figure PNGs and MANIFEST.sha256 from the evidence files.
set -e; cd "$(dirname "$0")"
python3 derive.py; python3 build_evidence.py; node shots.mjs
