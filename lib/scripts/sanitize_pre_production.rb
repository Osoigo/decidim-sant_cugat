# frozen_string_literal: true

# Deja una copia de la base de producción restaurada en pre-producción lista
# para trabajar sin riesgo de alcanzar a nadie de fuera.
#
# Se ejecuta UNA VEZ, justo después de restaurar el volcado y antes de arrancar
# nada más. Hace tres cosas:
#
#   1. Vacía la configuración SMTP de cada organización. Decidim permite que
#      cada tenant tenga su propio servidor de correo y la fusiona en el método
#      de entrega al enviar, así que no basta con la configuración del entorno.
#   2. Vacía la configuración de acceso con proveedores externos del tenant,
#      para que nadie entre en pre con las credenciales de producción.
#   3. Apunta el host de la organización al de pre, que además es necesario
#      para que la aplicación resuelva el tenant.
#
# Al final imprime una verificación del entorno: método de entrega de correo,
# servicio de almacenamiento y organizaciones. El almacenamiento importa: si
# pre comparte el bucket con producción, borrar cuentas purgaría avatares
# reales, así que ese dato hay que comprobarlo antes de ninguna limpieza.
#
# Uso:
#   RAILS_ENV=staging PRE_HOST=santcugat-pre.osoigonext.com \
#     bundle exec rails runner lib/scripts/sanitize_pre_production.rb

abort("Este script no se ejecuta en producción. Es solo para pre-producción.") if Rails.env.production?

host = ENV["PRE_HOST"].to_s.strip
abort("Define PRE_HOST con el host de pre, por ejemplo PRE_HOST=santcugat-pre.osoigonext.com") if host.empty?

organizations = Decidim::Organization.order(:id).to_a
abort("No hay ninguna organización en la base de datos.") if organizations.empty?

if organizations.size > 1
  abort(
    "Hay #{organizations.size} organizaciones y el host es único por organización. " \
    "Revisa a mano a qué host debe responder cada una."
  )
end

organization = organizations.first
antes = {
  host: organization.host,
  secondary_hosts: organization.secondary_hosts,
  smtp: organization.smtp_settings.present?,
  omniauth: organization.omniauth_settings.present?
}

organization.update_columns(
  host: host,
  secondary_hosts: [],
  smtp_settings: {},
  omniauth_settings: {}
)
organization.reload

puts "Organización #{organization.id}"
puts "  host:             #{antes[:host]} -> #{organization.host}"
puts "  hosts secundarios: #{antes[:secondary_hosts].inspect} -> #{organization.secondary_hosts.inspect}"
puts "  SMTP del tenant:   #{antes[:smtp] ? 'configurado' : 'vacío'} -> #{organization.smtp_settings.presence ? 'CONFIGURADO' : 'vacío'}"
puts "  acceso externo:    #{antes[:omniauth] ? 'configurado' : 'vacío'} -> #{organization.omniauth_settings.presence ? 'CONFIGURADO' : 'vacío'}"
puts

puts "Verificación del entorno"
puts "  RAILS_ENV:                 #{Rails.env}"
puts "  entrega de correo:         #{ActionMailer::Base.delivery_method}"
puts "  envío efectivo:            #{ActionMailer::Base.perform_deliveries ? 'ACTIVADO' : 'desactivado'}"
service = begin
  ActiveStorage::Blob.service
rescue StandardError => e
  puts "  almacenamiento:            no se pudo leer (#{e.class})"
  nil
end
if service
  puts "  almacenamiento:            #{service.class.name.split('::').last}"
  bucket = service.try(:bucket)
  puts "  bucket o raíz:             #{bucket ? bucket.name : service.try(:root)}"
end
puts "  cuentas en la base:        #{Decidim::User.where(deleted_at: nil).count}"
puts

correo_contenido = ActionMailer::Base.delivery_method == :test || !ActionMailer::Base.perform_deliveries
if correo_contenido
  puts "Correo: no sale nada de este servidor."
else
  puts "AVISO: el correo se entregaría de verdad, con el método #{ActionMailer::Base.delivery_method}. " \
       "Revisa config/environments/#{Rails.env}.rb antes de tocar ninguna cuenta."
end
puts "Comprueba que el bucket de arriba NO es el de producción antes de borrar ninguna cuenta: borrar una cuenta purga su avatar."
nil
