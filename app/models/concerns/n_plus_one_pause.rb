# Wraps intentionally per-record work in Prosopite.pause so the N+1 scanner
# (Phase 8c, test + dev only) does not flag it. The scan only runs when the
# gem is loaded, hence the defined?(Prosopite) guard in production.
module NPlusOnePause
  module_function

  def call(&)
    defined?(Prosopite) ? Prosopite.pause(&) : yield
  end
end
