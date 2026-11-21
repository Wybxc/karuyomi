UPDATE "reader_settings"
SET
  "values_json" = json_remove("values_json", '$.theme')
WHERE
  "scope_key" = ''
  AND json_type("values_json", '$.theme') IS NOT NULL;

--> statement-breakpoint
UPDATE "state_mutations"
SET
  "response_json" = json_remove("response_json", '$.global.values.theme')
WHERE
  "kind" = 'settings'
  AND json_type("response_json", '$.global.values.theme') IS NOT NULL;
