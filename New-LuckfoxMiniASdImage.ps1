[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$FirmwareDirectory,

    [Parameter(Mandatory = $true)]
    [string]$OutputImage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sectorSize = 512L
$layout = @(
    [pscustomobject]@{ Name = 'env.img';      StartSector = 0x0L;      SectorCount = 0x40L }
    [pscustomobject]@{ Name = 'idblock.img';  StartSector = 0x40L;     SectorCount = 0x400L }
    [pscustomobject]@{ Name = 'uboot.img';    StartSector = 0x440L;    SectorCount = 0x400L }
    [pscustomobject]@{ Name = 'boot.img';     StartSector = 0x840L;    SectorCount = 0x10000L }
    [pscustomobject]@{ Name = 'oem.img';      StartSector = 0x10840L;  SectorCount = 0x100000L }
    [pscustomobject]@{ Name = 'userdata.img'; StartSector = 0x110840L; SectorCount = 0x80000L }
    [pscustomobject]@{ Name = 'rootfs.img';   StartSector = 0x190840L; SectorCount = 0xC00000L }
)

function Convert-HexToInt64 {
    param([Parameter(Mandatory = $true)][string]$Value)
    return [Convert]::ToInt64(($Value -replace '^0x', ''), 16)
}

$firmwarePath = (Resolve-Path -LiteralPath $FirmwareDirectory).Path
$sdUpdatePath = Join-Path $firmwarePath 'sd_update.txt'
if (-not (Test-Path -LiteralPath $sdUpdatePath -PathType Leaf)) {
    throw "sd_update.txt was not found in: $firmwarePath"
}

$declared = @{}
$linePattern = '^\s*#?\s*(?<name>[A-Za-z0-9_.-]+\.img)\s+(?<startSector>0x[0-9A-Fa-f]+):(?<startByte>0x[0-9A-Fa-f]+)\s+(?<sectorCount>0x[0-9A-Fa-f]+):(?<byteCount>0x[0-9A-Fa-f]+)'
foreach ($line in Get-Content -LiteralPath $sdUpdatePath) {
    if ($line -match $linePattern) {
        $declared[$Matches.name.ToLowerInvariant()] = [pscustomobject]@{
            StartSector = Convert-HexToInt64 $Matches.startSector
            StartByte   = Convert-HexToInt64 $Matches.startByte
            SectorCount = Convert-HexToInt64 $Matches.sectorCount
            ByteCount   = Convert-HexToInt64 $Matches.byteCount
        }
    }
}

foreach ($part in $layout) {
    $key = $part.Name.ToLowerInvariant()
    if (-not $declared.ContainsKey($key)) {
        throw "The layout entry for $($part.Name) is missing from sd_update.txt."
    }

    $entry = $declared[$key]
    $expectedStartByte = $part.StartSector * $sectorSize
    $expectedByteCount = $part.SectorCount * $sectorSize
    if (($entry.StartSector -ne $part.StartSector) -or
        ($entry.StartByte -ne $expectedStartByte) -or
        ($entry.SectorCount -ne $part.SectorCount) -or
        ($entry.ByteCount -ne $expectedByteCount)) {
        throw "Unexpected sd_update.txt layout for $($part.Name). Refusing to create an image."
    }

    $imagePath = Join-Path $firmwarePath $part.Name
    if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
        throw "Required firmware image was not found: $imagePath"
    }

    $length = (Get-Item -LiteralPath $imagePath).Length
    if ($length -gt $expectedByteCount) {
        throw "$($part.Name) is too large for its declared region ($length > $expectedByteCount bytes)."
    }

    Add-Member -InputObject $part -NotePropertyName Path -NotePropertyValue $imagePath
    Add-Member -InputObject $part -NotePropertyName Length -NotePropertyValue $length
}

$outputFullPath = [IO.Path]::GetFullPath($OutputImage)
if (Test-Path -LiteralPath $outputFullPath) {
    throw "Output already exists: $outputFullPath"
}

$finalLength = 0L
foreach ($part in $layout) {
    $end = ($part.StartSector * $sectorSize) + $part.Length
    if ($end -gt $finalLength) { $finalLength = $end }
}
$finalLength = [long]([Math]::Ceiling($finalLength / [double]$sectorSize) * $sectorSize)

if (-not $PSCmdlet.ShouldProcess($outputFullPath, 'Create Luckfox Pico Mini A SD image')) {
    return
}

$outputDirectory = Split-Path -Parent $outputFullPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$buffer = New-Object byte[] (4MB)
$destination = [IO.File]::Open($outputFullPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    $destination.SetLength($finalLength)
    foreach ($part in $layout) {
        $offset = $part.StartSector * $sectorSize
        [void]$destination.Seek($offset, [IO.SeekOrigin]::Begin)
        $source = [IO.File]::OpenRead($part.Path)
        try {
            while (($read = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $destination.Write($buffer, 0, $read)
            }
        }
        finally {
            $source.Dispose()
        }
        Write-Host ('{0,-12} sector 0x{1:X} ({2:N0} bytes)' -f $part.Name, $part.StartSector, $part.Length)
    }
    $destination.Flush($true)
}
catch {
    $destination.Dispose()
    Remove-Item -LiteralPath $outputFullPath -Force -ErrorAction SilentlyContinue
    throw
}
finally {
    if ($null -ne $destination) { $destination.Dispose() }
}

$hash = Get-FileHash -LiteralPath $outputFullPath -Algorithm SHA256
Write-Host "Created: $outputFullPath"
Write-Host "SHA-256: $($hash.Hash)"

