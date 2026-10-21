"""Encode ten silent 2-second shots, verify metadata, and produce a preview sheet."""
import json
import subprocess
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw

capture = Path(__file__).resolve().parent.parent
project = capture.parent.parent
ffmpeg = Path(r"C:\Program Files\Krita (x64)\bin\ffmpeg.exe")
ffprobe = ffmpeg.with_name("ffprobe.exe")
cache = project / ".godot/promo_walk_20261021"
shots = json.loads((capture / "Capture.json").read_text(encoding="utf-8"))
assert len(shots) == 10
verification = []
preview = Image.new("RGB", (960, 5 * 300), "#172123")
draw = ImageDraw.Draw(preview)
for index, shot in enumerate(shots):
    number = index + 1
    level = int(shot["level"])
    frames = sorted((cache / f"Shot_{number:02d}").glob("frame*.png"))
    assert len(frames) == 120
    assert all(path.name == f"frame{i:08d}.png" for i, path in enumerate(frames))
    assert all(Image.open(path).size == (1920, 1080) for path in frames)
    assert shot["all_frames_grounded"] and shot["floor_y_range"] < 0.5
    assert shot["minimum_speed"] > 250
    name = f"Walk_{number:02d}_Level_{level:02d}_2s_1080p60.mp4"
    movie = capture / name
    movie_arg = movie.relative_to(project).as_posix()
    if not movie.exists():
        pattern = (frames[0].parent / "frame%08d.png").relative_to(project).as_posix()
        subprocess.run([
            str(ffmpeg), "-v", "warning", "-n", "-framerate", "60", "-start_number", "0", "-i", pattern,
            "-vf", "scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p",
            "-frames:v", "120", "-an", "-c:v", "libopenh264", "-profile:v", "high", "-coder", "cabac",
            "-rc_mode", "quality", "-b:v", "36M", "-maxrate", "48M", "-qmin", "12", "-qmax", "20",
            "-g", "60", "-allow_skip_frames", "false", "-movflags", "+faststart", movie_arg,
        ], check=True, cwd=project)
    info = json.loads(subprocess.check_output([
        str(ffprobe), "-v", "error", "-count_frames", "-show_streams", "-show_format", "-of", "json", movie_arg
    ], cwd=project))
    assert len(info["streams"]) == 1
    video = info["streams"][0]
    assert video["codec_type"] == "video"
    assert (video["width"], video["height"]) == (1920, 1080)
    assert int(video["nb_read_frames"]) == 120 and video["avg_frame_rate"] == "60/1"
    assert abs(float(video["duration"]) - 2) < 0.001
    still = cache / f"Encoded_Preview_{number:02d}.png"
    if not still.exists():
        subprocess.run([
            str(ffmpeg), "-v", "error", "-n", "-ss", "1", "-i", movie_arg,
            "-frames:v", "1", "-update", "1", still.relative_to(project).as_posix()
        ], check=True, cwd=project)
    thumb = Image.open(still).convert("RGB").resize((480, 270), Image.Resampling.LANCZOS)
    x, y = (index % 2) * 480, (index // 2) * 300
    preview.paste(thumb, (x, y))
    draw.text((x + 12, y + 277), f"{number:02d} / LEVEL {level:02d} / 2s / 60fps", fill="white")
    verification.append({"file": name, "level": level, "frames": 120, "fps": 60,
                         "duration": 2, "resolution": [1920, 1080], "silent": True,
                         "all_frames_grounded": True, "floor_y_range": shot["floor_y_range"],
                         "size_bytes": movie.stat().st_size})
    print("WALK_VIDEO_VERIFIED", number, name, flush=True)
preview.save(capture / "Preview.jpg", quality=92)
(capture / "Verification.json").write_text(json.dumps(verification, ensure_ascii=False, indent=2), encoding="utf-8")
bundle = capture / "All_10_Walking_Clips.zip"
if not bundle.exists():
    with zipfile.ZipFile(bundle, "x", compression=zipfile.ZIP_STORED) as archive:
        for item in verification:
            archive.write(capture / item["file"], arcname=item["file"])
with zipfile.ZipFile(bundle) as archive:
    assert len(archive.namelist()) == 10 and archive.testzip() is None
print("ALL_TEN_WALK_VIDEOS_VERIFIED", flush=True)
