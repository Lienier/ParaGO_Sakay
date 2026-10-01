const fs = require('fs');
const path = require('path');

const outDir = __dirname;

const C = {
  ink: '#17324d',
  muted: '#5c7185',
  line: '#6f8497',
  lane: '#f4f7f9',
  laneAlt: '#eef3f6',
  process: '#e8f2f5',
  processStroke: '#2c7285',
  decision: '#fff3d8',
  decisionStroke: '#b9791e',
  data: '#e8eef8',
  dataStroke: '#4f6694',
  notification: '#edf1fb',
  notificationStroke: '#677abd',
  exception: '#fff0ed',
  exceptionStroke: '#b14c3a',
  external: '#eeeaf9',
  externalStroke: '#765ca6',
  note: '#fffdf1',
  noteStroke: '#a58c3a',
};

function esc(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function wrap(text, maxChars) {
  const words = String(text).split(/\s+/);
  const lines = [];
  let line = '';
  for (const word of words) {
    const candidate = line ? `${line} ${word}` : word;
    if (candidate.length > maxChars && line) {
      lines.push(line);
      line = word;
    } else {
      line = candidate;
    }
  }
  if (line) lines.push(line);
  return lines;
}

function nodeStyle(kind) {
  if (kind === 'decision') return [C.decision, C.decisionStroke];
  if (kind === 'data') return [C.data, C.dataStroke];
  if (kind === 'notification') return [C.notification, C.notificationStroke];
  if (kind === 'exception') return [C.exception, C.exceptionStroke];
  if (kind === 'external') return [C.external, C.externalStroke];
  if (kind === 'note') return [C.note, C.noteStroke];
  return [C.process, C.processStroke];
}

function nodeCenter(n) {
  return { x: n.x + n.w / 2, y: n.y + n.h / 2 };
}

function svgText(text, x, y, maxChars, size = 17, weight = 500, fill = C.ink, anchor = 'middle') {
  const lines = wrap(text, maxChars);
  const lineHeight = size + 5;
  const startY = y - ((lines.length - 1) * lineHeight) / 2 + size * 0.35;
  return lines.map((line, i) => `<text x="${x}" y="${startY + i * lineHeight}" text-anchor="${anchor}" font-family="Arial, Helvetica, sans-serif" font-size="${size}px" font-weight="${weight}" fill="${fill}">${esc(line)}</text>`).join('');
}

function drawSvgNode(n) {
  const [fill, stroke] = nodeStyle(n.kind);
  const x = n.x; const y = n.y; const w = n.w; const h = n.h;
  const cx = x + w / 2; const cy = y + h / 2;
  const label = svgText(n.label, cx, cy, Math.max(12, Math.floor(w / 11)), 16, 500);
  if (n.kind === 'start' || n.kind === 'end') {
    const fillColor = n.kind === 'start' ? '#dff1e7' : '#e5e8ef';
    const strokeColor = n.kind === 'start' ? '#2f7a52' : '#536174';
    return `<ellipse cx="${cx}" cy="${cy}" rx="${w / 2}" ry="${h / 2}" fill="${fillColor}" stroke="${strokeColor}" stroke-width="2.5"/>${svgText(n.label, cx, cy, Math.max(12, Math.floor(w / 10)), 16, 600)}`;
  }
  if (n.kind === 'decision') {
    const points = `${cx},${y} ${x + w},${cy} ${cx},${y + h} ${x},${cy}`;
    return `<polygon points="${points}" fill="${fill}" stroke="${stroke}" stroke-width="2.5"/>${svgText(n.label, cx, cy, Math.max(11, Math.floor(w / 12)), 15, 600)}`;
  }
  if (n.kind === 'data') {
    return `<path d="M ${x + 16} ${y + 10} C ${x + 16} ${y} ${x + w - 16} ${y} ${x + w - 16} ${y + 10} L ${x + w - 16} ${y + h - 10} C ${x + w - 16} ${y + h} ${x + 16} ${y + h} ${x + 16} ${y + h - 10} Z" fill="${fill}" stroke="${stroke}" stroke-width="2.5"/>${svgText(n.label, cx, cy, Math.max(12, Math.floor(w / 11)), 15, 500)}`;
  }
  if (n.kind === 'document') {
    const fold = 18;
    return `<path d="M ${x} ${y} H ${x + w - fold} L ${x + w} ${y + fold} V ${y + h} H ${x} Z M ${x + w - fold} ${y} V ${y + fold} H ${x + w}" fill="${fill}" stroke="${stroke}" stroke-width="2.5"/>${label}`;
  }
  if (n.kind === 'cloud' || n.kind === 'external') {
    const p = `M ${x + 18} ${cy + 16} C ${x - 6} ${cy + 10} ${x - 2} ${cy - 20} ${x + 25} ${cy - 18} C ${x + 28} ${cy - 45} ${x + 72} ${cy - 48} ${x + 82} ${cy - 23} C ${x + 107} ${cy - 42} ${x + 143} ${cy - 20} ${x + 132} ${cy + 7} C ${x + 161} ${cy + 6} ${x + 161} ${cy + 35} ${x + 132} ${cy + 34} H ${x + 27} C ${x + 5} ${cy + 35} ${x - 4} ${cy + 18} ${x + 18} ${cy + 16} Z`;
    return `<path d="${p}" fill="${fill}" stroke="${stroke}" stroke-width="2.5"/>${svgText(n.label, cx, cy + 3, Math.max(12, Math.floor(w / 11)), 15, 500)}`;
  }
  const radius = n.kind === 'note' ? 4 : (n.kind === 'process' ? 8 : 24);
  return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${radius}" fill="${fill}" stroke="${stroke}" stroke-width="2.5"/>${label}`;
}

function edgePath(a, b) {
  const ac = nodeCenter(a); const bc = nodeCenter(b);
  if (Math.abs(ac.y - bc.y) < 10) return `M ${ac.x} ${ac.y} L ${bc.x} ${bc.y}`;
  const midX = (ac.x + bc.x) / 2;
  return `M ${ac.x} ${ac.y} L ${midX} ${ac.y} L ${midX} ${bc.y} L ${bc.x} ${bc.y}`;
}

function svgForPage(page) {
  const width = page.width || 1800;
  const height = page.height || 1250;
  const laneHtml = (page.lanes || []).map((lane, i) => {
    const fill = i % 2 ? C.laneAlt : C.lane;
    return `<rect x="0" y="${lane.y}" width="${width}" height="${lane.h}" fill="${fill}" stroke="#d3dde5" stroke-width="1"/><rect x="0" y="${lane.y}" width="170" height="${lane.h}" fill="#e4ebf0" stroke="#c2cfd8" stroke-width="1"/>${svgText(lane.label, 85, lane.y + lane.h / 2, 13, 16, 700, C.ink)}`;
  }).join('');
  const nodeMap = new Map(page.nodes.map(n => [n.id, n]));
  const edges = (page.edges || []).map(e => {
    const a = nodeMap.get(e.from); const b = nodeMap.get(e.to);
    if (!a || !b) throw new Error(`Missing edge node in ${page.id}: ${e.from} -> ${e.to}`);
    const ac = nodeCenter(a); const bc = nodeCenter(b);
    const labelX = (ac.x + bc.x) / 2; const labelY = (ac.y + bc.y) / 2 - 8;
    return `<path d="${edgePath(a, b)}" fill="none" stroke="${C.line}" stroke-width="2.2" marker-end="url(#arrow)"/>${e.label ? `<rect x="${labelX - 60}" y="${labelY - 13}" width="120" height="20" fill="#ffffff" opacity="0.92"/><text x="${labelX}" y="${labelY}" text-anchor="middle" font-family="Arial, Helvetica, sans-serif" font-size="13px" fill="${C.muted}">${esc(e.label)}</text>` : ''}`;
  }).join('');
  const nodes = page.nodes.map(drawSvgNode).join('');
  const legend = page.legend === false ? '' : `<g transform="translate(1380,${height - 102})"><text x="0" y="0" font-family="Arial, Helvetica, sans-serif" font-size="14px" font-weight="700" fill="${C.ink}">Legend</text><rect x="0" y="14" width="18" height="14" rx="6" fill="${C.process}" stroke="${C.processStroke}"/><text x="26" y="26" font-family="Arial" font-size="12px" fill="${C.muted}">Process</text><polygon points="85,14 95,21 85,28 75,21" fill="${C.decision}" stroke="${C.decisionStroke}"/><text x="104" y="26" font-family="Arial" font-size="12px" fill="${C.muted}">Decision</text><path d="M 180 15 C 180 10 205 10 205 15 L 205 28 C 205 33 180 33 180 28 Z" fill="${C.data}" stroke="${C.dataStroke}"/><text x="214" y="26" font-family="Arial" font-size="12px" fill="${C.muted}">Data store</text><path d="M 320 21 C 315 14 325 8 333 14 C 337 4 352 7 353 17 C 363 13 371 21 365 28 H 325 C 320 28 318 24 320 21 Z" fill="${C.external}" stroke="${C.externalStroke}"/><text x="377" y="26" font-family="Arial" font-size="12px" fill="${C.muted}">External service</text></g>`;
  return `<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="title desc"><title id="title">${esc(page.title)}</title><desc id="desc">${esc(page.description || page.title)}</desc><defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto" markerUnits="strokeWidth"><path d="M 0 0 L 10 3 L 0 6 z" fill="${C.line}"/></marker></defs><rect width="${width}" height="${height}" fill="#ffffff"/><text x="42" y="46" font-family="Arial, Helvetica, sans-serif" font-size="28px" font-weight="700" fill="${C.ink}">${esc(page.title)}</text><text x="42" y="76" font-family="Arial, Helvetica, sans-serif" font-size="15px" fill="${C.muted}">${esc(page.subtitle || 'ParaGO current system flow; API/database state is authoritative.')}</text>${laneHtml}${edges}${nodes}${legend}<text x="42" y="${height - 35}" font-family="Arial, Helvetica, sans-serif" font-size="13px" fill="${C.muted}">Documentation snapshot: 2026-09-27 - See README.md for scope, source references, and release caveats.</text></svg>`;
}

function mxStyle(kind) {
  if (kind === 'start' || kind === 'end') return 'shape=terminator;whiteSpace=wrap;html=1;rounded=1;fillColor=#dff1e7;strokeColor=#2f7a52;fontStyle=1;';
  if (kind === 'decision') return 'shape=rhombus;whiteSpace=wrap;html=1;fillColor=#fff3d8;strokeColor=#b9791e;fontStyle=1;';
  if (kind === 'data') return 'shape=cylinder;whiteSpace=wrap;html=1;fillColor=#e8eef8;strokeColor=#4f6694;';
  if (kind === 'document') return 'shape=document;whiteSpace=wrap;html=1;fillColor=#edf1fb;strokeColor=#677abd;';
  if (kind === 'cloud' || kind === 'external') return 'shape=cloud;whiteSpace=wrap;html=1;fillColor=#eeeaf9;strokeColor=#765ca6;';
  if (kind === 'exception') return 'rounded=1;whiteSpace=wrap;html=1;fillColor=#fff0ed;strokeColor=#b14c3a;';
  if (kind === 'note') return 'shape=note;whiteSpace=wrap;html=1;fillColor=#fffdf1;strokeColor=#a58c3a;';
  return 'rounded=1;whiteSpace=wrap;html=1;fillColor=#e8f2f5;strokeColor=#2c7285;';
}

function drawioForPages(pages) {
  const diagrams = pages.map((page, pageIndex) => {
    const nodeMap = new Map(page.nodes.map(n => [n.id, n]));
    const laneCells = (page.lanes || []).map((lane, i) => `<mxCell id="lane-${pageIndex}-${i}" value="${esc(lane.label)}" style="swimlane;html=1;horizontal=0;startSize=170;fillColor=${i % 2 ? '#eef3f6' : '#f4f7f9'};strokeColor=#c2cfd8;fontStyle=1;" vertex="1" parent="1"><mxGeometry x="0" y="${lane.y}" width="${page.width || 1800}" height="${lane.h}" as="geometry"/></mxCell>`).join('');
    const cells = page.nodes.map(n => `<mxCell id="${pageIndex}-${n.id}" value="${esc(n.label)}" style="${mxStyle(n.kind)}" vertex="1" parent="1"><mxGeometry x="${n.x}" y="${n.y}" width="${n.w}" height="${n.h}" as="geometry"/></mxCell>`).join('');
    const edges = (page.edges || []).map((e, i) => `<mxCell id="${pageIndex}-edge-${i}" value="${esc(e.label || '')}" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#6f8497;endArrow=block;" edge="1" parent="1" source="${pageIndex}-${e.from}" target="${pageIndex}-${e.to}"><mxGeometry relative="1" as="geometry"/></mxCell>`).join('');
    return `<diagram id="page-${page.id}" name="${esc(page.title)}"><mxGraphModel dx="1600" dy="1000" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1800" pageHeight="1250"><root><mxCell id="0"/><mxCell id="1" parent="0"/>${laneCells}${cells}${edges}</root></mxGraphModel></diagram>`;
  }).join('');
  return `<?xml version="1.0" encoding="UTF-8"?><mxfile host="app.diagrams.net" modified="2026-09-27T00:00:00.000Z" agent="ParaGO documentation generator" version="24.7.17" type="device">${diagrams}</mxfile>`;
}

const processMapPage = {
  id: 'end-to-end-process-map',
  title: '00 - ParaGO standard end-to-end process map',
  subtitle: 'The normal service procedure from configuration and terminal dispatch through booking, boarding, travel, unloading, and trip closure.',
  width: 1900,
  height: 3600,
  lanes: [
    { label: 'Administrator / setup', y: 95, h: 250 },
    { label: 'Driver / terminal dispatch', y: 345, h: 480 },
    { label: 'Backend / queue state', y: 825, h: 300 },
    { label: 'Passenger / booking', y: 1125, h: 420 },
    { label: 'Backend / ride state', y: 1545, h: 1330 },
    { label: 'Driver + passenger / completion', y: 2875, h: 725 },
  ],
  nodes: [
    { id: 'processStart', kind: 'start', label: 'Start service day', x: 835, y: 130, w: 230, h: 60 },
    { id: 'configure', kind: 'process', label: 'Admin configures active route, terminal, stops, fare, drivers, and jeep assignment', x: 760, y: 220, w: 380, h: 78 },
    { id: 'driverIntent', kind: 'process', label: 'Driver signs in and creates a terminal-intent trip', x: 760, y: 380, w: 380, h: 82 },
    { id: 'terminalConfigured', kind: 'decision', label: 'Terminal configured?', x: 810, y: 500, w: 280, h: 120 },
    { id: 'terminalConfigError', kind: 'exception', label: 'Reject start; admin must configure a terminal', x: 250, y: 520, w: 360, h: 80 },
    { id: 'gpsFixes', kind: 'process', label: 'Driver app sends ordered GPS fixes with timestamp and accuracy', x: 760, y: 650, w: 380, h: 78 },
    { id: 'twoFixes', kind: 'decision', label: 'Two fresh, accurate fixes inside terminal radius?', x: 810, y: 760, w: 280, h: 120 },
    { id: 'awaitFix', kind: 'exception', label: 'Remain off queue; wait for the next valid fix', x: 1300, y: 780, w: 350, h: 80 },
    { id: 'queueWaiting', kind: 'process', label: 'Create one idempotent queue entry in waiting state', x: 760, y: 910, w: 380, h: 76 },
    { id: 'promoteLoading', kind: 'process', label: 'Promote the earliest eligible jeep to loading', x: 760, y: 1010, w: 380, h: 78 },
    { id: 'loadingWindow', kind: 'process', label: '10-minute loading window; expiry closes terminal reservations and still requires explicit departure', x: 1280, y: 900, w: 390, h: 96 },
    { id: 'depart', kind: 'process', label: 'Driver or admin confirms Depart terminal', x: 1300, y: 1010, w: 350, h: 82 },
    { id: 'routeOperation', kind: 'process', label: 'Trip becomes route operation; roadside pickups can be accepted', x: 1300, y: 1115, w: 350, h: 82 },
    { id: 'passengerRequest', kind: 'process', label: 'Passenger chooses route and pins pickup and drop-off', x: 760, y: 1160, w: 380, h: 82 },
    { id: 'validatePins', kind: 'process', label: 'Validate route direction, pin order, alignment, fare, and deadline', x: 760, y: 1270, w: 380, h: 82 },
    { id: 'pinsValid', kind: 'decision', label: 'Pins and request valid?', x: 810, y: 1380, w: 280, h: 120 },
    { id: 'pinError', kind: 'exception', label: 'Show plain error; retain entered pins for correction', x: 250, y: 1400, w: 360, h: 84 },
    { id: 'pickupType', kind: 'decision', label: 'Pickup type?', x: 1270, y: 1380, w: 240, h: 120 },
    { id: 'terminalEligibility', kind: 'process', label: 'Terminal: only the loading jeep, open seats, and unexpired loading window', x: 1490, y: 1530, w: 360, h: 92 },
    { id: 'roadsideEligibility', kind: 'process', label: 'Roadside: departed route jeep, accepting requests, and open seats', x: 1090, y: 1530, w: 330, h: 92 },
    { id: 'capacity', kind: 'decision', label: 'Eligible jeep has capacity?', x: 810, y: 1670, w: 280, h: 120 },
    { id: 'bookingError', kind: 'exception', label: 'Reject as full/unavailable/expired; do not replay mutation', x: 250, y: 1690, w: 380, h: 84 },
    { id: 'bookingSaved', kind: 'data', label: 'Save pending booking with destination and fare snapshot', x: 760, y: 1820, w: 380, h: 98 },
    { id: 'cancelExpire', kind: 'exception', label: 'Passenger cancels or booking deadline expires; no ride is created', x: 1250, y: 1850, w: 380, h: 86 },
    { id: 'bookingClosed', kind: 'end', label: 'Booking closed', x: 1450, y: 1970, w: 210, h: 60 },
    { id: 'notifyAcknowledge', kind: 'notification', label: 'Notify assigned driver; driver acknowledges pickup', x: 760, y: 1970, w: 380, h: 86 },
    { id: 'ackValid', kind: 'decision', label: 'Acknowledged before expiry?', x: 810, y: 2090, w: 280, h: 120 },
    { id: 'ackWait', kind: 'exception', label: 'Remain pending until acknowledgement or expiry', x: 1260, y: 2110, w: 360, h: 82 },
    { id: 'boarding', kind: 'process', label: 'Passenger confirms boarding; eligible solo roadside auto-boarding may also complete after dwell', x: 760, y: 2250, w: 430, h: 92 },
    { id: 'boardingGps', kind: 'decision', label: 'Fresh passenger + jeep GPS and proximity valid?', x: 810, y: 2370, w: 280, h: 120 },
    { id: 'boardingRetry', kind: 'exception', label: 'Ask passenger to refresh location and try again; booking remains authoritative', x: 210, y: 2390, w: 440, h: 84 },
    { id: 'rideCreated', kind: 'process', label: 'Create ride transactionally and increase occupancy once', x: 760, y: 2520, w: 380, h: 84 },
    { id: 'travel', kind: 'process', label: 'Travel with map follow/free view, ETA, live status, and reconciliation', x: 760, y: 2630, w: 380, h: 84 },
    { id: 'paraDecision', kind: 'decision', label: 'Passenger sends para alert?', x: 1280, y: 2610, w: 250, h: 120 },
    { id: 'paraNotify', kind: 'notification', label: 'Notify driver with sound/push; acknowledgement does not unload', x: 1480, y: 2760, w: 350, h: 86 },
    { id: 'unload', kind: 'process', label: 'Passenger or driver starts the unload action', x: 760, y: 2760, w: 380, h: 84 },
    { id: 'autoEligible', kind: 'decision', label: 'Solo ride with fresh GPS and required outside samples?', x: 430, y: 2890, w: 300, h: 130 },
    { id: 'manualUnload', kind: 'process', label: 'Manual unload confirms the correct ride; GPS is not required for driver fallback', x: 1040, y: 2910, w: 390, h: 92 },
    { id: 'autoUnload', kind: 'process', label: 'Automatic separation completes solo ride only', x: 260, y: 3070, w: 350, h: 82 },
    { id: 'rideComplete', kind: 'process', label: 'Complete ride and release occupancy exactly once', x: 760, y: 3070, w: 380, h: 82 },
    { id: 'endTripDecision', kind: 'decision', label: 'Driver ends trip?', x: 810, y: 3190, w: 280, h: 120 },
    { id: 'continue', kind: 'process', label: 'Keep route operation active for the next booking', x: 1260, y: 3210, w: 360, h: 82 },
    { id: 'tripEnd', kind: 'process', label: 'End trip explicitly; close residual rides and pending pickups, then notify affected passengers', x: 760, y: 3340, w: 430, h: 92 },
    { id: 'processEnd', kind: 'end', label: 'End standard flow', x: 840, y: 3445, w: 240, h: 60 },
    { id: 'groupNote', kind: 'note', label: 'Group booking paths exist but are disabled by default. When enabled, boarding/unloading uses reserved, boarded, and remaining counts; organizer GPS never auto-boards companions.', x: 1320, y: 2320, w: 450, h: 92 },
  ],
  edges: [
    { from: 'processStart', to: 'configure' },
    { from: 'configure', to: 'driverIntent' },
    { from: 'driverIntent', to: 'terminalConfigured' },
    { from: 'terminalConfigured', to: 'terminalConfigError', label: 'No' },
    { from: 'terminalConfigError', to: 'configure', label: 'Fix setup' },
    { from: 'terminalConfigured', to: 'gpsFixes', label: 'Yes' },
    { from: 'gpsFixes', to: 'twoFixes' },
    { from: 'twoFixes', to: 'awaitFix', label: 'No' },
    { from: 'awaitFix', to: 'gpsFixes', label: 'Next fix' },
    { from: 'twoFixes', to: 'queueWaiting', label: 'Yes' },
    { from: 'queueWaiting', to: 'promoteLoading' },
    { from: 'promoteLoading', to: 'loadingWindow', label: 'Check terminal window' },
    { from: 'loadingWindow', to: 'passengerRequest', label: 'Open / terminal booking' },
    { from: 'loadingWindow', to: 'depart', label: 'Ready / expiry requires confirm' },
    { from: 'depart', to: 'routeOperation' },
    { from: 'routeOperation', to: 'passengerRequest', label: 'Roadside booking path' },
    { from: 'passengerRequest', to: 'validatePins' },
    { from: 'validatePins', to: 'pinsValid' },
    { from: 'pinsValid', to: 'pinError', label: 'No' },
    { from: 'pinError', to: 'passengerRequest', label: 'Correct pins' },
    { from: 'pinsValid', to: 'pickupType', label: 'Yes' },
    { from: 'pickupType', to: 'terminalEligibility', label: 'Terminal' },
    { from: 'pickupType', to: 'roadsideEligibility', label: 'Roadside' },
    { from: 'terminalEligibility', to: 'capacity' },
    { from: 'roadsideEligibility', to: 'capacity' },
    { from: 'capacity', to: 'bookingError', label: 'No' },
    { from: 'bookingError', to: 'passengerRequest', label: 'Retry after reload' },
    { from: 'capacity', to: 'bookingSaved', label: 'Yes' },
    { from: 'bookingSaved', to: 'notifyAcknowledge' },
    { from: 'bookingSaved', to: 'cancelExpire', label: 'Cancel/deadline' },
    { from: 'cancelExpire', to: 'bookingClosed' },
    { from: 'notifyAcknowledge', to: 'ackValid' },
    { from: 'ackValid', to: 'ackWait', label: 'No' },
    { from: 'ackWait', to: 'bookingClosed', label: 'Expires/cancels' },
    { from: 'ackValid', to: 'boarding', label: 'Yes' },
    { from: 'boarding', to: 'boardingGps' },
    { from: 'boardingGps', to: 'boardingRetry', label: 'No' },
    { from: 'boardingRetry', to: 'boarding', label: 'Refresh/retry' },
    { from: 'boardingGps', to: 'rideCreated', label: 'Yes' },
    { from: 'rideCreated', to: 'travel' },
    { from: 'travel', to: 'paraDecision' },
    { from: 'paraDecision', to: 'unload', label: 'No' },
    { from: 'paraDecision', to: 'paraNotify', label: 'Yes' },
    { from: 'paraNotify', to: 'unload', label: 'Continue ride' },
    { from: 'unload', to: 'autoEligible' },
    { from: 'autoEligible', to: 'autoUnload', label: 'Yes' },
    { from: 'autoEligible', to: 'manualUnload', label: 'No / group / GPS unavailable' },
    { from: 'autoUnload', to: 'rideComplete' },
    { from: 'manualUnload', to: 'rideComplete' },
    { from: 'rideComplete', to: 'endTripDecision' },
    { from: 'endTripDecision', to: 'continue', label: 'No' },
    { from: 'continue', to: 'passengerRequest', label: 'Next booking' },
    { from: 'endTripDecision', to: 'tripEnd', label: 'Yes' },
    { from: 'tripEnd', to: 'processEnd' },
  ],
};

const pages = [processMapPage,
  {
    id: 'system-map', title: '00 - ParaGO system map', subtitle: 'Actors, clients, backend services, durable state, realtime delivery, and external dependencies.', width: 1800, height: 1100, legend: true,
    nodes: [
      { id: 'passenger', kind: 'external', label: 'Passenger\n(human user)', x: 50, y: 190, w: 190, h: 90 },
      { id: 'driver', kind: 'external', label: 'Driver\n(human user)', x: 50, y: 420, w: 190, h: 90 },
      { id: 'admin', kind: 'external', label: 'Administrator\n(human user)', x: 50, y: 650, w: 190, h: 90 },
      { id: 'passengerApp', kind: 'process', label: 'Passenger Flutter app\nbooking - map - boarding - alerts', x: 320, y: 170, w: 260, h: 110 },
      { id: 'driverApp', kind: 'process', label: 'Driver Flutter app\nGPS - terminal - trip actions', x: 320, y: 400, w: 260, h: 110 },
      { id: 'adminApp', kind: 'process', label: 'Admin Flutter web\noperations - reports - setup', x: 320, y: 630, w: 260, h: 110 },
      { id: 'api', kind: 'process', label: 'Node.js / Express API\nREST routes - authorization - validation', x: 700, y: 360, w: 300, h: 130 },
      { id: 'auth', kind: 'process', label: 'Authentication & sessions\nJWT - refresh rotation - OTP for admin', x: 700, y: 145, w: 300, h: 100 },
      { id: 'ops', kind: 'process', label: 'Transportation operations\ntrips - queue - pickup - boarding - unloading', x: 1080, y: 330, w: 330, h: 140 },
      { id: 'support', kind: 'process', label: 'Admin/support services\nreports - announcements - support - releases', x: 1080, y: 615, w: 330, h: 110 },
      { id: 'mongo', kind: 'data', label: 'MongoDB Atlas\nsource of truth for users, routes, fares, rides', x: 1480, y: 220, w: 260, h: 115 },
      { id: 'redis', kind: 'data', label: 'Valkey / Redis\nshared limits - invalidation - ephemeral state', x: 1480, y: 390, w: 260, h: 105 },
      { id: 'realtime', kind: 'notification', label: 'Socket.IO + durable notifications\nreconcile from API after reconnect', x: 1480, y: 555, w: 260, h: 105 },
      { id: 'external', kind: 'external', label: 'External services\nFirebase Auth/FCM - email provider - OSM/routing', x: 1080, y: 835, w: 330, h: 110 },
      { id: 'aws', kind: 'external', label: 'AWS deployment\nCloudFront - EC2/Nginx - API\nS3 documents - CloudWatch', x: 700, y: 860, w: 300, h: 110 },
    ],
    edges: [
      { from: 'passenger', to: 'passengerApp' }, { from: 'driver', to: 'driverApp' }, { from: 'admin', to: 'adminApp' },
      { from: 'passengerApp', to: 'api', label: 'REST + Socket.IO' }, { from: 'driverApp', to: 'api', label: 'REST + GPS' }, { from: 'adminApp', to: 'api', label: 'REST + OTP' },
      { from: 'api', to: 'auth' }, { from: 'api', to: 'ops' }, { from: 'api', to: 'support' },
      { from: 'auth', to: 'mongo' }, { from: 'ops', to: 'mongo' }, { from: 'support', to: 'mongo' },
      { from: 'auth', to: 'redis' }, { from: 'ops', to: 'redis' }, { from: 'api', to: 'realtime' },
      { from: 'realtime', to: 'passengerApp' }, { from: 'realtime', to: 'driverApp' }, { from: 'realtime', to: 'adminApp' },
      { from: 'auth', to: 'external' }, { from: 'realtime', to: 'external' }, { from: 'api', to: 'aws' },
    ],
  },
  {
    id: 'passenger-ride', title: '01 - Passenger ride lifecycle', subtitle: 'Remote pickup booking, acknowledgement, boarding, travel alerts, and unloading.', width: 1900, height: 1450,
    lanes: [
      { label: 'Passenger', y: 95, h: 270 }, { label: 'Passenger app', y: 365, h: 270 }, { label: 'Backend API', y: 635, h: 330 }, { label: 'Mongo / realtime', y: 965, h: 220 }, { label: 'Driver app', y: 1185, h: 220 },
    ],
    nodes: [
      { id: 'pstart', kind: 'start', label: 'Open app / sign in', x: 215, y: 175, w: 190, h: 60 },
      { id: 'route', kind: 'process', label: 'Choose route and direction', x: 470, y: 160, w: 210, h: 90 },
      { id: 'pins', kind: 'process', label: 'Pin pickup and drop-off\n(or saved place)', x: 720, y: 420, w: 230, h: 90 },
      { id: 'pinvalid', kind: 'decision', label: 'Pins valid\nfor route/order?', x: 1000, y: 412, w: 180, h: 110 },
      { id: 'pinerror', kind: 'exception', label: 'Show actionable error;\nkeep entered details', x: 990, y: 565, w: 210, h: 80 },
      { id: 'confirm', kind: 'process', label: 'Confirm passenger count\nand fare preview', x: 1220, y: 420, w: 220, h: 90 },
      { id: 'book', kind: 'process', label: 'POST pickup request\n(no passenger GPS required)', x: 1480, y: 690, w: 240, h: 90 },
      { id: 'assign', kind: 'decision', label: 'Eligible jeep\nwith capacity?', x: 1500, y: 820, w: 190, h: 110 },
      { id: 'bookerror', kind: 'exception', label: 'No capacity / expired /\nconnectivity message', x: 1240, y: 820, w: 210, h: 90 },
      { id: 'saved', kind: 'data', label: 'Booking saved with\nfare + destination snapshot', x: 1500, y: 1000, w: 230, h: 95 },
      { id: 'notifyDriver', kind: 'notification', label: 'Notify assigned driver\n(durable + realtime)', x: 1030, y: 1015, w: 240, h: 90 },
      { id: 'ack', kind: 'process', label: 'Driver acknowledges\npickup request', x: 1240, y: 1220, w: 220, h: 90 },
      { id: 'status', kind: 'notification', label: 'Passenger sees jeep,\npickup, drop-off, expiry, ETA', x: 1480, y: 1220, w: 240, h: 90 },
      { id: 'board', kind: 'process', label: 'Passenger confirms ready /\nboarding near assigned jeep', x: 760, y: 1240, w: 230, h: 90 },
      { id: 'boardCheck', kind: 'decision', label: 'Fresh GPS +\nproximity valid?', x: 500, y: 1228, w: 190, h: 110 },
      { id: 'boardError', kind: 'exception', label: 'Retry location;\nbooking stays open', x: 240, y: 1240, w: 190, h: 80 },
      { id: 'ride', kind: 'process', label: 'Create ride; increment\noccupancy transactionally', x: 690, y: 800, w: 230, h: 90 },
      { id: 'travel', kind: 'process', label: 'Travel: map follow/free view,\nETA, status reconciliation', x: 980, y: 800, w: 240, h: 90 },
      { id: 'para', kind: 'notification', label: 'Passenger sends para alert\n(driver acknowledgement does not unload)', x: 1010, y: 1050, w: 290, h: 90 },
      { id: 'unload', kind: 'process', label: 'Unload: passenger/driver manual\nor solo auto-separation', x: 700, y: 1040, w: 250, h: 90 },
      { id: 'end', kind: 'end', label: 'Ride completed;\noccupancy released', x: 410, y: 1040, w: 210, h: 70 },
      { id: 'groupNote', kind: 'note', label: 'Group booking is feature-gated and disabled by default. When enabled, counts are reserved/boarded/remaining; organizer GPS never auto-boards companions.', x: 1120, y: 1350, w: 560, h: 70 },
    ],
    edges: [
      { from: 'pstart', to: 'route' }, { from: 'route', to: 'pins' }, { from: 'pins', to: 'pinvalid' }, { from: 'pinvalid', to: 'pinerror', label: 'No' }, { from: 'pinerror', to: 'pins', label: 'Correct pins' }, { from: 'pinvalid', to: 'confirm', label: 'Yes' }, { from: 'confirm', to: 'book' },
      { from: 'book', to: 'assign' }, { from: 'assign', to: 'bookerror', label: 'No' }, { from: 'bookerror', to: 'confirm', label: 'Retry after reload' }, { from: 'assign', to: 'saved', label: 'Yes' }, { from: 'saved', to: 'notifyDriver' }, { from: 'notifyDriver', to: 'ack' }, { from: 'ack', to: 'status' }, { from: 'status', to: 'board' }, { from: 'board', to: 'boardCheck' }, { from: 'boardCheck', to: 'boardError', label: 'No' }, { from: 'boardError', to: 'board', label: 'Retry' }, { from: 'boardCheck', to: 'ride', label: 'Yes' }, { from: 'ride', to: 'travel' }, { from: 'travel', to: 'para' }, { from: 'travel', to: 'unload' }, { from: 'para', to: 'unload', label: 'Stop request' }, { from: 'unload', to: 'end' },
    ],
  },
  {
    id: 'driver-terminal', title: '02 - Driver terminal-to-route operation', subtitle: 'Terminal-first dispatch: arrival, queue, loading timer, explicit departure, then roadside operation.', width: 1900, height: 1500,
    lanes: [
      { label: 'Driver', y: 95, h: 270 }, { label: 'Driver app + GPS', y: 365, h: 270 }, { label: 'Backend', y: 635, h: 350 }, { label: 'Queue + data', y: 985, h: 220 }, { label: 'Passenger / admin', y: 1205, h: 220 },
    ],
    nodes: [
      { id: 'login', kind: 'start', label: 'Driver signs in', x: 215, y: 170, w: 180, h: 60 },
      { id: 'online', kind: 'process', label: 'Go online and choose\nterminal route', x: 450, y: 160, w: 220, h: 90 },
      { id: 'intent', kind: 'process', label: 'Create terminal-intent trip\n(direct route start rejected)', x: 710, y: 420, w: 260, h: 90 },
      { id: 'terminal', kind: 'decision', label: 'Route terminal\nconfigured?', x: 1010, y: 412, w: 190, h: 110 },
      { id: 'termError', kind: 'exception', label: 'Cannot start terminal flow;\nadmin must configure terminal', x: 990, y: 575, w: 240, h: 90 },
      { id: 'gps', kind: 'process', label: 'Send ordered GPS fixes\nwith timestamp + accuracy', x: 1240, y: 420, w: 240, h: 90 },
      { id: 'geofence', kind: 'decision', label: 'Two fresh accurate\nfixes in radius?', x: 1510, y: 412, w: 210, h: 110 },
      { id: 'waitArrival', kind: 'process', label: 'Await terminal arrival\n(one fix is insufficient)', x: 1480, y: 575, w: 240, h: 90 },
      { id: 'checkin', kind: 'process', label: 'Idempotent terminal\nqueue check-in', x: 1250, y: 690, w: 220, h: 90 },
      { id: 'queue', kind: 'data', label: 'Queue record: waiting /\nloading / skipped', x: 1010, y: 1015, w: 220, h: 95 },
      { id: 'promote', kind: 'process', label: 'Promote earliest eligible\njeep to loading', x: 1270, y: 1015, w: 240, h: 95 },
      { id: 'loading', kind: 'process', label: 'Loading window 10 minutes\nterminal reservations only', x: 740, y: 690, w: 250, h: 90 },
      { id: 'expiry', kind: 'decision', label: 'Loading timer\nexpired?', x: 470, y: 680, w: 190, h: 110 },
      { id: 'warning', kind: 'note', label: 'Expiry blocks new terminal reservations and shows a warning; it does not auto-depart.', x: 210, y: 835, w: 310, h: 70 },
      { id: 'depart', kind: 'process', label: 'Driver or admin confirms\nDepart terminal', x: 700, y: 835, w: 250, h: 90 },
      { id: 'routeMode', kind: 'process', label: 'Trip becomes route operation;\nonboard passengers preserved', x: 1010, y: 835, w: 270, h: 90 },
      { id: 'roadside', kind: 'process', label: 'Accept roadside pickup\nwhen capacity permits', x: 1310, y: 835, w: 250, h: 90 },
      { id: 'actions', kind: 'notification', label: 'Acknowledge pickup, boarding,\npara alerts, manual unload', x: 1040, y: 1255, w: 290, h: 90 },
      { id: 'pause', kind: 'decision', label: 'No driver GPS\nfor route grace?', x: 1390, y: 1245, w: 210, h: 110 },
      { id: 'pauseNote', kind: 'exception', label: 'Pause new roadside pickups\nafter configured inactivity; resume with fresh GPS', x: 1450, y: 1390, w: 300, h: 70 },
      { id: 'endTrip', kind: 'end', label: 'Explicit End trip\ncloses residual rides', x: 650, y: 1260, w: 230, h: 70 },
    ],
    edges: [
      { from: 'login', to: 'online' }, { from: 'online', to: 'intent' }, { from: 'intent', to: 'terminal' }, { from: 'terminal', to: 'termError', label: 'No' }, { from: 'terminal', to: 'gps', label: 'Yes' }, { from: 'gps', to: 'geofence' }, { from: 'geofence', to: 'waitArrival', label: 'No' }, { from: 'waitArrival', to: 'gps', label: 'Next fix' }, { from: 'geofence', to: 'checkin', label: 'Yes' }, { from: 'checkin', to: 'queue' }, { from: 'queue', to: 'promote' }, { from: 'promote', to: 'loading' }, { from: 'loading', to: 'expiry' }, { from: 'expiry', to: 'warning', label: 'Yes' }, { from: 'expiry', to: 'depart', label: 'No / ready' }, { from: 'warning', to: 'depart', label: 'Explicit confirm' }, { from: 'depart', to: 'routeMode' }, { from: 'routeMode', to: 'roadside' }, { from: 'roadside', to: 'actions' }, { from: 'actions', to: 'pause' }, { from: 'pause', to: 'pauseNote', label: 'Yes' }, { from: 'pause', to: 'endTrip', label: 'No / end' },
    ],
  },
  {
    id: 'admin-operations', title: '03 - Administrator operations', subtitle: 'Secure administration of users, transport configuration, terminal dispatch, reports, and support.', width: 1900, height: 1450,
    lanes: [
      { label: 'Administrator', y: 95, h: 240 }, { label: 'Admin web', y: 335, h: 320 }, { label: 'API / authorization', y: 655, h: 350 }, { label: 'Mongo + realtime', y: 1005, h: 210 }, { label: 'Users / drivers', y: 1215, h: 190 },
    ],
    nodes: [
      { id: 'start', kind: 'start', label: 'Open admin web', x: 215, y: 170, w: 190, h: 60 },
      { id: 'pwd', kind: 'process', label: 'Password verification', x: 470, y: 160, w: 200, h: 90 },
      { id: 'otp', kind: 'decision', label: 'Email OTP\nverified?', x: 740, y: 150, w: 180, h: 110 },
      { id: 'denied', kind: 'exception', label: 'Reject login;\nno admin session', x: 760, y: 300, w: 190, h: 80 },
      { id: 'overview', kind: 'process', label: 'Overview / dispatch\nqueue and live operations', x: 1010, y: 160, w: 230, h: 90 },
      { id: 'setup', kind: 'process', label: 'Manage drivers, CP +\nlicenses; assign jeepneys', x: 1290, y: 410, w: 250, h: 90 },
      { id: 'routes', kind: 'process', label: 'Configure routes, geometry,\nstops, terminals and fares', x: 980, y: 410, w: 250, h: 90 },
      { id: 'coding', kind: 'process', label: 'Maintain number coding\nholidays / restrictions', x: 700, y: 410, w: 220, h: 90 },
      { id: 'dispatch', kind: 'process', label: 'Review loading/waiting/skipped\nqueue; skip/restore/depart', x: 440, y: 410, w: 230, h: 90 },
      { id: 'reports', kind: 'process', label: 'Reports: validate date range\n(maximum 366 days)', x: 440, y: 715, w: 240, h: 90 },
      { id: 'support', kind: 'process', label: 'Support threads and\nstatus updates', x: 720, y: 715, w: 220, h: 90 },
      { id: 'announce', kind: 'process', label: 'Publish service notices\nand announcements', x: 980, y: 715, w: 240, h: 90 },
      { id: 'accounts', kind: 'process', label: 'Manage user/admin accounts\nwithin role permissions', x: 1260, y: 715, w: 250, h: 90 },
      { id: 'write', kind: 'data', label: 'Transactional writes\nwith ownership and audit', x: 780, y: 1045, w: 250, h: 95 },
      { id: 'notify', kind: 'notification', label: 'Publish after commit\nSocket.IO + durable notifications', x: 1110, y: 1045, w: 280, h: 95 },
      { id: 'users', kind: 'external', label: 'Passengers and drivers\nreceive current status', x: 820, y: 1265, w: 280, h: 90 },
      { id: 'releaseNote', kind: 'note', label: 'APK catalog publication is PC-only through the local super-admin tool; the admin web does not upload APKs.', x: 1210, y: 1260, w: 460, h: 80 },
    ],
    edges: [
      { from: 'start', to: 'pwd' }, { from: 'pwd', to: 'otp' }, { from: 'otp', to: 'denied', label: 'No' }, { from: 'otp', to: 'overview', label: 'Yes' }, { from: 'overview', to: 'dispatch' }, { from: 'overview', to: 'setup' }, { from: 'overview', to: 'routes' }, { from: 'overview', to: 'coding' }, { from: 'dispatch', to: 'write' }, { from: 'setup', to: 'write' }, { from: 'routes', to: 'write' }, { from: 'coding', to: 'write' }, { from: 'reports', to: 'write' }, { from: 'support', to: 'write' }, { from: 'announce', to: 'write' }, { from: 'accounts', to: 'write' }, { from: 'write', to: 'notify' }, { from: 'notify', to: 'users' }, { from: 'overview', to: 'reports' }, { from: 'overview', to: 'support' }, { from: 'overview', to: 'announce' }, { from: 'overview', to: 'accounts' },
    ],
  },
  {
    id: 'shared-exceptions', title: '04 - Shared services and exception paths', subtitle: 'Security, idempotency, GPS limitations, notification delivery, and safe recovery behavior.', width: 1900, height: 1450,
    lanes: [
      { label: 'Client', y: 95, h: 260 }, { label: 'API guardrails', y: 355, h: 300 }, { label: 'Transactional state', y: 655, h: 300 }, { label: 'Delivery / cache', y: 955, h: 220 }, { label: 'External dependency', y: 1175, h: 220 },
    ],
    nodes: [
      { id: 'request', kind: 'start', label: 'Client mutation or\nrealtime event', x: 215, y: 170, w: 210, h: 70 },
      { id: 'session', kind: 'decision', label: 'Session valid,\nrole + owner allowed?', x: 480, y: 150, w: 220, h: 110 },
      { id: 'reject', kind: 'exception', label: '401/403 with plain\nmessage; do not mutate', x: 500, y: 300, w: 220, h: 80 },
      { id: 'validate', kind: 'process', label: 'Validate pins, counts,\nexpiry, capacity, revision', x: 790, y: 165, w: 240, h: 90 },
      { id: 'idempotent', kind: 'decision', label: 'Duplicate mutation\nor stale revision?', x: 1090, y: 155, w: 220, h: 110 },
      { id: 'previous', kind: 'process', label: 'Return prior result or\nrequire refresh; never replay', x: 1100, y: 305, w: 250, h: 80 },
      { id: 'txn', kind: 'process', label: 'Mongo transaction locks\nbooking / ride / queue state', x: 800, y: 430, w: 260, h: 90 },
      { id: 'commit', kind: 'decision', label: 'Commit succeeds?', x: 1130, y: 420, w: 190, h: 110 },
      { id: 'uncertain', kind: 'exception', label: 'Timeout / uncertain result:\nreload authoritative state', x: 1390, y: 435, w: 250, h: 80 },
      { id: 'records', kind: 'data', label: 'MongoDB records\nsource of truth', x: 800, y: 700, w: 250, h: 100 },
      { id: 'reconcile', kind: 'process', label: 'Reconnect/resume\nreconcile from API', x: 1100, y: 700, w: 240, h: 90 },
      { id: 'socket', kind: 'notification', label: 'Socket.IO + durable\nnotifications after commit', x: 780, y: 1000, w: 280, h: 90 },
      { id: 'cache', kind: 'data', label: 'Valkey / Redis\nrate limits + revocation', x: 1120, y: 1000, w: 250, h: 90 },
      { id: 'gps', kind: 'decision', label: 'Fresh GPS\navailable?', x: 460, y: 700, w: 180, h: 110 },
      { id: 'gpsWarn', kind: 'note', label: 'Booking can use a remote pin without passenger GPS. Actual boarding keeps fresh proximity checks; manual driver unload can work without passenger GPS.', x: 200, y: 850, w: 460, h: 90 },
      { id: 'external', kind: 'external', label: 'Firebase Auth/FCM,\nemail provider, OSM/routing', x: 730, y: 1240, w: 300, h: 100 },
      { id: 'aws', kind: 'external', label: 'AWS / Mongo Atlas\navailability and monitoring', x: 1150, y: 1240, w: 280, h: 100 },
      { id: 'fail', kind: 'exception', label: 'Dependency failure:\nfail closed for auth mutations;\nbounded fallback for transport reads', x: 1450, y: 1180, w: 300, h: 120 },
    ],
    edges: [
      { from: 'request', to: 'session' }, { from: 'session', to: 'reject', label: 'No' }, { from: 'session', to: 'validate', label: 'Yes' }, { from: 'validate', to: 'idempotent' }, { from: 'idempotent', to: 'previous', label: 'Yes' }, { from: 'idempotent', to: 'txn', label: 'No' }, { from: 'txn', to: 'commit' }, { from: 'commit', to: 'uncertain', label: 'No / timeout' }, { from: 'commit', to: 'records', label: 'Yes' }, { from: 'records', to: 'socket' }, { from: 'records', to: 'reconcile' }, { from: 'socket', to: 'cache' }, { from: 'gps', to: 'gpsWarn', label: 'No' }, { from: 'gps', to: 'validate', label: 'Yes / where required' }, { from: 'external', to: 'fail' }, { from: 'aws', to: 'fail' }, { from: 'fail', to: 'reconcile', label: 'Recover' },
    ],
  },
];

const readme = `# ParaGO full system flow documentation\n\nUpdated: 2026-09-27\n\nThis folder is a new, standalone documentation set. The original diagram folders are untouched. It describes the current ParaGO implementation as found in the repository: passenger, driver, administrator, backend/API, database, realtime delivery, and external services.\n\n## Open the diagrams\n\n- **Editable source:** \`ParaGO_full_system_flow.drawio\` - open with diagrams.net / draw.io and select a page from the page list.\n- **Local viewer:** \`index.html\` - open directly in a browser. It contains the six exported SVG sheets with tabs, a legend, and source notes.\n- **SVG sheets:** the primary \`end_to_end_process_map.svg\` plus \`system_map.svg\`, \`passenger_ride.svg\`, \`driver_terminal.svg\`, \`admin_operations.svg\`, and \`shared_exceptions.svg\` files are suitable for documentation, print, and review.\n\n## Diagram set\n\n0. **Standard end-to-end process map** - the primary start-to-finish procedure, separated by setup, terminal dispatch, booking, ride state, and completion lanes.\n1. **System map** - user roles, Flutter clients, API services, durable state, realtime delivery, AWS deployment, and external dependencies.\n2. **Passenger ride lifecycle** - route selection, remote pin booking, validation, assignment, driver acknowledgement, boarding, travel, para alert, and unloading.\n3. **Driver terminal-to-route operation** - terminal-intent trip, two-fix arrival, queue promotion, ten-minute loading window, explicit departure, route operation, inactivity pause, and explicit trip end.\n4. **Administrator operations** - OTP login, configuration, dispatch, reports, support, announcements, account management, and the separate PC-only mobile release note.\n5. **Shared services and exception paths** - authorization, transactions, idempotency, uncertain timeouts, reconciliation, GPS limitations, notifications, cache/revocation, and dependency failures.\n\n## Symbol legend\n\n- **Rounded rectangle:** process or user action.\n- **Ellipse:** start or end.\n- **Diamond:** decision or validation gate.\n- **Cylinder:** persistent or shared data store.\n- **Document/page:** notification or durable message.\n- **Cloud:** external actor or service.\n- **Note:** operational caveat or rollout boundary.\n- **Arrow:** direction of control or data flow.\n\n## Current behavior and boundaries\n\n- MongoDB/API state is authoritative; Socket.IO and push/email notifications are delivery mechanisms. Clients reconcile after reconnect or resume.\n- Passenger remote pickup pins do not require phone GPS. Actual boarding still requires the configured fresh-location/proximity checks; manual driver unloading remains available when passenger GPS is unavailable.\n- Drivers start with a terminal-intent trip. Direct route start is rejected for new flows. Terminal arrival needs two ordered, fresh, accurate fixes in the configured terminal radius. Departure is explicit; the ten-minute loading timer does not auto-depart.\n- A departed trip becomes route operation and can accept roadside pickups subject to capacity. Ending a trip is separate from departing the terminal.\n- Group booking support exists in the code path but is **disabled by default** behind \`GROUP_BOOKINGS_ENABLED=false\`; the passenger sheet labels the group behavior as a gated capability.\n- Existing terminal-first changes and indexes still have audit, maintenance-window, client/device, and deployment gates. This documentation is not a production-readiness claim.\n- APK catalog publication is performed by the PC-only local super-admin tool, not by the admin web.\n\n## Source references\n\n- \`docs/PARAGO_COMPLETE_SYSTEM_PROCESS_AND_CAPABILITIES.md\`\n- \`docs/PASSENGER_BOOKING_REVISION.md\`\n- \`docs/TERMINAL_FIRST_DRIVER_STATUS.md\`\n- \`docs/SECURITY_REPAIR_STATUS.md\`\n- \`src/routes/pickupRequests.routes.js\`, \`src/routes/boarding.routes.js\`, \`src/routes/stopAlerts.routes.js\`, \`src/routes/trips.routes.js\`\n- \`src/services/operatingRules.service.js\`, \`src/services/tripLifecycle.js\`, \`src/services/terminalArrival.service.js\`\n- Flutter clients under \`parago_passenger/\`, \`parago_mobile/\`, and \`parago_admin_web/\`\n\nWhen implementation changes, regenerate the SVG and Drawio sources with \`node generate_flowcharts.js\` and update this README's date and caveats.\n`;

fs.mkdirSync(outDir, { recursive: true });
for (const page of pages) {
  const svgName = `${page.id.replace(/-/g, '_')}.svg`;
  fs.writeFileSync(path.join(outDir, svgName), svgForPage(page), 'utf8');
}
fs.writeFileSync(path.join(outDir, 'ParaGO_full_system_flow.drawio'), drawioForPages(pages), 'utf8');
fs.writeFileSync(path.join(outDir, 'README.md'), readme, 'utf8');
console.log(`Generated ${pages.length} SVG sheets and ParaGO_full_system_flow.drawio`);
