# Creates the seller's personal store on their first listing. Every listing
# belongs to a Store (the public storefront), but users only manage one once
# the store UI ships — so an individual store named after the username is
# created on demand, idempotently.
module Stores
  class EnsureFor
    def initialize(user)
      @user = user
    end

    def call
      @user.store || @user.create_store!(name: @user.username, store_type: :individual)
    end
  end
end
