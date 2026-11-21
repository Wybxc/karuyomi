UPDATE "reader_settings"
SET
  "values_json" = json_remove(
    "values_json",
    '$.reader.background',
    '$.reader.dimPercent',
    '$.reader.tapZones',
    '$.reader.keyboard'
  )
WHERE
  "scope_key" = '';

--> statement-breakpoint
UPDATE "reader_settings"
SET
  "values_json" = json_remove(
    "values_json",
    '$.background',
    '$.dimPercent',
    '$.tapZones',
    '$.keyboard'
  )
WHERE
  "scope_key" <> '';

--> statement-breakpoint
UPDATE "state_mutations"
SET
  "response_json" = json_remove(
    "response_json",
    '$.global.values.reader.background',
    '$.global.values.reader.dimPercent',
    '$.global.values.reader.tapZones',
    '$.global.values.reader.keyboard',
    '$.manga.overrides.background',
    '$.manga.overrides.dimPercent',
    '$.manga.overrides.tapZones',
    '$.manga.overrides.keyboard',
    '$.effectiveReader.background',
    '$.effectiveReader.dimPercent',
    '$.effectiveReader.tapZones',
    '$.effectiveReader.keyboard'
  )
WHERE
  "kind" = 'settings';
