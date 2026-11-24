CREATE TABLE `browsing_history` (
  `subject` text NOT NULL,
  `manga_key` text NOT NULL,
  `title` text NOT NULL,
  `source_name` text NOT NULL,
  `metadata_json` text NOT NULL,
  `visited_at_ms` integer NOT NULL,
  PRIMARY KEY (`subject`, `manga_key`)
);

--> statement-breakpoint
CREATE INDEX `browsing_history_recent` ON `browsing_history` (`subject`, "visited_at_ms" DESC, `manga_key`);
