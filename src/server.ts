import Fastify from "fastify";
import jwt from "@fastify/jwt";
import { z } from "zod";

type LocationRecord = {
  id: string;
  lat: number;
  lon: number;
  receivedAtMs: number;
  cellX: number;
  cellY: number;
};

const app = Fastify({ logger: true });

// --- Config ---
const JWT_SECRET = process.env.JWT_SECRET ?? "dev-secret-change-me";

// --- Plugins ---
await app.register(jwt, { secret: JWT_SECRET });

// -------- Settings --------
const STALE_AFTER_MS = Number(process.env.STALE_AFTER_MS ?? 30_000); // default 30s
const CLEANUP_EVERY_MS = 5_000; // run cleanup every 5s
const NEARBY_RADIUS_M = 500;    // search radius

// Grid cell size (pick something <= radius; 250m is a good default for 500m radius)
const CELL_SIZE_M = 250;

// -------- Storage --------
const store = new Map<string, LocationRecord>();       // id -> record
const grid = new Map<string, Set<string>>();           // "x:y" -> set of ids

// -------- Validation --------
const LocationUpdateSchema = z.object({
  id: z.string().min(1).max(200),
  lat: z.number().min(-90).max(90),
  lon: z.number().min(-180).max(180),
});

// -------- Helpers --------
function cellKey(x: number, y: number): string {
  return `${x}:${y}`;
}

/**
 * Very simple meters-per-degree approximation for grid indexing:
 * - lat: ~111,320 meters per degree
 * - lon: ~111,320 * cos(lat) meters per degree
 *
 * Good enough for “nearby within 500m” use-cases.
 */
function latLonToCell(lat: number, lon: number): { x: number; y: number } {
  const metersPerDegLat = 111_320;
  const metersPerDegLon = 111_320 * Math.cos((lat * Math.PI) / 180);

  const yMeters = lat * metersPerDegLat;
  const xMeters = lon * metersPerDegLon;

  const y = Math.floor(yMeters / CELL_SIZE_M);
  const x = Math.floor(xMeters / CELL_SIZE_M);

  return { x, y };
}

/** Haversine distance in meters (exact check after grid prefilter) */
function distanceMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const R = 6_371_000;

  const phi1 = toRad(lat1);
  const phi2 = toRad(lat2);
  const dPhi = toRad(lat2 - lat1);
  const dLambda = toRad(lon2 - lon1);

  const a =
    Math.sin(dPhi / 2) ** 2 +
    Math.cos(phi1) * Math.cos(phi2) * Math.sin(dLambda / 2) ** 2;

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function addToGrid(id: string, x: number, y: number): void {
  const key = cellKey(x, y);
  let set = grid.get(key);
  if (!set) {
    set = new Set<string>();
    grid.set(key, set);
  }
  set.add(id);
}

function removeFromGrid(id: string, x: number, y: number): void {
  const key = cellKey(x, y);
  const set = grid.get(key);
  if (!set) return;

  set.delete(id);
  if (set.size === 0) grid.delete(key);
}

function deleteUser(id: string): void {
  const rec = store.get(id);
  if (!rec) return;
  removeFromGrid(id, rec.cellX, rec.cellY);
  store.delete(id);
}

/** Remove stale users (from store + grid) */
function cleanupStale(): void {
  const now = Date.now();
  for (const [id, rec] of store.entries()) {
    if (now - rec.receivedAtMs > STALE_AFTER_MS) {
      deleteUser(id);
    }
  }
}

setInterval(cleanupStale, CLEANUP_EVERY_MS).unref();

// -------- Routes --------
app.get("/health", async () => ({ ok: true }));

// Require auth for all routes except /health
app.addHook("onRequest", async (req, reply) => {
  if (req.url === "/health") return;
  try {
    await req.jwtVerify();
  } catch {
    return reply.code(401).send({ message: "Unauthorized" });
  }
});

/**
 * POST /v1/locations
 * Body: { id, lat, lon }
 * Response: { stored: true, nearByClients: [{id, lat, lon}, ...] }
 */
app.post("/v1/locations", async (req, reply) => {
  const parsed = LocationUpdateSchema.safeParse(req.body);
  if (!parsed.success) {
    return reply.code(400).send({
      message: "Invalid payload",
      issues: parsed.error.issues,
    });
  }

  const { id, lat, lon } = parsed.data;
  const nowMs = Date.now();

  // Compute new cell
  const { x: newCellX, y: newCellY } = latLonToCell(lat, lon);

  // Update store + grid (move between cells if needed)
  const prev = store.get(id);
  if (prev) {
    if (prev.cellX !== newCellX || prev.cellY !== newCellY) {
      removeFromGrid(id, prev.cellX, prev.cellY);
      addToGrid(id, newCellX, newCellY);
    }
    prev.lat = lat;
    prev.lon = lon;
    prev.receivedAtMs = nowMs;
    prev.cellX = newCellX;
    prev.cellY = newCellY;
  } else {
    store.set(id, { id, lat, lon, receivedAtMs: nowMs, cellX: newCellX, cellY: newCellY });
    addToGrid(id, newCellX, newCellY);
  }

  // Find nearby candidates by checking neighboring cells only
  const cellRange = Math.ceil(NEARBY_RADIUS_M / CELL_SIZE_M); // e.g. 500/250 => 2
  const nearByClients: Array<{ id: string; lat: number; lon: number }> = [];

  for (let dx = -cellRange; dx <= cellRange; dx++) {
    for (let dy = -cellRange; dy <= cellRange; dy++) {
      const key = cellKey(newCellX + dx, newCellY + dy);
      const idsInCell = grid.get(key);
      if (!idsInCell) continue;

      for (const otherId of idsInCell) {
        if (otherId === id) continue;

        const other = store.get(otherId);
        if (!other) continue;

        // Ignore stale (in case cleanup hasn't run yet)
        if (nowMs - other.receivedAtMs > STALE_AFTER_MS) {
          deleteUser(otherId);
          continue;
        }

        // Exact distance filter
        const d = distanceMeters(lat, lon, other.lat, other.lon);
        if (d <= NEARBY_RADIUS_M) {
          nearByClients.push({ id: other.id, lat: other.lat, lon: other.lon });
        }
      }
    }
  }

  return reply.code(200).send({
    stored: true,
    nearByClients,
  });
});

// Optional debug endpoints
app.get("/v1/locations/:id", async (req, reply) => {
  const id = (req.params as { id: string }).id;
  const rec = store.get(id);
  if (!rec) return reply.code(404).send({ message: "Not found" });

  if (Date.now() - rec.receivedAtMs > STALE_AFTER_MS) {
    deleteUser(id);
    return reply.code(404).send({ message: "Not found" });
  }

  return reply.code(200).send({ id: rec.id, lat: rec.lat, lon: rec.lon });
});

app.get("/v1/locations", async () => {
  cleanupStale();
  return { count: store.size, gridCells: grid.size };
});

const port = Number(process.env.PORT ?? 3000);
const host = process.env.HOST ?? "0.0.0.0";

await app.listen({ port, host });
