"""Encode and verify the two additional native Godot walking shots."""
import json
import subprocess
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw

capture = Path(__file__).resolve().parent.parent
project = capture.parent.parent
cache = project / ".godot/promo_walk_11_12_20261021"
ffmpeg = Path(r"C:\Program Files\Krita (x64)\bin\ffmpeg.exe")
ffprobe = ffmpeg.with_name("ffprobe.exe")
shots = json.loads((capture / "Capture.json").read_text(encoding="utf-8"))
assert [int(shot["level"]) for shot in shots] == [11, 12]
verification = []
preview = Image.new("RGB", (960, 300), "#172123")
review = Image.new("RGB", (1440, 600), "#172123")
draw = ImageDraw.Draw(preview)
review_draw = ImageDraw.Draw(review)

for index, shot in enumerate(shots):
    number = int(shot["shot"])
    level = int(shot["level"])
    frames = sorted((cache / f"Shot_{number:02d}").glob("frame*.png"))
    assert len(frames) == 120
    for frame_index, frame in enumerate(frames):
        assert frame.name == f"frame{frame_index:08d}.png"
        with Image.open(frame) as image:
            assert image.size == (1920, 1080)
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
    assert video["codec_type"] == "video" and video["codec_name"] == "h264"
    assert (video["width"], video["height"]) == (1920, 1080)
    assert int(video["nb_read_frames"]) == 120 and video["avg_frame_rate"] == "60/1"
    assert abs(float(video["duration"]) - 2) < 0.001
    # Decode start/middle/end frames from the final file, not the source images.
    for column, time in enumerate([0.0, 1.0, 1.95]):
        still = cache / f"Encoded_Review_{number:02d}_{column}.png"
        if not still.exists():
            subprocess.run([
                str(ffmpeg), "-v", "error", "-n", "-ss", str(time), "-i", movie_arg,
                "-frames:v", "1", "-update", "1", still.relative_to(project).as_posix()
            ], check=True, cwd=project)
        with Image.open(still) as image:
            thumb = image.convert("RGB").resize((480, 270), Image.Resampling.LANCZOS)
        x, y = column * 480, index * 300
        review.paste(thumb, (x, y))
        review_draw.text((x + 12, y + 277), f"LEVEL {level:02d} / {time:.2f}s", fill="white")
        if column == 1:
            preview.paste(thumb, (index * 480, 0))
            draw.text((index * 480 + 12, 277), f"LEVEL {level:02d} / 2s / 60fps", fill="white")
    verification.append({
        "file": name, "level": level, "frames": 120, "fps": 60, "duration": 2,
        "resolution": [1920, 1080], "silent": True, "all_frames_grounded": True,
        "floor_y_range": shot["floor_y_range"], "size_bytes": movie.stat().st_size,
    })
    print("WALK_VIDEO_VERIFIED", number, name, flush=True)

preview.save(capture / "Preview.jpg", quality=92)
review.save(capture / "Frames_Review.jpg", quality=92)
(capture / "Verification.json").write_text(json.dumps(verification, ensure_ascii=False, indent=2), encoding="utf-8")
bundle = capture / "Walking_Levels_11_12.zip"
if not bundle.exists():
    with zipfile.ZipFile(bundle, "x", compression=zipfile.ZIP_STORED) as archive:
        for item in verification:
            archive.write(capture / item["file"], arcname=item["file"])
with zipfile.ZipFile(bundle) as archive:
    assert len(archive.namelist()) == 2 and archive.testzip() is None
print("BOTH_WALK_VIDEOS_VERIFIED", flush=True)
