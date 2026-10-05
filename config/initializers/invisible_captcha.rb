# frozen_string_literal: true

# Endurece el formulario de alta.
#
# Decidim trae invisible_captcha con los campos trampa activados pero con la
# comprobación de tiempo desactivada, tanto en la 0.30 como en las versiones
# nuevas (decidim-core/config/initializers/invisible_captcha.rb). Aquí se
# activa: un formulario enviado en menos de cinco segundos desde que se cargó
# la página se rechaza.
#
# La marca de tiempo vive en la sesión, así que la página de alta no puede
# servirse desde una caché compartida ni desde un proxy que la guarde: sin
# marca en sesión, invisible_captcha trata el envío como spam.
InvisibleCaptcha.setup do |config|
  config.timestamp_enabled = true
  config.timestamp_threshold = 5
end

# Decidim y sus módulos registran el filtro sin acotarlo a ninguna acción:
# tanto el controlador de registro (decidim-core) como el de encuestas
# (decidim-forms) lo aplican a todas. Con la comprobación de tiempo activada,
# la primera visita a esas páginas no tiene marca en sesión, el gem la trata
# como spam y las deja inaccesibles. La comprobación solo tiene sentido cuando
# se envía el formulario, así que se limita a las peticiones de escritura.
module InvisibleCaptchaOnSubmitOnly
  private

  def timestamp_spam?(_options = {})
    return false unless request.post? || request.patch? || request.put?

    super
  end
end

ActiveSupport.on_load(:action_controller_base) do
  prepend InvisibleCaptchaOnSubmitOnly
end
