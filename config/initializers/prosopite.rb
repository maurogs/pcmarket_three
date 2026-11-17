# frozen_string_literal: true

# N+1 detection (Phase 8c). In development every request is scanned and any
# N+1 goes to the Rails log; tests raise instead (Prosopite.raise = true in
# config/environments/test.rb, one scan per test in test/test_helper.rb).
if Rails.env.development?
  require "prosopite/middleware/rack"
  Rails.application.config.middleware.use(Prosopite::Middleware::Rack)
end

if Rails.env.test?
  # Keep detection on app frames only (no allow_stack_paths, which would
  # hide app N+1s triggered from tests). Fixture/setup queries are excluded
  # by scanning only around the HTTP request (see test/test_helper.rb).
  Prosopite.min_n_queries = 3
  Prosopite.ignore_queries = []
end
