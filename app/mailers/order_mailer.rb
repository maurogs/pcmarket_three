# Transactional e-mails for the order lifecycle. Every action runs in the
# recipient's locale. Checkout posts `new_sale` (seller) and `confirmation`
# (buyer); Orders::Transition posts `payment_received` (seller, direct
# mode) and `order_shipped` (buyer).
class OrderMailer < ApplicationMailer
  def new_sale
    @order = params[:order]
    @recipient = params[:recipient]

    mail_to_locale do
      mail to: @recipient.email_address, subject: t(".subject", number: @order.number)
    end
  end

  def confirmation
    @order = params[:order]
    @recipient = params[:recipient]

    mail_to_locale do
      mail to: @recipient.email_address, subject: t(".subject", number: @order.number)
    end
  end

  def payment_received
    @order = params[:order]
    @recipient = params[:recipient]

    mail_to_locale do
      mail to: @recipient.email_address, subject: t(".subject", number: @order.number)
    end
  end

  def order_shipped
    @order = params[:order]
    @recipient = params[:recipient]

    mail_to_locale do
      mail to: @recipient.email_address, subject: t(".subject", number: @order.number)
    end
  end

  private

  def mail_to_locale(&block)
    locale = @recipient.locale.presence || I18n.default_locale.to_s
    I18n.with_locale(locale, &block)
  end
end
