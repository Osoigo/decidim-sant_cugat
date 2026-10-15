# frozen_string_literal: true

# Interruptor para callar el correo durante la limpieza masiva de cuentas.
#
# Hace falta porque al bloquear una cuenta con ocultación de contenido, Decidim
# publica un ResourceHiddenEvent por cada contenido ocultado, con
# extra[:force_email] = true. Y EmailNotificationGenerator#should_send_email?
# devuelve ese valor tal cual, así que el aviso se envía aunque la cuenta tenga
# las notificaciones en "none", que es justo lo que BlockUser acaba de hacer.
#
# En el ensayo del 15 de octubre de 2026, bloquear 248 cuentas disparó 1.381
# EmailNotificationGeneratorJob y 231 entregas reales. En pre cayeron en el
# sumidero :test; en producción habrían salido del servidor del Ayuntamiento
# hacia direcciones de bots.
#
# El parche que anula BlockUserMailer en el script no sirve aquí: estos correos
# los genera Sidekiq, en otro proceso. Por eso la bandera vive en Redis, que
# comparten el script y los workers, y por eso se interpone en el propio
# trabajo de entrega.
#
# Caduca sola a las 12 horas: si algo deja la bandera puesta, el correo se
# recupera sin intervención en lugar de quedarse mudo para siempre.
class CleanupMailSwitch
  CLAVE = "limpieza:correo_silenciado"
  CADUCIDAD = 12 * 60 * 60

  class << self
    def silenciado?
      redis { |r| r.get(CLAVE).present? }
    rescue StandardError
      false
    end

    def silenciar!
      redis { |r| r.set(CLAVE, Time.current.iso8601, ex: CADUCIDAD) }
      true
    end

    def reactivar!
      redis { |r| r.del(CLAVE) }
      true
    end

    private

    def redis(&)
      Sidekiq.redis(&)
    end
  end

  # Se interpone en la entrega, no en la generación: así cubre cualquier correo
  # que nazca de la limpieza, venga del mailer que venga.
  module SaltarEntrega
    def perform(*)
      return if CleanupMailSwitch.silenciado?

      super
    end
  end
end
