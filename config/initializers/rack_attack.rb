# Rack::Attack request throttling. Rails' own rate_limit covers login/password
# forms in controllers; this is the coarse network-level layer.
Rack::Attack.throttle("logins/ip", limit: 20, period: 1.hour) do |req|
  req.post? && req.path.end_with?("/session") ? req.ip : nil
end
