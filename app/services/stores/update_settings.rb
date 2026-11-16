# Applies the store settings form to the seller's store (creating it first if
# they somehow got here without one — EnsureFor is idempotent). Euro strings
# are converted to cents with the shared form parser; blank money fields keep
# the NOT NULL default at 0 and clear the optional threshold. Uploads only
# overwrite when the form actually sent a new file. A name change triggers a
# new slug through FriendlyId, with the old one kept in friendly_id_slugs.
module Stores
  class UpdateSettings
    TEXT_FIELDS = %i[name description vat_number city returns_policy shipping_policy].freeze
    BOOLEAN_FIELDS = %i[allow_offers_default].freeze
    # form field => cents column (default_shipping blank becomes 0, the
    # threshold blank becomes NULL).
    MONEY_FIELDS = { "default_shipping" => :default_shipping_cents,
                     "free_shipping_threshold" => :free_shipping_threshold_cents }.freeze

    Result = Struct.new(:store, :saved, keyword_init: true) do
      def saved? = saved
    end

    def initialize(user, raw)
      @user = user
      @raw = raw
    end

    def call
      store = EnsureFor.new(@user).call

      attrs, invalid_money = build_attrs
      if invalid_money.any?
        invalid_money.each { |column| store.errors.add(column, :not_a_number) }
        return Result.new(store: store, saved: false)
      end

      store.assign_attributes(attrs)
      store.logo = @raw[:logo] if @raw[:logo].present?
      store.banner = @raw[:banner] if @raw[:banner].present?

      Result.new(store: store, saved: store.save)
    end

    private

    def build_attrs
      attrs = {}
      invalid = []

      (TEXT_FIELDS + BOOLEAN_FIELDS + %i[store_type region]).each do |key|
        attrs[key] = @raw[key] if @raw.key?(key)
      end

      MONEY_FIELDS.each do |form_key, column|
        next unless @raw.key?(form_key)

        cents = Listings::FormAttributes.euros_to_cents(@raw[form_key])
        if cents == Listings::FormAttributes::INVALID
          invalid << column
        elsif cents.nil? && column == :default_shipping_cents
          attrs[column] = 0
        else
          attrs[column] = cents
        end
      end

      [ attrs, invalid ]
    end
  end
end
