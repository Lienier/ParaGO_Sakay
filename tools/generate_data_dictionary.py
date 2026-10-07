"""Generate editable draw.io dictionaries and matching, measured previews.

Reads current Mongoose definitions through a local, connection-free exporter.
Every table cell is a native mxCell; no screenshot is used as diagram content.
"""
from pathlib import Path
import hashlib
import html
import json
import re
import subprocess
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'artifacts/data_dictionary_2026-10-07'
OUT.mkdir(parents=True, exist_ok=True)
subprocess.run(['node', str(ROOT / 'tools/export_data_dictionary.cjs'), str(OUT / 'schema.json')], check=True, cwd=ROOT)
SCHEMA = json.loads((OUT / 'schema.json').read_text(encoding='utf-8'))
MODELS = {m['model']: m for m in SCHEMA['models']}
CORE = ['User', 'Passenger', 'Driver', 'Route', 'Jeepney', 'TripSession', 'PickupRequest', 'RideSession', 'StopAlert']
CORE_FIELDS = {
    'User': ['_id', 'fullName', 'email', 'phone', 'role', 'status'],
    'Passenger': ['_id', 'userId', 'phone', 'defaultRouteId'],
    'Driver': ['_id', 'userId', 'licenseNumber', 'assignedJeepneyId', 'assignedRouteId', 'status', 'operatingMode', 'terminalQueueStatus'],
    'Route': ['_id', 'name', 'code', 'status', 'stops', 'terminal.name', 'fareConfig.baseAmount', 'fareConfig.baseDistanceKm', 'fareConfig.additionalAmountPerKm'],
    'Jeepney': ['_id', 'plateNumber', 'capacity', 'currentDriverId', 'status', 'lastKnownLocation.coordinates', 'lastSeenAt'],
    'TripSession': ['_id', 'driverId', 'jeepneyId', 'routeId', 'status', 'occupancyCount', 'operatingMode', 'terminalQueueStatus', 'startedAt', 'endedAt'],
    'PickupRequest': ['_id', 'passengerId', 'tripSessionId', 'routeId', 'pickupType', 'pickupLocation.coordinates', 'destinationLocation.coordinates', 'partySize', 'status', 'expiresAt'],
    'RideSession': ['_id', 'passengerId', 'tripSessionId', 'pickupRequestId', 'boardedCount', 'remainingCount', 'fareSnapshot.amount', 'regularTotal', 'status', 'boardedAt', 'endedAt'],
    'StopAlert': ['_id', 'passengerId', 'rideSessionId', 'tripSessionId', 'routeId', 'location.coordinates', 'note', 'status'],
}
GROUPS = {
    'Main ride flow': CORE,
    'Terminal operations': ['TerminalQueue', 'TerminalQueueAction', 'OccupancyOperation', 'CodingHoliday'],
    'Accounts and security': ['Admin', 'AuthSession', 'AdminLoginChallenge', 'PasswordResetToken', 'RefreshToken', 'PushDevice', 'ActivityLog'],
    'Support and communications': ['SupportThread', 'SupportMessage', 'Notification', 'Announcement', 'AnnouncementDismissal', 'ReportMetadata'],
    'Mobile distribution': ['MobileRelease', 'MobileReleasePolicy'],
}
FONTS = {}

def font(size=14, bold=False):
    key = (size, bold)
    if key not in FONTS:
        FONTS[key] = ImageFont.truetype(str(Path('C:/Windows/Fonts') / ('arialbd.ttf' if bold else 'arial.ttf')), size)
    return FONTS[key]

def wrap(value, width, size=14, bold=False):
    result = []
    for paragraph in str(value).split('\n'):
        line = ''
        for token in paragraph.split(' '):
            candidate = (line + ' ' + token).strip()
            if font(size, bold).getlength(candidate) <= width:
                line = candidate
                continue
            if line:
                result.append(line)
                line = ''
            while font(size, bold).getlength(token) > width:
                n = 1
                while n < len(token) and font(size, bold).getlength(token[:n+1]) <= width:
                    n += 1
                result.append(token[:n])
                token = token[n:]
            line = token
        result.append(line)
    return result

def requirement(row):
    key = row['key']
    if key == 'PK':
        return 'PK / ID'
    if row['generated']:
        return 'Automatic'
    if row['requiredWithinParent']:
        return 'Yes in parent'
    return (key + '\n' if key else '') + ('Yes' if row['required'] else 'Not required')

W, H = 1520, 1100
COLS = [720, 360, 360]
HEADERS = ['Column name', 'Data type', 'Key / required']
PAGES = []

