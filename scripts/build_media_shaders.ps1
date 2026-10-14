param([string]$FlutterRoot = 'D:/Tools/flutter')
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$shaderRoot = Join-Path $projectRoot 'assets/shaders'
$compiler = Join-Path $FlutterRoot 'bin/cache/artifacts/engine/windows-x64/impellerc.exe'
$includes = Join-Path $FlutterRoot 'bin/cache/artifacts/engine/windows-x64/shader_lib'
$manifest = Get-Content -LiteralPath (Join-Path $shaderRoot 'socket_media.shaderbundle.json') -Raw
Push-Location $shaderRoot
try {
    & $compiler "--sl=$shaderRoot/socket_media.shaderbundle" "--shader-bundle=$manifest" "--include=$shaderRoot" "--include=$includes" '--gles-language-version=300'
    if ($LASTEXITCODE -ne 0) { throw 'Physical-media shader compilation failed.' }
} finally { Pop-Location }
