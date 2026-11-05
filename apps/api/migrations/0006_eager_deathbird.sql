CREATE TABLE `reader_settings` (
  `subject` text NOT NULL,
  `scope_key` text NOT NULL,
  `revision` integer NOT NULL,
  `values_json` text NOT NULL,
  PRIMARY KEY (`subject`, `scope_key`)
);
