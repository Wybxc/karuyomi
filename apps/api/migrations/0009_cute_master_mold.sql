/* Prototype reset: old approvals and Source values have no catalog identity.
Re-register current static builds; do not infer or migrate trusted origins. */
DROP TABLE `extension_builds`;

--> statement-breakpoint
CREATE TABLE `extension_builds` (
  `build_id` text PRIMARY KEY NOT NULL,
  `package_name` text NOT NULL,
  `catalog_url` text NOT NULL,
  `repo_id` text NOT NULL,
  `bundle_sha256` text NOT NULL,
  `status` text NOT NULL,
  `created_at` integer NOT NULL,
  `allowed_hosts_json` text DEFAULT '[]' NOT NULL
);

--> statement-breakpoint
CREATE UNIQUE INDEX `extension_builds_catalog_package_unique` ON `extension_builds` (`catalog_url`, `repo_id`, `package_name`);

--> statement-breakpoint
DROP TABLE `source_preferences`;

--> statement-breakpoint
CREATE TABLE `source_preferences` (
  `subject` text NOT NULL,
  `catalog_url` text NOT NULL,
  `repo_id` text NOT NULL,
  `package_name` text NOT NULL,
  `source_id` text NOT NULL,
  `revision` integer NOT NULL,
  `entries_json` text NOT NULL,
  PRIMARY KEY (
    `subject`,
    `catalog_url`,
    `repo_id`,
    `package_name`,
    `source_id`
  )
);

--> statement-breakpoint
DELETE FROM `state_mutations`
WHERE
  `kind` = 'source_preferences';
