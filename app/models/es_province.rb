# Read-only lookup for the Spanish province list in config/data/es_provinces.yml
# (the 50 provinces plus Ceuta and Melilla). Used by the listing location form;
# the Listing model validates `region` against these names.
class EsProvince
  attr_reader :code, :name, :region

  def self.all
    Rails.cache.fetch("es_provinces", expires_in: 1.day) do
      YAML.load_file(Rails.root.join("config/data/es_provinces.yml"))
          .map { |row| new(row) }
          .freeze
    end
  end

  def self.names
    all.map(&:name)
  end

  def self.name?(name)
    names.include?(name.to_s)
  end

  # Provinces grouped by autonomous community, preserving file order inside
  # each group: [[region, [province, …]], …] for grouped select options.
  def self.grouped_by_region
    all.group_by(&:region).to_a.sort_by { |region, _| region }
  end

  def initialize(row)
    @code = row["code"]
    @name = row["name"]
    @region = row["region"]
  end
end
