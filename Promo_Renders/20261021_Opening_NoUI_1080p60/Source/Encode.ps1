param(
    [string]$Ffmpeg = 'C:\Program Files\Krita (x64)\bin\ffmpeg.exe'
)
$ErrorActionPreference = 'Stop'
$captureRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$metadata = Get-Content -Raw -LiteralPath (Join-Path $captureRoot 'Capture.json') | ConvertFrom-Json
$framePattern = '.godot/promo_opening_20261021/Frames1080p/frame%08d.png'
$pianoPath = 'Audio/SFX/opening_piano.wav'
$outputPath = 'Promo_Renders/20261021_Opening_NoUI_1080p60/PICTOUR_Opening_NoUI_1920x1080_60fps.mp4'
$ffprobePath = Join-Path (Split-Path $Ffmpeg) 'ffprobe.exe'
Push-Location -LiteralPath $projectRoot
try {
$sampleRate = [int](& $ffprobePath -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 $pianoPath)
if ($LASTEXITCODE -ne 0) { throw "FFprobe failed: $LASTEXITCODE" }
$delaySamples = [long][math]::Round($metadata.piano_start_frame * $sampleRate / $metadata.fps)
$endSamples = [long][math]::Round($metadata.frame_count * $sampleRate / $metadata.fps)
$filters = "[0:v]scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p[v];[1:a]adelay=${delaySamples}S:all=1,apad,atrim=end_sample=${endSamples}[a]"
# 不读取游戏录音：唯一音源是原 opening_piano.wav，按实际揭示帧精确延迟。
& $Ffmpeg -hide_banner -n -framerate $metadata.fps -start_number 0 -i $framePattern -i $pianoPath `
    -filter_complex $filters -map '[v]' -map '[a]' -frames:v $metadata.frame_count `
    -c:v libopenh264 -profile:v high -coder cabac -rc_mode quality -b:v 36M -maxrate 48M -bufsize 96M `
    -qmin 12 -qmax 20 -g 60 -allow_skip_frames false -pix_fmt yuv420p `
    -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 `
    -c:a aac -b:a 256k -movflags +faststart $outputPath
if ($LASTEXITCODE -ne 0) { throw "FFmpeg failed: $LASTEXITCODE" }
} finally { Pop-Location }
