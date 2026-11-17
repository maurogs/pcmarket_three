require "test_helper"

# Admin contact-form inbox (Phase 7b): read-only list + detail, with an
# optional locale filter. Invalid locale params must not raise.
class Admin::ContactMessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
    @first = create_message(locale: "es", subject: "No llega mi pedido",
                            body: "Hice el pedido hace una semana y nada.", name: "Marta")
    @second = create_message(locale: "en", subject: "Invoice request",
                             body: "Could you send me an invoice, please?", name: "John")
  end

  test "index lists submissions newest first with subject and sender" do
    get admin_contact_messages_path

    assert_response :success
    assert_select "h1", text: I18n.t("admin.contact_messages.index.title")
    assert_includes response.body, "No llega mi pedido"
    assert_includes response.body, "Invoice request"
    assert_includes response.body, "marta@example.com"
    assert body_shows_newest_first?
  end

  test "index filters by locale and ignores unknown locale params" do
    # `locale` is the routing segment, so the filter param is `lang`.
    get admin_contact_messages_path(lang: "en")
    assert_includes response.body, "Invoice request"
    assert_not_includes response.body, "No llega mi pedido"

    get admin_contact_messages_path(lang: "xx")
    assert_response :success
    assert_includes response.body, "No llega mi pedido"
  end

  test "index shows the empty state when there are no messages" do
    ContactMessage.delete_all

    get admin_contact_messages_path
    assert_response :success
    assert_includes response.body, I18n.t("admin.contact_messages.index.empty")
  end

  test "show renders the full message and its metadata" do
    get admin_contact_message_path(@first)

    assert_response :success
    assert_includes response.body, "Hice el pedido hace una semana y nada."
    assert_includes response.body, "Marta"
    assert_includes response.body, "marta@example.com"
  end

  private

  def create_message(locale:, subject:, body:, name:)
    ContactMessage.create!(name: name, email: "#{name.downcase}@example.com",
                           subject: subject, body: body, locale: locale)
  end

  def body_shows_newest_first?
    response.body.index("Invoice request") < response.body.index("No llega mi pedido")
  end
end
