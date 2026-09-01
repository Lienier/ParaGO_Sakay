param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\artifacts\diagrams\ParaGO_entity_relationship_diagrams.drawio')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Escape-Html {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Security.SecurityElement]::Escape($Text)
}

function Add-Element {
    param(
        [System.Xml.XmlDocument]$Document,
        [System.Xml.XmlNode]$Parent,
        [string]$Name,
        [hashtable]$Attributes = @{}
    )

    $element = $Document.CreateElement($Name)
    foreach ($key in $Attributes.Keys) {
        $attribute = $Document.CreateAttribute($key)
        $attribute.Value = [string]$Attributes[$key]
        [void]$element.Attributes.Append($attribute)
    }
    [void]$Parent.AppendChild($element)
    return $element
}

function Add-Cell {
    param(
        [System.Xml.XmlDocument]$Document,
        [System.Xml.XmlNode]$Root,
        [string]$Id,
        [string]$Value,
        [string]$Style,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [string]$Parent = '1'
    )

    $cell = Add-Element $Document $Root 'mxCell' @{
        id = $Id
        value = $Value
        style = $Style
        vertex = '1'
        parent = $Parent
    }
    [void](Add-Element $Document $cell 'mxGeometry' @{
        x = $X
        y = $Y
        width = $Width
        height = $Height
        as = 'geometry'
    })
    return $cell
}

function Add-Edge {
    param(
        [System.Xml.XmlDocument]$Document,
        [System.Xml.XmlNode]$Root,
        [string]$Id,
        [string]$Source,
        [string]$Target,
        [string]$StartArrow = 'ERone',
        [string]$EndArrow = 'ERmany',
        [string]$Label = '',
        [object[]]$Points = @()
    )

    $edgeStyle = "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;endArrow=$EndArrow;startArrow=$StartArrow;strokeColor=#475569;fontSize=11;fontFamily=Arial;labelBackgroundColor=#FFFFFF;jumpStyle=arc;jumpSize=8;"
    $cell = Add-Element $Document $Root 'mxCell' @{
        id = $Id
        value = (Escape-Html $Label)
        style = $edgeStyle
        edge = '1'
        parent = '1'
        source = $Source
        target = $Target
    }
    $geometry = Add-Element $Document $cell 'mxGeometry' @{ relative = '1'; as = 'geometry' }
    if ($Points.Count -gt 0) {
        $array = Add-Element $Document $geometry 'Array' @{ as = 'points' }
        foreach ($point in $Points) {
            [void](Add-Element $Document $array 'mxPoint' @{ x = $point[0]; y = $point[1] })
        }
    }
    return $cell
}

function New-FieldLine {
    param(
        [string]$Name,
        [string]$Type,
        [string]$Key = '',
        [string]$Rule = ''
    )

    $suffix = @()
    if ($Key) { $suffix += $Key }
    if ($Rule) { $suffix += $Rule }
    if ($suffix.Count -gt 0) {
        return "${Name}: $Type [$($suffix -join ', ')]"
    }
    return "${Name}: $Type"
}

