require "test_helper"

class ListingsHelperTest < ActionView::TestCase
  include ListingsHelper

  # --- money ------------------------------------------------------------------

  test "money formats cents as EUR for English" do
    I18n.with_locale(:en) do
      assert_equal "€599.99", money(599_99)
      assert_equal "€1,299.90", money(129_990)
      assert_equal "€0.00", money(0)
    end
  end

  test "money follows the locale's number format in Spanish" do
    I18n.with_locale(:es) do
      assert_equal "1.299,90 €", money(129_990)
      assert_equal "599,99 €", money(599_99)
    end
  end

  test "money falls back to the currency code for unknown units" do
    I18n.with_locale(:en) do
      assert_equal "XXX10.00", money(1_000, "XXX")
    end
  end

  # --- spec values --------------------------------------------------------------

  test "spec_value_label translates the option's own names" do
    attribute = spec_attributes(:ports)
    I18n.with_locale(:en) do
      assert_equal "HDMI", spec_value_label(attribute, "hdmi")
      assert_equal "DisplayPort", spec_value_label(attribute, "displayport")
    end
  end

  test "spec_value_label falls back to the raw value when no option matches" do
    attribute = spec_attributes(:ports)
    assert_equal "mystery", spec_value_label(attribute, "mystery")
    assert_equal "8GB", spec_value_label("vram", "8GB")
  end

  test "sorted_spec_pairs orders by attribute position with unknown keys last" do
    listing = listings(:as_new)
    listing.specs = { "not_an_attribute" => "x", "vram" => "8GB", "ports" => [ "hdmi" ] }
    keys = sorted_spec_pairs(listing).map(&:first)
    assert_equal %w[vram ports not_an_attribute], keys
  end

  test "spec_value_text renders arrays, booleans and scalars" do
    I18n.with_locale(:en) do
      assert_equal "HDMI, DisplayPort", spec_value_text("ports", [ "hdmi", "displayport" ])
      assert_equal "Yes", spec_value_text("negotiable", true)
      assert_equal "No", spec_value_text("negotiable", false)
      assert_equal "8GB", spec_value_text("vram", "8GB")
    end
  end

  # --- stars ---------------------------------------------------------------------

  test "stars fills the right number of glyphs and labels itself" do
    I18n.with_locale(:en) do
      html = stars(4)
      assert_includes html, %(role="img")
      assert_includes html, %(aria-label="Rated 4.0 out of 5")
      assert_equal 5, html.scan("<svg").size
      assert_equal 4, html.scan("fill-amber-400").size
    end
  end

  test "stars clamps out-of-range ratings" do
    assert_equal 5, stars(9).scan("fill-amber-400").size
    assert_equal 0, stars(-2).scan("fill-amber-400").size
  end

  # --- condition / labels ----------------------------------------------------------

  test "condition_label humanises the enum key through the locale" do
    I18n.with_locale(:en) do
      assert_equal "Used – like new", condition_label(listings(:as_new))
    end
    I18n.with_locale(:es) do
      assert_equal Listing.human_attribute_name("condition/used_like_new", locale: :es),
                   condition_label(listings(:as_new))
    end
  end
end
