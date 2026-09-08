param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\artifacts\diagrams\ParaGO_entity_relationship_diagrams.drawio')
)
$ErrorActionPreference = 'Stop'
& python (Join-Path $PSScriptRoot 'generate_diagrams.py') --only erd
if ($LASTEXITCODE -ne 0) { throw 'Diagram generation failed.' }
$defaultPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\artifacts\diagrams\ParaGO_entity_relationship_diagrams.drawio'))
$requestedPath = [IO.Path]::GetFullPath($OutputPath)
if ($requestedPath -ne $defaultPath) {
    Copy-Item -LiteralPath $defaultPath -Destination $requestedPath
}
Write-Output 'Corrected editable diagrams and matching SVGs generated from the shared source.'
