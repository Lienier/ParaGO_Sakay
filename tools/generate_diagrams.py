"""Generate editable diagrams and matching SVGs from shared, reviewed sources.

Run from any directory: python tools/generate_diagrams.py
Requires Pillow for Arial font measurement; schema export requires local mongoose.
All routes use explicit orthogonal points and all text uses measured line breaks.
No network, cloud, application-state or database access.
"""
from pathlib import Path
import argparse
import heapq
import html
import itertools
import json
import math
import subprocess
import xml.etree.ElementTree as ET
from PIL import ImageFont

ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'artifacts/diagrams'
PALETTE={'process':('#ffffff','#536675'),'user':('#edf4fc','#315b7d'),'system':('#fff2e8','#aa5017'),'warning':('#fff0f0','#a62e38'),'decision':('#fff5d9','#946300'),'data':('#eaf7ee','#287447'),'start':('#17324d','#17324d'),'end':('#17324d','#17324d'),'note':('#f5f7fa','#8a98a6'),'boundary':('#f8fafc','#94a3b8'),'actor':('#ffffff','#315b7d'),'ellipse':('#edf4fc','#315b7d')}
FONTS={}
def font(size=15,bold=False):
    key=(size,bold)
    if key not in FONTS:
        filename='arialbd.ttf' if bold else 'arial.ttf'
        FONTS[key]=ImageFont.truetype(str(Path('C:/Windows/Fonts')/filename),size)
    return FONTS[key]
def wrap(text,width,size=15,bold=False):
    lines=[]; f=font(size,bold)
    for paragraph in str(text).split('\n'):
        line=''
        for word in paragraph.split():
            trial=(line+' '+word).strip()
            if f.getlength(trial)>width and line:lines.append(line);line=word
            else:line=trial
        lines.append(line)
    return lines
def node(id,text,x,y,w=320,h=100,kind='process',**kw):
    return dict(id=id,text=text,x=x,y=y,w=w,h=h,kind=kind,**kw)
def edge(s,t,label='',**kw):return dict(source=s,target=t,label=label,**kw)
def rect(n,pad=0):return (n['x']-pad,n['y']-pad,n['x']+n['w']+pad,n['y']+n['h']+pad)
def overlap(a,b):return min(a[2],b[2])-max(a[0],b[0])>0.1 and min(a[3],b[3])-max(a[1],b[1])>0.1
def hits(a,b,r):
    if a[0]==b[0]:return r[0]<a[0]<r[2] and min(max(a[1],b[1]),r[3])>max(min(a[1],b[1]),r[1])+0.1
    return r[1]<a[1]<r[3] and min(max(a[0],b[0]),r[2])>max(min(a[0],b[0]),r[0])+0.1
def ports(n):
    x,y,w,h=n['x'],n['y'],n['w'],n['h']
    return [((x+w/2,y),(x+w/2,y-20),'top'),((x+w,y+h/2),(x+w+20,y+h/2),'right'),((x+w/2,y+h),(x+w/2,y+h+20),'bottom'),((x,y+h/2),(x-20,y+h/2),'left')]
def simplify(points):
    out=[]
    for p in points:
        if out and p==out[-1]:continue
        while len(out)>1 and ((out[-2][0]==out[-1][0]==p[0]) or (out[-2][1]==out[-1][1]==p[1])):out.pop()
        out.append(p)
    return out

