import { z } from "zod";

// ── Shared / Reusable Schemas ──────────────────────────────────────────

export const ImageSchema = z.object({
  url: z.string(),
  width: z.number().int().positive().optional(),
  height: z.number().int().positive().optional(),
  alt: z.string().optional(),
});

export const ImageSetSchema = z.object({
  default: z.string(),
  sizes: z.record(z.string(), z.string()).optional(),
});

export const SocialLinksSchema = z.object({
  instagram: z.string().url().optional(),
  twitter: z.string().url().optional(),
  tiktok: z.string().url().optional(),
  youtube: z.string().url().optional(),
  website: z.string().url().optional(),
});

export const SeoSchema = z.object({
  meta_title: z.string(),
  meta_description: z.string(),
  canonical_url: z.string().url(),
  og_image: z.string().optional(),
});

export const GiscusConfigSchema = z.object({
  repo: z.string(),
  repo_id: z.string(),
  category: z.string(),
  category_id: z.string(),
  mapping: z.string(),
  reactions_enabled: z.boolean(),
  emit_metadata: z.boolean(),
  theme: z.string(),
  lang: z.string(),
});

export const InteractionConfigSchema = z.object({
  giscus: GiscusConfigSchema.optional(),
  reactions_enabled: z.boolean().optional(),
  comments_enabled: z.boolean().optional(),
});

export const P2PConfigSchema = z.object({
  swarm_id: z.string(),
  tracker_urls: z.array(z.string().url()),
  max_peers: z.number().int().positive().optional(),
  upload_enabled: z.boolean().optional(),
});

// ── Series Schema ──────────────────────────────────────────────────────

export const SeriesSchema = z.object({
  id: z.string(),
  title: z.string(),
  slug: z.string(),
  description: z.string(),
  description_short: z.string().optional(),
  genres: z.array(z.string()),
  network: z.string(),
  production_company: z.string().optional(),
  country: z.string(),
  language: z.string(),
  year_start: z.number().int(),
  year_end: z.number().int().nullable().optional(),
  status: z.enum(["airing", "ended", "hiatus", "upcoming"]),
  rating: z.object({
    age: z.string(),
    description: z.string().optional(),
  }),
  images: z.object({
    logo: z.string().optional(),
    poster: z.string().optional(),
    banner: z.string().optional(),
    background: z.string().optional(),
  }),
  social: SocialLinksSchema.optional(),
  total_seasons: z.number().int().positive(),
  total_episodes: z.number().int().positive(),
  updated_at: z.string().datetime(),
});

// ── Season Schema ──────────────────────────────────────────────────────

export const SeasonSummarySchema = z.object({
  id: z.string(),
  number: z.number().int().positive(),
  title: z.string(),
  year: z.number().int(),
  episode_count: z.number().int().positive(),
  status: z.enum(["airing", "completed", "upcoming"]),
  poster: z.string().optional(),
});

export const CoupleSchema = z.object({
  participant_ids: z.tuple([z.string(), z.string()]),
  names: z.tuple([z.string(), z.string()]),
  status: z.enum([
    "together",
    "separated",
    "reconciled",
    "unknown",
    "new_couple",
  ]),
  status_detail: z.string().optional(),
});

export const SeasonEpisodeSummarySchema = z.object({
  id: z.string(),
  number: z.number().int().positive(),
  title: z.string(),
});

export const SeasonSchema = z.object({
  id: z.string(),
  series_id: z.string(),
  number: z.number().int().positive(),
  title: z.string(),
  subtitle: z.string().optional(),
  description: z.string(),
  year: z.number().int(),
  premiere_date: z.string(),
  finale_date: z.string(),
  episode_count: z.number().int().positive(),
  status: z.enum(["airing", "completed", "upcoming"]),
  images: z.object({
    poster: z.string().optional(),
    banner: z.string().optional(),
    poster_sizes: z.record(z.string(), z.string()).optional(),
  }),
  couples: z.array(CoupleSchema),
  episodes: z.array(SeasonEpisodeSummarySchema),
  updated_at: z.string().datetime().optional(),
});

