"""Talk-back's Kokoro voice: speaks a line into a wav file, with the model kept loaded.

Usage: speak.py serve | check
  serve  reads lines on stdin, "say<tab>voice<tab>text" or "quit", and prints "ready" once
         the model is loaded, then "audio<tab>path" for each line, or "problem<tab>reason".
  check  loads the model and speaks one line, for voice-install.sh; exits non-zero on failure.

Runs in the environment voice-install.sh makes in ~/.local/share/omv/voice. The protocol
loop takes the speaking function as an argument, so tests drive it without the model.
"""

import os
import sys
import tempfile
import wave

MODEL = "mlx-community/Kokoro-82M-bf16"
# Homebrew's espeak-ng: the copy bundled with espeakng-loader looks for its data in the folder
# it was built in, which no Mac has.
ESPEAK_LIBRARY = "/opt/homebrew/lib/libespeak-ng.dylib"
ESPEAK_DATA = "/opt/homebrew/share/espeak-ng-data"
VOICES = {"af_heart", "am_michael"}


def load_speaker():
    """Loads Kokoro once and gives a function that speaks (voice, text) into a wav file."""
    import misaki.espeak  # noqa: F401  points phonemizer at the bundled espeak on import
    from phonemizer.backend.espeak.wrapper import EspeakWrapper

    EspeakWrapper.set_library(ESPEAK_LIBRARY)
    EspeakWrapper.set_data_path(ESPEAK_DATA)
    import mlx.core as mx
    import numpy as np
    from mlx_audio.tts.utils import load_model

    model = load_model(model_path=MODEL)
    folder = tempfile.mkdtemp(prefix="omv-speak-")
    count = 0

    def speak(voice, text):
        nonlocal count
        chunks = []
        for result in model.generate(text=text, voice=voice, lang_code="a"):
            if result.audio.size:
                mx.eval(result.audio)
                chunks.append(np.array(result.audio))
        if not chunks:
            raise RuntimeError("no audio")
        samples = np.clip(np.concatenate(chunks), -1, 1)
        count += 1
        path = os.path.join(folder, f"line-{count % 4}.wav")
        with wave.open(path, "wb") as file:
            file.setnchannels(1)
            file.setsampwidth(2)
            file.setframerate(model.sample_rate)
            file.writeframes((samples * 32767).astype("<i2").tobytes())
        return path

    return speak


def serve(speak, lines, out):
    """The protocol: ready, then an audio path or a problem for each say line, until quit."""
    out.write("ready\n")
    out.flush()
    for line in lines:
        line = line.rstrip("\n")
        if line == "quit":
            return
        parts = line.split("\t", 2)
        if len(parts) != 3 or parts[0] != "say" or parts[1] not in VOICES or not parts[2].strip():
            out.write("problem\tbad line\n")
        else:
            try:
                out.write(f"audio\t{speak(parts[1], parts[2])}\n")
            except Exception as error:  # a line that fails never stops the server
                out.write(f"problem\t{type(error).__name__}\n")
        out.flush()


def main(argv):
    if argv[1:] == ["serve"]:
        serve(load_speaker(), sys.stdin, sys.stdout)
        return 0
    if argv[1:] == ["check"]:
        print(load_speaker()("af_heart", "omv is ready."))
        return 0
    print("usage: speak.py serve | check", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