class Diagram:
    def __init__(self,name,width=1480,height=1000,subtitle=''):
        self.name=name;self.width=width;self.height=height;self.subtitle=subtitle;self.nodes=[];self.edges=[];self.labels=[];self.routes=[]
    def n(self,*a,**kw):self.nodes.append(node(*a,**kw));return self.nodes[-1]
    def e(self,*a,**kw):self.edges.append(edge(*a,**kw));return self.edges[-1]
    def layout_routes(self):
        nodes={n['id']:n for n in self.nodes}; obstacles=[rect(n,12) for n in self.nodes if n['kind'] not in ('boundary','frame','lifeline')]
        xs={30,self.width-30};ys={130,self.height-50}
        for n in self.nodes:
            if n['kind'] in ('boundary','frame','lifeline'):continue
            xs.update([n['x']-40,n['x']-20,n['x']+n['w']/2,n['x']+n['w']+20,n['x']+n['w']+40])
            ys.update([n['y']-40,n['y']-20,n['y']+n['h']/2,n['y']+n['h']+20,n['y']+n['h']+40])
        xs=sorted(x for x in xs if 20<=x<=self.width-20);ys=sorted(y for y in ys if 115<=y<=self.height-20)
        pts={(i,j):(x,y) for i,x in enumerate(xs) for j,y in enumerate(ys) if not any(r[0]<x<r[2] and r[1]<y<r[3] for r in obstacles)}
        pointkeys={p:k for k,p in pts.items()}; adj={k:[] for k in pts}
        for k,p in pts.items():
            for nk in [(k[0]+1,k[1]),(k[0],k[1]+1)]:
                if nk in pts and not any(hits(p,pts[nk],r) for r in obstacles):
                    dist=abs(p[0]-pts[nk][0])+abs(p[1]-pts[nk][1]);axis=0 if p[1]==pts[nk][1] else 1
                    adj[k].append((nk,dist,axis));adj[nk].append((k,dist,axis))
        used={}
        for e in self.edges:
            if 'points' in e:
                points=e['points'];sp=e.get('source_port','bottom');tp=e.get('target_port','top')
            else:
                s,t=nodes[e['source']],nodes[e['target']]
                starts=[p for p in ports(s) if p[1] in pointkeys];ends=[p for p in ports(t) if p[1] in pointkeys]
                goals={pointkeys[p[1]]:p for p in ends}; dist={}; prev={}; orig={};q=[];counter=itertools.count()
                def heuristic(k):return min(abs(pts[k][0]-pts[g][0])+abs(pts[k][1]-pts[g][1]) for g in goals)
                for port in starts:
                    k=pointkeys[port[1]];axis=0 if port[2] in ('left','right') else 1;state=(k,axis)
                    penalty=0
                    if t['y']>s['y'] and port[2]=='top':penalty=100
                    if t['y']<s['y'] and port[2]=='bottom':penalty=100
                    dist[state]=penalty;orig[state]=port;heapq.heappush(q,(penalty+heuristic(k),next(counter),state))
                final=None
                while q:
                    _,_,st=heapq.heappop(q);k,axis=st
                    if k in goals:final=st;break
                    for nk,length,na in adj[k]:
                        seg=tuple(sorted((k,nk)));cost=dist[st]+length+(35 if na!=axis else 0)+used.get(seg,0)*length*4
                        ns=(nk,na)
                        if cost<dist.get(ns,float('inf')):
                            dist[ns]=cost;prev[ns]=st;orig[ns]=orig[st];heapq.heappush(q,(cost+heuristic(nk),next(counter),ns))
                if final is None:raise ValueError(f'No safe route: {self.name}: {e}')
                endport=goals[final[0]];startport=orig[final];chain=[];cur=final
                while True:
                    chain.append(pts[cur[0]])
                    if cur not in prev:break
                    before=prev[cur];seg=tuple(sorted((cur[0],before[0])));used[seg]=used.get(seg,0)+1;cur=before
                points=simplify([startport[0]]+list(reversed(chain))+[endport[0]])
                sp,tp=startport[2],endport[2]
            e['route']=points;e['source_port']=sp;e['target_port']=tp
            # Verified line segments cannot cross unrelated action interiors.
            for n in self.nodes:
                if n['id'] in (e['source'],e['target']) or n['kind'] in ('boundary','frame','lifeline'):continue
                if any(hits(a,b,rect(n,1)) for a,b in zip(points,points[1:])):raise ValueError(f"Edge crosses {n['id']}: {self.name}: {e['source']} -> {e['target']}")
            if e.get('label'):
                label=e['label']; lines=wrap(label,300 if 'sequence_y' in e else 150,12,True);w=max(font(12,True).getlength(x) for x in lines)+14;h=len(lines)*16+8
                occupied=[rect(n,5) for n in self.nodes if n['kind'] not in ('boundary','frame')]+[rect(l,4) for l in self.labels]
                for n in self.nodes:
                    if n['kind'] in ('boundary','frame'):
                        x,y,xx,yy=rect(n);occupied.extend([(x-4,y-4,x+4,yy+4),(xx-4,y-4,xx+4,yy+4),(x,y-4,xx,y+4),(x,yy-4,xx,yy+4)])
                candidates=[]
                for index,(a,b) in enumerate(zip(points,points[1:])):
                    for f in (.5,.25,.75,.1,.2,.3,.4,.6,.7,.8,.9):
                        mx=a[0]+(b[0]-a[0])*f;my=a[1]+(b[1]-a[1])*f
                        for ox,oy in [(0,0),(0,-h/2-5),(w/2+6,0),(-w/2-6,0)]:
                            r=(mx-w/2+ox,my-h/2+oy,mx+w/2+ox,my+h/2+oy)
                            if r[0]>12 and r[1]>108 and r[2]<self.width-12 and r[3]<self.height-10 and not any(overlap(r,o) for o in occupied):candidates.append((index+abs(f-.5)+abs(ox)/20+abs(oy)/20,r))
                if not candidates:raise ValueError(f'No safe label: {self.name}: {label}')
                _,r=min(candidates,key=lambda v:v[0]);self.labels.append(node('label-'+str(len(self.labels)),label,r[0],r[1],w,h,'label',size=12,bold=True))
    def prepare(self):
        for n in self.nodes:
            if n['kind'] in ('boundary','frame','lifeline'):continue
            if n['kind']=='table':continue
            size=n.get('size',15);bold=n.get('bold',n['kind'] in ('decision','start','end','actor'))
            width=n['w']*(.55 if n['kind']=='decision' else .82 if n['kind'] in ('ellipse','start','end') else 1)-24
            lines=n.get('lines') or wrap(n['text'],width,size,bold)
            available=n['h']*(.68 if n['kind']=='decision' else 1)-20
            if len(lines)*(size+5)>available:
                size=13;lines=wrap(n['text'],width,size,bold)
                if len(lines)*(size+5)>available:raise ValueError(f"Text overflow: {self.name} {n['id']}: {lines}")
            n.update(lines=lines,size=size,bold=bold)
        self.layout_routes()
    def xml(self):
        d=ET.Element('diagram',{'id':self.name.lower().replace(' ','-'),'name':self.name});m=ET.SubElement(d,'mxGraphModel',{'grid':'1','gridSize':'10','page':'1','pageScale':'1','pageWidth':str(self.width),'pageHeight':str(self.height),'background':'#ffffff'})
        r=ET.SubElement(m,'root');ET.SubElement(r,'mxCell',{'id':'0'});ET.SubElement(r,'mxCell',{'id':'1','parent':'0'})
        def cell(n):
            k=n['kind'];fill,stroke=PALETTE.get(k,('#ffffff','#536675'));size=n.get('size',15);bold=n.get('bold',False)
            shape='shape=rhombus;' if k=='decision' else 'ellipse;' if k in ('ellipse','start','end') else 'rounded=1;arcSize=8;'
            if k in ('boundary','frame'):shape='rounded=0;verticalAlign=top;spacingTop=12;';fill='none' if k=='frame' else fill
            if k=='lifeline':shape='shape=line;direction=south;dashed=1;';fill='none'
            if k=='label':shape='text;';stroke='none'
            if k=='actor':shape='shape=umlActor;verticalLabelPosition=bottom;verticalAlign=top;';fill='none'
            value='<br>'.join(html.escape(x) for x in n.get('lines',[n['text']]))
            if k=='table':
                shape='rounded=0;verticalAlign=top;';fill='#ffffff';stroke='#315b7d'
                value='<table style="border-collapse:collapse;width:100%;font-size:13px"><tr><td colspan="4" style="padding:10px;background:#edf4fc"><b>'+html.escape(n['text'])+'</b></td></tr><tr><td>Key</td><td>Field</td><td>Type</td><td>Req.</td></tr>'
                for row in n['rows']:value+='<tr>'+''.join('<td style="border-top:1px solid #dae3eb;padding:5px 4px">'+html.escape(v)+'</td>' for v in row)+'</tr>'
                value+='</table><div style="padding:8px;font-size:12px">'+'<br>'.join(html.escape(x) for x in n['notes'])+'</div>'
            style=f'{shape}html=1;whiteSpace=wrap;align=center;fontFamily=Arial;fontSize={size};fontStyle={1 if bold else 0};fontColor={"#ffffff" if k in ("start","end") else "#17324d"};fillColor={fill};strokeColor={stroke};strokeWidth=1.5;spacing=8;'
            parent='1';x,y=n['x'],n['y']
            if k=='lifeline':
                parent=n['id'].removesuffix('-line');header=next(v for v in self.nodes if v['id']==parent);x-=header['x'];y-=header['y']
            c=ET.SubElement(r,'mxCell',{'id':n['id'],'value':value,'style':style,'vertex':'1','parent':parent,'data-kind':k});ET.SubElement(c,'mxGeometry',{'x':str(x),'y':str(y),'width':str(n['w']),'height':str(n['h']),'as':'geometry'})
        for n in self.nodes:
            if n['kind'] in ('boundary','frame','lifeline'):cell(n)
        def heading(id,text,y,size):
            n=node(id,text,30,y,self.width-60,45,'label',size=size,bold=True);cell(n)
        heading('page-title',self.name,15,22)
        heading('page-subtitle',self.subtitle,65,12)
        portvalues={'top':(.5,0),'bottom':(.5,1),'left':(0,.5),'right':(1,.5)}
        for i,e in enumerate(self.edges):
            a,b=portvalues[e['source_port']],portvalues[e['target_port']]
            if 'sequence_y' in e:
                sn=next(n for n in self.nodes if n['id']==e['source']);tn=next(n for n in self.nodes if n['id']==e['target'])
                a=(.5,(e['sequence_y']-sn['y'])/sn['h']);b=(.5,(e['sequence_y']-tn['y'])/tn['h'])
            style=f'edgeStyle=none;rounded=0;html=1;noLabel=1;strokeColor=#536675;strokeWidth=1.5;endArrow={e.get("arrow","block")};endFill={0 if e.get("arrow")=="open" else 1};jumpStyle=gap;jumpSize=6;exitX={a[0]};exitY={a[1]};entryX={b[0]};entryY={b[1]};exitPerimeter=0;entryPerimeter=0;'
            if e.get('dashed'):style+='dashed=1;'
            c=ET.SubElement(r,'mxCell',{'id':f'edge-{i}','value':e.get('label',''),'style':style,'edge':'1','parent':'1','source':e['source'],'target':e['target']})
            g=ET.SubElement(c,'mxGeometry',{'relative':'1','as':'geometry'});arr=ET.SubElement(g,'Array',{'as':'points'})
            for x,y in e['route'][1:-1]:ET.SubElement(arr,'mxPoint',{'x':str(x),'y':str(y)})
        for n in self.nodes:
            if n['kind'] not in ('boundary','frame','lifeline'):cell(n)
        for n in self.labels:cell(n)
        return d
    def svg(self):
        esc=html.escape;out=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" height="{self.height}" viewBox="0 0 {self.width} {self.height}">','<rect width="100%" height="100%" fill="white"/>','<defs><marker id="arrow" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto"><path d="M0,0 L8,4.5 L0,9 Z" fill="#536675"/></marker><marker id="open" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto"><path d="M0,0 L8,4.5 L0,9" fill="none" stroke="#536675"/></marker></defs>']
        def text(lines,x,y,size=15,bold=False,color='#17324d',anchor='middle'):
            for i,line in enumerate(lines):out.append(f'<text x="{x}" y="{y+i*(size+5)}" text-anchor="{anchor}" font-family="Arial" font-size="{size}" font-weight="{700 if bold else 400}" fill="{color}">{esc(line)}</text>')
        for n in self.nodes:
            if n['kind'] in ('boundary','frame'):
                fill,stroke=PALETTE.get(n['kind'],('none','#94a3b8'));out.append(f'<rect x="{n["x"]}" y="{n["y"]}" width="{n["w"]}" height="{n["h"]}" fill="{fill}" stroke="{stroke}"/>');text([n['text']],n['x']+n['w']/2,n['y']+24,14,True)
            if n['kind']=='lifeline':out.append(f'<path d="M {n["x"]+n["w"]/2} {n["y"]} v {n["h"]}" stroke="#94a3b8" stroke-dasharray="6 5"/>')
        text(wrap(self.name,self.width-100,22,True),self.width/2,43,22,True)
        text(wrap(self.subtitle,self.width-100,12),self.width/2,85,12)
        for e in self.edges:
            path='M '+' L '.join(f'{x},{y}' for x,y in e['route']);out.append(f'<path d="{path}" fill="none" stroke="white" stroke-width="6"/>')
            marker='' if e.get('arrow')=='none' else f' marker-end="url(#{"open" if e.get("arrow")=="open" else "arrow"})"'
            dash=' stroke-dasharray="6 4"' if e.get('dashed') else ''
            out.append(f'<path d="{path}" fill="none" stroke="#536675" stroke-width="1.5"{marker}{dash}/>')
        for n in self.nodes+self.labels:
            k=n['kind']
            if k in ('boundary','frame','lifeline'):continue
            x,y,w,h=n['x'],n['y'],n['w'],n['h'];fill,stroke=PALETTE.get(k,('white','none'))
            if k=='table':
                out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="white" stroke="#315b7d"/>');out.append(f'<rect x="{x}" y="{y}" width="{w}" height="40" fill="#edf4fc"/>');text([n['text']],x+w/2,y+26,15,True)
                cols=[x+12,x+74,x+345,x+462]
                for j,v in enumerate(['Key','Field','Type','Req.']):text([v],cols[j],y+61,13,True,anchor='start')
                for i,row in enumerate(n['rows']):
                    yy=y+72+i*28;out.append(f'<path d="M {x},{yy} h {w}" stroke="#dae3eb"/>')
                    for j,v in enumerate(row):text([v],cols[j],yy+19,13,anchor='start')
                yy=y+90+len(n['rows'])*28
                for line in n['notes']:text([line],x+12,yy,12,anchor='start');yy+=17
                continue
            if k=='decision':out.append(f'<polygon points="{x+w/2},{y} {x+w},{y+h/2} {x+w/2},{y+h} {x},{y+h/2}" fill="{fill}" stroke="{stroke}" stroke-width="1.5"/>')
            elif k in ('ellipse','start','end'):out.append(f'<ellipse cx="{x+w/2}" cy="{y+h/2}" rx="{w/2}" ry="{h/2}" fill="{fill}" stroke="{stroke}"/>')
            elif k=='actor':
                cx=x+w/2;out.append(f'<circle cx="{cx}" cy="{y+18}" r="15" fill="white" stroke="{stroke}"/><path d="M {cx},{y+33} v 42 M {cx-30},{y+50} h 60 M {cx},{y+75} l -26,32 M {cx},{y+75} l 26,32" stroke="{stroke}" fill="none"/>');text([n['text']],cx,y+132,15,True);continue
            else:out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{0 if k=="label" else 8}" fill="{fill}" stroke="{stroke}" stroke-width="1.5"/>')
            size=n.get('size',15);lines=n.get('lines') or wrap(n['text'],w-12,size,n.get('bold',False));baseline=y+(h-len(lines)*(size+5))/2+size
            text(lines,x+w/2,baseline,size,n.get('bold',False),'white' if k in ('start','end') else '#17324d')
        out.append('</svg>');return '\n'.join(out)

