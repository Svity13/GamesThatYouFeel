# Games That Feel You: Emotion-Aware Interrogation Game

A short story game where a detective reacts to your webcam-estimated emotion
(calm, anxious, scared). We compare three versions:
A = buttons only, B = hidden sensing, C = open sensing (you can see, correct and switch it off).

## Requirements
- Godot 4.3 or newer (standard version, not .NET): https://godotengine.org
- Python 3.10 to 3.12
- A webcam (not needed for condition A)
- Tested on: Ubuntu lab computer [add version], macOS [add version]

## Install and run
1. In a terminal, from this folder: `./run_tracker.sh`
   (first run creates a virtual environment, installs the libraries and downloads the face model, so it needs internet).
   On Ubuntu you may need: `sudo apt install python3-venv`
2. Open Godot, click Import, choose `godot/project.godot`, press F5.
3. In the game: tick the consent box, press Calibrate (relaxed face, 3 seconds), then pick A, B or C.
Leave the tracker running while you play. Esc quits.

## How it works
The Python tracker reads the webcam with MediaPipe, turns facial expression scores into
calm / anxious / scared estimates, and sends only those numbers to Godot on localhost.
No video is shown, saved or sent anywhere.

## Logged data and analysis
Each run saves a CSV (path shown at the end of the game; on macOS under
~/Library/Application Support/Godot/app_userdata/). Anonymised logs are in `data/`.
[Explain how to reproduce the analysis, for example `python3 analysis/analyse.py`]
Example output: [paste a few lines of a real log]

## What is simulated / limits
The emotion estimate is a simple rule on facial expression scores, not a true reading of feelings,
and it is often wrong. The story is short and scripted.

## AI use
Code was written with help from Claude (Anthropic): [list which files and parts].
Team members can explain the code they committed.

## Team
[names and roles]
