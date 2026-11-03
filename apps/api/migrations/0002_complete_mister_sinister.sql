DROP TABLE `build_artifacts`;

--> statement-breakpoint
DROP TABLE `extension_artifacts`;

--> statement-breakpoint
/* Retire prototype distribution records; register current static builds anew. */
DELETE FROM `extension_builds`;

--> statement-breakpoint
ALTER TABLE `extension_builds`
ADD `bundle_sha256` text NOT NULL;

--> statement-breakpoint
CREATE UNIQUE INDEX `extension_builds_package_name_unique` ON `extension_builds` (`package_name`);

--> statement-breakpoint
ALTER TABLE `extension_builds`
DROP COLUMN `manifest_json`;
