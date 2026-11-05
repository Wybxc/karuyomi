CREATE TABLE `cover_assets` (
  `subject` text NOT NULL,
  `manga_key` text NOT NULL,
  `asset_id` text NOT NULL,
  `object_key` text NOT NULL,
  `descriptor_json` text NOT NULL,
  PRIMARY KEY (`subject`, `manga_key`),
  FOREIGN KEY (`subject`, `manga_key`) REFERENCES `manga_state` (`subject`, `manga_key`) ON UPDATE NO ACTION ON DELETE CASCADE
);

--> statement-breakpoint
CREATE UNIQUE INDEX `cover_assets_subject_asset` ON `cover_assets` (`subject`, `asset_id`);

--> statement-breakpoint
CREATE UNIQUE INDEX `cover_assets_object_key` ON `cover_assets` (`object_key`);