def features():
    result=[]
    for spec in json.loads((ROOT/'tools/diagram_feature_sources.json').read_text(encoding='utf-8')):
        d=Diagram(spec['name'],1480,340+200*max(n['row'] for n in spec['nodes']),spec['purpose'])
        for n in spec['nodes']:
            kind=n['kind'];w=360 if kind=='decision' else 320;h=160 if kind=='decision' else 120
            d.n(n['id'],n['text'],80+n['col']*480+(320-w)/2,150+n['row']*200,w,h,kind)
        d.edges=spec['edges'];result.append(d)
    return result

def activity(name,steps,edges):
    maxrow=max(s[3] for s in steps);d=Diagram(name,1320,330+maxrow*180,'Blue: user action | Orange: system action | Labeled branches are choices; crossing lines are not junctions')
    d.n('lane-user','USER',40,120,600,d.height-150,'boundary');d.n('lane-system','SYSTEM',660,120,620,d.height-150,'boundary')
    for id,text,col,row,kind in steps:
        if col==0 and kind=='warning':text=text.replace('Show ','Read ').replace('Display ','Read ')
        d.n(id,text,160 if col==0 else 800,180+row*180,360,140 if kind=='decision' else 100,kind)
    d.edges=[edge(*e) for e in edges];return d

def activities():
    admin=[('start','Admin opens sign-in',0,0,'start'),('login','Submit email and password',0,1,'user'),('check','Backend validates local credentials, role and account status',1,1,'system'),('valid','Valid admin session?',1,2,'decision'),('error','Show sign-in error; retry',0,2,'warning'),('menu','Choose management action',0,3,'user'),('choice','Selected action?',0,4,'decision'),('view','Read operations, reports or support',0,5,'user'),('read','Query records and display results; no management write',1,5,'system'),('edit','Enter or edit drivers, jeepneys, routes, fares or terminals',0,6,'user'),('save','Validate and save only valid changes; otherwise show errors',1,6,'system'),('message','Publish announcement or send support reply',0,7,'user'),('send','Validate, persist and notify authorized users',1,7,'system'),('logout','Choose logout',0,8,'user'),('clear','Attempt refresh-token revocation; clear local session',1,8,'system'),('end','Signed out',0,9,'end')]
    ae=[('start','login'),('login','check'),('check','valid'),('valid','error','No'),('error','login'),('valid','menu','Yes'),('menu','choice'),('choice','view','View'),('view','read'),('read','menu','Return'),('choice','edit','Manage'),('edit','save'),('save','menu','Return'),('choice','message','Communicate'),('message','send'),('send','menu','Return'),('choice','logout','Log out'),('logout','clear'),('clear','end')]
    driver=[('start','Driver opens sign-in',0,0,'start'),('login','Submit local email and password',0,1,'user'),('check','Validate role, account and profile',1,1,'system'),('valid','Valid driver session?',1,2,'decision'),('error','Show error and retry',0,2,'warning'),('mode','Choose assigned route or terminal operation',0,3,'user'),('trip','Validate assignments; create active trip or terminal queue entry',1,3,'system'),('ready','Trip start succeeds?',1,4,'decision'),('blocked','Show assignment or trip-start error',0,4,'warning'),('operate','Share GPS while operating; choose an action when needed',0,5,'user'),('event','Next action?',0,6,'decision'),('gps','Validate and store vehicle location; publish scoped updates and run location automation',1,5,'system'),('request','View and acknowledge assigned pickup request',0,7,'user'),('ack','Validate ownership; mark acknowledged; notify passenger',1,7,'system'),('ride','Confirm existing pickup, complete onboard ride or adjust walk-in count',0,8,'user'),('update','Validate action; update relevant request, ride or occupancy. Driver does not initiate passenger boarding',1,8,'system'),('finish','End trip and stop location sharing',0,9,'user'),('close','Close trip; disable requests. Presence expires separately from recent GPS',1,9,'system'),('end','Trip closed; passenger rides have their own completion state',0,10,'end')]
    de=[('start','login'),('login','check'),('check','valid'),('valid','error','No'),('error','login'),('valid','mode','Yes'),('mode','trip'),('trip','ready'),('ready','blocked','No'),('blocked','mode'),('ready','operate','Yes'),('operate','event'),('event','gps','GPS update'),('gps','operate'),('event','request','Pickup arrives'),('request','ack'),('ack','operate'),('event','ride','Ride / count'),('ride','update'),('update','operate'),('event','finish','End trip'),('finish','close'),('close','end')]
    passenger=[('start','Passenger opens application',0,0,'start'),('login','Register or sign in: local credentials or Google',0,1,'user'),('auth','Backend validates identity and passenger role; issues ParaGO session',1,1,'system'),('valid','Valid passenger session?',1,2,'decision'),('error','Show sign-in error; retry',0,2,'warning'),('selection','Choose route, roadside/terminal pickup and destination; preview jeepneys',0,3,'user'),('submit','Submit pickup request',0,4,'user'),('assign','Validate locations and capacity; backend selects eligible trip and saves pending request',1,4,'system'),('accepted','Request accepted?',1,5,'decision'),('reject','Show booking/availability error; no unassigned request',0,5,'warning'),('wait','Wait for asynchronous driver response; passenger may cancel',0,6,'user'),('outcome','Request outcome?',1,6,'decision'),('retry','Cancelled or expired; choose whether to submit a new request',0,7,'warning'),('board','Passenger validates manual boarding or waits for automatic proximity boarding',0,8,'user'),('boarding','Recheck boarding requirements; on success create onboard ride and increase occupancy',1,8,'system'),('onboard','Boarding succeeded?',1,9,'decision'),('boarderror','Display validation error or continue waiting for qualifying proximity',0,9,'warning'),('ride','Track vehicle and destination; choose ride action',0,10,'user'),('action','Next ride action?',0,11,'decision'),('alert','Validate and publish optional digital para stop alert',1,11,'system'),('unload','Passenger requests unload, or system observes qualifying separation',0,12,'user'),('complete','Complete onboard ride; decrease occupancy, dismiss alerts and notify',1,12,'system'),('end','Ride completed',0,13,'end')]
    passenger=[(id, 'Passenger requests manual unload' if id=='unload' else 'Validate caller and ride; complete onboard ride, decrease count and dismiss alerts' if id=='complete' else text, col, 13 if id=='complete' else 15 if id=='end' else row, kind) for id,text,col,row,kind in passenger]
    passenger.extend([('auto-event','Event: system observes qualifying separation while ride is onboard',1,12,'system'),('completed','Completion succeeded or already completed?',1,14,'decision')])
    pe=[('start','login'),('login','auth'),('auth','valid'),('valid','error','No'),('error','login'),('valid','selection','Yes'),('selection','submit'),('submit','assign'),('assign','accepted'),('accepted','reject','No'),('reject','selection'),('accepted','wait','Yes'),('wait','outcome'),('outcome','retry','Cancel / expire'),('retry','selection'),('outcome','wait','Still pending'),('outcome','board','Acknowledged'),('board','boarding'),('boarding','onboard'),('onboard','boarderror','No'),('boarderror','board'),('onboard','ride','Yes'),('ride','action'),('action','alert','Send para'),('alert','ride'),('action','ride','Continue tracking'),('action','unload','Complete ride'),('unload','complete'),('auto-event','complete','Automatic'),('complete','completed'),('completed','end','Yes'),('completed','ride','No; show error')]
    return [activity('Admin Activity Diagram',admin,ae),activity('Driver Activity Diagram',driver,de),activity('Passenger Activity Diagram',passenger,pe)]

