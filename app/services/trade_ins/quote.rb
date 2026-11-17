# Instant trade-in offers ("Sell to us", behind Flipper :sell_to_us).
#
# The payout math lives in one place: base table config/data/trade_in_prices.yml
# × condition multiplier (like new 1.0, good 0.85, fair 0.65, for parts 0.2),
# then −5% when the original box is not included. Result offered_cents is
# rounded to whole cents; a quote row is written with status `quoted` and
# expires_at = 7 days from now (TradeIn::QUOTE_TTL).
#
#   result = TradeIns::Quote.call(component_type: "gpu", model: "rtx4070",
#                                 condition: "good", has_box: false)
#   result.record # => persisted TradeIn (or nil when result.invalid?)
module TradeIns
  class Quote
    PRICES = YAML.load_file(Rails.root.join("config/data/trade_in_prices.yml")).freeze

    CONDITION_MULTIPLIERS = {
      "like_new" => 1.0, "good" => 0.85, "fair" => 0.65, "for_parts" => 0.2
    }.freeze
    NO_BOX_MULTIPLIER = 0.95

    # Curated payout examples for the marketing landing (keys must exist in
    # PRICES; the table shows base vs the three sellable conditions).
    EXAMPLE_MODELS = {
      "gpu" => %w[rtx4070 rtx3060 rx6700xt],
      "cpu" => %w[ryzen75800x3d i512400f ryzen55600x]
    }.freeze

    Result = Struct.new(:record, :error, keyword_init: true) do
      def success? = record.present?
      def invalid? = error.present?
    end

    class << self
      # Dropdown options for one component type: [normalized key, display].
      def models(component_type)
        table_for(component_type).map { |key, data| [ key, data["display"] ] }
            .sort_by { |(_key, display)| display }
      end

      def model_entry(component_type, model_key)
        table_for(component_type)[model_key.to_s]
      end

      # Payout example rows for the landing table:
      # { key:, display:, offers: { "like_new" => cents, ... } }.
      def example_rows(component_type)
        models = table_for(component_type)
        EXAMPLE_MODELS.fetch(component_type.to_s).filter_map do |key|
          entry = models[key]
          next if entry.nil?

          offers = %w[like_new good fair].index_with do |condition|
            (entry["base_cents"] * CONDITION_MULTIPLIERS.fetch(condition)).round
          end
          { key: key, display: entry["display"], base_cents: entry["base_cents"], offers: offers }
        end
      end

      def call(component_type:, model:, condition:, has_box:, user: nil)
        entry = model_entry(component_type, model)
        return Result.new(error: :unknown_model) if entry.nil?

        multiplier = CONDITION_MULTIPLIERS[condition.to_s]
        return Result.new(error: :unknown_condition) if multiplier.nil?

        has_box = ActiveModel::Type::Boolean.new.cast(has_box)
        offered = (entry["base_cents"] * multiplier * (has_box ? 1.0 : NO_BOX_MULTIPLIER)).round

        record = TradeIn.create!(
          user: user,
          component_type: component_type.to_s,
          model: model.to_s,
          condition: condition.to_s,
          has_box: has_box,
          offered_cents: offered,
          status: :quoted,
          expires_at: Time.current + TradeIn::QUOTE_TTL
        )
        Result.new(record: record)
      end

      private

      def table_for(component_type)
        PRICES.fetch(component_type.to_s, {})
      end
    end
  end
end