function New-EntityValue {
    param(
        [string]$Collection,
        [string[]]$Fields,
        [string[]]$Indexes = @()
    )

    $html = '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;font-family:Arial;font-size:11px;color:#3f2a1d;">'
    $html += "<tr><td colspan=`"4`" align=`"center`" style=`"background-color:#f2a65a;padding:7px 5px;border-bottom:1px solid #a85d24;font-size:13px;`"><b>$(Escape-Html $Collection)</b></td></tr>"
    $html += '<tr style="background-color:#f8c98f;">'
    $html += '<td width="14%" style="padding:4px;border-right:1px solid #c98445;border-bottom:1px solid #c98445;"><b>Key</b></td>'
    $html += '<td width="38%" style="padding:4px;border-right:1px solid #c98445;border-bottom:1px solid #c98445;"><b>Field</b></td>'
    $html += '<td width="32%" style="padding:4px;border-right:1px solid #c98445;border-bottom:1px solid #c98445;"><b>Data type</b></td>'
    $html += '<td width="16%" align="center" style="padding:4px;border-bottom:1px solid #c98445;"><b>Req.</b></td></tr>'

    foreach ($field in $Fields) {
        $name = ''
        $type = ''
        $constraints = ''

        if ($field -match '^(.+?):\s*(.+?)(?:\s+\[(.+)\])?$') {
            $name = $Matches[1].Trim()
            $type = $Matches[2].Trim()
            $constraints = if ($Matches.Count -gt 3) { $Matches[3].Trim() } else { '' }
        }
        else {
            $parts = @($field -split '\s+')
            if ($parts.Count -ge 2) {
                $name = $parts[0]
                $type = $parts[1]
                if ($parts.Count -gt 2) { $constraints = ($parts[2..($parts.Count - 1)] -join ' ') }
            }
            else {
                $name = $field
            }
        }

        $keyParts = @()
        if ($constraints -match '\bPK\b') { $keyParts += 'PK' }
        if ($constraints -match '\bFK\b') { $keyParts += 'FK' }
        if ($constraints -match '\b(UK|unique)\b') { $keyParts += 'UK' }
        if ($constraints -match '\bTTL\b') { $keyParts += 'TTL' }
        $keyText = $keyParts -join '/'
        $required = if ($constraints -match 'required' -or $keyParts -contains 'PK') { 'Yes' } else { 'No' }
        $keyColor = if ($keyParts -contains 'PK') { '#8a4b08' } elseif ($keyParts -contains 'FK') { '#146b3a' } else { '#475569' }

        $html += '<tr style="background-color:#fde6c8;">'
        $html += "<td style=`"padding:4px;border-right:1px solid #d49a62;border-bottom:1px solid #e2b98f;color:$keyColor;`"><b>$(Escape-Html $keyText)</b></td>"
        $html += "<td style=`"padding:4px;border-right:1px solid #d49a62;border-bottom:1px solid #e2b98f;`">$(Escape-Html $name)</td>"
        $html += "<td style=`"padding:4px;border-right:1px solid #d49a62;border-bottom:1px solid #e2b98f;`">$(Escape-Html $type)</td>"
        $html += "<td align=`"center`" style=`"padding:4px;border-bottom:1px solid #e2b98f;`">$required</td></tr>"
    }
    $indexList = @($Indexes)
    if ($null -ne $Indexes -and $indexList.Count -gt 0) {
        $html += "<tr><td colspan=`"4`" style=`"background-color:#fff4e6;padding:5px;color:#6b4a32;font-size:10px;`"><b>Indexes:</b> $(Escape-Html ($indexList -join '; '))</td></tr>"
    }
    return "$html</table>"
}

function Add-Entity {
    param(
        [System.Xml.XmlDocument]$Document,
        [System.Xml.XmlNode]$Root,
        [string]$Id,
        [string]$Collection,
        [string[]]$Fields,
        [int]$X,
        [int]$Y,
        [int]$Width = 300,
        [string[]]$Indexes = @()
    )

    $fieldCount = @($Fields).Count
    $indexCount = if ($null -eq $Indexes) { 0 } else { @($Indexes).Count }
    $height = [Math]::Max(118, 56 + ($fieldCount * 25) + $(if ($indexCount -gt 0) { 29 } else { 0 }))
    $style = 'rounded=1;arcSize=6;html=1;whiteSpace=wrap;overflow=hidden;fillColor=#fde6c8;strokeColor=#a85d24;strokeWidth=1.5;fontColor=#3f2a1d;fontSize=11;verticalAlign=top;align=left;spacing=0;fontFamily=Arial;shadow=0;'
    return Add-Cell $Document $Root $Id (New-EntityValue $Collection $Fields $Indexes) $style $X $Y $Width $height
}

function Add-Note {
    param(
        [System.Xml.XmlDocument]$Document,
        [System.Xml.XmlNode]$Root,
        [string]$Id,
        [string]$Title,
        [string[]]$Lines,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height
    )

    $value = "<b>$(Escape-Html $Title)</b>"
    foreach ($line in $Lines) { $value += "<br>$(Escape-Html $line)" }
    $style = 'rounded=1;whiteSpace=wrap;html=1;fillColor=#f8fafc;strokeColor=#94a3b8;fontColor=#334155;fontSize=12;spacing=8;fontFamily=Arial;'
    return Add-Cell $Document $Root $Id $value $style $X $Y $Width $Height
}

function Add-Title {
    param(
        [System.Xml.XmlDocument]$Document,
        [System.Xml.XmlNode]$Root,
        [string]$Id,
        [string]$Title,
        [int]$PageWidth
    )

    $style = 'text;html=1;align=center;verticalAlign=middle;fontFamily=Arial;fontSize=22;fontStyle=1;fontColor=#17324D;spacing=4;'
    [void](Add-Cell $Document $Root $Id (Escape-Html $Title) $style 30 10 ($PageWidth - 60) 30)
}

function New-Diagram {
    param(
        [System.Xml.XmlDocument]$Document,
        [System.Xml.XmlNode]$MxFile,
        [string]$Id,
        [string]$Name,
        [int]$PageWidth,
        [int]$PageHeight
    )

    $diagram = Add-Element $Document $MxFile 'diagram' @{ id = $Id; name = $Name }
    $model = Add-Element $Document $diagram 'mxGraphModel' @{
        dx = '1600'; dy = '1100'; grid = '1'; gridSize = '10'; guides = '1'
        tooltips = '1'; connect = '1'; arrows = '1'; fold = '1'; page = '1'
        pageScale = '1'; pageWidth = $PageWidth; pageHeight = $PageHeight
        math = '0'; shadow = '0'; background = '#FFFFFF'
    }
    $root = Add-Element $Document $model 'root'
    [void](Add-Element $Document $root 'mxCell' @{ id = '0' })
    [void](Add-Element $Document $root 'mxCell' @{ id = '1'; parent = '0' })
    Add-Title $Document $root "title-$Id" "ParaGO $Name" $PageWidth
    return $root
}

