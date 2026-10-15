# frozen_string_literal: true

# Informe de cierre de la limpieza: comprueba contra la base de datos que lo
# que se hizo es lo que se acordó, y dice si ya se puede devolver master.
#
#   RAILS_ENV=production bundle exec rails runner lib/scripts/cleanup_closing_report.rb
#
# Es de solo lectura: no borra, no bloquea y no toca el apagón del correo.
#
# La parte que importa es la de las comprobaciones a posteriori. Antes de
# ejecutar, el plan dice lo que va a pasar; después, buena parte de la prueba
# se ha ido con los datos: al borrar una cuenta se vacían nombre, apodo,
# correo, URL y biografía, así que no se puede volver a clasificar y comparar.
#
# Lo que sí sobrevive al borrado, y por eso se usa aquí como prueba:
#
#   - managed, officialized_at, roles y admin, que distinguen a las cuentas de
#     gestión y a las que votaron sin registrarse identificándose en el censo
#   - created_at y last_sign_in_at, de donde salen la antigüedad y el uso
#   - las autorizaciones, que DestroyAccount no destruye: si una cuenta
#     borrada tuviera una verificación censal concedida, el criterio habría
#     fallado y aquí se vería
#
# Si alguna de esas comprobaciones sale distinta de cero, hay una cuenta
# borrada que no debía borrarse y la copia previa a la limpieza está en el
# servidor de producción, en /home/debian/database.dump.20261015-antes-limpieza.gpg
#
# Con PLAN=0 se salta la clasificación completa, que es la parte lenta.

require "shellwords"

DIR = ENV.fetch("REGISTROS", "/var/www/decidim/shared/limpieza")
CON_PLAN = ENV.fetch("PLAN", "1") != "0"
HOY = Time.zone.today.beginning_of_day
AUTOR = "Decidim::UserBaseEntity"

def titulo(texto)
  puts
  puts texto
  puts "-" * 78
end

def linea(etiqueta, valor)
  valor = ActiveSupport::NumberHelper.number_to_delimited(valor) if valor.is_a?(Integer)
  puts format("  %-62s %12s", etiqueta, valor)
end

# Las comprobaciones que tienen que salir a cero se acumulan para el veredicto
# final, en lugar de ir dando veredictos parciales por el camino.
@fallos = []

def exigir(etiqueta, valor, esperado: 0)
  ok = valor == esperado
  @fallos << "#{etiqueta}: #{valor} (se esperaba #{esperado})" unless ok
  puts format("  %-62s %12s %s", etiqueta, valor, ok ? "ok" : "<- REVISAR")
end

puts "Informe de cierre de la limpieza de cuentas"
puts "=" * 78
linea("Entorno", Rails.env)
linea("Momento del informe", Time.zone.now.strftime("%Y-%m-%d %H:%M:%S %Z"))
linea("Correo apagado por el código desplegado", CleanupMailSwitch.silenciado? ? "sí" : "NO")
linea("Revisión desplegada", File.read(Rails.root.join("REVISION")).strip) if Rails.root.join("REVISION").exist?

# Con la limpieza en marcha este informe no puede cerrar nada: cuenta la base
# y lee los registros en momentos distintos, y entre medias se siguen borrando
# cuentas, así que los cruces no cuadran por unidades. El corchete evita que
# pgrep se cuente a sí mismo a través del shell que lo lanza.
vivos = `pgrep -fc "[c]leanup_unverified_accounts" 2>/dev/null`.to_i
linea("Procesos de limpieza en marcha", vivos)
if vivos.positive?
  @fallos << "la limpieza sigue en marcha (#{vivos} procesos)"
  puts
  puts "  AVISO: la limpieza no ha terminado. Lo que sigue es una foto del momento:"
  puts "  los cruces entre la base y los registros no van a cuadrar por unidades,"
  puts "  porque no se leen a la vez. Hay que repetirlo cuando no quede ninguno."
end

titulo("Lo que se hizo hoy, según la base de datos")
borradas_hoy = Decidim::User.where(deleted_at: HOY..).count
bloqueadas_hoy = Decidim::User.where(blocked: true).where(blocked_at: HOY..).count
linea("Cuentas anonimizadas hoy", borradas_hoy)
linea("Cuentas bloqueadas hoy", bloqueadas_hoy)
linea("Moderaciones ocultadas hoy", Decidim::Moderation.where(hidden_at: HOY..).count)
linea("Cuentas que quedan sin borrar", Decidim::User.where(deleted_at: nil).count)
linea("De ellas, cuentas de personas", Decidim::User.where(deleted_at: nil, type: "Decidim::User").count)

titulo("Lo que dicen los registros de los procesos")
registros = Dir[File.join(DIR, "limpieza*.log")].reject { |f| f.end_with?("_claves.log") }.sort
if registros.empty?
  puts "  No hay registros en #{DIR} (con REGISTROS=... se indica otro sitio)."
else
  acciones = Hash.new { |h, k| h[k] = [] }
  registros.each do |fichero|
    File.foreach(fichero) do |linea_registro|
      id, accion = linea_registro.split
      acciones[accion] << id.to_i if id && accion
    end
  end
  linea("Ficheros de registro leídos", registros.size)
  acciones.each do |accion, ids|
    linea("Anotadas como '#{accion}' (ids únicos)", ids.uniq.size)
  end
  anotadas = acciones["borrada"].uniq
  # Las anotadas tienen que estar borradas de verdad. Al revés no: hay cuentas
  # borradas hoy por las calibraciones previas con otros registros.
  pendientes = anotadas.each_slice(5_000).sum do |lote|
    Decidim::User.where(id: lote, deleted_at: nil).count
  end
  exigir("Anotadas como borradas que siguen sin borrar", pendientes)
  claves = Dir[File.join(DIR, "*_claves.log")].sum { |f| File.foreach(f).count }
  linea("Claves purgadas en S3, anotadas", claves)
