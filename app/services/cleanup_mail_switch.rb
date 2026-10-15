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
# Es una cuenta y no una bandera porque la limpieza se lanza en varios
# procesos a la vez, repartidos por rangos de id. Con una bandera, el primero
# en terminar reactivaría el correo mientras los demás siguen bloqueando
# cuentas. Cada proceso suma al entrar y resta al salir; el correo sigue
# callado mientras quede alguno.
#
# Caduca sola a las 12 horas: si un proceso muere sin restar, el correo se
# recupera sin intervención en lugar de quedarse mudo para siempre.
class CleanupMailSwitch
  CLAVE = "limpieza:correo_silenciado"
  CADUCIDAD = 12 * 60 * 60

  class << self
    def silenciado?
      procesos_silenciando.positive?
    end

    # Devuelve cuántos procesos están silenciando tras entrar este.
    def silenciar!
      redis do |r|
        cuantos = r.incr(CLAVE)
        r.expire(CLAVE, CADUCIDAD)
        cuantos
      end
    end

    # Devuelve cuántos quedan silenciando tras salir este.
    def reactivar!
      redis do |r|
        quedan = r.decr(CLAVE)
        r.del(CLAVE) if quedan <= 0
        [quedan, 0].max
      end
    end

    def procesos_silenciando
      redis { |r| r.get(CLAVE).to_i }
    rescue StandardError
      0
    end

    private

    def redis(&)
      Sidekiq.redis(&)
    end
  end

  # Se interpone en la entrega, no en la generación: así cubre cualquier correo
  # que nazca de la limpieza, venga del mailer que venga.
  module SaltarEntrega
    # Con (...) y no (*): ActionMailer::MailDeliveryJob#perform recibe tres
    # posicionales y varios argumentos con nombre, y (*) no captura los
    # segundos. En Ruby 3 se convertirían en un hash posicional de más y el
    # super reventaría con ArgumentError, rompiendo la entrega de todo el
    # correo justo cuando el interruptor está apagado, que es lo normal.
    def perform(...)
      return if CleanupMailSwitch.silenciado?

      super
    end
  end
end
