// Parity fixture generator: these functions are copied VERBATIM from the web
// app (index.html) so the values below are the reference implementation's own
// output. The Swift Geometry module must reproduce them.

const FT = 0.3048;

function offset(c, dx, dy) {
  const dLat = dy / 111320;
  const dLng = dx / (111320 * Math.cos(c.lat * Math.PI / 180));
  return { lat: c.lat + dLat, lng: c.lng + dLng };
}

function llToXY(ll, ref) {
  const latRad = ref.lat * Math.PI / 180;
  return {
    x: (ll.lng - ref.lng) * 111320 * Math.cos(latRad),
    y: (ll.lat - ref.lat) * 111320
  };
}

function xyToLL(pt, ref) {
  return {
    lat: ref.lat + pt.y / 111320,
    lng: ref.lng + pt.x / (111320 * Math.cos(ref.lat * Math.PI / 180))
  };
}

function distPointSeg(p, a, b) {
  const abx = b.x - a.x, aby = b.y - a.y;
  const apx = p.x - a.x, apy = p.y - a.y;
  const len2 = abx * abx + aby * aby;
  let t = len2 ? (apx * abx + apy * aby) / len2 : 0;
  t = Math.max(0, Math.min(1, t));
  const cx = a.x + t * abx, cy = a.y + t * aby;
  const dx = p.x - cx, dy = p.y - cy;
  return Math.sqrt(dx * dx + dy * dy);
}

function closestPtSeg(p, a, b) {
  const abx = b.x - a.x, aby = b.y - a.y;
  const apx = p.x - a.x, apy = p.y - a.y;
  const len2 = abx * abx + aby * aby;
  let t = len2 ? (apx * abx + apy * aby) / len2 : 0;
  t = Math.max(0, Math.min(1, t));
  const c = { x: a.x + t * abx, y: a.y + t * aby };
  const dx = p.x - c.x, dy = p.y - c.y;
  return { d: Math.sqrt(dx * dx + dy * dy), c: c };
}

