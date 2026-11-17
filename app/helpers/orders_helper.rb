module OrdersHelper
  # Public tracking URL for a shipped order, per carrier. Returns nil when
  # there is no tracking number or the carrier has no lookup page.
  TRACKING_URLS = {
    "Correos" => ->(t) { "https://www.correos.es/es/es/particulares/seguir-envio/#{ERB::Util.url_encode(t)}" },
    "SEUR" => ->(t) { "https://www.seur.com/es/area-clientes/detailEnvioSeur#{ERB::Util.url_encode(t)}" },
    "MRW" => ->(t) { "https://www.mrw.es/localizacion/?numEnvio=#{ERB::Util.url_encode(t)}" },
    "GLS" => ->(t) { "https://gls-group.com/ES/es/localizacion-de-envios?match=#{ERB::Util.url_encode(t)}" },
    "DHL" => ->(t) { "https://www.dhl.com/es-es/home/home.html?submit=Enviar+buscar+referencia&id=%23track-search-bar&lang=es&loc=es&idc=es&track-preference=es&mailNo=#{ERB::Util.url_encode(t)}" },
    "UPS" => ->(t) { "https://www.ups.com/track?loc=es_ES&tracknum=#{ERB::Util.url_encode(t)}" }
  }.freeze

  def tracking_url(order)
    builder = TRACKING_URLS[order.carrier]
    return nil if builder.nil? || order.tracking_number.blank?

    builder.call(order.tracking_number)
  end

  def carrier_options_for_select
    Order::CARRIERS.map { |carrier| [ t("orders.carrier.#{carrier}"), carrier ] }
  end

  # "12/11/2026, 18:30"-style step stamps for the order timeline.
  def order_step_time(order, step)
    time = order.step_times[step]
    time && l(time, format: :long)
  end

  def shipping_address_lines(order)
    snapshot = order.shipping_address.to_h
    [
      snapshot["full_name"],
      [ snapshot["line1"], snapshot["line2"] ].compact_blank.join(", "),
      [ snapshot["postal_code"], snapshot["city"] ].compact_blank.join(" – "),
      snapshot["region"],
      t("countries.#{snapshot["country_code"].to_s.downcase}")
    ].compact_blank
  end
end