end

titulo("Las cuentas bloqueadas siguen con su contenido oculto")
bloqueadas = Decidim::User.where(blocked: true).where(blocked_at: HOY..)
visibles = 0
bloqueadas.pluck(:id).each_slice(500) do |lote|
  visibles += Decidim::Comments::Comment.not_hidden
                                        .where(decidim_author_id: lote, decidim_author_type: AUTOR)
                                        .count
end
exigir("Comentarios visibles de las cuentas bloqueadas hoy", visibles)

titulo("Ninguna cuenta protegida acabó borrada")
# Cada una de estas señales sobrevive al borrado, así que si aparece en una
# cuenta anonimizada hoy es que el criterio la clasificó mal.
borradas = Decidim::User.where(deleted_at: HOY..)
exigir("Borradas que eran de gestión (admin)", borradas.where(admin: true).count)
exigir("Borradas que estaban oficializadas", borradas.where.not(officialized_at: nil).count)
exigir("Borradas con algún rol en la organización",
       borradas.where("coalesce(array_length(roles, 1), 0) > 0").count)
exigir("Borradas que votaron sin registrarse (managed)", borradas.where(managed: true).count)

con_autorizacion = Decidim::Authorization.where.not(granted_at: nil)
                                         .where(decidim_user_id: borradas.select(:id))
                                         .distinct
                                         .count(:decidim_user_id)
exigir("Borradas con una verificación censal concedida", con_autorizacion)

visibles_borradas = 0
borradas.pluck(:id).each_slice(5_000) do |lote|
  visibles_borradas += Decidim::Comments::Comment.not_hidden
                                                 .where(decidim_author_id: lote, decidim_author_type: AUTOR)
                                                 .count
end
exigir("Comentarios visibles de cuentas borradas hoy", visibles_borradas)

# Esto no es un fallo, es el dato que el Ayuntamiento va a preguntar: cuántas
# de las borradas eran antiguas. Las anteriores a noviembre de 2020 con
# participación que exigía identificarse están protegidas por el criterio; las
# que se borran de ese tramo son las que no dejaron ningún rastro.
linea("Borradas registradas antes de 2021", borradas.where(created_at: ...Time.zone.parse("2021-01-01")).count)
linea("Borradas registradas en 2025 o 2026", borradas.where(created_at: Time.zone.parse("2025-01-01")..).count)

titulo("La administración sigue en pie")
admins = Decidim::User.where(admin: true, deleted_at: nil)
linea("Cuentas de administración activas", admins.count)
exigir("Cuentas de administración bloqueadas", admins.where(blocked: true).count)

titulo("El plan ya no tiene trabajo pendiente")
if CON_PLAN
  recuento = AccountCleanupPlan.new.counts
  recuento.each { |decision, n| linea(decision.to_s, n) }
  exigir("Cuentas que quedan en el grupo 'borrar'", recuento.fetch(:borrar, 0))
  exigir("Cuentas que quedan en el grupo 'bloquear'", recuento.fetch(:bloquear, 0))
  puts
  puts "  El grupo 'pendiente' se conserva a propósito: es la decisión que el"
  puts "  Ayuntamiento se reservó, y se tratará en una pasada posterior."
else
  puts "  Saltado (PLAN=0). Es la comprobación que dice que no queda trabajo:"
  puts "  conviene ejecutarla al menos una vez antes de devolver master."
end

titulo("No salió ni un correo durante la ventana")
registros_de_correo = ["log/production.log", "../shared/log/production.log", "log/sidekiq.log",
                       "../shared/log/sidekiq.log"]
                      .map { |ruta| Rails.root.join(ruta) }
                      .select(&:exist?)
                      .uniq { |ruta| File.realpath(ruta) }

if registros_de_correo.empty?
  puts "  No se encontró ningún log donde buscar entregas."
else
  registros_de_correo.each do |fichero|
    entregados = `grep -c "Sent mail to" #{fichero.to_s.shellescape} 2>/dev/null`.to_i
    exigir("Correos entregados según #{File.basename(fichero)}", entregados)
  end
end

# El detalle de las colas lo da el script que ya existe, para no tener dos
# sitios que decidan lo mismo.
titulo("Estado de las colas (lib/scripts/cleanup_mail_queue_check.rb)")
comprobacion_de_colas = Rails.root.join("lib/scripts/cleanup_mail_queue_check.rb")
if comprobacion_de_colas.exist?
  load comprobacion_de_colas.to_s
else
  puts "  No está en este despliegue. Las colas son la última condición para"
  puts "  devolver master: hay que mirarlas con el release que lleva el script."
  @fallos << "no se pudo comprobar el estado de las colas"
end

puts
puts "=" * 78
if @fallos.empty?
  puts "VEREDICTO: todas las comprobaciones de este informe salen como se esperaba."
  puts "Si la sección de colas dice LISTO, se puede desplegar master y, después,"
  puts "quitar el modo de mantenimiento, en ese orden."
else
  puts "VEREDICTO: #{@fallos.size} comprobación(es) no salen como se esperaba:"
  @fallos.each { |fallo| puts "  - #{fallo}" }
  puts
  puts "No devuelvas master hasta aclararlo. La copia previa a la limpieza está en"
  puts "/home/debian/database.dump.20261015-antes-limpieza.gpg, en producción."
end
nil
