class Category < ApplicationRecord
  extend FriendlyId

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
  def all_spec_attributes
    rows = CategorySpecAttribute
      .where(category_id: self_and_ancestor_ids)
      .joins(:spec_attribute)
      .order("spec_attributes.position ASC, category_spec_attributes.category_id ASC")
    unique_by_spec = {}
    rows.each do |row|
      existing = unique_by_spec[row.spec_attribute_id]
      unique_by_spec[row.spec_attribute_id] = row if existing.nil? || row.category_id == id
    end
    SpecAttribute.where(id: unique_by_spec.keys).includes(:spec_options).order(position: :asc, id: :asc).to_a
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

  def translated(hash)
    locale = I18n.locale.to_s
    hash[locale].presence || hash["en"].presence
  end

  def slug_candidates
    [ :name, [ :name, :id ] ]
  end
end