class Page:
    def __init__(self, name, title, subtitle, scope='all'):
        self.name, self.scope = name, scope
        self.id = 'dd-' + re.sub(r'[^a-zA-Z0-9]+', '-', name).strip('-')
        self.cells = []
        self.add(title, 40, 26, 1440, 44, fill='#17324d', color='#ffffff', size=26, bold=True)
        self.add(subtitle, 40, 80, 1440, 50, size=15, color='#475569')
        self.y = 146
        PAGES.append(self)

    def add(self, text, x, y, w, h, fill='#ffffff', color='#172b3a', size=14, bold=False, border=False):
        lines = wrap(text, w - 20, size, bold)
        assert len(lines) * (size + 3) <= h - 8, (self.name, text, h, lines)
        cell = dict(id=f'{self.id}-cell-{len(self.cells)+1}', text='\n'.join(lines), x=x, y=y, w=w, h=h,
                    fill=fill, color=color, size=size, bold=bold, border=border)
        self.cells.append(cell)
        return cell

    def row(self, values, widths=COLS, header=False):
        h = max(46, max(len(wrap(s, w - 20, 14, header)) for s, w in zip(values, widths)) * 17 + 18)
        x = 40
        for i, (s, w) in enumerate(zip(values, widths)):
            self.add(s, x, self.y, w, h, fill=('#e4edf4' if header else ('#f5f8fb' if len(self.cells) % 10 < 5 else '#ffffff')),
                     bold=header, border=True)
            x += w
        self.y += h
        return h

    def footer(self):
        self.add('SAKAY | Data dictionary | 07 October 2026 | MongoDB / Mongoose | Schema requirements, not complete API validation',
                 40, 1054, 1440, 28, size=12, color='#64748b')

def row_height(values, widths=COLS):
    return max(46, max(len(wrap(s, w - 20)) for s, w in zip(values, widths)) * 17 + 18)

for group, names in GROUPS.items():
    for name in names:
        model = MODELS[name]
        scope = 'core' if name in CORE else 'support'
        part = 1
        page = Page(f'{name} - {part}', name, f'{group} | Collection: {model["collection"]}\nSource: {model["source"]}', scope)
        page.row(HEADERS, header=True)
        ordered = sorted(model['fields'], key=lambda r: (0 if r['path'] == '_id' else 2 if r['generated'] else 1))
        for row in ordered:
            values = [row['path'], row['type'], requirement(row)]
            if page.y + row_height(values) > 1024:
                page.footer()
                part += 1
                page = Page(f'{name} - {part}', f'{name} | continued ({part})',
                            f'{group} | Collection: {model["collection"]} | Source: {model["source"]}', scope)
                page.row(HEADERS, header=True)
            page.row(values)
        page.footer()

def drawio(pages, filename):
    tree = ET.Element('mxfile', {'host': 'app.diagrams.net', 'modified': '2026-10-07T00:00:00Z',
                                 'agent': 'SAKAY schema dictionary generator', 'version': '24.7.17', 'type': 'device',
                                 'compressed': 'false', 'pages': str(len(pages))})
    for page in pages:
        diagram = ET.SubElement(tree, 'diagram', {'id': page.id, 'name': page.name})
        model = ET.SubElement(diagram, 'mxGraphModel', {'dx': str(W), 'dy': str(H), 'grid': '0', 'gridSize': '10',
                    'guides': '1', 'tooltips': '1', 'connect': '1', 'arrows': '1', 'fold': '1', 'page': '1',
                    'pageScale': '1', 'pageWidth': str(W), 'pageHeight': str(H), 'math': '0', 'shadow': '0'})
        root = ET.SubElement(model, 'root')
        ET.SubElement(root, 'mxCell', {'id': '0'})
        ET.SubElement(root, 'mxCell', {'id': '1', 'parent': '0'})
        for c in page.cells:
            style = f'shape=rectangle;html=0;whiteSpace=wrap;overflow=hidden;rounded=0;align=left;verticalAlign=middle;spacingLeft=10;spacingRight=10;fontFamily=Arial;fontSize={c["size"]};fontStyle={1 if c["bold"] else 0};fillColor={c["fill"]};fontColor={c["color"]};strokeColor={"#cbd5e1" if c["border"] else "none"};'
            cell = ET.SubElement(root, 'mxCell', {'id': c['id'], 'value': c['text'], 'style': style, 'vertex': '1', 'parent': '1'})
            ET.SubElement(cell, 'mxGeometry', {'x': str(c['x']), 'y': str(c['y']), 'width': str(c['w']), 'height': str(c['h']), 'as': 'geometry'})
    ET.indent(tree)
    ET.ElementTree(tree).write(OUT / filename, encoding='utf-8', xml_declaration=True)

