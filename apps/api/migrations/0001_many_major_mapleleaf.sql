CREATE TABLE `build_artifacts` (
	`build_id` text NOT NULL,
	`sha256` text NOT NULL,
	PRIMARY KEY(`build_id`, `sha256`),
	FOREIGN KEY (`build_id`) REFERENCES `extension_builds`(`build_id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`sha256`) REFERENCES `extension_artifacts`(`sha256`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `extension_artifacts` (
	`sha256` text PRIMARY KEY NOT NULL,
	`object_key` text NOT NULL,
	`size` integer NOT NULL,
	`content_type` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `extension_artifacts_object_key_unique` ON `extension_artifacts` (`object_key`);--> statement-breakpoint
CREATE TABLE `extension_builds` (
	`build_id` text PRIMARY KEY NOT NULL,
	`package_name` text NOT NULL,
	`manifest_json` text NOT NULL,
	`status` text NOT NULL,
	`created_at` integer NOT NULL,
	`allowed_hosts_json` text DEFAULT '[]' NOT NULL
);
