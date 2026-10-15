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
#   DESDE / HASTA      rango de id que trata este proceso. Permite lanzar
#                      varios en paralelo sobre rangos disjuntos, que es lo que
#                      acorta la ventana: el coste por cuenta son unos 0,37 s
#                      de base de datos y no se puede bajar mucho más.
#                      lib/scripts/cleanup_ranges.rb calcula los rangos.
#   REGISTRO=ruta      fichero de registro. Por defecto tmp/limpieza_<fecha>.log
#
# El registro anota una línea por cuenta con la acción realizada, así que si la
# ejecución se corta se puede relanzar: las cuentas ya tratadas se saltan.
#
# Antes de hacer nada comprueba que el bucket de ActiveStorage no es el de
# producción cuando el entorno no lo es, porque borrar una cuenta purga su
# avatar y las credenciales de AWS son las mismas en los dos servidores.
#
# Durante la ejecución silencia el correo en todos los procesos con
# CleanupMailSwitch, porque ocultar el contenido de una cuenta bloqueada genera
# un aviso por cada contenido y esos los manda Sidekiq, fuera de este proceso.
#
# También agrupa los borrados en S3 con BatchedStoragePurge, porque purgar los
# avatares de uno en uno son horas de espera. Las claves enviadas quedan
# anotadas en un fichero junto al registro.

require "set"

$stdout.sync = true

APLICAR = %w[1 true si sí yes].include?(ENV["APPLY"].to_s.downcase)
PENDIENTE = ENV.fetch("PENDIENTE", "conservar")
BLOQUEADAS = ENV.fetch("BLOQUEADAS", "conservar")
LIMITE = ENV["LIMITE"].presence&.to_i
MOTIVO = "Limpieza de cuentas de spam acordada con el Ayuntamiento, octubre de 2026. " \
         "Cuenta sin verificación censal, sin participación y con señales de spam."
SELLO = Time.current.strftime("%Y%m%d_%H%M")
DESDE = ENV["DESDE"].presence&.to_i
HASTA = ENV["HASTA"].presence&.to_i
SUFIJO = DESDE || HASTA ? "_#{DESDE || 'inicio'}-#{HASTA || 'fin'}" : ""
REGISTRO = ENV.fetch("REGISTRO", Rails.root.join("tmp", "limpieza_#{SELLO}#{SUFIJO}.log").to_s)

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

# Cada proceso trata un rango de id distinto. Las consultas que alimentan el
# criterio siguen siendo globales: lo que se reparte es a qué cuentas se
# aplica, no con qué datos se decide, así que la clasificación no cambia por
# trocearla.
ambito = Decidim::User.where(deleted_at: nil)
ambito = ambito.where(id: DESDE..) if DESDE
ambito = ambito.where(id: ..HASTA) if HASTA

plan = AccountCleanupPlan.new(scope: ambito)
log "Clasificando cuentas#{DESDE || HASTA ? " con id de #{DESDE || 'inicio'} a #{HASTA || 'fin'}" : ''}..."
decisiones = plan.decisions
recuento = plan.counts

ETIQUETAS = {
  gestion: "Conservar: administración, roles o participantes privadas",
  gestionada: "Conservar: votaron sin registrarse, identificándose contra el censo",
  verificada: "Conservar: verificación censal vigente o pasada",
  participo: "Conservar: participación anterior a noviembre de 2020",
  veterana_activa: "Conservar: anterior a 2021 y con acceso en los últimos 3 años",
  pendiente: "Grupo pendiente: con contenido y sin señales de spam",
  bloquear: "Bloquear y ocultar: con contenido y señales de spam",
  borrar: "Borrar: sin ningún contenido",
  ya_bloqueada: "Ya bloqueadas por administración"
}.freeze

puts
puts "Plan de limpieza #{APLICAR ? 'EJECUCIÓN REAL' : '(SIMULACIÓN, no se escribe nada)'}"
puts "Rango de id: #{DESDE || 'inicio'} a #{HASTA || 'fin'}" if DESDE || HASTA
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

# El parche de BlockUserMailer de arriba solo vale en este proceso. Los avisos
# de contenido ocultado los genera Sidekiq, y esos los para CleanupMailSwitch,
# que en esta rama tiene el correo apagado por código: no depende de que este
# script entre ni salga. Lo que se lleva la cuenta es solo para la traza.
CleanupMailSwitch.silenciar!
at_exit do
  quedan = CleanupMailSwitch.reactivar!
  warn("Correo: sigue apagado por código; quedan #{quedan} limpiezas corriendo.")
end
abort("ALTO: el correo no está apagado. Revisa CleanupMailSwitch antes de seguir.") unless CleanupMailSwitch.silenciado?