drawio(PAGES, 'SAKAY_data_dictionary.drawio')
full_count = len(PAGES)
CORE_PAGES = []
for name in CORE:
    model = MODELS[name]
    page = Page(f'Core {name} - 1', name + ' | important fields',
                f'Collection: {model["collection"]}\nSource: {model["source"]}', 'simple')
    page.row(HEADERS, header=True)
    for field in CORE_FIELDS[name]:
        row = next(r for r in model['fields'] if r['path'] == field)
        values = [row['path'], row['type'], requirement(row)]
        assert page.y + row_height(values) <= 1024, name
        page.row(values)
    page.footer()
    CORE_PAGES.append(page)
drawio(CORE_PAGES, 'SAKAY_core_data_dictionary.drawio')
FULL_PAGES = PAGES[:full_count]

manifest = []
for i, page in enumerate(PAGES):
    base = f'{i:02d}_{page.id}'
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">', '<rect width="100%" height="100%" fill="white"/>']
    raster = Image.new('RGB', (W, H), 'white')
    pen = ImageDraw.Draw(raster)
    for c in page.cells:
        x, y, w, h = c['x'], c['y'], c['w'], c['h']
        stroke = '#cbd5e1' if c['border'] else c['fill']
        svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{c["fill"]}" stroke="{stroke}"/>')
        pen.rectangle((x, y, x+w, y+h), fill=c['fill'], outline=stroke)
        lines = c['text'].split('\n')
        line_h = c['size'] + 3
        ty = y + (h - len(lines) * line_h) / 2
        for line in lines:
            svg.append(f'<text x="{x+10}" y="{ty+c["size"]}" font-family="Arial, sans-serif" font-size="{c["size"]}" font-weight="{"bold" if c["bold"] else "normal"}" fill="{c["color"]}">{html.escape(line)}</text>')
            pen.text((x+10, ty), line, font=font(c['size'], c['bold']), fill=c['color'], anchor='lt')
            ty += line_h
    svg.append('</svg>')
    (OUT / (base + '.svg')).write_text('\n'.join(svg), encoding='utf-8')
    raster.save(OUT / (base + '.png'))
    manifest.append(dict(name=page.name, scope=page.scope, svg=base+'.svg', png=base+'.png'))

# XML round-trip and source coverage; per-cell measured bounds were asserted above.
for filename, pages in [('SAKAY_data_dictionary.drawio', FULL_PAGES), ('SAKAY_core_data_dictionary.drawio', CORE_PAGES)]:
    parsed = ET.parse(OUT / filename)
    assert len(parsed.findall('./diagram')) == len(pages)
    for diagram in parsed.findall('./diagram'):
        ids = [c.get('id') for c in diagram.findall('./mxGraphModel/root/mxCell')]
        assert len(ids) == len(set(ids))
        table_cells = [c for c in diagram.findall('./mxGraphModel/root/mxCell') if 'strokeColor=#cbd5e1' in c.get('style', '')]
        assert [c.get('value') for c in table_cells[:3]] == HEADERS
        assert len(table_cells) % 3 == 0
    for name, model in MODELS.items():
        if filename.startswith('SAKAY_core') and name not in CORE:
            continue
        texts = [c.get('value') for d in parsed.findall('./diagram') if d.get('name').startswith((name + ' - ', 'Core ' + name + ' - ')) for c in d.findall('./mxGraphModel/root/mxCell')]
        normalized = [t.replace('\n', '') for t in texts if t]
        for row in model['fields']:
            if filename.startswith('SAKAY_core') and row['path'] not in CORE_FIELDS[name]:
                continue
            assert row['path'] in normalized, (filename, name, row['path'])

validation = dict(models=len(MODELS), fields=sum(len(m['fields']) for m in MODELS.values()),
                  indexes=sum(len(m['indexes']) for m in MODELS.values()), fullPages=len(FULL_PAGES), corePages=len(CORE_PAGES),
                  coreFields=sum(len(v) for v in CORE_FIELDS.values()),
                  columns=HEADERS, nativeEditableCells=True, xmlRoundTrip=True, completeFieldCoverage=True, measuredTextBounds=True,
                  applicationModified=False, databaseConnected=False)
