# Rebuilds public/sitemaps/ nightly (config/recurring.yml). Same code path
# as `bin/rails sitemap:refresh:no_ping` — config/sitemap.rb decides which
# URLs and alternates go in. Ping is skipped on purpose: Google picks the
# updated sitemap up from robots.txt on its own schedule.
class SitemapRefreshJob < ApplicationJob
  queue_as :default

  def perform
    SitemapGenerator::Interpreter.run(config_file: Rails.root.join("config/sitemap.rb"))
  end
end
