$ErrorActionPreference = 'Stop'

$rootPath = Split-Path -Parent $PSScriptRoot
$diagramPath = Join-Path $rootPath 'artifacts/diagrams/ParaGO_deployment_diagram.drawio'
[xml]$document = Get-Content -LiteralPath $diagramPath -Raw
$root = $document.mxfile.diagram.mxGraphModel.root

$awsBoundary = $root.mxCell | Where-Object { $_.id -eq '2' }
$awsBoundary.mxGeometry.height = '830'

$existing = $root.mxCell | Where-Object { $_.id -eq 'driver-documents-s3' }
if (-not $existing) {
    $node = $document.CreateElement('mxCell')
    $node.SetAttribute('id', 'driver-documents-s3')
    $node.SetAttribute('value', "<<node>> Private Amazon S3`nEncrypted driver license documents")
    $node.SetAttribute('style', 'shape=cylinder;whiteSpace=wrap;html=1;fillColor=#ecfdf5;strokeColor=#16803c;fontColor=#14532d;fontSize=14;fontStyle=1;spacing=8;fontFamily=Arial;')
    $node.SetAttribute('vertex', '1')
    $node.SetAttribute('parent', '1')
    $geometry = $document.CreateElement('mxGeometry')
    $geometry.SetAttribute('x', '820')
    $geometry.SetAttribute('y', '650')
    $geometry.SetAttribute('width', '300')
    $geometry.SetAttribute('height', '95')
    $geometry.SetAttribute('as', 'geometry')
    [void]$node.AppendChild($geometry)
    [void]$root.AppendChild($node)

    $edge = $document.CreateElement('mxCell')
    $edge.SetAttribute('id', 'driver-documents-edge')
    $edge.SetAttribute('value', 'private signed access')
    $edge.SetAttribute('style', 'edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;endArrow=block;strokeColor=#202124;fontSize=11;fontFamily=Arial;labelBackgroundColor=#FFFFFF;exitX=0.5;exitY=1;entryX=0.5;entryY=0;exitPerimeter=1;entryPerimeter=1;')
    $edge.SetAttribute('edge', '1')
    $edge.SetAttribute('parent', '1')
    $edge.SetAttribute('source', '8')
    $edge.SetAttribute('target', 'driver-documents-s3')
    $edgeGeometry = $document.CreateElement('mxGeometry')
    $edgeGeometry.SetAttribute('relative', '1')
    $edgeGeometry.SetAttribute('as', 'geometry')
    [void]$edge.AppendChild($edgeGeometry)
    [void]$root.AppendChild($edge)
}

$settings = [System.Xml.XmlWriterSettings]::new()
$settings.Encoding = [System.Text.UTF8Encoding]::new($false)
$settings.Indent = $false
$writer = [System.Xml.XmlWriter]::Create($diagramPath, $settings)
try {
    $document.Save($writer)
} finally {
    $writer.Dispose()
}

Write-Host "Updated $diagramPath"
