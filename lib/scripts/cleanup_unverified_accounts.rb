# frozen_string_literal: true

# Limpieza de cuentas de spam con el criterio del censo, tarea 1 del plan
# antibots. La clasificación vive en AccountCleanupPlan; aquí está la
# ejecución.
#
# POR DEFECTO NO ESCRIBE NADA. Simula, cuenta y enseña muestras. Para actuar
# de verdad hay que pasar APPLY=1 de forma explícita.
#
#   # simulación, lo normal
#   RAILS_ENV=production bundle exec rails runner lib/scripts/cleanup_unverified_accounts.rb
#
#   # ejecución real
#   APPLY=1 ADMIN_EMAIL=persona@ayuntamiento bundle exec rails runner lib/scripts/cleanup_unverified_accounts.rb
#
# Variables:
#   APPLY=1            ejecuta de verdad. Sin ella, solo simula.
#   ADMIN_EMAIL        cuenta administradora que figura como autora de los
#                      bloqueos. Obligatoria al aplicar.
#   PENDIENTE=borrar   qué hacer con el grupo que el Ayuntamiento dejó en
#                      decisión. Por defecto no se toca.
#   BLOQUEADAS=borrar  borra también las cuentas que ya estaban bloqueadas.
#                      Por defecto no se tocan.
#   LIMITE=100         actúa solo sobre las primeras N cuentas de cada grupo.
#                      Útil para una primera pasada corta en pre.
#   REGISTRO=ruta      fichero de registro. Por defecto tmp/limpieza_<fecha>.log
#
# El registro anota una línea por cuenta con la acción realizada, así que si la
# ejecución se corta se puede relanzar: las cuentas ya tratadas se saltan.
#
# Antes de hacer nada comprueba que el bucket de ActiveStorage no es el de
# producción cuando el entorno no lo es, porque borrar una cuenta purga su
# avatar y las credenciales de AWS son las mismas en los dos servidores.

require "set"

$stdout.sync = true

APLICAR = %w[1 true si sí yes].include?(ENV["APPLY"].to_s.downcase)
PENDIENTE = ENV.fetch("PENDIENTE", "conservar")
BLOQUEADAS = ENV.fetch("BLOQUEADAS", "conservar")
LIMITE = ENV["LIMITE"].presence&.to_i
MOTIVO = "Limpieza de cuentas de spam acordada con el Ayuntamiento, octubre de 2026. " \
         "Cuenta sin verificación censal, sin participación y con señales de spam."
SELLO = Time.current.strftime("%Y%m%d_%H%M")
REGISTRO = ENV.fetch("REGISTRO", Rails.root.join("tmp", "limpieza_#{SELLO}.log").to_s)

# Borrar una cuenta purga su avatar, y el avatar vive en S3. Los dos entornos
# usan el mismo nombre de servicio (:amazon) y la misma clave de AWS: lo único
# que separa el bucket de pre del de producción es una línea de secrets.yml.
# Si alguna vez se copia el secrets.yml de producción a pre, un ensayo
# borraría ficheros reales, así que aquí se comprueba antes de empezar.
BUCKET_PRODUCCION = "santcugat-pro"
SERVICIO = ActiveStorage::Blob.service
BUCKET = SERVICIO.try(:bucket)&.name || SERVICIO.try(:root) || "desconocido"

if BUCKET == BUCKET_PRODUCCION && !Rails.env.production?
  abort(
    "ALTO: el entorno es #{Rails.env} pero el almacenamiento apunta al bucket de PRODUCCIÓN " \
    "(#{BUCKET}). Borrar cuentas aquí purgaría avatares reales. Revisa la clave " \
    "storage.s3.bucket en shared/config/secrets.yml antes de seguir."
  )
end
warn("AVISO: en producción el bucket esperado era #{BUCKET_PRODUCCION} y es #{BUCKET}.") if Rails.env.production? && BUCKET != BUCKET_PRODUCCION

def log(mensaje)
  puts "[#{Time.current.strftime('%H:%M:%S')}] #{mensaje}"
end

# Al bloquear, Decidim envía un correo a la persona con el motivo. En una
# operación masiva eso serían más de mil avisos a direcciones casi todas
# falsas, así que se anula durante la ejecución de este script.
class CorreoAnulado
  def deliver_later(*) = nil
  def deliver_now(*) = nil
end

module SinCorreoDeBloqueo
  def notify(*) = CorreoAnulado.new
