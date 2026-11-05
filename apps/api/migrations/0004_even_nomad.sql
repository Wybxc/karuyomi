CREATE TABLE `categories` (
  `subject` text NOT NULL,
  `id` text NOT NULL,
  `name` text NOT NULL,
  `sort_order` integer NOT NULL,
  PRIMARY KEY (`subject`, `id`)
);

--> statement-breakpoint
CREATE TABLE `manga_categories` (
  `subject` text NOT NULL,
  `manga_key` text NOT NULL,
  `category_id` text NOT NULL,
  PRIMARY KEY (`subject`, `manga_key`, `category_id`),
  FOREIGN KEY (`subject`, `manga_key`) REFERENCES `manga_state` (`subject`, `manga_key`) ON UPDATE NO ACTION ON DELETE CASCADE,
  FOREIGN KEY (`subject`, `category_id`) REFERENCES `categories` (`subject`, `id`) ON UPDATE NO ACTION ON DELETE CASCADE
);

--> statement-breakpoint
ALTER TABLE `account_state`
ADD `categories_revision` integer DEFAULT 0 NOT NULL;

--> statement-breakpoint
ALTER TABLE `state_mutations`
ADD `kind` text DEFAULT 'manga' NOT NULL;
