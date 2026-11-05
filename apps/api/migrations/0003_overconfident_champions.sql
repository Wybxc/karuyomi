CREATE TABLE `account_state` (
  `subject` text PRIMARY KEY NOT NULL,
  `revision` integer DEFAULT 0 NOT NULL
);

--> statement-breakpoint
CREATE TABLE `chapter_progress` (
  `subject` text NOT NULL,
  `manga_key` text NOT NULL,
  `chapter_key` text NOT NULL,
  `state_json` text NOT NULL,
  PRIMARY KEY (`subject`, `manga_key`, `chapter_key`)
);

--> statement-breakpoint
CREATE TABLE `manga_state` (
  `subject` text NOT NULL,
  `manga_key` text NOT NULL,
  `revision` integer NOT NULL,
  `favorite` integer NOT NULL,
  `state_json` text NOT NULL,
  PRIMARY KEY (`subject`, `manga_key`)
);

--> statement-breakpoint
CREATE TABLE `state_mutations` (
  `subject` text NOT NULL,
  `mutation_id` text NOT NULL,
  `request_hash` text NOT NULL,
  `attempt_nonce` text NOT NULL,
  `response_json` text NOT NULL,
  PRIMARY KEY (`subject`, `mutation_id`)
);
