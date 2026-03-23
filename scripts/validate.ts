import { readFileSync, existsSync } from "node:fs";
import { resolve, relative } from "node:path";
import {
  SeriesSchema,
  SeasonSummarySchema,
  SeasonSchema,
  EpisodeSummarySchema,
  EpisodeSchema,
  ParticipantSummarySchema,
  ParticipantSchema,
  ClipSchema,
  PollSchema,
  ReactionAggregateSchema,
} from "../schemas/index.js";
import { z } from "zod";

const ROOT = resolve(import.meta.dirname, "..");
const API = resolve(ROOT, "api/v1");

let errors = 0;
let validated = 0;

function validateFile<T>(
  filePath: string,
  schema: z.ZodType<T>,
  label: string
): T | null {
  const rel = relative(ROOT, filePath);
  if (!existsSync(filePath)) {
    console.error(`  MISSING  ${rel}`);
    errors++;
    return null;
  }
  try {
    const raw = readFileSync(filePath, "utf-8");
    const data = JSON.parse(raw);
    const result = schema.parse(data);
    validated++;
    console.log(`  OK       ${rel}`);
    return result;
  } catch (err) {
    errors++;
    if (err instanceof z.ZodError) {
      console.error(`  FAIL     ${rel}`);
      for (const issue of err.issues) {
        console.error(
          `           -> ${issue.path.join(".")}: ${issue.message}`
        );
      }
    } else if (err instanceof SyntaxError) {
      console.error(`  FAIL     ${rel} (invalid JSON: ${err.message})`);
    } else {
      console.error(`  FAIL     ${rel} (${err})`);
    }
    return null;
  }
}

function validateArray<T>(
  filePath: string,
  schema: z.ZodType<T>,
  label: string
): T[] | null {
  const arraySchema = z.array(schema);
  return validateFile(filePath, arraySchema, label) as T[] | null;
}

// ── Main ───────────────────────────────────────────────────────────────

console.log("\nValidating lidlt-data...\n");

// Series
console.log("Series:");
validateFile(resolve(API, "series.json"), SeriesSchema, "series");

// Seasons index
console.log("\nSeasons index:");
const seasonsIndex = validateArray(
  resolve(API, "seasons/index.json"),
  SeasonSummarySchema,
  "seasons index"
);

// Season detail files
console.log("\nSeason details:");
const seasonFiles = ["season-1.json", "season-2.json", "season-3.json"];
for (const file of seasonFiles) {
  validateFile(resolve(API, "seasons", file), SeasonSchema, file);
}

// Episodes index (season 1)
console.log("\nEpisodes index (S01):");
validateArray(
  resolve(API, "episodes/s01/index.json"),
  EpisodeSummarySchema,
  "s01 index"
);

// Episode detail files
console.log("\nEpisode details (S01):");
const episodeFiles = ["s01e01.json", "s01e02.json", "s01e03.json"];
for (const file of episodeFiles) {
  validateFile(resolve(API, "episodes/s01", file), EpisodeSchema, file);
}

// Participants index
console.log("\nParticipants index:");
validateArray(
  resolve(API, "participants/index.json"),
  ParticipantSummarySchema,
  "participants index"
);

// Participant detail files
console.log("\nParticipant details:");
const participantFiles = [
  "p-001.json",
  "p-002.json",
  "p-003.json",
  "p-004.json",
];
for (const file of participantFiles) {
  validateFile(
    resolve(API, "participants", file),
    ParticipantSchema,
    file
  );
}

// Clips
console.log("\nClips:");
validateArray(resolve(API, "clips/index.json"), ClipSchema, "clips");

// Reactions
console.log("\nReactions:");
validateFile(
  resolve(API, "interactions/reactions/s01e01.json"),
  ReactionAggregateSchema,
  "reactions s01e01"
);

// Polls
console.log("\nPolls:");
validateFile(
  resolve(API, "interactions/polls/active.json"),
  PollSchema,
  "active poll"
);

// ── Summary ────────────────────────────────────────────────────────────

console.log("\n" + "─".repeat(50));
console.log(`Validated: ${validated} files`);
console.log(`Errors:    ${errors}`);
console.log("─".repeat(50) + "\n");

if (errors > 0) {
  console.error("Validation failed!");
  process.exit(1);
} else {
  console.log("All validations passed!");
}