$doc = New-Object System.Xml.XmlDocument
$doc.AppendChild($doc.CreateXmlDeclaration('1.0', 'utf-8', $null)) | Out-Null
$mxfile = Add-Element $doc $doc 'mxfile' @{
    host = 'app.diagrams.net'
    modified = '2026-09-01T00:00:00.000Z'
    agent = 'ParaGO Codex'
    version = '24.7.17'
}

$baseFields = @{
    users = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'email' 'String' 'UK' 'required'),
        (New-FieldLine 'passwordHash' 'String' '' 'hidden'),
        (New-FieldLine 'fullName' 'String' '' 'required'),
        (New-FieldLine 'phone' 'String'),
        (New-FieldLine 'role' 'String' '' 'PASSENGER|DRIVER|ADMIN'),
        (New-FieldLine 'authProvider' 'String' '' 'local|google|facebook'),
        (New-FieldLine 'providerId' 'String' 'partial UK'),
        (New-FieldLine 'status' 'String' '' 'active|suspended|deactivated'),
        (New-FieldLine 'isVerified' 'Boolean'),
        (New-FieldLine 'lastLoginAt' 'Date'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    passengers = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'userId' 'ObjectId' 'FK users._id' 'required unique'),
        (New-FieldLine 'phone' 'String'),
        (New-FieldLine 'photoUrl' 'String'),
        (New-FieldLine 'emergencyContact' 'Embedded object'),
        (New-FieldLine 'defaultRouteId' 'ObjectId' 'FK routes._id'),
        (New-FieldLine 'lastKnownLocation' 'GeoJSON Point' '2dsphere'),
        (New-FieldLine 'lastSeenAt' 'Date'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    drivers = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'userId' 'ObjectId' 'FK users._id' 'required unique'),
        (New-FieldLine 'licenseNumber' 'String'),
        (New-FieldLine 'employeeNumber' 'String'),
        (New-FieldLine 'phone' 'String'),
        (New-FieldLine 'licenseDocuments.front' 'Embedded document' '' 'private S3 object metadata'),
        (New-FieldLine 'licenseDocuments.back' 'Embedded document' '' 'private S3 object metadata'),
        (New-FieldLine 'assignedJeepneyId' 'ObjectId' 'FK jeepneys._id'),
        (New-FieldLine 'assignedRouteId' 'ObjectId' 'FK routes._id'),
        (New-FieldLine 'status' 'String' '' 'active|inactive'),
        (New-FieldLine 'operatingMode' 'String' '' 'route|terminal_queue'),
        (New-FieldLine 'terminalQueueStatus' 'String'),
        (New-FieldLine 'terminalQueueNumber' 'Number'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    admins = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'userId' 'ObjectId' 'FK users._id' 'required unique'),
        (New-FieldLine 'permissions' 'Array<String>'),
        (New-FieldLine 'notes' 'String'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    jeepneys = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'plateNumber' 'String' 'UK' 'required'),
        (New-FieldLine 'capacity' 'Number'),
        (New-FieldLine 'vehicleTag' 'String'),
        (New-FieldLine 'jeepneyName' 'String'),
        (New-FieldLine 'manufacturer' 'String'),
        (New-FieldLine 'capacityBand' 'String'),
        (New-FieldLine 'status' 'String' '' 'active|inactive|maintenance'),
        (New-FieldLine 'currentDriverId' 'ObjectId' 'FK drivers._id'),
        (New-FieldLine 'lastKnownLocation' 'GeoJSON Point' '2dsphere'),
        (New-FieldLine 'latestLocationOrder' 'Embedded object'),
        (New-FieldLine 'lastSeenAt' 'Date'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    routes = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'name' 'String' '' 'required'),
        (New-FieldLine 'code' 'String' 'UK' 'required'),
        (New-FieldLine 'direction' 'String' '' 'up|down|circular'),
        (New-FieldLine 'status' 'String' '' 'active|inactive'),
        (New-FieldLine 'description' 'String'),
        (New-FieldLine 'path' 'GeoJSON LineString' '2dsphere'),
        (New-FieldLine 'waypoints' 'Array<Embedded>'),
        (New-FieldLine 'stops' 'Array<Embedded>'),
        (New-FieldLine 'terminal' 'Embedded object'),
        (New-FieldLine 'navigation' 'Embedded object'),
        (New-FieldLine 'fareConfig' 'Embedded object'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    tripsessions = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'jeepneyId' 'ObjectId' 'FK jeepneys._id' 'required'),
        (New-FieldLine 'driverId' 'ObjectId' 'FK drivers._id'),
        (New-FieldLine 'routeId' 'ObjectId' 'FK routes._id' 'required'),
        (New-FieldLine 'routePathSnapshot' 'GeoJSON LineString'),
        (New-FieldLine 'status' 'String' '' 'scheduled|active|completed|cancelled'),
        (New-FieldLine 'startedAt, endedAt' 'Date'),
        (New-FieldLine 'acceptRequests' 'Boolean'),
        (New-FieldLine 'manualOccupancyCount' 'Number'),
        (New-FieldLine 'occupancyCount' 'Number'),
        (New-FieldLine 'active' 'Boolean'),
        (New-FieldLine 'operatingMode' 'String'),
        (New-FieldLine 'terminalQueueStatus' 'String'),
        (New-FieldLine 'terminalQueueNumber' 'Number' 'partial UK'),
        (New-FieldLine 'terminalLocation' 'GeoJSON Point'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    pickuprequests = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'passengerId' 'ObjectId' 'FK passengers._id' 'required'),
        (New-FieldLine 'tripSessionId' 'ObjectId' 'FK tripsessions._id' 'required'),
        (New-FieldLine 'routeId' 'ObjectId' 'FK routes._id' 'required'),
        (New-FieldLine 'stopRef' 'String'),
        (New-FieldLine 'pickupLocation' 'GeoJSON Point'),
        (New-FieldLine 'destinationLocation' 'GeoJSON Point' '2dsphere'),
        (New-FieldLine 'pickupType' 'String' '' 'roadside|terminal'),
        (New-FieldLine 'terminalLocation' 'GeoJSON Point'),
        (New-FieldLine 'fareSnapshot' 'Embedded object'),
        (New-FieldLine 'status' 'String'),
        (New-FieldLine 'acknowledgedBy' 'ObjectId' 'FK drivers._id'),
        (New-FieldLine 'autoBoarding' 'Embedded object'),
        (New-FieldLine 'expiresAt' 'Date' 'TTL'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    ridesessions = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'passengerId' 'ObjectId' 'FK passengers._id' 'required'),
        (New-FieldLine 'tripSessionId' 'ObjectId' 'FK tripsessions._id' 'required'),
        (New-FieldLine 'pickupRequestId' 'ObjectId' 'FK pickuprequests._id' 'required unique'),
        (New-FieldLine 'pickupType' 'String'),
        (New-FieldLine 'boardingMethod' 'String'),
        (New-FieldLine 'boardingLocation' 'GeoJSON Point' '2dsphere'),
        (New-FieldLine 'destinationLocation' 'GeoJSON Point' '2dsphere'),
        (New-FieldLine 'fareSnapshot' 'Embedded object'),
        (New-FieldLine 'status' 'String'),
        (New-FieldLine 'offboardingMethod' 'String'),
        (New-FieldLine 'autoOffboarding' 'Embedded object'),
        (New-FieldLine 'boardedAt, endedAt' 'Date'),
        (New-FieldLine 'canSendStopAlert' 'Boolean'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    stopalerts = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'passengerId' 'ObjectId' 'FK passengers._id' 'required'),
        (New-FieldLine 'tripSessionId' 'ObjectId' 'FK tripsessions._id' 'required'),
        (New-FieldLine 'rideSessionId' 'ObjectId' 'FK ridesessions._id' 'required'),
        (New-FieldLine 'routeId' 'ObjectId' 'FK routes._id' 'required'),
        (New-FieldLine 'stopRef' 'String'),
        (New-FieldLine 'note' 'String'),
        (New-FieldLine 'status' 'String' '' 'sent|seen|acknowledged|dismissed'),
        (New-FieldLine 'acknowledgedBy' 'ObjectId' 'FK drivers._id'),
        (New-FieldLine 'location' 'GeoJSON Point'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    notifications = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'userId' 'ObjectId' 'FK users._id' 'required'),
        (New-FieldLine 'type' 'String' '' 'required'),
        (New-FieldLine 'title' 'String' '' 'required'),
        (New-FieldLine 'body' 'String' '' 'required'),
        (New-FieldLine 'payload' 'Mixed'),
        (New-FieldLine 'readAt' 'Date'),
        (New-FieldLine 'isRead' 'Boolean'),
        (New-FieldLine 'category' 'String'),
        (New-FieldLine 'expiresAt' 'Date'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    activitylogs = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'actorId' 'ObjectId' 'FK users._id'),
        (New-FieldLine 'actorRole' 'String'),
        (New-FieldLine 'action' 'String' '' 'required'),
        (New-FieldLine 'entity' 'String' '' 'required'),
        (New-FieldLine 'entityId' 'String'),
        (New-FieldLine 'details' 'Mixed'),
        (New-FieldLine 'ip' 'String'),
        (New-FieldLine 'client' 'String'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    refreshtokens = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'userId' 'ObjectId' 'FK users._id' 'required'),
        (New-FieldLine 'tokenHash' 'String' 'UK' 'required'),
        (New-FieldLine 'expiresAt' 'Date' 'TTL'),
        (New-FieldLine 'revokedAt' 'Date'),
        (New-FieldLine 'replacedByHash' 'String'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    passwordresettokens = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'userId' 'ObjectId' 'FK users._id' 'required'),
        (New-FieldLine 'tokenHash' 'String' 'UK' 'required'),
        (New-FieldLine 'expiresAt' 'Date' 'TTL'),
        (New-FieldLine 'usedAt' 'Date'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    adminloginchallenges = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'userId' 'ObjectId' 'FK users._id' 'required'),
        (New-FieldLine 'phone' 'String' '' 'required'),
        (New-FieldLine 'codeHash' 'String' '' 'required'),
        (New-FieldLine 'expiresAt' 'Date' 'TTL'),
        (New-FieldLine 'attempts' 'Number'),
        (New-FieldLine 'maxAttempts' 'Number'),
        (New-FieldLine 'usedAt' 'Date'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    announcements = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'title' 'String' '' 'required max 160'),
        (New-FieldLine 'body' 'String' '' 'required max 5000'),
        (New-FieldLine 'category' 'String'),
        (New-FieldLine 'severity' 'String'),
        (New-FieldLine 'audiences' 'Array<String>' '' 'required'),
        (New-FieldLine 'status' 'String' 'indexed'),
        (New-FieldLine 'revision' 'Number'),
        (New-FieldLine 'startsAt, expiresAt' 'Date'),
        (New-FieldLine 'createdByAdminId' 'ObjectId' 'FK users._id'),
        (New-FieldLine 'updatedByAdminId' 'ObjectId' 'FK users._id'),
        (New-FieldLine 'archivedByAdminId' 'ObjectId' 'FK users._id'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    announcementdismissals = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'announcementId' 'ObjectId' 'FK announcements._id' 'required'),
        (New-FieldLine 'userId' 'ObjectId' 'FK users._id' 'required'),
        (New-FieldLine 'revision' 'Number' 'compound UK' 'required'),
        (New-FieldLine 'dismissedAt' 'Date'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    supportthreads = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'userId' 'ObjectId' 'FK users._id' 'required'),
        (New-FieldLine 'userRole' 'String' '' 'PASSENGER|DRIVER'),
        (New-FieldLine 'assignedAdminId' 'ObjectId' 'FK users._id'),
        (New-FieldLine 'subject' 'String'),
        (New-FieldLine 'category' 'String'),
        (New-FieldLine 'status' 'String'),
        (New-FieldLine 'tripSessionId' 'ObjectId' 'FK tripsessions._id'),
        (New-FieldLine 'pickupRequestId' 'ObjectId' 'FK pickuprequests._id'),
        (New-FieldLine 'rideSessionId' 'ObjectId' 'FK ridesessions._id'),
        (New-FieldLine 'routeId' 'ObjectId' 'FK routes._id'),
        (New-FieldLine 'lastMessageAt' 'Date'),
        (New-FieldLine 'unreadAdminCount, unreadUserCount' 'Number'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    supportmessages = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'threadId' 'ObjectId' 'FK supportthreads._id' 'required'),
        (New-FieldLine 'senderId' 'ObjectId' 'FK users._id' 'required'),
        (New-FieldLine 'senderRole' 'String' '' 'PASSENGER|DRIVER|ADMIN'),
        (New-FieldLine 'body' 'String' '' 'required'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
    reportmetadata = @(
        (New-FieldLine '_id' 'ObjectId' 'PK'),
        (New-FieldLine 'reportType' 'String' '' 'required'),
        (New-FieldLine 'periodStart' 'Date' '' 'required'),
        (New-FieldLine 'periodEnd' 'Date' '' 'required'),
        (New-FieldLine 'generatedBy' 'ObjectId' 'FK users._id' 'required'),
        (New-FieldLine 'params' 'Mixed'),
        (New-FieldLine 'resultSummary' 'Mixed'),
        (New-FieldLine 'fileUrl' 'String'),
        (New-FieldLine 'createdAt, updatedAt' 'Date')
    )
}

