CREATE TABLE `source_preferences` (
  `subject` text NOT NULL,
  `package_name` text NOT NULL,
  `source_id` text NOT NULL,
  `revision` integer NOT NULL,
  `entries_json` text NOT NULL,
  PRIMARY KEY (`subject`, `package_name`, `source_id`)
);
