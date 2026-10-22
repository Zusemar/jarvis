"""Local speech worker. JSON lines on stdin/stdout; never opens a socket."""
import contextlib
from concurrent.futures import ThreadPoolExecutor
from collections import OrderedDict
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile

def load_engine(root):
    import onnxruntime
    from kokoro_onnx import Kokoro
    onnxruntime.disable_telemetry_events()
    # Keep library diagnostics away from the JSON protocol.
    with contextlib.redirect_stdout(sys.stderr):
        options = onnxruntime.SessionOptions()
        options.intra_op_num_threads = 2
        options.inter_op_num_threads = 1
        session = onnxruntime.InferenceSession(str(root / "kokoro-v1.0.onnx"), options,
                                              providers=["CPUExecutionProvider"])
        engine = Kokoro.from_session(session, str(root / "voices-v1.0.bin"))
    return engine


def run():
    protocol = sys.stdout
    root = Path(sys.argv[1])
    cache = root / "phrases"
    preparing = "--prepare-cache" in sys.argv
    if preparing:
        cache.mkdir(mode=0o700, exist_ok=True)
    recent = OrderedDict()
    with ThreadPoolExecutor(max_workers=1) as executor, tempfile.TemporaryDirectory(prefix="JarvisKokoro-") as directory:
        engine_future = executor.submit(load_engine, root)
        for line in sys.stdin:
            try:
                request = json.loads(line)
                text, voice, speed = request["text"], request["voice"], request["speed"]
                if not isinstance(text, str) or not text.strip() or len(text) > 3000:
                    raise ValueError("Invalid speech text")
                if not isinstance(voice, str) or not voice.startswith(("af_", "am_", "bf_", "bm_")):
                    raise ValueError("Unsupported English voice")
                if not 0.5 <= speed <= 2:
                    raise ValueError("Invalid speech speed")
                key = hashlib.sha256(json.dumps([text, voice, float(speed)], ensure_ascii=False).encode()).hexdigest()
                cached = cache / (key + ".wav")
                wav = recent.get(key)
                if wav is None and cached.is_file():
                    wav = cached.read_bytes()
                if wav is None:
                    import soundfile
                    engine = engine_future.result(timeout=45)
                    if voice not in engine.get_voices():
                        raise ValueError("Unknown voice")
                    with contextlib.redirect_stdout(sys.stderr):
                        audio, rate = engine.create(text, voice=voice, speed=speed,
                                                    lang="en-gb" if voice.startswith("b") else "en-us")
                    buffer = io.BytesIO()
                    soundfile.write(buffer, audio, rate, format="WAV", subtype="PCM_16")
                    wav = buffer.getvalue()
                if preparing:
                    cached.write_bytes(wav)
                recent[key] = wav
                recent.move_to_end(key)
                while len(recent) > 24:
                    recent.popitem(last=False)
                descriptor, path = tempfile.mkstemp(suffix=".wav", dir=directory)
                with os.fdopen(descriptor, "wb") as output:
                    output.write(wav)
                print(json.dumps({"path": path}), file=protocol, flush=True)
            except Exception as error:
                # Do not log the recognized phrase or spoken text.
                print(json.dumps({"error": type(error).__name__}), file=protocol, flush=True)


if __name__ == "__main__":
    run()