// ── Episode Schema ─────────────────────────────────────────────────────

export const VideoSourceSchema = z.object({
  id: z.string(),
  label: z.string(),
  type: z.enum(["hls", "dash", "mp4"]),
  url: z.string().url(),
  quality: z.string().optional(),
  qualities: z
    .array(
      z.object({
        label: z.string(),
        resolution: z.string(),
        bitrate: z.string().optional(),
        url: z.string().url(),
      })
    )
    .optional(),
  drm: z
    .object({
      widevine: z.string().url().optional(),
      fairplay: z.string().url().optional(),
    })
    .optional(),
  priority: z.number().int().optional(),
});

export const SubtitleSchema = z.object({
  id: z.string(),
  language: z.string(),
  label: z.string(),
  url: z.string(),
  format: z.enum(["vtt", "srt", "ass"]),
  default: z.boolean().optional(),
});

export const ChapterSchema = z.object({
  id: z.string(),
  title: z.string(),
  start_time: z.number(),
  end_time: z.number(),
  thumbnail: z.string().optional(),
});

export const SkipSegmentSchema = z.object({
  start_time: z.number(),
  end_time: z.number(),
  label: z.string().optional(),
});

export const KeyMomentSchema = z.object({
  id: z.string(),
  title: z.string(),
  description: z.string().optional(),
  timestamp: z.number(),
  thumbnail: z.string().optional(),
  type: z.enum(["dramatic", "romantic", "confrontation", "revelation", "funny", "ceremony"]).optional(),
});

export const RelatedItemSchema = z.object({
  id: z.string(),
  title: z.string(),
  thumbnail: z.string().optional(),
  url: z.string().optional(),
});

export const EpisodeSummarySchema = z.object({
  id: z.string(),
  number: z.number().int().positive(),
  title: z.string(),
  duration_display: z.string(),
  air_date: z.string(),
  thumbnail: z.string().optional(),
});

export const EpisodeSchema = z.object({
  id: z.string(),
  series_id: z.string(),
  season_id: z.string(),
  season_number: z.number().int().positive(),
  episode_number: z.number().int().positive(),
  absolute_number: z.number().int().positive(),
  title: z.string(),
  slug: z.string(),
  description: z.string(),
  description_short: z.string(),
  air_date: z.string(),
  duration_seconds: z.number().int().positive(),
  duration_display: z.string(),
  images: z.object({
    thumbnail: z.string(),
    thumbnail_sizes: z.record(z.string(), z.string()).optional(),
    preview_sprite: z.string().optional(),
  }),
  sources: z.array(VideoSourceSchema),
  subtitles: z.array(SubtitleSchema),
  chapters: z.array(ChapterSchema),
  skip_intro: SkipSegmentSchema.optional(),
  skip_recap: SkipSegmentSchema.optional(),
  participants: z.array(
    z.object({
      id: z.string(),
      name: z.string(),
      role: z.string().optional(),
    })
  ),
  key_moments: z.array(KeyMomentSchema).optional(),
  related_episodes: z.array(RelatedItemSchema).optional(),
  related_clips: z.array(RelatedItemSchema).optional(),
  p2p: P2PConfigSchema.optional(),
  seo: SeoSchema,
  interaction: InteractionConfigSchema.optional(),
  updated_at: z.string().datetime(),
});

// ── Participant Schema ─────────────────────────────────────────────────

export const ParticipantSummarySchema = z.object({
  id: z.string(),
  name: z.string(),
  season_ids: z.array(z.string()),
  role: z.enum(["contestant", "temptation", "host", "guest"]),
  avatar: z.string().optional(),
});

