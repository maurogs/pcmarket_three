require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "self_and_descendant_ids includes the category and all descendants" do
    assert_equal [ categories(:gpus).id, categories(:rtx).id ].sort,
      categories(:gpus).self_and_descendant_ids.sort
  end

  test "a leaf category only contains itself" do
    assert_equal [ categories(:rtx).id ], categories(:rtx).self_and_descendant_ids
  end

  test "all_spec_attributes inherits from ancestor categories" do
    assert_includes categories(:rtx).all_spec_attributes, spec_attributes(:vram)
  end

  test "localised name falls back to English" do
    I18n.with_locale(:es) do
      assert_equal "Tarjetas gráficas", categories(:gpus).name
    end
  end

  test "slug candidates fall back to name plus id on collision" do
    category = Category.create!(names: { "en" => "Graphics Cards" })
    assert_match(/\Agraphics-cards/, category.slug)
    assert_not_equal categories(:gpus).slug, category.slug
  end
end
