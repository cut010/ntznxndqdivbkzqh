import { readFileSync, writeFileSync, readdirSync, statSync } from "node:fs";
import { resolve, relative, join } from "node:path";
import { createHash } from "node:crypto";

const ROOT = resolve(import.meta.dirname, "..");
const API_DIR = resolve(ROOT, "api/v1");
const MANIFEST_PATH = resolve(API_DIR, "manifest.json");

interface ManifestEntry {
  hash: string;
  size: number;
}

function walkDir(dir: string): string[] {
  const results: string[] = [];
  const entries = readdirSync(dir, { withFileTypes: true });

  for (const entry of entries) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...walkDir(fullPath));
    } else if (entry.isFile() && entry.name.endsWith(".json")) {
      results.push(fullPath);
    }
  }

  return results;
}

function computeHash(filePath: string): string {
  const content = readFileSync(filePath);
  const hash = createHash("sha256").update(content).digest("hex");
  return hash.substring(0, 8);
}

// ── Main ───────────────────────────────────────────────────────────────

console.log("Generating manifest...\n");

const jsonFiles = walkDir(API_DIR).sort();
const files: Record<string, ManifestEntry> = {};

for (const filePath of jsonFiles) {
  const relPath = relative(API_DIR, filePath);

  // Skip the manifest itself
  if (filePath === MANIFEST_PATH) {
    continue;
  }

  const stat = statSync(filePath);
  const hash = computeHash(filePath);

  files[relPath] = {
    hash,
    size: stat.size,
  };

  console.log(`  ${hash}  ${relPath} (${stat.size} bytes)`);
}

const manifest = {
  version: "1.0.0",
  generated_at: new Date().toISOString(),
  files,
};

writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + "\n");

console.log(`\nManifest written to ${relative(ROOT, MANIFEST_PATH)}`);
console.log(`Total files: ${Object.keys(files).length}`);
