# Minimal CRUD for the signed-in user's shipping addresses (account
# area). Every lookup is scoped through current_user.addresses, so other
# people's addresses 404. The first address becomes the default
# automatically; making a new one default unsets the others (Address
# model). When checkout sent the visitor here (`?from=checkout`), the
# after-save redirects go back to the checkout page.
class AddressesController < ApplicationController
  before_action :set_address, only: %i[edit update destroy]

  def index
    @addresses = current_user.addresses.order(default_desc)
  end

  def new
    @address = current_user.addresses.new
  end

  def create
    @address = current_user.addresses.new(address_params)

    if @address.save
      redirect_to after_save_url, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @address.update(address_params)
      redirect_to after_save_url, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @address.destroy
    redirect_to addresses_path, notice: t(".destroyed")
  end

  private

  def set_address
    @address = current_user.addresses.find(params[:id])
  end

  def address_params
    params.require(:address).permit(:full_name, :line1, :line2, :city, :region,
                                    :postal_code, :country_code, :phone, :default)
  end

  def default_desc
    Arel.sql('"addresses"."default" DESC, "addresses"."id"')
  end

  # Only the literal "checkout" is honoured — no open redirect.
  def from_checkout?
    params[:from] == "checkout"
  end

  def after_save_url
    from_checkout? ? checkout_path : addresses_path
  end
end