def deployment():
    d=Diagram('ParaGO AWS Staging Deployment',2280,1580,'Checked-in infrastructure and client defaults; deployed resources and build overrides require runtime verification')
    d.n('aws','AWS staging resources (not external identity or database ownership)',650,130,980,1260,'boundary')
    d.n('ec2','Private EC2 instance',720,430,840,540,'boundary')
    d.n('browser','Admin browser\nFlutter web client',80,200,400,120,'user')
    d.n('vercel','Vercel\nStatic admin web assets',80,430,400,100,'system')
    d.n('passenger','Passenger Android application',80,690,400,100,'user')
    d.n('driver','Driver Android application',80,910,400,100,'user')
    d.n('cloudfront','CloudFront\nHTTPS API + configured Socket.IO\nVPC origin: HTTP port 80',920,210,400,140,'system')
    d.n('nginx','NGINX :80\nOrigin-header check and reverse proxy',940,490,400,100,'system')
    d.n('api','Node.js / Express :5000\nREST API + Socket.IO process',780,690,340,120,'system')
    d.n('worker','Separate Node.js worker process\nBackground jobs and event publication',1180,790,340,120,'system')
    d.n('valkey','Private Valkey (TLS)\nCache, job queue and operational pub/sub',800,1050,340,120,'data')
    d.n('ssm','SSM Parameter Store + KMS\nSecure runtime configuration',1220,1050,340,120,'data')
    d.n('s3','Private S3\nEncrypted driver-license image objects',800,1240,340,110,'data')
    d.n('logs','CloudWatch\nLogs and monitoring',1220,1240,340,110,'system')
    d.n('atlas','External: MongoDB Atlas\nDurable users, trips, rides and document metadata',1770,210,400,140,'data')
    d.n('firebase','External: Firebase / Google\nPassenger Google sign-in only',1770,470,400,120,'system')
    d.n('routing','External: Google Routes / TomTom\nTraffic ETA and route preview',1770,750,400,120,'system')
    d.n('fallback','Alternative DigitalOcean API endpoint\nClient candidate when configured and healthy\nNot a CloudFront origin or automatic AWS failover',1770,1070,400,170,'note')
    d.n('legend','Local email/password is checked by the backend against MongoDB. Realtime and API candidates depend on build configuration. S3 document URLs expire after 300 seconds. Lines show initiated requests / dependencies; responses return to the caller.',80,1280,470,210,'note',size=13)
    for x in [('browser','vercel','Fetch web assets'),('browser','cloudfront','API / realtime'),('passenger','cloudfront','API / realtime'),('driver','cloudfront','API / realtime'),('cloudfront','nginx','VPC origin HTTP'),('nginx','api','Proxy :5000'),('api','atlas','Read / write'),('worker','atlas','Background records'),('api','valkey','Cache / queue / pubsub'),('worker','valkey','Consume / publish'),('api','ssm','Runtime config'),('api','logs','Logs'),('api','s3','Upload / delete objects'),('browser','s3','Presigned GET'),('passenger','firebase','Google identity'),('api','firebase','Verify ID token'),('api','routing','ETA / preview')]:d.e(*x)
    return d

