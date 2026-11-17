module Authentication
  extend ActiveSupport::Concern

  included do
    # Resume the session on every controller — public pages still want to know
    # who the visitor is (etags, moderation affordances). Only the enforcement
    # callback is skipped by allow_unauthenticated_access.
    before_action :resume_session
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
      Current.session
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
        # Carry the guest cart over: merge it into the user's cart and drop
        # the cookie cart (see Carts::Merge for the rules).
        Carts::Merge.call(from: Cart.for_token(cookies.signed[:cart_token]), to: Cart.for_user(user))
        cookies.delete(:cart_token)
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
