module Api
  module V1
    # Raised by API controllers for "authenticated but not allowed" cases;
    # BaseController renders it as 403 with the standard error envelope.
    class Forbidden < StandardError
    end
  end
end