def architecture(thesis=False):
    if thesis:
        d=Diagram('ParaGO Logical Architecture — Thesis Overview',1740,1070,'Logical responsibilities; AWS staging transport details are shown in the separate deployment diagram')
        ns=[('clients','Passenger and driver mobile clients\nAdmin browser client',80,200,'user'),('entry','CloudFront HTTPS entry\nREST + configured realtime',660,200,'system'),('server','Private EC2\nNGINX → Node API / Socket.IO\nSeparate background worker',660,440,'system'),('db','MongoDB Atlas\nDurable application records',1220,200,'data'),('auth','Firebase / Google\nPassenger Google identity only',80,490,'system'),('cache','Valkey\nCache, queue and pub/sub',1220,490,'data'),('config','SSM secure runtime configuration',660,750,'data'),('s3','Private S3 driver documents\nAPI uploads; client presigned reads',1220,750,'data')]
        for id,text,x,y,k in ns:d.n(id,text,x,y,420,140,k)
        d.n('note','Local email/password and ParaGO sessions belong to the backend. External routing/ETA services are detailed in the full architecture. Client endpoint fallback and realtime are configuration-dependent.',80,760,420,190,'note',size=13)
        for e in [('clients','entry','Requests / updates'),('entry','server','Origin traffic'),('server','db','Read / write'),('clients','auth','Google sign-in'),('server','auth','Verify token'),('server','cache','Transient / jobs'),('server','config','Read configuration'),('server','s3','Document storage')]:d.e(*e)
        return d
    d=Diagram('ParaGO System Architecture',2240,1510,'Runtime responsibilities and external dependencies; arrows identify initiated calls/events, not server ownership')
    for args in [('passenger','Passenger Flutter app\nLocal or Google sign-in',70,200,420,120,'user'),('driver','Driver Flutter app\nLocal email/password sign-in',70,440,420,120,'user'),('admin','Admin Flutter web in browser\nLocal email/password sign-in',70,680,420,120,'user'),('vercel','Vercel serves static admin assets',70,940,420,100,'system'),('entry','CloudFront → VPC origin → NGINX\nHTTPS clients, private HTTP origin',800,200,480,130,'system'),('api','Express API + Socket.IO server\nAuthorize, validate and serve requests\nIssue ParaGO access / refresh tokens',800,460,480,150,'system'),('worker','Separate background worker\nExpiry, announcements and async jobs',800,790,480,120,'system'),('valkey','Valkey\nRead cache, transient state, jobs, event bridge',800,1080,480,120,'data'),('mongo','MongoDB Atlas\nDurable records and document metadata',1620,200,490,130,'data'),('firebase','Firebase Authentication / Google\nPassenger Google identity verification',1620,470,490,120,'system'),('maps','Google Routes: traffic ETA\nGoogle / TomTom: route preview',1620,740,490,120,'system'),('s3','Private S3 license documents\nAPI writes; short-lived client reads',1620,1010,490,120,'data'),('infra','Deployment dependencies: Terraform state in S3; SSM + KMS for runtime secrets; CloudWatch logs/alarms. These are not user request intermediaries.',70,1190,570,200,'note'),('fallback','Client endpoint candidates can include DigitalOcean; this is not a CloudFront fallback origin. Realtime depends on each build setting.',1420,1280,680,140,'note')]:d.n(*args)
    for e in [('passenger','entry','REST / realtime'),('driver','entry','REST / realtime'),('admin','entry','REST / optional realtime'),('admin','vercel','Web assets'),('entry','api','Reverse proxy'),('api','mongo','Durable state'),('worker','mongo','Background updates'),('api','valkey','Cache / queue / event bridge'),('worker','valkey','Consume / publish'),('passenger','firebase','Google identity'),('api','firebase','Verify Google token'),('api','maps','ETA / geometry'),('api','s3','Upload and URL signing'),('admin','s3','Presigned GET')]:d.e(*e)
    return d

