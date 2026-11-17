require "test_helper"
require "tmpdir"
require "zlib"

# Phase 8a: sitemap generation (config/sitemap.rb + sitemap_generator).
# The Interpreter writes into a temp dir through SITEMAP_PUBLIC_PATH, and
# APP_URL pins the canonical host so assertions are deterministic.
class SitemapTest < ActionDispatch::IntegrationTest
  HOST = "http://sitemap.example.com".freeze

  def sitemap_bodies(dir)
    Dir[File.join(dir, "sitemaps", "*.xml.gz")].sort.map { |path| Zlib::GzipReader.open(path, &:read) }.join
  end

  test "generates a sitemap index with localized listing urls and alternates" do
    Dir.mktmpdir("sitemap") do |dir|
      with_env("SITEMAP_PUBLIC_PATH" => dir, "APP_URL" => HOST) do
        SitemapGenerator::Interpreter.run(config_file: Rails.root.join("config/sitemap.rb"))
      end

      assert File.exist?(File.join(dir, "sitemaps", "sitemap.xml.gz"))
      urls = sitemap_bodies(dir)
      # Approved fixture listing is in, draft/pending/sold ones are not.
      assert_includes urls, "#{HOST}/listings/gigabyte-rtx-4070-gaming-oc"
      assert_includes urls, "#{HOST}/en/listings/gigabyte-rtx-4070-gaming-oc"
      assert_not_includes urls, "used-rtx-3080"
      assert_not_includes urls, "pending-gpu-listing"
      assert_not_includes urls, "sold-asus-rog-strix-rtx-3070"

      # Every URL back-links its six locale alternates. sitemap_generator
      # renders the xhtml:link attributes in rel/href/hreflang order
      # (Builder::SitemapUrl#add_to_builder), so assert in that order.
      assert_includes urls, '<xhtml:link rel="alternate" ' \
                            'href="http://sitemap.example.com/listings/gigabyte-rtx-4070-gaming-oc" hreflang="es"/>'
      assert_includes urls, 'href="http://sitemap.example.com/pt/listings/gigabyte-rtx-4070-gaming-oc" hreflang="pt"'

      # Static content pages and active categories make it in.
      assert_includes urls, "#{HOST}/c/graphics-cards"
      assert_includes urls, "#{HOST}/fr/pages/about"
      assert_includes urls, "#{HOST}/trust-and-safety"
    end
  end

  private

  def with_env(pairs)
    previous = pairs.keys.index_with { |key| ENV[key] }
    pairs.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