$indexMap = @{
    users = @('email unique', 'role+status', 'authProvider+providerId partial unique')
    passengers = @('lastKnownLocation 2dsphere')
    drivers = @('assignedRouteId+status', 'assignedRouteId+operatingMode+terminalQueueStatus')
    jeepneys = @('status+currentDriverId', 'lastKnownLocation 2dsphere')
    routes = @('code unique', 'status', 'path 2dsphere')
    tripsessions = @('status+startedAt', 'jeepneyId+driverId+status', 'routeId+terminalQueueNumber partial unique')
    pickuprequests = @('passengerId+status+createdAt', 'tripSessionId+status', 'expiresAt TTL')
    ridesessions = @('pickupRequestId partial unique', 'boardingLocation 2dsphere', 'destinationLocation 2dsphere')
    stopalerts = @('tripSessionId+status', 'passengerId+status', 'createdAt')
    notifications = @('userId+isRead+createdAt', 'createdAt')
    activitylogs = @('actorId+createdAt', 'entity+entityId+createdAt')
    refreshtokens = @('tokenHash unique', 'expiresAt TTL', 'userId+revokedAt')
    passwordresettokens = @('tokenHash unique', 'expiresAt TTL', 'userId+usedAt')
    adminloginchallenges = @('expiresAt TTL', 'userId+usedAt+createdAt')
    announcements = @('status', 'audiences+status+startsAt', 'status+startsAt+expiresAt')
    announcementdismissals = @('announcementId+userId+revision unique', 'userId+dismissedAt')
    supportthreads = @('userId+createdAt', 'status+lastMessageAt', 'assignedAdminId+status+lastMessageAt')
    supportmessages = @('threadId+createdAt', 'senderId+createdAt')
    reportmetadata = @('reportType+periodStart+periodEnd')
}