def usecases():
    d=Diagram('ParaGO Use Case Diagram',1660,2220,'Current user capabilities; system automation supports passenger boarding and ride completion')
    d.n('system','ParaGO transportation management system',450,130,1160,2030,'boundary')
    groups=[('admin','ADMIN',230,['Log in with local credentials','Manage users and drivers, including license documents','Manage jeepneys, routes, fares and terminals','Monitor operations; view reports and activity','Manage announcements and support']),('driver','DRIVER',860,['Log in and enable/disable operation','Start and manage assigned trip or terminal queue','Share vehicle location','Acknowledge pickup; confirm an existing boarded pickup','Complete onboard ride; adjust manual walk-in count','Read announcements; contact support']),('passenger','PASSENGER',1540,['Register / log in locally or with Google','Browse routes; preview jeepneys; request assigned pickup','Cancel pending or acknowledged request','Validate manual boarding; use automatic proximity boarding','Track jeepney; optionally send digital para','Complete ride manually or by automatic separation','Read notifications and announcements; contact support'])]
    for role,title,y,labels in groups:
        d.n(role,'«actor»\n'+title,80,y+100,250,100,'process',bold=True)
        for i,label in enumerate(labels):
            id=f'{role}-{i}';d.n(id,label,680,y+i*85,670,65,'ellipse',size=14);d.e(role,id,arrow='none')
    return d