(OUT / 'validation.json').write_text(json.dumps(validation, indent=2)+'\n', encoding='utf-8')
(OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')

# Retire obsolete generated previews so old five-column pages are not left beside the new files.
current_previews = {item[key] for item in manifest for key in ('svg', 'png')}
for old_preview in OUT.iterdir():
    if re.fullmatch(r'\d{2}_dd-.*\.(svg|png)', old_preview.name) and old_preview.name not in current_previews:
        assert old_preview.resolve().parent == OUT.resolve()
        old_preview.unlink()

sections = []
for item in sorted(manifest, key=lambda item: 0 if item['scope'] == 'simple' else 1):
    sections.append(f'<section data-scope="{item["scope"]}"><h2>{html.escape(item["name"])}</h2><img loading="lazy" src="{item["svg"]}" alt="{html.escape(item["name"])} data dictionary page"></section>')
(OUT / 'index.html').write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SAKAY data dictionary</title>
<style>body{font-family:Arial,sans-serif;margin:0;background:#eef2f6;color:#17324d}header{padding:24px 4%;background:#17324d;color:white;position:sticky;top:0;z-index:1}h1{margin:0 0 10px;font-size:25px}header a,button{display:inline-block;background:white;color:#17324d;border:0;border-radius:5px;padding:9px 14px;margin:4px;text-decoration:none;cursor:pointer}main{margin:25px auto;width:95%;max-width:1520px}section{background:white;padding:12px;margin:25px 0;box-shadow:0 2px 8px #0001}section img{width:100%;height:auto}h2{font-size:18px;margin:8px}.hidden{display:none}@media print{header{position:static}header a,button{display:none}section{break-after:page;margin:0;box-shadow:none;padding:0}section h2{display:none}}</style>
<header><h1>SAKAY data dictionary</h1><div>Current MongoDB application models | 07 October 2026 | Editable tables in draw.io</div>
<a href="SAKAY_core_data_dictionary.drawio" download>Download core dictionary</a><a href="SAKAY_data_dictionary.drawio" download>Download full dictionary</a>
<button onclick="filter(true)">Show main functionality</button><button onclick="filter(false)">Show all pages</button></header>
<main>'''+''.join(sections)+'''</main><script>function filter(core){document.querySelectorAll('section').forEach(s=>s.classList.toggle('hidden',core?s.dataset.scope!=='simple':s.dataset.scope==='simple'));}filter(true);</script></html>''', encoding='utf-8')

readme = f'''# SAKAY data dictionary — draw.io

Open **SAKAY_core_data_dictionary.drawio** for the nine main functionality entities. Open **SAKAY_data_dictionary.drawio** for the complete system.

1. Open draw.io / diagrams.net.
2. Choose **File > Open From > Device** and select the `.drawio` file.
3. Select a page tab at the bottom. Large models continue onto numbered pages.
4. Click any table cell to edit its column name, data type or key/required value. All cells are native diagram objects.
5. Save the drawing, or export the selected pages using draw.io's export menu.

The core dictionary covers **User, Passenger, Driver, Route, Jeepney, TripSession, PickupRequest, RideSession and StopAlert**, with **{validation['coreFields']} selected important fields**. The complete dictionary covers **{len(MODELS)} collections, {validation['fields']} field paths**, including embedded fields and Mongoose-generated fields. There are {len(CORE_PAGES)} pages in the core file and {len(FULL_PAGES)} in the complete file. Both drawings retain only **Column name**, **Data type**, and **Key / required**; relationship overview diagrams remain in the earlier ERD package.

Use **index.html** for a local readable preview. It initially shows the main functionality; click Show all pages for supporting records. SVG and PNG previews match the generated layout.

## Data conventions

- This describes the **current MongoDB/Mongoose application**, not the earlier Oracle documentation mapping. No Oracle schema change is made.
- PK / ID identifies the document. Embedded ID identifies an item within a parent document.
- Required describes schema validation only. Embedded required values apply within their parent; API/service validation can impose additional rules.
- Dot paths are embedded objects; [] denotes array items. Embedded records are stored in the parent collection.
- GeoJSON points use [longitude, latitude]. Date fields are BSON timestamps. Fare descriptions use Philippine pesos.
- Descriptions, defaults, validation rules and index appendix pages are omitted from the drawings. The supporting schema.json retains full source metadata for traceability.
- Announcement/admin author IDs refer to **User**, matching the code even where their name says Admin.

## Verification and regeneration

Verified: XML parse/round-trip, unique object IDs, every exported field present, measured text fitting within each cell, page boundaries and current source hashes. Visual previews were generated for review. Opening/rendering in the native draw.io editor has not been automated; import instructions are provided above.

Run `python tools/generate_data_dictionary.py` from the repository. It reads model definitions without a database connection or .env file. `schema.json` contains exact declarations and source SHA-256 hashes; `validation.json` records generation checks. Regeneration updates these dictionary artifacts only; application source is unchanged.
'''
(OUT / 'START_HERE.md').write_text(readme, encoding='utf-8')
print(json.dumps(validation, indent=2))
