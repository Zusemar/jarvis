"""Prepare only Jarvis's public stock replies, never private track titles."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

parser = argparse.ArgumentParser()
parser.add_argument("--voice", default="af_heart")
parser.add_argument("--speed", type=float, default=1.0)
args = parser.parse_args()
root = Path.home() / "Library/Application Support/Jarvis/Kokoro"
project = Path(__file__).resolve().parent.parent
phrases = json.loads(subprocess.check_output([
    str(project / "dist/Jarvis.app/Contents/MacOS/Jarvis"), "--export-speech-phrases"
]))
worker = subprocess.Popen([str(root / "venv/bin/python"), "-u",
                           str(project / "packaging/kokoro_worker.py"), str(root), "--prepare-cache"],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
try:
    started = time.monotonic()
    for index, phrase in enumerate(phrases, 1):
        worker.stdin.write(json.dumps(dict(text=phrase, voice=args.voice, speed=args.speed)) + "\n")
        worker.stdin.flush()
        response = json.loads(worker.stdout.readline())
        if "path" not in response:
            raise RuntimeError(response)
        Path(response["path"]).unlink()
        print(f"Prepared {index}/{len(phrases)}", flush=True)
    worker.stdin.close()
    if worker.wait(timeout=15) != 0:
        raise RuntimeError("Speech worker failed")
    print(f"Prepared in {time.monotonic() - started:.1f}s", flush=True)
finally:
    if worker.poll() is None:
        worker.terminate()