def erds(models):
    byname={m['collection']:m for m in models};refnames={m['model']:m['collection'] for m in models}
    sets=[('Selected Physical Relationships — All Collections',list(byname)),('Authentication — Selected Physical Fields',['users','passengers','drivers','admins','refreshtokens','passwordresettokens','adminloginchallenges','notifications']),('Transportation — Selected Physical Fields',['users','passengers','drivers','jeepneys','routes','tripsessions','pickuprequests','ridesessions','stopalerts']),('Communication — Selected Physical Fields',['users','announcements','announcementdismissals','notifications','supportthreads','supportmessages','activitylogs','reportmetadatas','tripsessions','routes','pickuprequests','ridesessions'])]
    result=[]
    for title,names in sets:
        d=Diagram(title,3300,2000,'Application ObjectId references, not database foreign keys. Req = Mongoose required. Full paths and index predicates: ParaGO_schema_reference.json')
        cards=[]
        for name in names:
            m=byname[name];paths=[p for p in m['paths'] if p['path'] not in ('_id','__v')];refs=[p for p in paths if p.get('ref')]
            # Every drawn relationship has its field displayed. Other displayed fields are explicitly selected.
            selected=refs+[p for p in paths if '.' not in p['path'] and not p.get('ref')][:6 if len(names)>15 else 14]
            selected_ids={p['path'] for p in selected}
            for p in paths:
                if p['path'] not in selected_ids and '.' not in p['path'] and (p['required'] or p['path'] in ('autoOffboarding','destinationApproachAlertedAt','destinationStopRef','terminalCheckedInAt','manualOccupancyCount')):
                    selected.append(p);selected_ids.add(p['path'])
            selected=sorted(selected,key=lambda p:(not bool(p.get('ref')),p['path']))
            rows=[['PK','_id','ObjectId','Auto']];notes=[]
            for p in selected:
                key='REF' if p.get('ref') else ''
                if any(list(keys)==[p['path']] and opts.get('unique') for keys,opts in m['indexes']):key+='/UK' if key else 'UK'
                rows.append([key,p['path'],p['type'],'Yes' if p['required'] else 'No'])
                if p.get('ref'):notes.append(p['path']+' → '+refnames.get(p['ref'],p['ref'])+' ['+('1' if p['required'] else '0..1')+' parent]')
            unique=[]
            for keys,opts in m['indexes']:
                if opts.get('unique'):unique.append(' + '.join(keys)+(' [partial]' if opts.get('partialFilterExpression') else ''))
            if unique:notes+=['Unique indexes (whole key):']+unique
            notes+=['_id is auto-generated; Req applies to Mongoose validators.','REF: application reference; no database FK.','Reverse: 0..many children unless reference is unique.','Selected fields. Full fields / predicates: schema reference.']
            measured=[]
            for line in notes:measured.extend(wrap(line,530,12,False))
            for row in rows:
                for v,width in zip(row,[54,260,100,55]):
                    if font(13).getlength(v)>width:raise ValueError('ERD cell too wide: '+str(row))
            cards.append((name,rows,refs,measured))
        columns=4;row_heights=[]
        for row in range(math.ceil(len(cards)/columns)):
            row_heights.append(max(110+len(c[1])*28+len(c[3])*17 for c in cards[row*columns:(row+1)*columns]))
        d.height=300+sum(h+160 for h in row_heights)
        for i,(name,rows,refs,notes) in enumerate(cards):
            row=i//columns;y=160+sum(h+160 for h in row_heights[:row]);x=100+(i%columns)*810
            d.n(name,name,x,y,590,110+len(rows)*28+len(notes)*17,'table',size=13,rows=rows,notes=notes)
        # One named edge per ordered pair, fields remain named in the child box.
        groups={}
        for name,rows,refs,notes in cards:
            for p in refs:
                parent=refnames.get(p['ref'])
                if parent in names and parent!=name:groups.setdefault((name,parent),[]).append(p)
        for (child,parent),ps in groups.items():
            # Direction is child reference -> parent; no false mandatory cardinality implied.
            d.e(child,parent,arrow='open')
        result.append(d)
    return result

def sequence():
    d=Diagram('Core Ride Lifecycle — Successful Scenario',2420,4000,'Solid open arrows: asynchronous events. Dashed arrows: HTTP responses. Combined fragments show alternatives and optional work.')
    names=[('admin','Admin browser'),('passenger','Passenger app'),('driver','Driver app'),('api','API / Socket.IO'),('mongo','MongoDB Atlas'),('valkey','Valkey bridge'),('worker','Background worker')]
    xs={}
    for i,(id,title) in enumerate(names):
        x=60+i*340;xs[id]=x+130;d.n(id,title,x,150,260,70,'system')
        d.n(id+'-line','',x+129,240,2,3500,'lifeline')
    cursor=300
    def messages(rows):
        nonlocal cursor
        for s,t,label,*kind in rows:
            y=cursor;cursor+=90
            d.edges.append(edge(s+'-line',t+'-line',label,points=[(xs[s],y),(xs[t],y)],source_port='right',target_port='left',arrow='open' if kind in (['event'],['response']) else 'block',dashed=kind==['response'],sequence_y=y))
    def block(id,title,rows):
        nonlocal cursor
        cursor+=50;top=cursor-45
        messages(rows)
        d.n(id,title,35,top,d.width-70,cursor-top-30,'frame');cursor+=55
    messages([('admin','api','Configure operations via authorized REST'),('api','mongo','Save routes, drivers, vehicles and fares'),('api','admin','HTTP success','response'),('driver','api','Start assigned route / terminal trip'),('api','mongo','Validate assignment; create trip'),('api','driver','HTTP trip response','response'),('passenger','api','Authenticate; browse route / pickup options'),('api','passenger','HTTP ParaGO session / options','response'),('passenger','api','Submit route, pickup type and points'),('api','mongo','Select eligible trip; save pending pickup'),('api','driver','EVENT: assigned pickup notification','event'),('driver','api','Acknowledge assigned request'),('api','mongo','Save acknowledged state; sync terminal state if applicable'),('api','passenger','EVENT: request acknowledged','event')])
    block('alt-boarding','alt — choose manual validation OR qualifying proximity updates',[
        ('passenger','api','[manual] Passenger submits boarding validation'),('passenger','api','[automatic] Location updates satisfy proximity dwell')])
    messages([('api','mongo','Shared boarding validation; create onboard ride and increase occupancy'),('api','passenger','EVENT: ride onboard','event')])
    block('loop-tracking','loop — while driver operates; repeats independently of one passenger ride',[
        ('driver','api','Submit vehicle location update'),('api','mongo','Store accepted vehicle location / ordering'),('api','passenger','EVENT: authorized location update','event')])
    block('opt-para','opt — passenger sends digital para while onboard',[
        ('passenger','api','Request digital para stop alert'),('api','mongo','Validate onboard context; save alert'),('api','driver','EVENT: requested stop','event')])
    block('alt-completion','alt — manual completion OR automatic separation evaluation',[
        ('passenger','api','[manual] Request unload (assigned driver/admin also permitted)'),('passenger','api','[automatic] Location updates yield qualifying separation evaluations')])
    messages([('api','mongo','Complete ride; decrease count; dismiss active alerts'),('api','passenger','EVENT: completed ride','event'),('api','driver','EVENT: passenger completion when applicable','event'),('admin','api','Monitoring REST refresh (realtime is build-dependent)'),('api','admin','HTTP current operational records','response')])
    block('opt-worker','opt — separate worker publishes an operational event (not a required hop for local API events)',[
        ('worker','mongo','Persist background job result / notification'),('worker','valkey','Publish scoped operational event','event'),('valkey','api','Subscriber receives event','event'),('api','passenger','Forward event to authorized Socket.IO client','event')])
    for n in d.nodes:
        if n['kind']=='lifeline':n['h']=cursor-240
    d.height=cursor+220
    d.n('bridge-note','Valkey is the backend event bridge, not a client socket server. HTTP responses and some notification persistence are condensed. Driver GPS can also trigger automatic checks; error/cancel/expiry paths are in the feature flowcharts.',80,cursor+35,d.width-160,125,'note',size=13)
    return d

