# frozen_string_literal: true

# Comprueba si ya se puede volver a desplegar master después de la limpieza.
#
# Mientras esta rama está desplegada no sale ni un correo: CleanupMailSwitch lo
# apaga en el código. Eso tiene un filo, y es el único que queda: los avisos que
# la limpieza encoló y todavía estén esperando se entregarían en cuanto master
# vuelva. Son avisos de contenido ocultado, casi todos a direcciones de bots,
# por contenido que acabamos de ocultar precisamente por eso.
#
# Con esta rama corriendo las colas se vacían solas: los trabajos de entrega se
# ejecutan y se descartan. Lo que hay que hacer es esperar a que terminen, y
# esto dice si ya terminaron.
#
#   RAILS_ENV=production bundle exec rails runner lib/scripts/cleanup_mail_queue_check.rb
#
# Es de solo lectura: no borra trabajos ni toca el apagón.

require "sidekiq/api"

# Lo que acaba en un correo: la entrega en sí, los generadores de avisos y el
# publicador de eventos, que es quien los encadena.
CORREO = /Mail|Notification|EventPublisher/

MUESTRA = 2_000

def clases(trabajos)
  trabajos.first(MUESTRA).group_by { |t| t.display_class.to_s }.transform_values(&:size).sort_by { |_, n| -n }
end

def pintar(titulo, pares)
  return if pares.empty?

  puts titulo
  pares.each { |clase, n| puts format("  %-60s %6d%s", clase, n, clase.match?(CORREO) ? "  <- correo" : "") }
  puts
end

apagado = CleanupMailSwitch.silenciado?
puts "Entorno #{Rails.env}. Correo apagado por el código desplegado: #{apagado ? 'sí' : 'NO'}."
puts "Si dice NO, master ya está desplegado y esta comprobación llega tarde." unless apagado
puts

colas = Sidekiq::Queue.all.reject { |cola| cola.size.zero? }
en_vuelo = Sidekiq::Workers.new.to_a
reintentos = Sidekiq::RetrySet.new
programados = Sidekiq::ScheduledSet.new
muertos = Sidekiq::DeadSet.new

puts format("encolados %d · en vuelo %d · reintentos %d · programados %d · muertos %d",
            colas.sum(&:size), en_vuelo.size, reintentos.size, programados.size, muertos.size)
puts

pintar("En cola:", colas.map { |cola| [cola.name, cola.size] })
pintar("En vuelo:", en_vuelo.group_by { |_, _, trabajo| trabajo["payload"]["wrapped"] || trabajo["payload"]["class"] }
                           .transform_values(&:size).sort_by { |_, n| -n })
pintar("En reintento:", clases(reintentos))
pintar("Programados:", clases(programados))

# Los muertos no se entregan solos: hacen falta 25 intentos fallidos para
# llegar ahí y nadie los reencola salvo a mano. Se informa, no bloquean.
pintar("Muertos (no se entregan salvo que alguien los reencole):", clases(muertos))

pendientes = colas.sum(&:size) + en_vuelo.size
aplazados = [reintentos, programados].sum do |conjunto|
  conjunto.first(MUESTRA).count { |trabajo| trabajo.display_class.to_s.match?(CORREO) }
end

puts "---"
if pendientes.positive?
  puts "ESPERA: quedan #{pendientes} trabajos por digerir. Con esta rama desplegada se descartan"
  puts "al ejecutarse, así que vuelve a mirar en un par de minutos."
elsif aplazados.positive?
  puts "ESPERA: no hay nada en cola, pero #{aplazados} trabajos de correo están en reintento o"
  puts "programados para más tarde. Si master vuelve antes de que les toque, se entregarían."
  puts "Revisa arriba de qué son: si son avisos de la limpieza, se pueden descartar con"
  puts '  Sidekiq::RetrySet.new.each { |t| t.delete if t.display_class.match?(/Mail|Notification/) }'
  puts "ejecutado con esta rama todavía desplegada."
else
  puts "LISTO: no queda nada que pudiera entregarse. Se puede desplegar master."
  puts "Después del despliegue, acuérdate de quitar el modo de mantenimiento, en ese orden."
end
nil