export const ParticipantSchema = z.object({
  id: z.string(),
  name: z.string(),
  full_name: z.string(),
  slug: z.string(),
  age_at_show: z.number().int().positive(),
  origin: z.string(),
  role: z.enum(["contestant", "temptation", "host", "guest"]),
  seasons: z.array(
    z.object({
      season_id: z.string(),
      season_number: z.number().int().positive(),
      partner_id: z.string().optional(),
      outcome: z.string().optional(),
    })
  ),
  images: z.object({
    avatar: z.string().optional(),
    portrait: z.string().optional(),
    gallery: z.array(z.string()).optional(),
  }),
  bio: z.string(),
  social: SocialLinksSchema.optional(),
  updated_at: z.string().datetime().optional(),
});

// ── Clip Schema ────────────────────────────────────────────────────────

export const ClipSchema = z.object({
  id: z.string(),
  title: z.string(),
  description: z.string().optional(),
  episode_id: z.string(),
  season_id: z.string().optional(),
  timestamp: z.number(),
  duration: z.number().int().positive(),
  duration_display: z.string().optional(),
  thumbnail: z.string().optional(),
  sources: z.array(VideoSourceSchema).optional(),
  type: z.enum(["highlight", "moment", "preview", "recap", "bonus"]).optional(),
  participants: z.array(z.string()).optional(),
  tags: z.array(z.string()).optional(),
  views: z.number().int().nonnegative().optional(),
  updated_at: z.string().datetime().optional(),
});

// ── Poll Schema ────────────────────────────────────────────────────────

export const PollOptionSchema = z.object({
  id: z.string(),
  label: z.string(),
  image: z.string().optional(),
  votes: z.number().int().nonnegative(),
});

export const PollSchema = z.object({
  id: z.string(),
  title: z.string(),
  description: z.string().optional(),
  episode_id: z.string().optional(),
  season_id: z.string().optional(),
  type: z.enum(["single_choice", "multiple_choice", "rating"]),
  status: z.enum(["active", "closed", "scheduled"]),
  options: z.array(PollOptionSchema),
  total_votes: z.number().int().nonnegative(),
  starts_at: z.string().datetime().optional(),
  ends_at: z.string().datetime().optional(),
  created_at: z.string().datetime(),
  updated_at: z.string().datetime().optional(),
});

// ── Reaction Schema ────────────────────────────────────────────────────

export const ReactionAggregateSchema = z.object({
  episode_id: z.string(),
  total_reactions: z.number().int().nonnegative(),
  reactions: z.record(z.string(), z.number().int().nonnegative()),
  timeline: z
    .array(
      z.object({
        timestamp: z.number(),
        reactions: z.record(z.string(), z.number().int().nonnegative()),
      })
    )
    .optional(),
  updated_at: z.string().datetime(),
});

// ── Manifest Schema ────────────────────────────────────────────────────

export const ManifestSchema = z.object({
  version: z.string(),
  generated_at: z.string().datetime(),
  files: z.record(
    z.string(),
    z.object({
      hash: z.string(),
      size: z.number().int().positive().optional(),
    })
  ),
});

// ── Search Index Schema ────────────────────────────────────────────────

export const SearchIndexEntrySchema = z.object({
  title: z.string(),
  description: z.string(),
  type: z.enum(["episode", "participant", "season", "clip"]),
  url: z.string(),
});

export const SearchIndexSchema = z.object({
  version: z.string(),
  generated_at: z.string().datetime(),
  entries: z.array(SearchIndexEntrySchema),
});

// ── Type Exports ───────────────────────────────────────────────────────

export type Series = z.infer<typeof SeriesSchema>;
export type SeasonSummary = z.infer<typeof SeasonSummarySchema>;
export type Season = z.infer<typeof SeasonSchema>;
export type EpisodeSummary = z.infer<typeof EpisodeSummarySchema>;
export type Episode = z.infer<typeof EpisodeSchema>;
export type ParticipantSummary = z.infer<typeof ParticipantSummarySchema>;
export type Participant = z.infer<typeof ParticipantSchema>;
export type Clip = z.infer<typeof ClipSchema>;
export type Poll = z.infer<typeof PollSchema>;
export type ReactionAggregate = z.infer<typeof ReactionAggregateSchema>;
export type Manifest = z.infer<typeof ManifestSchema>;
export type SearchIndex = z.infer<typeof SearchIndexSchema>;
