param(
    [Parameter(Mandatory=$true, ParameterSetName='Single')][string]$ImagePath,
    [Parameter(Mandatory=$true, ParameterSetName='Batch')][string]$ImageManifest,
    [string]$LanguageTag='en-US'
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Globalization, ContentType=WindowsRuntime]
$taskMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
function Await-Operation($Operation, [Type]$ResultType) {
    $task = $taskMethod.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    $task.GetAwaiter().GetResult()
}
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new($LanguageTag))
if ($null -eq $engine) { throw "Windows OCR language unavailable: $LanguageTag" }
$paths = if ($PSCmdlet.ParameterSetName -eq 'Batch') {
    @(Get-Content -LiteralPath $ImageManifest -Raw -Encoding UTF8 | ConvertFrom-Json)
} else { @($ImagePath) }
foreach ($path in $paths) {
  $file = Await-Operation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
  $stream = Await-Operation ($file.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
  try {
    $decoder = Await-Operation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $bitmap = Await-Operation ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    try {
        $result = Await-Operation ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
        $words = @(foreach ($line in $result.Lines) {
            foreach ($word in $line.Words) {
                @{text=$word.Text; x=$word.BoundingRect.X; y=$word.BoundingRect.Y;
                  width=$word.BoundingRect.Width; height=$word.BoundingRect.Height}
            }
        })
        @{path=$path; text=$result.Text; words=$words; textAngle=$result.TextAngle;
          engine="Windows.Media.Ocr/$LanguageTag"; osVersion=[Environment]::OSVersion.Version.ToString();
          width=$bitmap.PixelWidth; height=$bitmap.PixelHeight} | ConvertTo-Json -Depth 5 -Compress
    } finally { $bitmap.Dispose() }
  } finally { $stream.Dispose() }
}