$overview = New-Diagram $doc $mxfile 'complete-physical-erd' 'Complete Physical ERD' 1880 1400
$overviewIds = @{
    users='ov-users'; passengers='ov-passengers'; drivers='ov-drivers'; admins='ov-admins'; jeepneys='ov-jeepneys'; routes='ov-routes'; tripsessions='ov-tripsessions'; pickuprequests='ov-pickuprequests'; ridesessions='ov-ridesessions'; stopalerts='ov-stopalerts'; notifications='ov-notifications'; activitylogs='ov-activitylogs'; refreshtokens='ov-refreshtokens'; passwordresettokens='ov-passwordresettokens'; adminloginchallenges='ov-adminloginchallenges'; announcements='ov-announcements'; announcementdismissals='ov-announcementdismissals'; supportthreads='ov-supportthreads'; supportmessages='ov-supportmessages'; reportmetadata='ov-reportmetadata'
}
$overviewFields = @{
    users = @('_id ObjectId PK', 'email String UK', 'role String', 'authProvider String', 'status String')
    passengers = @('_id ObjectId PK', 'userId ObjectId FK UK', 'defaultRouteId ObjectId FK', 'lastKnownLocation Point')
    drivers = @('_id ObjectId PK', 'userId ObjectId FK UK', 'licenseDocuments Embedded', 'assignedJeepneyId ObjectId FK', 'assignedRouteId ObjectId FK', 'operatingMode String')
    admins = @('_id ObjectId PK', 'userId ObjectId FK UK', 'permissions Array')
    jeepneys = @('_id ObjectId PK', 'plateNumber String UK', 'currentDriverId ObjectId FK', 'lastKnownLocation Point')
    routes = @('_id ObjectId PK', 'code String UK', 'path LineString', 'stops Embedded[]', 'terminal Embedded', 'fareConfig Embedded')
    tripsessions = @('_id ObjectId PK', 'jeepneyId ObjectId FK', 'driverId ObjectId FK', 'routeId ObjectId FK', 'terminalQueueNumber Number')
    pickuprequests = @('_id ObjectId PK', 'passengerId ObjectId FK', 'tripSessionId ObjectId FK', 'routeId ObjectId FK', 'expiresAt Date TTL')
    ridesessions = @('_id ObjectId PK', 'passengerId ObjectId FK', 'tripSessionId ObjectId FK', 'pickupRequestId ObjectId FK UK')
    stopalerts = @('_id ObjectId PK', 'passengerId ObjectId FK', 'tripSessionId ObjectId FK', 'rideSessionId ObjectId FK', 'routeId ObjectId FK')
    notifications = @('_id ObjectId PK', 'userId ObjectId FK', 'type String', 'isRead Boolean')
    activitylogs = @('_id ObjectId PK', 'actorId ObjectId FK', 'action String', 'entity String')
    refreshtokens = @('_id ObjectId PK', 'userId ObjectId FK', 'tokenHash String UK', 'expiresAt Date TTL')
    passwordresettokens = @('_id ObjectId PK', 'userId ObjectId FK', 'tokenHash String UK', 'expiresAt Date TTL')
    adminloginchallenges = @('_id ObjectId PK', 'userId ObjectId FK', 'phone String', 'expiresAt Date TTL')
    announcements = @('_id ObjectId PK', 'createdByAdminId ObjectId FK', 'updatedByAdminId ObjectId FK', 'status String')
    announcementdismissals = @('_id ObjectId PK', 'announcementId ObjectId FK', 'userId ObjectId FK', 'revision Number UK')
    supportthreads = @('_id ObjectId PK', 'userId ObjectId FK', 'assignedAdminId ObjectId FK', 'tripSessionId ObjectId FK', 'status String')
    supportmessages = @('_id ObjectId PK', 'threadId ObjectId FK', 'senderId ObjectId FK', 'body String')
    reportmetadata = @('_id ObjectId PK', 'generatedBy ObjectId FK', 'reportType String', 'periodStart Date', 'periodEnd Date')
}
$overviewPositions = @{
    users=@(60,90); passengers=@(430,70); drivers=@(430,285); admins=@(430,500)
    refreshtokens=@(60,330); passwordresettokens=@(60,520); adminloginchallenges=@(60,710)
    jeepneys=@(790,80); routes=@(790,320); tripsessions=@(1140,180)
    pickuprequests=@(1140,455); ridesessions=@(1140,710); stopalerts=@(1490,710)
    notifications=@(1490,80); announcements=@(1490,285); announcementdismissals=@(1490,500)
    supportthreads=@(790,760); supportmessages=@(790,1040); activitylogs=@(1490,1030); reportmetadata=@(1490,1210)
}
foreach ($name in $overviewPositions.Keys) {
    $pos = $overviewPositions[$name]
    [void](Add-Entity $doc $overview $overviewIds[$name] $name $overviewFields[$name] $pos[0] $pos[1] 305)
}
[void](Add-Note $doc $overview 'ov-note' 'Physical Model Notes' @(
    'PK = MongoDB _id ObjectId.',
    'FK = ObjectId reference enforced by application/Mongoose.',
    'UK = unique index.',
    'TTL = MongoDB expiration index.',
    'Embedded fields are stored inside the parent document.'
) 60 1110 650 150)

