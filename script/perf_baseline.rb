# frozen_string_literal: true

# Performance baseline runner (Phase 8c).
#
#   bin/rails runner script/perf_baseline.rb            # label "baseline"
#   bin/rails runner script/perf_baseline.rb after      # label "after"
#
# Requests the key pages through ActionDispatch::Integration::Session with
# caching forced ON (a temporary MemoryStore + perform_caching, independent of
# tmp/caching-dev.txt), twice per page: COLD (Rails.cache cleared first) and
# WARM (immediate second hit). Records status, total ms, SQL query count and
# SQL ms per request (via sql.active_record notifications, ignoring SCHEMA,
# CACHE/query-cache replays and transaction rows).
#
# Read-only by design: Active Job runs on the :test adapter (so ListingViewJob
# never writes) and the only DB writes are the Session rows this script creates
# for the admin/seller pages, which it destroys again at the end.
#
# Output: printed table + full log in tmp/perf/<label>_<UTC stamp>.txt
# (kept for the before/after report).

module PerfBaseline
  LABEL = ARGV[0] || "baseline"

  def self.run!
    raise "development/test only" if Rails.env.production?

    # --- force caching + quiet instrumentation -------------------------------
    Rails.cache = ActiveSupport::Cache::MemoryStore.new(size: 256.megabytes)
    ActionController::Base.perform_caching = true
    ActiveRecord.verbose_query_logs = false
    ActiveJob::Base.queue_adapter = :test
    # Rails 8.1's query-log tags read the execution context, which the
    # middleware stack clears after each integration request; without this the
    # script's own model queries (session create/destroy) crash on a nil
    # context once the first request has run.
    ActiveRecord.query_transformers.clear

    sql_samples = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |event|
      payload = event.payload
      next if payload[:name].in?([ "SCHEMA", "CACHE" ]) || payload[:cached]

      sql_samples << event.duration
    end

    target = Rails.application
    created_sessions = []
    admin = User.find_by(email_address: "admin@demo.pcmarket.test") || User.where(role: :admin).order(:id).first
    seller = User.joins(:store).where(role: :user).where("stores.listings_count > 0").order(:id).first
    listing = Listing.published.where(status: :approved)
                     .where("EXISTS (SELECT 1 FROM active_storage_attachments a
                                    WHERE a.record_type = 'Listing' AND a.record_id = listings.id AND a.name = 'photos')")
                     .where(store_id: Store.visible.select(:id))
                     .order(:id).first
    store = Store.visible.where(id: Listing.published.select(:store_id)).order(:id).first

    raise "demo seed data missing (need listings/stores/users)" if listing.nil? || store.nil? || admin.nil? || seller.nil?

    pages = [
      [ "home /es",                                  "/es",                                      nil ],
      [ "category /es/c/gaming-pcs",                 "/es/c/gaming-pcs",                         nil ],
      [ "gpu facet /es/c/gpus f+sort",               "/es/c/gpus?f[gpu_chipset][]=nvidia&sort=price_asc", nil ],
      [ "search /es/listings?q=rtx",                 "/es/listings?q=rtx",                       nil ],
      [ "listing show",                              "/es/listings/#{listing.slug}",             nil ],
      [ "store show",                                "/es/stores/#{store.slug}",                 nil ],
      [ "pc-finder results",                         "/es/pc-finder/results?games[]=fortnite&resolution=1440p&fps=144&budget=1200-2000", nil ],
      [ "api listings index",                        "/api/v1/listings",                         nil ],
      [ "api listing show",                          "/api/v1/listings/#{listing.slug}",         nil ],
      [ "admin dashboard",                           "/es/admin",                                admin ],
      [ "admin moderation queue",                    "/es/admin/moderations",                    admin ],
      [ "sell dashboard",                            "/es/sell",                                 seller ]
    ]

    rows = pages.map do |label, path, user|
      sess, db_session = open_session(target, user, created_sessions)
      Rails.cache.clear
      cold = measure(sess, path, sql_samples)
      warm = measure(sess, path, sql_samples)
      { label:, path:, cold:, warm:, cache_control: sess.response.headers["Cache-Control"] }
    end

    ActiveSupport::Notifications.unsubscribe(subscriber)

    # Read-only contract: remove every Session row this script created.
    created_sessions.each(&:destroy)

    report(rows)
  end

  def self.open_session(target, user, created_sessions)
    sess = ActionDispatch::Integration::Session.new(target)
    if user
      db_session = user.sessions.create!
      created_sessions << db_session
      # Same signing dance as test/test_helpers/session_test_helper.rb: sign
      # in a throwaway jar, copy the serialized value into the session's jar.
      ActionDispatch::TestRequest.create.cookie_jar.tap do |jar|
        jar.signed[:session_id] = db_session.id
        sess.cookies[:session_id] = jar[:session_id]
      end
    end
    [ sess, db_session ]
  end

  def self.measure(sess, path, sql_samples)
    sql_samples.clear
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    # Host header: the dev HostAuthorization middleware only allows localhost
    # hosts, while Integration::Session defaults to www.example.com.
    sess.get path, headers: { "host" => "localhost:3000" }
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
    {
      status: sess.response.status,
      ms:,
      queries: sql_samples.size,
      sql_ms: sql_samples.sum.round(1)
    }
  end

  def self.report(rows)
    stamp = Time.now.utc.strftime("%Y%m%d_%H%M%S")
    out = []
    out << "PCMarket perf baseline — label=#{LABEL} env=#{Rails.env} #{stamp}"
    out << "cache=#{Rails.cache.class} perform_caching=#{ActionController::Base.perform_caching}"
    out << ""
    header = format("%-34s | %5s %8s %5s %8s | %5s %8s %5s %8s | %s",
                    "page", "status", "cold ms", "q", "cold SQL", "status", "warm ms", "q", "warm SQL", "cache-control (warm)")
    out << header
    out << "-" * header.length
    rows.each do |r|
      out << format(
        "%<label>-34s | %5<cs>d %8<cms>g %5<cq>d %8<csq>g | %5<ws>d %8<wms>g %5<wq>d %8<wsq>g | %<cc>s",
        label: r[:label],
        cs: r[:cold][:status], cms: r[:cold][:ms], cq: r[:cold][:queries], csq: r[:cold][:sql_ms],
        ws: r[:warm][:status], wms: r[:warm][:ms], wq: r[:warm][:queries], wsq: r[:warm][:sql_ms],
        cc: r[:cache_control].to_s
      )
    end
    text = out.join("\n")
    puts text

    dir = Rails.root.join("tmp/perf")
    FileUtils.mkdir_p(dir)
    file = dir.join("#{LABEL}_#{stamp}.txt")
    File.write(file, "#{text}\n\n--- paths ---\n#{rows.map { |r| "#{r[:label]} -> #{r[:path]}" }.join("\n")}\n")
    puts "\nwritten: #{file}"
  end
end

begin
  PerfBaseline.run!
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "perf_baseline failed: #{e.class}: #{e.message}"
  puts e.full_message(highlight: false)
  exit 1
end
