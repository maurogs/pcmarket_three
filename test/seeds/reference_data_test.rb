require "test_helper"

# Runs db/seeds.rb (reference data, Phase 2a) against the fixture-loaded
# test database. The test transaction wraps the seeds, so the run never
# touches the real test DB and can be repeated inside the test.
class ReferenceDataSeedTest < ActiveSupport::TestCase
  LOCALES = %w[es en fr de it pt]
  ROOT_SLUGS = %w[gaming-pcs gpus components peripherals laptops mobile consoles workstations accessories games-software]
  CORES_POPULAR = %w[4 6 8 10 12 14 16 20 24]

  test "seeds are idempotent: a second run changes no counts" do
    before = table_counts
    run_seeds
    first = table_counts
    run_seeds
    second = table_counts

    assert_equal first, second, "re-running db/seeds.rb must not change any table count"

    created = first.keys.to_h { |table| [ table, first[table] - before[table] ] }
    # 10 roots + 51 children, but the gaming-pcs root pre-exists in the fixtures
    # (Phase 7a), so the seed upserts it instead of creating it.
    assert_equal 60, created[:categories]
    # gpu_model / cpu_model spec attributes already exist in the fixtures too.
    assert_equal 32, created[:spec_attributes]
    assert_equal 293, created[:spec_options]
    # …and their two gaming-pcs / gaming-desktops category links pre-exist too.
    assert_equal 86, created[:category_spec_attributes]
    assert_equal 13, created[:labels]
    # 21 style tags are created; the 3 phase-7a finder filters (competitive,
    # air-cooling, aio-cooling) already exist in the fixtures.
    assert_equal 21, created[:seller_tags]
    assert_equal 4, created[:countries], "fixtures ship ES + GB, seeds add FR DE IT PT"
    assert_equal 7, created[:settings],
                 "4 core + min_offer_percent (Phase 4a) + min_public_stat (Phase 7b) + search_engine_indexing (Phase 8a)"
  end

  test "every seeded category, spec attribute and spec option carries all six locales" do
    seeded = run_seeds

    assert_operator seeded[:categories].size, :>, 0
    Category.where(id: seeded[:categories]).find_each do |category|
      assert_equal LOCALES.sort, category.names.keys.sort, "category #{category.slug}"
    end
    SpecAttribute.where(id: seeded[:spec_attributes]).find_each do |attribute|
      assert_equal LOCALES.sort, attribute.names.keys.sort, "spec attribute #{attribute.key}"
    end
    SpecOption.where(id: seeded[:spec_options]).find_each do |option|
      assert_equal LOCALES.sort, option.names.keys.sort, "spec option #{option.spec_attribute.key}:#{option.value}"
    end
    Label.where(id: seeded[:labels]).find_each do |label|
      assert_equal LOCALES.sort, label.names.keys.sort, "label #{label.slug}"
      assert_match(/\A#[0-9a-fA-F]{6}\z/, label.color, "label #{label.slug} needs a hex colour")
    end
    SellerTag.where(id: seeded[:seller_tags]).find_each do |tag|
      assert_equal LOCALES.sort, tag.names.keys.sort, "seller tag #{tag.slug}"
    end
  end

  test "root categories have an icon and a fully translated seo_description" do
    seeded = run_seeds

    ROOT_SLUGS.each do |slug|
      category = Category.find_by!(slug:)
      if slug == "gaming-pcs"
        # Pre-exists in the fixtures (Phase 7a), so the seed upserts the row
        # instead of creating it; icon/seo assertions below still must hold.
        assert_not_includes seeded[:categories], category.id
      else
        assert seeded[:categories].include?(category.id), "#{slug} was not seeded by this run"
      end
      assert category.icon.present?, "#{slug} needs an icon"
      assert_equal LOCALES.sort, category.seo_descriptions.keys.sort, "#{slug} seo_description"
    end
  end

  test "category spec attributes are inherited and flags are set" do
    run_seeds

    gpus = Category.find_by!(slug: "gpus")
    assert_includes gpus.all_spec_attributes.map(&:key), "gpu_chipset"

    nvidia = Category.find_by!(slug: "nvidia-gpus")
    assert_includes nvidia.all_spec_attributes.map(&:key), "gpu_chipset"

    gpu_chipset = CategorySpecAttribute.find_by(category: gpus, spec_attribute: SpecAttribute.find_by!(key: "gpu_chipset"))
    assert gpu_chipset.required?, "gpu_chipset must be required for gpus"
    cpu_brand = CategorySpecAttribute.find_by(category: Category.find_by!(slug: "cpus"), spec_attribute: SpecAttribute.find_by!(key: "cpu_brand"))
    assert cpu_brand.required?, "cpu_brand must be required for cpus"

    monitor_keys = Category.find_by!(slug: "monitors").all_spec_attributes.map(&:key)
    assert_equal %w[refresh_rate resolution screen_size], monitor_keys.sort
  end

  test "popular options match the spec for representative attributes" do
    run_seeds

    cores = SpecAttribute.find_by!(key: "cpu_cores")
    assert_equal CORES_POPULAR, cores.spec_options.popular.pluck(:value)

    sockets = SpecAttribute.find_by!(key: "cpu_socket")
    assert_equal %w[lga1851 lga1700 lga1200 am5 am4 other], sockets.spec_options.popular.pluck(:value)

    memory = SpecAttribute.find_by!(key: "memory_capacity")
    assert_equal %w[lt2 8 12 16 24 32 48 64 128], memory.spec_options.popular.pluck(:value)
  end

  private

  # Re-runs db/seeds.rb and returns the ids of rows this run created
  # (fixture rows loaded before the run are excluded).
  def run_seeds
    before_ids = current_ids
    load Rails.root.join("db/seeds.rb").to_s
    after_ids = current_ids
    after_ids.to_h do |table, ids|
      [ table, ids - before_ids[table] ]
    end
  end

  def current_ids
    {
      categories: Category.ids,
      spec_attributes: SpecAttribute.ids,
      spec_options: SpecOption.ids,
      category_spec_attributes: CategorySpecAttribute.ids,
      labels: Label.ids,
      seller_tags: SellerTag.ids
    }
  end

  def table_counts
    {
      categories: Category.count,
      spec_attributes: SpecAttribute.count,
      spec_options: SpecOption.count,
      category_spec_attributes: CategorySpecAttribute.count,
      labels: Label.count,
      seller_tags: SellerTag.count,
      countries: Country.count,
      settings: Setting.count
    }
  end
end
