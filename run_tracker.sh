#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
if [ ! -d venv ]; then python3 -m venv venv; fi
source venv/bin/activate
pip install -r tracker/requirements.txt
python3 tracker/tracker.py
