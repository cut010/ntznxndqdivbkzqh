import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { resolve, relative, join } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const API_DIR = resolve(ROOT, "api/v1");
const OUTPUT_PATH = resolve(API_DIR, "search-index.json");

interface SearchEntry {
  title: string;
  description: string;
  type: "episode" | "participant" | "season" | "clip";
  url: string;
}

const entries: SearchEntry[] = [];

// ── Seasons ────────────────────────────────────────────────────────────

console.log("Indexing seasons...");
const seasonsIndexPath = resolve(API_DIR, "seasons/index.json");
if (existsSync(seasonsIndexPath)) {
  const seasons = JSON.parse(readFileSync(seasonsIndexPath, "utf-8"));
  for (const season of seasons) {
    const detailPath = resolve(API_DIR, `seasons/${season.id}.json`);
    let description = `${season.title} (${season.year}) - ${season.episode_count} episodios`;

    if (existsSync(detailPath)) {
      const detail = JSON.parse(readFileSync(detailPath, "utf-8"));
      description = detail.description || description;
    }

    entries.push({
      title: season.title,
      description,
      type: "season",
      url: `/api/v1/seasons/${season.id}.json`,
    });
  }
}

// ── Episodes ───────────────────────────────────────────────────────────

console.log("Indexing episodes...");
const episodesDir = resolve(API_DIR, "episodes");
if (existsSync(episodesDir)) {
  const seasonDirs = readdirSync(episodesDir, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name);

  for (const seasonDir of seasonDirs) {
    const indexPath = resolve(episodesDir, seasonDir, "index.json");
    if (!existsSync(indexPath)) continue;

    const episodesList = JSON.parse(readFileSync(indexPath, "utf-8"));

    for (const ep of episodesList) {
      // Try to read full episode for description
      const detailPath = resolve(episodesDir, seasonDir, `${ep.id}.json`);
      let description = `${ep.title} - ${ep.duration_display}`;

      if (existsSync(detailPath)) {
        const detail = JSON.parse(readFileSync(detailPath, "utf-8"));
        description = detail.description_short || detail.description || description;
      }

      entries.push({
        title: `${ep.id.toUpperCase().replace("S0", "S0").replace("E0", "E0")}: ${ep.title}`,
        description,
        type: "episode",
        url: `/api/v1/episodes/${seasonDir}/${ep.id}.json`,
      });
    }
  }
}

// ── Participants ───────────────────────────────────────────────────────

console.log("Indexing participants...");
const participantsIndexPath = resolve(API_DIR, "participants/index.json");
if (existsSync(participantsIndexPath)) {
  const participants = JSON.parse(
    readFileSync(participantsIndexPath, "utf-8")
  );

  for (const participant of participants) {
    // Try to read full participant for bio
    const detailPath = resolve(
      API_DIR,
      `participants/${participant.id}.json`
    );
    let description = `${participant.name} - ${participant.role}`;

    if (existsSync(detailPath)) {
      const detail = JSON.parse(readFileSync(detailPath, "utf-8"));
      description = detail.bio
        ? detail.bio.substring(0, 200)
        : description;
    }

    entries.push({
      title: participant.name,
      description,
      type: "participant",
      url: `/api/v1/participants/${participant.id}.json`,
    });
  }
}

// ── Clips ──────────────────────────────────────────────────────────────

console.log("Indexing clips...");
const clipsPath = resolve(API_DIR, "clips/index.json");
if (existsSync(clipsPath)) {
  const clips = JSON.parse(readFileSync(clipsPath, "utf-8"));
  for (const clip of clips) {
    entries.push({
      title: clip.title,
      description: `Clip del episodio ${clip.episode_id} - ${clip.duration}s`,
      type: "clip",
      url: `/api/v1/clips/index.json#${clip.id}`,
    });
  }
}

// ── Write output ───────────────────────────────────────────────────────

const searchIndex = {
  version: "1.0.0",
  generated_at: new Date().toISOString(),
  entries,
};

writeFileSync(OUTPUT_PATH, JSON.stringify(searchIndex, null, 2) + "\n");

console.log(`\nSearch index written to ${relative(ROOT, OUTPUT_PATH)}`);
console.log(`Total entries: ${entries.length}`);