end

Decidim::BlockUserMailer.singleton_class.prepend(SinCorreoDeBloqueo)

plan = AccountCleanupPlan.new
log "Clasificando cuentas..."
decisiones = plan.decisions
recuento = plan.counts

ETIQUETAS = {
  gestion: "Conservar: administración, roles o participantes privadas",
  gestionada: "Conservar: votaron sin registrarse, identificándose contra el censo",
  verificada: "Conservar: verificación censal vigente o pasada",
  participo: "Conservar: participación anterior a noviembre de 2020",
  pendiente: "Grupo pendiente: con contenido y sin señales de spam",
  bloquear: "Bloquear y ocultar: con contenido y señales de spam",
  borrar: "Borrar: sin ningún contenido",
  ya_bloqueada: "Ya bloqueadas por administración"
}.freeze

puts
puts "Plan de limpieza #{APLICAR ? 'EJECUCIÓN REAL' : '(SIMULACIÓN, no se escribe nada)'}"
puts "-" * 78
ETIQUETAS.each do |decision, etiqueta|
  puts format("  %-62s %8d", etiqueta, recuento.fetch(decision, 0))
end
puts format("  %-62s %8d", "Total de cuentas no borradas", decisiones.size)
puts
desglose = plan.verification_breakdown
puts "De dónde sale la protección de las verificadas"
puts format("  %-62s %8d", "Con autorización censal vigente", desglose[:con_autorizacion_vigente])
puts format("  %-62s %8d", "Solo por el historial de versions, ya revocada", desglose[:solo_por_historial])
puts format("  %-62s %8d", "Por transferencia de autorización", desglose[:por_transferencia])
puts


a_borrar = plan.ids_for(:borrar)
a_bloquear = plan.ids_for(:bloquear)
pendientes = plan.ids_for(:pendiente)
ya_bloqueadas = plan.ids_for(:ya_bloqueada)

a_borrar += pendientes if PENDIENTE == "borrar"
a_borrar += ya_bloqueadas if BLOQUEADAS == "borrar"

puts "Acciones previstas"
puts format("  %-62s %8d", "Cuentas a borrar, anonimizando", a_borrar.size)
puts format("  %-62s %8d", "Cuentas a bloquear con ocultación de contenido", a_bloquear.size)
puts format("  %-62s %8d", "Cuentas que no se tocan", decisiones.size - a_borrar.size - a_bloquear.size)
puts "  Grupo pendiente: #{PENDIENTE == 'borrar' ? 'se borra' : 'no se toca'} · Ya bloqueadas: #{BLOQUEADAS == 'borrar' ? 'se borran' : 'no se tocan'}"
puts "  Límite por grupo: #{LIMITE || 'sin límite'}"
puts

# Medido contra S3 el 8 de octubre de 2026: 88 ms por avatar, entre el DELETE
# del original y el LIST con borrado por lotes de sus variantes. Con más de
# cien mil avatares eso son horas, así que conviene saberlo antes de empezar.
SEGUNDOS_POR_AVATAR = 0.088
ids_estimados = LIMITE ? a_borrar.first(LIMITE) : a_borrar
con_avatar = ids_estimados.each_slice(5_000).sum { |lote| Decidim::User.where(id: lote).joins(:avatar_attachment).count }
puts "Almacenamiento"
puts format("  %-62s %8s", "Bucket de ActiveStorage", BUCKET)
puts format("  %-62s %8d", "Cuentas a borrar que tienen avatar", con_avatar)
puts format("  %-62s %8.1f h", "Tiempo estimado solo en purgar avatares en S3", con_avatar * SEGUNDOS_POR_AVATAR / 3600.0)
puts

# Al azar y no las primeras por id: las primeras son siempre las más antiguas,
# que es justo la muestra menos representativa de un grupo donde la mayoría son
# cuentas recientes.
def muestra(ids, titulo, cuantas = 8)
  return if ids.empty?

  elegidas = ids.sample(cuantas)
  puts "#{titulo}: muestra al azar de #{elegidas.size} sobre #{ids.size}"
  Decidim::User.where(id: elegidas).order(:created_at).each do |u|
    señas = [u.personal_url.presence && "url", u.about.presence && "texto"].compact.join(" ")
    puts format("  %-8s %-26s %-30s %s  %s", u.id, u.name.to_s[0, 24], u.email.to_s[0, 28], u.created_at.to_date, señas)
  end
  puts
