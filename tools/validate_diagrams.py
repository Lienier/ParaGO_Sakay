"""Validate generated diagram artifacts, not application behavior or live state."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from generate_diagrams import overlap, hits

ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'artifacts/diagrams'
class Rows(HTMLParser):
    def __init__(self):super().__init__();self.rows=[];self.row=None;self.cell=None
    def handle_starttag(self,tag,attrs):
        if tag=='tr':self.row=[]
        if tag in ('td','th'):self.cell=''
    def handle_data(self,data):
        if self.cell is not None:self.cell+=data
    def handle_endtag(self,tag):
        if tag in ('td','th') and self.cell is not None:
            if self.row is not None:self.row.append(self.cell.strip())
            self.cell=None
        if tag=='tr' and self.row is not None:self.rows.append(self.row);self.row=None

def main():
    schemas={m['collection']:m for m in json.loads((OUT/'ParaGO_schema_reference.json').read_text(encoding='utf-8'))}
    errors=[];pages=[];field_checks=0;segment_checks=0
    for file in sorted(OUT.glob('*.drawio')):
        for page in ET.parse(file).getroot().findall('diagram'):
            model=page.find('mxGraphModel');allcells=model.findall('.//mxCell');cells={c.get('id'):c for c in allcells};bounds={}
            if len(cells)!=len(allcells):errors.append(f'{file.name}: duplicate cell IDs')
            vertices={i:c for i,c in cells.items() if c.get('vertex')=='1'}
            edges=[c for c in cells.values() if c.get('edge')=='1']
            def pos(id):
                if id in bounds:return bounds[id]
                c=cells[id];g=c.find('mxGeometry');x,y,w,h=[float(g.get(k,0)) for k in ('x','y','width','height')]
                if c.get('parent') in vertices:
                    px,py,_,_=pos(c.get('parent'));x+=px;y+=py
                bounds[id]=(x,y,x+w,y+h);return bounds[id]
            for id,c in vertices.items():
                r=pos(id)
                if r[0]<0 or r[1]<0 or r[2]>float(model.get('pageWidth')) or r[3]>float(model.get('pageHeight')):errors.append(f'{page.get("name")}: outside page {id}')
                if c.get('data-kind')=='table':
                    parser=Rows();parser.feed(c.get('value'));collection=parser.rows[0][0]
                    if collection not in schemas:errors.append(f'Unknown collection: {collection}');continue
                    paths={p['path']:p for p in schemas[collection]['paths']}
                    for row in parser.rows:
                        if len(row)!=4 or row[1] in ('Field','_id'):continue
                        field_checks+=1
                        if row[1] not in paths:errors.append(f'Unknown field: {collection}.{row[1]}');continue
                        p=paths[row[1]]
                        if row[3]!=('Yes' if p['required'] else 'No') or row[2]!=p['type']:errors.append(f'Schema mismatch: {collection}.{row[1]}')
            for e in edges:
                s,t=e.get('source'),e.get('target')
                if s not in vertices or t not in vertices:errors.append(f'{page.get("name")}: broken edge reference');continue
                style=dict(v.split('=',1) for v in e.get('style','').split(';') if '=' in v)
                def port(id,prefix):
                    x,y,xx,yy=pos(id);return (x+(xx-x)*float(style.get(prefix+'X',.5)),y+(yy-y)*float(style.get(prefix+'Y',.5)))
                points=[port(s,'exit')]+[(float(p.get('x')),float(p.get('y'))) for p in e.findall('./mxGeometry/Array/mxPoint')]+[port(t,'entry')]
                for a,b in zip(points,points[1:]):
                    segment_checks+=1
                    if a[0]!=b[0] and a[1]!=b[1]:errors.append(f'{page.get("name")}: nonorthogonal segment')
                    for id,c in vertices.items():
                        if id in (s,t) or c.get('data-kind') in ('boundary','frame','lifeline','label'):continue
                        if hits(a,b,pos(id)):errors.append(f'{page.get("name")}: edge through {id}')
            visible=[i for i,c in vertices.items() if c.get('data-kind') not in ('boundary','frame','lifeline')]
            for n,a in enumerate(visible):
                for b in visible[n+1:]:
                    if overlap(pos(a),pos(b)):errors.append(f'{page.get("name")}: overlapping boxes {a}, {b}')
            for id,c in vertices.items():
                if c.get('data-kind')=='decision':
                    outgoing=[e for e in edges if e.get('source')==id]
                    if len(outgoing)<2 or any(not e.get('value') for e in outgoing):errors.append(f'{page.get("name")}: unlabeled/incomplete decision {id}')
            pages.append(dict(file=file.name,page=page.get('name'),nodes=len(vertices),edges=len(edges)))
    if len(pages)!=34:errors.append(f'Expected 34 pages; found {len(pages)}')
    if field_checks<300:errors.append(f'Insufficient schema checks: {field_checks}')
    result=dict(pages=len(pages),schema_field_checks=field_checks,edge_segments_checked=segment_checks,errors=errors,scope='Generated artifact geometry and loaded schema declarations; no live deployment/database certification',details=pages)
    (OUT/'validation-report.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='details'},indent=2))
    if errors:raise SystemExit(1)
if __name__=='__main__':main()
