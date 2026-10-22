"""Local speech worker. JSON lines on stdin/stdout; never opens a socket."""
import contextlib
import json
import os
from pathlib import Path
import sys
import tempfile

import soundfile
import onnxruntime

onnxruntime.disable_telemetry_events()


def run():
    from kokoro_onnx import Kokoro

    root = Path(sys.argv[1])
    # Keep library diagnostics away from the JSON protocol.
    with contextlib.redirect_stdout(sys.stderr):
        options = onnxruntime.SessionOptions()
        options.intra_op_num_threads = 2
        options.inter_op_num_threads = 1
        session = onnxruntime.InferenceSession(str(root / "kokoro-v1.0.onnx"), options,
                                              providers=["CPUExecutionProvider"])
        engine = Kokoro.from_session(session, str(root / "voices-v1.0.bin"))
    voices = set(engine.get_voices())
    with tempfile.TemporaryDirectory(prefix="JarvisKokoro-") as directory:
        for line in sys.stdin:
            try:
                request = json.loads(line)
                text, voice, speed = request["text"], request["voice"], request["speed"]
                if not isinstance(text, str) or not text.strip() or len(text) > 3000:
                    raise ValueError("Invalid speech text")
                if voice not in voices or not voice.startswith(("af_", "am_", "bf_", "bm_")):
                    raise ValueError("Unsupported English voice")
                if not 0.5 <= speed <= 2:
                    raise ValueError("Invalid speech speed")
                with contextlib.redirect_stdout(sys.stderr):
                    audio, rate = engine.create(text, voice=voice, speed=speed,
                                                lang="en-gb" if voice.startswith("b") else "en-us")
                descriptor, path = tempfile.mkstemp(suffix=".wav", dir=directory)
                with os.fdopen(descriptor, "wb") as output:
                    soundfile.write(output, audio, rate, format="WAV", subtype="PCM_16")
                print(json.dumps({"path": path}), flush=True)
            except Exception as error:
                # Do not log the recognized phrase or spoken text.
                print(json.dumps({"error": type(error).__name__}), flush=True)


if __name__ == "__main__":
    run()
