class Category < ApplicationRecord
  extend FriendlyId
  include TranslatableJsonb

  friendly_id :slug_candidates, use: :slugged

  belongs_to :parent, class_name: "Category", optional: true
  has_many :children, -> { order(position: :asc, id: :asc) },
           class_name: "Category", dependent: :destroy, inverse_of: :parent
  has_many :listings, dependent: :nullify
  has_many :category_spec_attributes, dependent: :destroy
  has_many :spec_attributes, through: :category_spec_attributes
  has_many :saved_searches, dependent: :nullify

  validates :slug, presence: true, uniqueness: true
  validates :names, presence: true
  validates :position, numericality: { only_integer: true }
  validates :icon, length: { maximum: 100 }, allow_nil: true

  scope :roots, -> { where(parent_id: nil) }
  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  validate :parent_not_descendant

  # Swap positions with the adjacent sibling (admin up/down buttons).
  # Returns true when a swap happened.
  def move!(direction)
    offset = { "up" => -1, "down" => 1 }.fetch(direction.to_s) do
      raise ArgumentError, "direction must be up or down"
    end

    siblings = self.class.where(parent_id: parent_id).order(position: :asc, id: :asc).to_a
    index = siblings.index { |sibling| sibling.id == id }
    target = index + offset
    # Explicit bounds: Array#[] with a negative index would wrap around and
    # "move" the first row to the end instead of refusing.
    return false if target.negative? || target >= siblings.size

    other = siblings[target]

    transaction do
      my_position = position
      update!(position: other.position)
      other.update!(position: my_position)
    end
    true
  end

  # Localised name for the current I18n locale, English as fallback.
  def name
    translated(names)
  end

  def seo_description
    translated(seo_descriptions)
  end

  # Ids of this category plus all categories below it, in one recursive CTE.
  # Memoised: the browse page asks for it several times (scope, facets, SEO copy).
  def self_and_descendant_ids
    @self_and_descendant_ids ||=
      self.class.connection.select_values(
        self.class.sanitize_sql_array([ <<~SQL, id ])
          WITH RECURSIVE tree AS (
            SELECT id FROM categories WHERE id = ?
            UNION ALL
            SELECT c.id FROM categories c JOIN tree t ON c.parent_id = t.id
          )
          SELECT id FROM tree
        SQL
      ).map(&:to_i)
  end

  # Own spec attributes plus those inherited from every ancestor category
  # (one recursive CTE walking up the parent chain).
  # Memoised: validate_specs and the spec pickers call it repeatedly per instance.
  def all_spec_attributes
    @all_spec_attributes ||=
      spec_attribute_rows.each_value
                         .sort_by { |row| [ row.spec_attribute.position, row.spec_attribute.id ] }
                         .map(&:spec_attribute)
  end

  # Batched #all_spec_attributes for an already-loaded set of categories:
  # chains, join rows and attributes each resolve in ONE query for the whole
  # set and the result is memoised per instance (the preload shares one
  # Category instance per id, so listing collections repeat instances).
  # Used by the sell API index, which serialises every listing's category.
  def self.warm_spec_attributes!(categories)
    pending = categories.reject { |category| category.instance_variable_defined?(:@all_spec_attributes) }
    return if pending.empty?

    chains = connection.select_all(
      sanitize_sql_array([ <<~SQL, pending.map(&:id) ])
        WITH RECURSIVE chain AS (
          SELECT id AS root_id, id, parent_id FROM categories WHERE id IN (?)
          UNION ALL
          SELECT ch.root_id, c.id, c.parent_id FROM categories c JOIN chain ch ON c.id = ch.parent_id
        )
        SELECT root_id, id FROM chain
      SQL
    )
    ancestor_ids_by_root =
      chains.each_with_object(Hash.new { |hash, key| hash[key] = [] }) { |row, map| map[row["root_id"]] << row["id"] }

    rows = CategorySpecAttribute.where(category_id: ancestor_ids_by_root.values.flatten.uniq)
                                .left_joins(:spec_attribute).preload(:spec_attribute)
    attribute_ids_by_root = ancestor_ids_by_root.transform_values do |ancestor_ids|
      ancestor_set = Set.new(ancestor_ids)
      rows.filter { |row| ancestor_set.include?(row.category_id) }.map(&:spec_attribute_id).uniq
    end

    needed = attribute_ids_by_root.values.flatten.uniq
    attributes = SpecAttribute.where(id: needed).includes(:spec_options).order(position: :asc, id: :asc).to_a
    pending.each do |category|
      ids = attribute_ids_by_root[category.id]
      category.instance_variable_set(:@all_spec_attributes, attributes.select { |attribute| ids.include?(attribute.id) })
      category.instance_variable_set(:@self_and_ancestor_ids, ancestor_ids_by_root[category.id])
    end
  end

  # spec_attribute_id => required flag for every attribute usable in this
  # category (own attachments win over inherited ones).
  def spec_attribute_required_map
    spec_attribute_rows.transform_values(&:required)
  end

  def leaf?
    children.empty?
  end

  # Ids of this category plus every ancestor, in one recursive CTE.
  def self_and_ancestor_ids
    @self_and_ancestor_ids ||=
      self.class.connection.select_values(
        self.class.sanitize_sql_array([ <<~SQL, id ])
          WITH RECURSIVE chain AS (
            SELECT id, parent_id FROM categories WHERE id = ?
            UNION ALL
            SELECT c.id, c.parent_id FROM categories c JOIN chain ch ON c.id = ch.parent_id
          )
          SELECT id FROM chain
        SQL
      ).map(&:to_i)
  end

  private

  # A category can never be its own parent or sit under one of its own
  # descendants (would break the recursive tree CTEs).
  def parent_not_descendant
    return if parent_id.nil? || new_record?

    errors.add(:parent_id, :cyclic) if parent_id == id || self_and_descendant_ids.include?(parent_id)
  end

  # Join rows for every spec attribute attached to this category or an
  # ancestor; own-category attachments override inherited ones. The ORDER BY
  # references spec_attributes, so includes is promoted to a single eager-load
  # JOIN; the options ride in one extra preload.
  def spec_attribute_rows
    @spec_attribute_rows ||= begin
      rows = CategorySpecAttribute
        .where(category_id: self_and_ancestor_ids)
        .eager_load(:spec_attribute)
        .preload(spec_attribute: :spec_options)
        .order("spec_attributes.position ASC, category_spec_attributes.category_id ASC")
      unique_by_spec = {}
      rows.each do |row|
        existing = unique_by_spec[row.spec_attribute_id]
        unique_by_spec[row.spec_attribute_id] = row if existing.nil? || row.category_id == id
      end
      unique_by_spec
    end
  end

  def translated(hash)
    locale = I18n.locale.to_s
    hash[locale].presence || hash["en"].presence
  end

  def slug_candidates
    [ :name, [ :name, :id ] ]
  end
end
