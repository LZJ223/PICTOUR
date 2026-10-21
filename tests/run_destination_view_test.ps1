param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [switch]$WithRendering
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotExecutable = (Resolve-Path -LiteralPath $Godot).Path
# Resource junctions share only project assets/cache. The copied configuration
# redirects saves before any autoload starts; the normal progress.json is untouched.
$qaRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('pictour-destination-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $qaRoot | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.godot/global_script_class_cache.cfg'))) {
    & $godotExecutable --headless --path $projectRoot --import
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
}
$config = Get-Content -LiteralPath (Join-Path $projectRoot 'project.godot') -Raw
$config = $config.Replace('[application]', "[application]`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"PICTOUR_destination_view_qa`"")
Set-Content -LiteralPath (Join-Path $qaRoot 'project.godot') -Value $config -Encoding utf8
Get-ChildItem -LiteralPath $projectRoot -Directory -Force | Where-Object { $_.Name -ne '.git' } | ForEach-Object {
    New-Item -ItemType Junction -Path (Join-Path $qaRoot $_.Name) -Target $_.FullName | Out-Null
}
$runArgs = @('--path', $qaRoot, 'res://tests/destination_view_test.tscn', '--log-file', (Join-Path $qaRoot 'test.log'))
if ($WithRendering) {
    $runArgs += @('--audio-driver', 'Dummy', '--resolution', '1280x720')
} else {
    $runArgs += '--headless'
}
Write-Host "QA project and log: $qaRoot"
& $godotExecutable @runArgs
exit $LASTEXITCODE