# El apagón vive en el código, así que vale lo que valga el código que corre
# el worker: los avisos de la ocultación los entrega Sidekiq, no este proceso.
# Si Sidekiq arrancó antes que este release sigue con el anterior, donde el
# correo salía. Es el fallo clásico de desplegar y no reiniciar el worker.
require "sidekiq/api"
nacimiento = begin
  File.mtime(Rails.root.join("REVISION"))
rescue StandardError
  nil
end
workers = Sidekiq::ProcessSet.new.to_a
if workers.empty?
  warn("AVISO: no hay ningún worker de Sidekiq vivo. Lo que se encole esperará en la cola y se entregaría al volver a master.")
elsif nacimiento
  antiguos = workers.select { |w| Time.zone.at(w["started_at"]) < nacimiento }
  if antiguos.any?
    abort(
      "ALTO: #{antiguos.size} de #{workers.size} workers arrancaron antes de este release "       "(#{antiguos.map { |w| Time.zone.at(w['started_at']).strftime('%d/%m %H:%M') }.join(', ')} "       "frente a #{nacimiento.strftime('%d/%m %H:%M')}), así que están corriendo el código anterior "       "y entregarían los avisos de la ocultación. Reinicia Sidekiq antes de seguir."
    )
  end
  log "Workers comprobados: #{workers.size} corriendo código de este release o posterior."
end
log "Correo apagado por código mientras esta rama esté desplegada."

# Purgado de avatares por lotes. ActiveStorage borra de uno en uno, 88 ms por
# avatar medidos contra S3, y en producción hay 104.218 que purgar. La
# envoltura acumula las claves y las manda de mil en mil. Blob#service resuelve
# por el registro, así que hay que sustituir la entrada ahí, no solo el
# servicio por defecto.
NOMBRE_SERVICIO = Rails.application.config.active_storage.service.to_sym
CLAVES = REGISTRO.sub(/\.log\z/, "") + "_claves.log"
SERVICIO_REAL = ActiveStorage::Blob.service
PURGA = BatchedStoragePurge.new(SERVICIO_REAL, registro: CLAVES)
MAPA_SERVICIOS = ActiveStorage::Blob.services.send(:services)
MAPA_SERVICIOS[NOMBRE_SERVICIO] = PURGA
ActiveStorage::Blob.service = PURGA

at_exit do
  PURGA.vaciar
  MAPA_SERVICIOS[NOMBRE_SERVICIO] = SERVICIO_REAL
  ActiveStorage::Blob.service = SERVICIO_REAL
  warn("Purgado en S3: #{PURGA.claves_borradas} claves en #{PURGA.peticiones} peticiones. Quedan #{PURGA.pendientes} sin enviar.")
end
log "Purgado de avatares agrupado; claves anotadas en #{CLAVES}"

def anotar(registro, id, accion, detalle = nil)
  registro.puts([id, accion, detalle].compact.join(" "))
end

borradas = 0
falladas = 0
reparados = 0
ids = LIMITE ? a_borrar.first(LIMITE) : a_borrar
log "Borrando #{ids.size} cuentas..."
ids.each_slice(500) do |lote|
  Decidim::User.where(id: lote).find_each do |user|
    next if tratadas.include?(user.id)

    reparados += 1 if AccountNicknameRepair.call(user)
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
  PURGA.vaciar
  log "  #{borradas} borradas, #{falladas} con error, #{PURGA.claves_borradas} ficheros purgados"
end

bloqueadas = 0
ids = LIMITE ? a_bloquear.first(LIMITE) : a_bloquear
log "Bloqueando #{ids.size} cuentas con ocultación de su contenido..."
ids.each_slice(200) do |lote|
  Decidim::User.where(id: lote).find_each do |user|
    next if tratadas.include?(user.id)

    reparados += 1 if AccountNicknameRepair.call(user)
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
  PURGA.vaciar
  log "  #{bloqueadas} bloqueadas, #{falladas} con error"
end

registro.close
puts
log "Terminado: #{borradas} borradas, #{bloqueadas} bloqueadas, #{falladas} con error."
log "Apodos antiguos reparados para poder tratarlas: #{reparados}."
log "Ficheros purgados en S3: #{PURGA.claves_borradas} en #{PURGA.peticiones} peticiones, #{PURGA.prefijos_resueltos} prefijos listados."
log "Quedan #{Decidim::User.where(deleted_at: nil).count} cuentas sin borrar en la base."
log "La ocultación del contenido de las bloqueadas la hace Decidim en segundo plano: revisa que Sidekiq procese la cola."
log "El correo vuelve al desplegar master, no al salir de aquí. Antes de desplegarlo, comprueba"
log "que no quede nada en cola ni en reintentos: lo que quede se entregaría."
nil