def write_set(filename,diagrams,svg_names=None):
    mx=ET.Element('mxfile',{'host':'app.diagrams.net','agent':'ParaGO schema/source generator','version':'24.7.17'})
    for i,d in enumerate(diagrams):
        d.prepare();mx.append(d.xml())
        name=svg_names[i] if svg_names else filename.removesuffix('.drawio')+('-'+str(i+1).zfill(2) if len(diagrams)>1 else '')+'.svg'
        (OUT/name).write_text(d.svg(),encoding='utf-8')
        ALL.append((filename,name,d))
    ET.indent(mx);ET.ElementTree(mx).write(OUT/filename,encoding='utf-8',xml_declaration=True)

ALL=[]
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--only',choices=['features','activities','erd','architecture','deployment','usecases','sequence']);args=parser.parse_args()
    OUT.mkdir(exist_ok=True)
    if not args.only or args.only=='features':write_set('ParaGO_feature_algorithm_flowcharts.drawio',features())
    if not args.only or args.only=='activities':write_set('ParaGO_activity_diagrams.drawio',activities(),['admin_activity_diagram.svg','driver_activity_diagram.svg','passenger_activity_diagram.svg'])
    if not args.only or args.only=='deployment':write_set('ParaGO_deployment_diagram.drawio',[deployment()])
    if not args.only or args.only=='architecture':
        write_set('ParaGO_system_architecture.drawio',[architecture()]);write_set('ParaGO_system_architecture_thesis_format.drawio',[architecture(True)])
    if not args.only or args.only=='usecases':write_set('ParaGO_use_case_diagram.drawio',[usecases()])
    if not args.only or args.only=='erd':
        subprocess.run(['node',str(ROOT/'tools/export_diagram_schema.cjs')],cwd=ROOT,check=True)
        models=json.loads((OUT/'ParaGO_schema_reference.json').read_text(encoding='utf-8'));write_set('ParaGO_entity_relationship_diagrams.drawio',erds(models))
        lines=['# ParaGO schema reference','','Generated from Mongoose declarations without connecting to a database. Required means an explicit Mongoose required validator. Defaults are not required validators. Declared indexes are not proof of live installed indexes. ObjectId references are application-level links, not database foreign keys.','']
        for m in models:
            lines += ['## '+m['collection'],'','Model source: `src/models/'+m['file']+'`','','| Field path | Type | Required | Reference / enum |','|---|---|---|---|']
            for p in m['paths']:lines.append('| '+p['path']+' | '+p['type']+' | '+('Yes' if p['required'] else 'No')+' | '+str(p.get('ref') or ', '.join(p.get('enum',[])))+' |')
            lines+=['','Declared indexes, including partial and TTL options:','','```json',json.dumps(m['indexes'],indent=2),'```','']
        (OUT/'ParaGO_schema_reference.md').write_text('\n'.join(lines),encoding='utf-8')
    if not args.only or args.only=='sequence':write_set('ParaGO_Sequence_Diagram.drawio',[sequence()])
    rows=[]
    for filename,svg,d in ALL:rows.append(dict(file=filename,page=d.name,svg=svg,nodes=len(d.nodes),edges=len(d.edges),routes_clear=True,text_fits=True))
    (OUT/('validation-'+(args.only or 'all')+'.json')).write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
    links='\n'.join(f'<li><a href="{html.escape(svg)}">{html.escape(d.name)}</a></li>' for _,svg,d in ALL)
    if not args.only:
        (OUT/'index.html').write_text('<!doctype html><meta charset="utf-8"><title>ParaGO diagrams</title><style>body{font:16px Arial;max-width:1000px;margin:40px auto;color:#17324d}li{margin:12px 0}</style><h1>ParaGO corrected diagrams</h1><p>SVGs and editable draw.io files share the same measured text and explicit connector geometry. Reviewed against repository source; deployment flags and live indexes are not certified.</p><ol>'+links+'</ol>',encoding='utf-8')
    print(f'Generated {len(ALL)} pages; measured text and clear connector routes verified.')
if __name__=='__main__':main()
