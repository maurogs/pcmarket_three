module Account
  # Base for the account settings area (Phase 5): everything here requires
  # a signed-in user and renders with the account layout (sidebar).
  class BaseController < ApplicationController
    before_action :require_authentication
    layout "account"
  end
end
