"""Encode 12 full-scene player layer cycles with their original synchronized SFX."""
import json
import subprocess
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

capture = Path(__file__).resolve().parent.parent
project = capture.parent.parent
cache = project / ".godot/promo_player_cycle_20261021"
ffmpeg = Path(r"C:\Program Files\Krita (x64)\bin\ffmpeg.exe")
ffprobe = ffmpeg.with_name("ffprobe.exe")
shots = json.loads((capture / "Capture.json").read_text(encoding="utf-8"))
assert [int(shot["level"]) for shot in shots] == list(range(1, 13))
preview = Image.new("RGB", (1440, 1200), "#172123")
review = Image.new("RGB", (1440, 3600), "#172123")
draw, review_draw = ImageDraw.Draw(preview), ImageDraw.Draw(review)
verification = []

for index, shot in enumerate(shots):
    number, level = int(shot["shot"]), int(shot["level"])
    frames = sorted((cache / f"Shot_{number:02d}").glob("frame*.png"))
    assert len(frames) == 30
    for frame_index, path in enumerate(frames):
        assert path.name == f"frame{frame_index:08d}.png"
        with Image.open(path) as image:
            assert image.size == (1920, 1080)
    assert shot["cycle_succeeded"] and shot["target_layer_id"] != shot["source_layer_id"]
    assert shot["player_visible"] and shot["all_layers_visible"] and shot["camera_zoom"] == 1.0
    assert not shot["music"] and not shot["ui"]
    assert shot["cycle_animation_seen"] and shot["wrap_fade_seen"] and shot["intermediate_depth_seen"]
    assert shot["grounded_frames"] == 30 and shot["player_y_range"] < 1.5
    audio = shot["audio"]
    source = str(audio["source"]).removeprefix("res://")
    assert source.startswith("Audio/SFX/") and (project / source).is_file()
    delay_samples = round(int(audio["start_frame"]) * 48000 / 60)
    audio_filter = (
        f"aresample=48000,volume={float(audio['volume_db'])}dB,"
        f"adelay={delay_samples}S:all=1,apad,atrim=end_sample=24000,afade=t=out:st=0.488:d=0.012"
    )
    name = f"Player_Layer_Cycle_{number:02d}_Level_{level:02d}_{shot['motion'].title()}_05s_1080p60.mp4"
    movie = capture / name
    movie_arg = movie.relative_to(project).as_posix()
    if not movie.exists():
        pattern = (frames[0].parent / "frame%08d.png").relative_to(project).as_posix()
        subprocess.run([
            str(ffmpeg), "-v", "warning", "-n", "-framerate", "60", "-start_number", "0", "-i", pattern,
            "-i", source, "-filter_complex",
            f"[0:v]scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p[v];[1:a]{audio_filter}[a]",
            "-map", "[v]", "-map", "[a]", "-frames:v", "30", "-t", "0.5",
            "-c:v", "libopenh264", "-profile:v", "high", "-coder", "cabac", "-rc_mode", "quality",
            "-b:v", "36M", "-maxrate", "48M", "-qmin", "12", "-qmax", "20",
            "-g", "60", "-allow_skip_frames", "false", "-color_range", "tv",
            "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
            "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2", "-movflags", "+faststart", movie_arg,
        ], check=True, cwd=project)
    info = json.loads(subprocess.check_output([
        str(ffprobe), "-v", "error", "-count_frames", "-show_streams", "-show_format", "-of", "json", movie_arg
    ], cwd=project))
    assert len(info["streams"]) == 2
    video = next(stream for stream in info["streams"] if stream["codec_type"] == "video")
    sound = next(stream for stream in info["streams"] if stream["codec_type"] == "audio")
    assert (video["width"], video["height"]) == (1920, 1080)
    assert int(video["nb_read_frames"]) == 30 and video["avg_frame_rate"] == "60/1"
    assert abs(float(video["duration"]) - 0.5) < 0.001 and abs(float(info["format"]["duration"]) - 0.5) < 0.001
    assert sound["codec_name"] == "aac" and sound["sample_rate"] == "48000"
    actual_bytes = subprocess.check_output([
        str(ffmpeg), "-v", "error", "-i", movie_arg, "-map", "0:a:0", "-t", "0.5",
        "-ar", "48000", "-ac", "2", "-f", "s16le", "pipe:1"
    ], cwd=project)
    reference_bytes = subprocess.check_output([
        str(ffmpeg), "-v", "error", "-i", source, "-af", audio_filter, "-t", "0.5",
        "-ar", "48000", "-ac", "2", "-f", "s16le", "pipe:1"
    ], cwd=project)
    actual = np.frombuffer(actual_bytes, dtype="<i2").astype(np.float64) / 32768
    reference = np.frombuffer(reference_bytes, dtype="<i2").astype(np.float64) / 32768
    count = min(len(actual), len(reference))
    correlation = float(np.corrcoef(actual[:count], reference[:count])[0, 1])
    rms_db = float(20 * np.log10(max(np.sqrt(np.mean(actual * actual)), 1e-10)))
    assert correlation > 0.95 and rms_db > -55
    for column, time in enumerate([0.05, 0.15, 0.45]):
        still = cache / f"Encoded_{number:02d}_{column}.png"
        if not still.exists():
            subprocess.run([
                str(ffmpeg), "-v", "error", "-n", "-ss", str(time), "-i", movie_arg,
                "-frames:v", "1", "-update", "1", still.relative_to(project).as_posix()
            ], check=True, cwd=project)
        with Image.open(still) as image:
            thumb = image.convert("RGB").resize((480, 270), Image.Resampling.LANCZOS)
        review.paste(thumb, (column * 480, index * 300))
        review_draw.text((column * 480 + 12, index * 300 + 277),
                         f"{number:02d} / {shot['type']} / {shot['motion']} / {time:.2f}s", fill="white")
        if column == 1:
            x, y = (index % 3) * 480, (index // 3) * 300
            preview.paste(thumb, (x, y))
            draw.text((x + 12, y + 277), f"LEVEL {level:02d} / {shot['motion']} / 0.5s / FULL SCENE", fill="white")
    verification.append({
        "file": name, "level": level, "type": shot["type"], "motion": shot["motion"],
        "resolution": [1920, 1080], "fps": 60, "frames": 30, "duration": 0.5,
        "player_visible": True, "all_layers_visible": True, "layer_count": int(shot["layer_count"]),
        "camera_zoom": 1.0, "ui": False, "music": False,
        "source_layer_id": int(shot["source_layer_id"]), "target_layer_id": int(shot["target_layer_id"]),
        "grounded_frames": int(shot["grounded_frames"]), "cycle_succeeded": True,
        "sfx_source": source, "sfx_start_frame": int(audio["start_frame"]),
        "audio_correlation_to_original_sfx": correlation, "audio_rms_dbfs": rms_db,
        "size_bytes": movie.stat().st_size,
    })
    print("PLAYER_CYCLE_VIDEO_VERIFIED", number, f"SFX correlation={correlation:.6f}", flush=True)

preview.save(capture / "Preview.jpg", quality=93)
review.save(capture / "Frames_Review.jpg", quality=93)
(capture / "Verification.json").write_text(json.dumps(verification, ensure_ascii=False, indent=2), encoding="utf-8")
bundle = capture / "All_12_Player_Layer_Cycle_Clips.zip"
if not bundle.exists():
    with zipfile.ZipFile(bundle, "x", compression=zipfile.ZIP_STORED) as archive:
        for item in verification:
            archive.write(capture / item["file"], arcname=item["file"])
with zipfile.ZipFile(bundle) as archive:
    assert len(archive.namelist()) == 12 and archive.testzip() is None
print("ALL_12_PLAYER_LAYER_CYCLE_VIDEOS_VERIFIED", flush=True)