end

# El reparto por año es lo que de verdad necesita el Ayuntamiento para decidir:
# una cuenta de 2017 sin contenido es un vecino que se registró y no volvió,
# una de 2025 sin contenido es un bot. El criterio las trata igual.
def por_anyo(ids, titulo)
  return if ids.empty?

  conteo = Hash.new(0)
  ids.each_slice(5_000) do |lote|
    Decidim::User.where(id: lote).pluck(:created_at).each { |fecha| conteo[fecha.year] += 1 }
  end
  escala = [conteo.values.max / 40.0, 1].max

  puts "#{titulo}: reparto por año de registro"
  conteo.sort.each do |anyo, n|
    puts format("  %d %8d  %s", anyo, n, "#" * [(n / escala).round, 1].max)
  end
  puts
end

por_anyo(a_borrar, "A borrar")
muestra(a_borrar, "A borrar")
muestra(a_bloquear, "A bloquear, con la señal de spam que las delata")
muestra(pendientes, "Grupo pendiente, para que lo revise el Ayuntamiento")

unless APLICAR
  puts "Simulación terminada. Nada ha cambiado en la base de datos."
  puts "Para ejecutar de verdad: APPLY=1 ADMIN_EMAIL=... #{$PROGRAM_NAME.split('/').last}"
  exit
end

administradora = Decidim::User.find_by(email: ENV.fetch("ADMIN_EMAIL", nil), admin: true)
abort("Define ADMIN_EMAIL con el correo de una cuenta administradora: figura como autora de los bloqueos.") if administradora.nil?

tratadas = Set.new
if File.exist?(REGISTRO)
  File.foreach(REGISTRO) { |linea| tratadas << linea.split(" ", 2).first.to_i }
  log "Registro existente con #{tratadas.size} cuentas ya tratadas: se saltan."
end

registro = File.open(REGISTRO, "a")
registro.sync = true
log "Registro en #{REGISTRO}"

def anotar(registro, id, accion, detalle = nil)
  registro.puts([id, accion, detalle].compact.join(" "))
end

borradas = 0
falladas = 0
ids = LIMITE ? a_borrar.first(LIMITE) : a_borrar
log "Borrando #{ids.size} cuentas..."
ids.each_slice(500) do |lote|
  Decidim::User.where(id: lote).find_each do |user|
    next if tratadas.include?(user.id)

    formulario = Decidim::DeleteAccountForm.from_params(delete_reason: MOTIVO).with_context(current_user: user)
    Decidim::DestroyAccount.call(formulario) do
      on(:ok) do
        borradas += 1
        anotar(registro, user.id, "borrada")
      end
      on(:invalid) do
        falladas += 1
        anotar(registro, user.id, "error_borrado")
      end
    end
  rescue StandardError => e
    falladas += 1
    anotar(registro, user.id, "excepcion_borrado", e.class.name)
  end
  log "  #{borradas} borradas, #{falladas} con error"
end

bloqueadas = 0
ids = LIMITE ? a_bloquear.first(LIMITE) : a_bloquear
log "Bloqueando #{ids.size} cuentas con ocultación de su contenido..."
ids.each_slice(200) do |lote|
  Decidim::User.where(id: lote).find_each do |user|
    next if tratadas.include?(user.id)

    formulario = Decidim::Admin::BlockUserForm.from_params(user_id: user.id, justification: MOTIVO, hide: true)
                                              .with_context(current_user: administradora, current_organization: user.organization)
    Decidim::Admin::BlockUser.call(formulario) do
      on(:ok) do
        bloqueadas += 1
        anotar(registro, user.id, "bloqueada")
      end
      on(:invalid) do
        falladas += 1
        anotar(registro, user.id, "error_bloqueo")
      end
    end
  rescue StandardError => e
    falladas += 1
    anotar(registro, user.id, "excepcion_bloqueo", e.class.name)
  end
  log "  #{bloqueadas} bloqueadas, #{falladas} con error"
end

registro.close
puts
log "Terminado: #{borradas} borradas, #{bloqueadas} bloqueadas, #{falladas} con error."
log "Quedan #{Decidim::User.where(deleted_at: nil).count} cuentas sin borrar en la base."
log "La ocultación del contenido de las bloqueadas la hace Decidim en segundo plano: revisa que Sidekiq procese la cola."
nil