function pointInPoly(pt, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const xi = poly[i].x, yi = poly[i].y, xj = poly[j].x, yj = poly[j].y;
    const intersect = ((yi > pt.y) !== (yj > pt.y)) &&
      (pt.x < (xj - xi) * (pt.y - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

function polygonAreaM2(ptsLL) {
  if (!ptsLL || ptsLL.length < 3) return 0;
  const ref = ptsLL[0];
  const xy = ptsLL.map(ll => llToXY(ll, ref));
  let a = 0;
  for (let i = 0, j = xy.length - 1; i < xy.length; j = i++) {
    a += (xy[j].x + xy[i].x) * (xy[j].y - xy[i].y);
  }
  return Math.abs(a / 2);
}

function shapePoints(c, aM, bM, rotDeg, shape) {
  const th = rotDeg * Math.PI / 180;
  const cos = Math.cos(th), sin = Math.sin(th);
  const pts = [];
  if (shape === 'rect') {
    const corners = [[-aM, -bM], [aM, -bM], [aM, bM], [-aM, bM]];
    for (const [x, y] of corners) {
      pts.push(offset(c, x * cos - y * sin, x * sin + y * cos));
    }
  } else {
    const n = 72;
    for (let i = 0; i < n; i++) {
      const t = (i / n) * 2 * Math.PI;
      const x = aM * Math.cos(t), y = bM * Math.sin(t);
      pts.push(offset(c, x * cos - y * sin, x * sin + y * cos));
    }
  }
  return pts;
}

function nearestOnPoly(p, poly) {
  let best = { d: Infinity, c: null };
  for (let i = 0; i < poly.length; i++) {
    const r = closestPtSeg(p, poly[i], poly[(i + 1) % poly.length]);
    if (r.d < best.d) best = { d: r.d, c: r.c };
  }
  return best;
}

function round05(x) { return Math.round(x / 0.05) * 0.05; }

// ---------- fixtures ----------

const fixtures = {};

// 1. Projection round-trips at three latitudes
fixtures.projection = [
  { ref: { lat: 45.5017, lng: -73.5673 }, ll: { lat: 45.5023, lng: -73.5668 } },
  { ref: { lat: 33.749, lng: -84.388 }, ll: { lat: 33.7481, lng: -84.3874 } },
  { ref: { lat: 60.7212, lng: -135.0568 }, ll: { lat: 60.722, lng: -135.055 } },
].map(({ ref, ll }) => {
  const xy = llToXY(ll, ref);
  const back = xyToLL(xy, ref);
  return { ref, ll, xy, back };
});

// 2. Segment distance / closest point / point-in-poly
const segCases = [
  { p: { x: 3, y: 4 }, a: { x: 0, y: 0 }, b: { x: 10, y: 0 } },
  { p: { x: -2, y: 1 }, a: { x: 0, y: 0 }, b: { x: 10, y: 0 } },
  { p: { x: 15, y: -3 }, a: { x: 0, y: 0 }, b: { x: 10, y: 0 } },
  { p: { x: 1.25, y: 7.5 }, a: { x: -4, y: 2 }, b: { x: 6, y: 9 } },
  { p: { x: 5, y: 5 }, a: { x: 5, y: 5 }, b: { x: 5, y: 5 } }, // degenerate
];
fixtures.segments = segCases.map(({ p, a, b }) => {
  const r = closestPtSeg(p, a, b);
  return { p, a, b, dist: distPointSeg(p, a, b), closest: r.c };
});

const poly = [
  { x: 0, y: 0 }, { x: 20, y: 2 }, { x: 24, y: 15 }, { x: 10, y: 22 }, { x: -3, y: 12 },
];
fixtures.pointInPoly = [
  { x: 10, y: 10 }, { x: -5, y: -5 }, { x: 0.1, y: 0.5 }, { x: 23, y: 14 }, { x: 10, y: 21.9 },
].map(pt => ({ poly, pt, inside: pointInPoly(pt, poly) }));

// 3. Polygon area — irregular lot near Montreal
const lotLL = [
  { lat: 45.5017, lng: -73.5673 },
  { lat: 45.50195, lng: -73.56755 },
  { lat: 45.50209, lng: -73.56695 },
  { lat: 45.50184, lng: -73.56655 },
  { lat: 45.50158, lng: -73.56684 },
];
fixtures.polygonArea = [{ ptsLL: lotLL, areaM2: polygonAreaM2(lotLL) }];

// 4. Shape points — rect and oval with rotation, at two latitudes
const shapeCases = [
  { c: { lat: 45.5018, lng: -73.567 }, wFt: 21, lFt: 41, rot: 0, shape: 'oval' },
  { c: { lat: 45.5018, lng: -73.567 }, wFt: 21, lFt: 41, rot: 37, shape: 'oval' },
  { c: { lat: 45.5018, lng: -73.567 }, wFt: 16, lFt: 32, rot: 90, shape: 'rect' },
  { c: { lat: 33.749, lng: -84.388 }, wFt: 24, lFt: 24, rot: 15, shape: 'round' },
];
fixtures.shapes = shapeCases.map(({ c, wFt, lFt, rot, shape }) => {
  // same semi-axis convention as the web app's redraw()
  const aM = (lFt * FT) / 2, bM = (wFt * FT) / 2;
  return { c, wFt, lFt, rot, shape, aM, bM, pts: shapePoints(c, aM, bM, rot, shape) };
});

// 5. Full compliance scenario, mirroring refreshLotDistance / refreshStructDistance /
//    refreshEquip / updateCoverage
const center = { lat: 45.50182, lng: -73.56695 };
const scWFt = 15, scLFt = 30, scRot = 20, scShape = 'oval';
const scAM = (scLFt * FT) / 2, scBM = (scWFt * FT) / 2;
const poolLL = shapePoints(center, scAM, scBM, scRot, scShape);
const structLL = [
  { lat: 45.50196, lng: -73.56726 },
  { lat: 45.50203, lng: -73.56701 },
  { lat: 45.50193, lng: -73.56692 },
  { lat: 45.50186, lng: -73.56716 },
];
const equipLL = { lat: 45.50176, lng: -73.56684 };
const ref = center;
const poolXY = poolLL.map(ll => llToXY(ll, ref));
const lotXY = lotLL.map(ll => llToXY(ll, ref));

// two nearest lot edges (web: per lot edge, min over pool vertices; sort; take 2)
const edges = [];
for (let i = 0; i < lotXY.length; i++) {
  const a = lotXY[i], b = lotXY[(i + 1) % lotXY.length];
  let best = { d: Infinity };
  for (const p of poolXY) {
    const r = closestPtSeg(p, a, b);
    if (r.d < best.d) best = { d: r.d, from: p, to: r.c };
  }
  edges.push({ edgeIndex: i, ...best });
}
edges.sort((x, y) => x.d - y.d);
const insideLot = pointInPoly({ x: 0, y: 0 }, lotXY);

// nearest structure gap (web: min over pool vertices x structure edges)
const structXY = structLL.map(ll => llToXY(ll, ref));
let structBest = { d: Infinity };
for (const p of poolXY) {
  for (let i = 0; i < structXY.length; i++) {
    const r = closestPtSeg(p, structXY[i], structXY[(i + 1) % structXY.length]);
    if (r.d < structBest.d) structBest = { d: r.d, from: p, to: r.c };
  }
}

// equipment distances (web refreshEquip: nearestOnPoly to pool and to lot)
const equipXY = llToXY(equipLL, ref);
const equipPool = nearestOnPoly(equipXY, poolXY);
const equipLot = nearestOnPoly(equipXY, lotXY);

// coverage (web updateCoverage: ellipse footprint from ft dims)
const lotM2 = polygonAreaM2(lotLL);
const footM2 = (Math.PI * (scWFt / 2) * (scLFt / 2)) * FT * FT;

fixtures.compliance = {
  center, shape: scShape, wFt: scWFt, lFt: scLFt, rot: scRot,
  lotLL, structLL, equipLL,
  nearestLotEdges: edges.slice(0, 2).map(e => ({ edgeIndex: e.edgeIndex, d: e.d, from: e.from, to: e.to })),
  insideLot,
  nearestStructure: { d: structBest.d, from: structBest.from, to: structBest.to },
  equipToPool: equipPool.d,
  equipToLot: equipLot.d,
  lotAreaM2: lotM2,
  poolFootprintM2: footM2,
  coveragePct: footM2 / lotM2 * 100,
};

// 6. round05 metric display rounding
fixtures.round05 = [0, 0.024, 0.025, 1.47, 1.475, 2.9999, 12.301].map(x => ({ x, rounded: round05(x) }));

process.stdout.write(JSON.stringify(fixtures, null, 1));
