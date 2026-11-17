require "test_helper"

# Placeholder.render must ALWAYS hand back a readable image path — the seed
# attaches it as a blob and the gallery variants process it afterwards.
class DemoImages::PlaceholderTest < ActiveSupport::TestCase
  setup { @dir = Pathname(Dir.mktmpdir("demo_images_placeholder")) }
  teardown { FileUtils.remove_entry(@dir) }

  test "render returns an existing PNG path, creating parent directories" do
    path = @dir.join("nested", "deeper", "placeholder.png").to_s

    rendered = DemoImages::Placeholder.render(
      title: "MSI RTX 4060 Gaming X 8GB", category_label: "Gráfica RTX", path:, seed: 3
    )

    assert_equal path, rendered
    assert File.exist?(path), "render must leave a readable file behind"
    assert_equal "\x89PNG".b, File.binread(path, 4)
    if magick?
      assert_equal [ 1200, 900 ], identify_dims(path), "gradient tile must keep its canvas size"
    end
  end

  test "render falls back to a valid pure-Ruby PNG when ImageMagick is unavailable" do
    path = @dir.join("fallback.png").to_s
    original = DemoImages::Placeholder.method(:render_gradient)
    DemoImages::Placeholder.define_singleton_method(:render_gradient) { |*_args, **_kwargs| false }

    begin
      rendered = DemoImages::Placeholder.render(title: "Sin ImageMagick", category_label: nil, path:, seed: 1)
      assert_equal path, rendered
    ensure
      DemoImages::Placeholder.define_singleton_method(:render_gradient, original)
    end
    assert File.exist?(path)
    assert_equal "\x89PNG".b, File.binread(path, 4)
    if magick?
      assert_equal [ 120, 90 ], identify_dims(path), "fallback PNG must be decodable and sized"
    end
  end

  test "the rendered file uploads into a real blob and processes a variant" do
    path = @dir.join("blob-ready.png").to_s
    DemoImages::Placeholder.render(title: "Gigabyte RTX 3060", category_label: "Gráfica", path:, seed: 0)

    blob = File.open(path, "rb") do |io|
      ActiveStorage::Blob.create_and_upload!(io: io, filename: "ph.png", content_type: "image/png")
    end

    assert blob.service.exist?(blob.key)
    assert_equal "image/png", blob.content_type
    variant = blob.variant(resize_to_limit: [ 400, 300 ]).processed
    assert blob.service.exist?(variant.key), "the gallery variant pipeline must accept the placeholder"
  end

  private

  def magick?
    system("magick", "-version", out: File::NULL, err: File::NULL)
  end

  def identify_dims(path)
    `magick identify -format "%w %h" "#{path}"`.split.map(&:to_i)
  end
end
