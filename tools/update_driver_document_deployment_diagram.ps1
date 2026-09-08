$ErrorActionPreference = 'Stop'
& python (Join-Path $PSScriptRoot 'generate_diagrams.py') --only deployment
if ($LASTEXITCODE -ne 0) { throw 'Deployment diagram generation failed.' }
Write-Output 'Deployment diagram regenerated with private S3 uploads and presigned client reads.'