$edgeId = 1
function Add-OvEdge($from, $to, $end='ERmany', $start='ERone') {
    $script:edgeId++
    [void](Add-Edge $doc $overview "ov-e$script:edgeId" $overviewIds[$from] $overviewIds[$to] $start $end)
}
Add-OvEdge users passengers 'ERzeroToOne'
Add-OvEdge users drivers 'ERzeroToOne'
Add-OvEdge users admins 'ERzeroToOne'
Add-OvEdge users refreshtokens
Add-OvEdge users passwordresettokens
Add-OvEdge users adminloginchallenges
Add-OvEdge users notifications
Add-OvEdge users activitylogs
Add-OvEdge users reportmetadata
Add-OvEdge users announcements
Add-OvEdge users announcementdismissals
Add-OvEdge users supportthreads
Add-OvEdge users supportmessages
Add-OvEdge routes passengers
Add-OvEdge jeepneys drivers
Add-OvEdge routes drivers
Add-OvEdge drivers jeepneys
Add-OvEdge jeepneys tripsessions
Add-OvEdge drivers tripsessions
Add-OvEdge routes tripsessions
Add-OvEdge passengers pickuprequests
Add-OvEdge tripsessions pickuprequests
Add-OvEdge routes pickuprequests
Add-OvEdge pickuprequests ridesessions 'ERzeroToOne'
Add-OvEdge passengers ridesessions
Add-OvEdge tripsessions ridesessions
Add-OvEdge ridesessions stopalerts
Add-OvEdge passengers stopalerts
Add-OvEdge tripsessions stopalerts
Add-OvEdge routes stopalerts
Add-OvEdge announcements announcementdismissals
Add-OvEdge supportthreads supportmessages
Add-OvEdge tripsessions supportthreads
Add-OvEdge pickuprequests supportthreads
Add-OvEdge ridesessions supportthreads

