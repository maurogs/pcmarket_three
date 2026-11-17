# frozen_string_literal: true

# YJIT in production: enable the method JIT when the Ruby build provides it.
# YJIT cuts Rails request CPU time meaningfully with no code changes; keeping
# the guard production-only leaves dev reloads fast, and the defined? check
# makes this a no-op on Ruby builds compiled without YJIT (or on JRuby/Truffle).
if Rails.env.production? && defined?(RubyVM::YJIT) && RubyVM::YJIT.available? && !RubyVM::YJIT.enabled?
  begin
    RubyVM::YJIT.enable
  rescue StandardError => e
    Rails.logger.warn("YJIT could not be enabled: #{e.message}")
  end
end
