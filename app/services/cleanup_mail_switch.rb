# frozen_string_literal: true

# Apagón del correo durante la limpieza masiva de cuentas.
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
# los genera Sidekiq, en otro proceso. Por eso el apagón se interpone en el
# propio trabajo de entrega, que es por donde pasan todos.
#
# Y está apagado sin condición, no detrás de una bandera, porque esta rama no
# se fusiona en master: se despliega para la ventana de limpieza y al terminar
# se vuelve a desplegar master, que es lo que devuelve el correo.
#
# Con una bandera había tres maneras de que se escapara un correo:
#
#   - Las colas. Ocultar el contenido de una cuenta bloqueada encola un aviso
#     por cada contenido —1.381 en el ensayo de pre con 248 cuentas— y los
#     workers los digieren minutos después de que el script haya terminado. Al
#     salir el último proceso, la bandera caía con miles de avisos aún en cola.
#   - Un proceso que muriera sin restar de la cuenta, o la caducidad de 12
#     horas, devolvían el correo a media limpieza.
#   - Un Redis que no respondiera: el apagón se consultaba en la entrega de
#     cada correo y ante la duda dejaba pasar.
#
# Lo que cuesta: mientras esta rama esté desplegada no sale ni un correo de la
# plataforma. Es asumible porque está cerrada durante la ventana, y es el
# orden de reapertura acordado: primero volver a master, después quitar el
# mantenimiento. Antes de volver a master hay que comprobar que las colas
# están vacías, porque lo que quede encolado sí se entregaría.
#
# La cuenta de procesos se conserva para la traza: dice cuántas limpiezas hay
# corriendo, pero ya no decide si el correo sale.
class CleanupMailSwitch
  CLAVE = "limpieza:correo_silenciado"
  CADUCIDAD = 12 * 60 * 60
  APAGADO_POR_CODIGO = true

  class << self
    def silenciado?
      APAGADO_POR_CODIGO || procesos_silenciando.positive?
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