$auth = New-Diagram $doc $mxfile 'authentication-physical-erd' 'Authentication Physical ERD' 1620 1160
$authPos = @{
    users=@(50,80); passengers=@(430,80); drivers=@(430,430); admins=@(430,905)
    refreshtokens=@(820,80); passwordresettokens=@(820,380); adminloginchallenges=@(820,655); notifications=@(1210,80)
}
$authIds = @{}
foreach ($name in $authPos.Keys) {
    $authIds[$name] = "auth-$name"
    $pos = $authPos[$name]
    [void](Add-Entity $doc $auth $authIds[$name] $name $baseFields[$name] $pos[0] $pos[1] 330 $indexMap[$name])
}
$edgeId = 1
function Add-AuthEdge($from, $to, $end='ERmany', $start='ERone') {
    $script:edgeId++
    [void](Add-Edge $doc $auth "auth-e$script:edgeId" $authIds[$from] $authIds[$to] $start $end)
}
Add-AuthEdge users passengers 'ERzeroToOne'
Add-AuthEdge users drivers 'ERzeroToOne'
Add-AuthEdge users admins 'ERzeroToOne'
Add-AuthEdge users refreshtokens
Add-AuthEdge users passwordresettokens
Add-AuthEdge users adminloginchallenges
Add-AuthEdge users notifications

