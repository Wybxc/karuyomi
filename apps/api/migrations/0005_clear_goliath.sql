CREATE TABLE `chapter_bookmarks` (
  `subject` text NOT NULL,
  `manga_key` text NOT NULL,
  `chapter_key` text NOT NULL,
  PRIMARY KEY (`subject`, `manga_key`, `chapter_key`)
);
