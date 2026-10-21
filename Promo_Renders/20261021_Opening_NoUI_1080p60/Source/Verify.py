"""Read-only media checks, plus a preview sheet from the encoded video."""
import json
import subprocess
import wave
from pathlib import Path

import numpy as np
from PIL import Image

capture = Path(__file__).resolve().parent.parent
project = capture.parent.parent
ffmpeg = Path(r"C:\Program Files\Krita (x64)\bin\ffmpeg.exe")
ffprobe = ffmpeg.with_name("ffprobe.exe")
movie = capture / "PICTOUR_Opening_NoUI_1920x1080_60fps.mp4"
movie_arg = movie.relative_to(project).as_posix()
metadata = json.loads((capture / "Capture.json").read_text(encoding="utf-8"))
frames = project / ".godot/promo_opening_20261021/Frames1080p"
paths = sorted(frames.glob("frame*.png"))
assert len(paths) == metadata["frame_count"]
assert all(p.name == f"frame{i:08d}.png" for i, p in enumerate(paths))
assert all(Image.open(p).size == (1920, 1080) for p in paths)
assert metadata["frame_count"] - metadata["camera_return_frame"] == 600

probe = json.loads(subprocess.check_output([
    str(ffprobe), "-v", "error", "-count_frames", "-show_streams", "-show_format", "-of", "json", movie_arg
], cwd=project))
video = next(s for s in probe["streams"] if s["codec_type"] == "video")
audio = next(s for s in probe["streams"] if s["codec_type"] == "audio")
assert (video["width"], video["height"]) == (1920, 1080)
assert video["avg_frame_rate"] == "60/1"
assert int(video["nb_read_frames"]) == metadata["frame_count"]
assert abs(float(video["duration"]) - metadata["duration_seconds"]) < 0.001
assert abs(float(audio["duration"]) - metadata["duration_seconds"]) < 0.03

with wave.open(str(project / "Audio/SFX/opening_piano.wav"), "rb") as source:
    rate = source.getframerate()
    assert source.getsampwidth() == 2 and source.getnchannels() == 2
    piano = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").reshape(-1, 2) / 32768.0
decoded_bytes = subprocess.check_output([
    str(ffmpeg), "-v", "error", "-i", movie_arg, "-map", "0:a:0", "-f", "f32le", "-ar", str(rate), "-ac", "2", "pipe:1"
], cwd=project)
decoded = np.frombuffer(decoded_bytes, dtype="<f4").reshape(-1, 2)
delay = round(metadata["piano_start_frame"] * rate / metadata["fps"])
actual = decoded[delay:delay + len(piano)].astype(np.float64)
correlation = float(np.sum(actual * piano) / np.sqrt(np.sum(actual * actual) * np.sum(piano * piano)))
silence = np.concatenate([decoded[:delay - rate // 20].ravel(), decoded[delay + len(piano) + rate // 10:].ravel()])
silence_peak = float(np.max(np.abs(silence)))
assert correlation > 0.98, correlation
assert silence_peak < 0.0001, silence_peak

selected = [36, 100, 153, 300, metadata["camera_return_frame"], metadata["frame_count"] - 1]
selection = "+".join(f"eq(n,{n})" for n in selected)
subprocess.run([
    str(ffmpeg), "-v", "error", "-n", "-i", movie_arg, "-vf",
    f"select='{selection}',scale=480:270,tile=3x2", "-frames:v", "1", "-update", "1", (capture / "Preview.jpg").relative_to(project).as_posix()
], check=True, cwd=project)
result = {
    "video": movie.name, "resolution": [video["width"], video["height"]],
    "fps": 60, "frames": int(video["nb_read_frames"]), "duration_seconds": float(video["duration"]),
    "camera_return_seconds": metadata["camera_return_frame"] / 60, "tail_seconds": 10.0,
    "audio": "Only the original opening_piano.wav, aligned to the Logo reveal frame",
    "piano_start_seconds": delay / rate, "piano_correlation_after_aac": correlation,
    "silence_peak_outside_piano": silence_peak, "file_size_bytes": movie.stat().st_size,
    "all_source_frames_native_1080p": True, "source_frames_continuous": True,
    "all_runtime_ui_checks_passed": metadata["ui_hidden_checks"],
}
(capture / "Verification.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(result, ensure_ascii=False))
