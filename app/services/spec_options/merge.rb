module SpecOptions
  # Merge one spec option into another of the same attribute (Phase 6b).
  # Rewrites every listing's `specs` jsonb with a SINGLE UPDATE: scalar
  # values (select/number/text) are replaced directly, array members
  # (multi_select) are swapped in place. Then the source option is removed —
  # afterwards no listing references it, which is exactly why plain
  # deletion of an in-use option is blocked in the admin UI.
  class Merge
    Result = Struct.new(:option, :listings_rewritten, keyword_init: true)

    SQL = <<~SQL.squish
      UPDATE listings
      SET specs = jsonb_set(
        specs,
        ARRAY[?]::text[],
        CASE
          WHEN jsonb_typeof(specs -> ?) = 'array'
          THEN (SELECT jsonb_agg(CASE WHEN e = ?::jsonb THEN ?::jsonb ELSE e END)
                FROM jsonb_array_elements(specs -> ?) e)
          ELSE ?::jsonb
        END
      )
      WHERE specs -> ? = ?::jsonb
         OR (jsonb_typeof(specs -> ?) = 'array' AND specs -> ? @> ?::jsonb)
    SQL

    # Merges `option` INTO `target` (target keeps existing rows that already
    # have the target value — the array form de-duplicates only when the
    # target equals the source, which is enough for our catalogue hygiene).
    def self.call(option:, target:)
      raise ArgumentError, "cannot merge an option into itself" if option.id == target.id
      raise ArgumentError, "options must belong to the same spec attribute" if option.spec_attribute_id != target.spec_attribute_id

      key = option.spec_attribute.key
      source = option.value.to_json
      destination = target.value.to_json

      rewritten = ActiveRecord::Base.connection.exec_update(
        Listing.sanitize_sql_array([ SQL, key, key, source, destination, key, destination,
                                     key, source, key, key, source ]),
        "MergeSpecOption"
      )
      option.destroy!
      Result.new(option: option, listings_rewritten: rewritten)
    end
  end
end