$transport = New-Diagram $doc $mxfile 'transportation-physical-erd' 'Transportation Operations Physical ERD' 1700 1510
$transportPos = @{
    passengers=@(50,80); drivers=@(50,430); jeepneys=@(440,80); routes=@(440,530)
    tripsessions=@(840,260); pickuprequests=@(1235,80); ridesessions=@(1235,580); stopalerts=@(1235,1080)
}
$transportIds = @{}
foreach ($name in $transportPos.Keys) {
    $transportIds[$name] = "trans-$name"
    $pos = $transportPos[$name]
    [void](Add-Entity $doc $transport $transportIds[$name] $name $baseFields[$name] $pos[0] $pos[1] 355 $indexMap[$name])
}
[void](Add-Note $doc $transport 'embedded-route-note' 'Embedded Route Documents' @(
    'routes.waypoints[]: name, location',
    'routes.stops[]: name, code, order, fare, location',
    'routes.terminal: enabled, stopRef, location, radiusMeters',
    'routes.navigation: source, traffic, origin, destination, bounds, distance, duration',
    'fareSnapshot is embedded in pickuprequests and ridesessions.'
) 50 1000 745 170)
$edgeId = 1
function Add-TransEdge($from, $to, $end='ERmany', $start='ERone') {
    $script:edgeId++
    [void](Add-Edge $doc $transport "trans-e$script:edgeId" $transportIds[$from] $transportIds[$to] $start $end)
}
Add-TransEdge jeepneys drivers
Add-TransEdge routes drivers
Add-TransEdge drivers jeepneys
Add-TransEdge jeepneys tripsessions
Add-TransEdge drivers tripsessions
Add-TransEdge routes tripsessions
Add-TransEdge routes passengers
Add-TransEdge passengers pickuprequests
Add-TransEdge tripsessions pickuprequests
Add-TransEdge routes pickuprequests
Add-TransEdge drivers pickuprequests
Add-TransEdge pickuprequests ridesessions 'ERzeroToOne'
Add-TransEdge passengers ridesessions
Add-TransEdge tripsessions ridesessions
Add-TransEdge ridesessions stopalerts
Add-TransEdge passengers stopalerts
Add-TransEdge tripsessions stopalerts
Add-TransEdge routes stopalerts
Add-TransEdge drivers stopalerts

$comm = New-Diagram $doc $mxfile 'communication-monitoring-physical-erd' 'Communication and Monitoring Physical ERD' 2150 1360
$commPos = @{
    users=@(50,80); announcements=@(440,80); announcementdismissals=@(440,530)
    notifications=@(440,805); supportthreads=@(840,80); supportmessages=@(840,560)
    activitylogs=@(1235,80); reportmetadata=@(1235,455); tripsessions=@(1235,805); routes=@(1630,80)
}
$commIds = @{}
foreach ($name in $commPos.Keys) {
    $commIds[$name] = "comm-$name"
    $pos = $commPos[$name]
    [void](Add-Entity $doc $comm $commIds[$name] $name $baseFields[$name] $pos[0] $pos[1] 350 $indexMap[$name])
}
$edgeId = 1
function Add-CommEdge($from, $to, $end='ERmany', $start='ERone') {
    $script:edgeId++
    [void](Add-Edge $doc $comm "comm-e$script:edgeId" $commIds[$from] $commIds[$to] $start $end)
}
Add-CommEdge users announcements
Add-CommEdge announcements announcementdismissals
Add-CommEdge users announcementdismissals
Add-CommEdge users notifications
Add-CommEdge users supportthreads
Add-CommEdge users supportmessages
Add-CommEdge supportthreads supportmessages
Add-CommEdge users activitylogs
Add-CommEdge users reportmetadata
Add-CommEdge tripsessions supportthreads
Add-CommEdge routes supportthreads

$resolved = Resolve-Path (Split-Path $OutputPath -Parent)
$finalPath = Join-Path $resolved.Path (Split-Path $OutputPath -Leaf)
$settings = New-Object System.Xml.XmlWriterSettings
$settings.Indent = $false
$settings.Encoding = [System.Text.UTF8Encoding]::new($false)
$writer = [System.Xml.XmlWriter]::Create($finalPath, $settings)
$doc.Save($writer)
$writer.Close()

Write-Host "Physical ERD written to $finalPath"
Write-Host "Pages: $($mxfile.SelectNodes('diagram').Count)"
