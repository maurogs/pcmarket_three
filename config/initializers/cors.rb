# CORS for the JSON API. Only the origins listed in the API_CORS_ORIGINS
# env var (comma-separated) may call /api/* from a browser; unset means no
# cross-origin browser access at all (native apps don't need CORS).
origins = ENV["API_CORS_ORIGINS"].to_s.split(",").map(&:strip).reject(&:blank?)

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins origins
    resource "/api/*",
             headers: :any,
             methods: %i[get post put patch delete options head],
             expose: %w[Link ETag],
             max_age: 600
  end
end
