"""Package Oracle DDL and all editable diagram pages without lossy conversion."""
from pathlib import Path
import copy
import hashlib
import json
import re
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'artifacts' / 'diagrams'
OUT = SOURCE / 'oracle_data_modeler'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sources = sorted(SOURCE.glob('*.drawio'))
    combined = ET.Element('mxfile', host='app.diagrams.net', agent='ParaGO package builder')
    pages = []
    for source in sources:
        for page in ET.parse(source).getroot().findall('diagram'):
            clone = copy.deepcopy(page)
            clone.set('id', f'parago-page-{len(pages) + 1:02d}')
            combined.append(clone)
            pages.append({'source': source.name, 'page': page.get('name')})
    assert len(pages) == 34, f'Expected 34 pages, got {len(pages)}'
    all_diagrams = OUT / 'ParaGO_all_diagrams.drawio'
    ET.ElementTree(combined).write(all_diagrams, encoding='utf-8', xml_declaration=True)
    # Confirm every original page payload survives consolidation unchanged.
    originals = [p for s in sources for p in ET.parse(s).getroot().findall('diagram')]
    for original, clone in zip(originals, ET.parse(all_diagrams).getroot()):
        clone.set('id', original.get('id'))
        assert ET.tostring(original) == ET.tostring(clone)

    ddl = SOURCE / 'ParaGO_oracle_data_modeler.sql'
    sql = ddl.read_text(encoding='utf-8')
    tables = {}
    for name, body in re.findall(r'CREATE TABLE\s+(\w+)\s*\((.*?)\n\);', sql, re.S | re.I):
        tables[name.lower()] = {m.lower() for m in re.findall(r'^\s+(\w+)\s+(?:VARCHAR2|NUMBER|TIMESTAMP|CLOB)\b', body, re.M | re.I)}
    assert tables, 'No DDL tables found'
    refs = re.findall(r'ALTER TABLE\s+(\w+).*?FOREIGN KEY\s*\((\w+)\)\s+REFERENCES\s+(\w+)\s*\((\w+)\)', sql, re.I)
    for table, column, target, key in refs:
        assert column.lower() in tables[table.lower()], (table, column)
        assert key.lower() in tables[target.lower()], (target, key)
    (OUT / ddl.name).write_bytes(ddl.read_bytes())
    guide = f'''# ParaGO diagram editing package

## Open the database model in Oracle SQL Developer Data Modeler

1. Extract the ZIP into a folder.
2. In Data Modeler, choose **File > Import > DDL File**.
3. Select `ParaGO_oracle_data_modeler.sql`, choose an Oracle database dialect, and complete the import wizard.
4. Open the imported relational model diagram. Use automatic layout, then arrange tables and create subviews as desired.
5. Choose **File > Save As** to save your native `.dmd` design. Keep its associated design directory with the `.dmd` file when moving it.

The import contains {len(tables)} relational documentation tables and {len(refs)} foreign-key relationships. It reuses the existing ParaGO Oracle projection. The application runs MongoDB: SQL foreign keys, normalization, cascades and NOT NULL constraints describe this projection, not MongoDB enforcement. Exact collection fields and index predicates are in `ParaGO_schema_reference.json` and `.md`. Importing DDL reconstructs the ERD; it does not preserve the four original ERD page layouts.

## Open and edit all 34 original diagram pages

Open `ParaGO_all_diagrams.drawio` in diagrams.net or the draw.io desktop application. It contains all pages from the eight original files, preserving their shapes, text, connectors and geometry. `index.html` provides a read-only gallery of SVG previews. Individual editable originals are included too.

| Diagram family | Oracle Data Modeler editing |
| --- | --- |
| Entity relationships | Import the SQL projection; arrange the resulting model in Oracle |
| Activity and algorithm flowcharts | Edit the preserved pages in draw.io |
| Sequence and use cases | Edit the preserved pages in draw.io |
| Architecture and deployment | Edit the preserved pages in draw.io |

Oracle supports process/data-flow models, but these are not interchangeable with UML or control-flow diagrams. This package does not disguise unsupported diagrams as database tables or claim a lossless Oracle conversion. No native `.dmd` was generated. Native import and visual layout have not been tested inside Oracle; the package checks XML preservation and DDL relationship endpoints only.

Oracle documentation: https://docs.oracle.com/en/database/oracle/sql-developer-data-modeler/24.3/dmdug/data-modeler-concepts-usage.html

## Rebuild

Run `python tools/package_diagrams_for_oracle.py` from the repository after regenerating the diagrams. Edits made in the combined file or an imported Oracle model are independent and are not synchronized back into the source generators.
'''
    (OUT / 'START_HERE.md').write_text(guide, encoding='utf-8')
    report = {'pages': pages, 'page_count': len(pages), 'source_file_count': len(sources),
              'original_page_payloads_preserved': True, 'ddl_table_count': len(tables),
              'ddl_foreign_keys_checked': len(refs), 'native_oracle_import_tested': False}
    (OUT / 'package-validation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    files = [all_diagrams, OUT / ddl.name, OUT / 'START_HERE.md', OUT / 'package-validation.json',
             *sources, *sorted(SOURCE.glob('*.svg')), SOURCE / 'index.html',
             SOURCE / 'ParaGO_schema_reference.json', SOURCE / 'ParaGO_schema_reference.md']
    archive = OUT / 'ParaGO_diagram_editing_package.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as package:
        for file in files:
            package.write(file, file.name)
    with zipfile.ZipFile(archive) as package:
        assert package.testzip() is None
        for file in files:
            assert hashlib.sha256(package.read(file.name)).digest() == hashlib.sha256(file.read_bytes()).digest()
    print(json.dumps({'archive': str(archive), 'pages': len(pages), 'tables': len(tables),
                      'relationships': len(refs), 'archived_files': len(files), 'checks': 'passed'}, indent=2))


if __name__ == '__main__':
    main()
