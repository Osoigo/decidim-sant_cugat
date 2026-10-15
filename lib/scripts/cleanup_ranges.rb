# frozen_string_literal: true

# Calcula rangos de id equilibrados para lanzar varias limpiezas en paralelo.
#
# El coste de la limpieza lo marca el trabajo de base de datos por cuenta,
# unos 0,37 s, y eso no baja apreciablemente optimizando. Lo que sí acorta la
# ventana es repartir el trabajo: cuatro procesos sobre rangos disjuntos
# hacen en cuatro horas lo que uno hace en dieciséis.
#
# Los rangos se reparten por número de cuentas, no por amplitud de id, porque
# los id están muy agrupados: la mitad de la base se registró en 2025 y 2026.
#
#   RANGOS=4 bundle exec rails runner lib/scripts/cleanup_ranges.rb
#
# Imprime los rangos y las órdenes listas para copiar. Es de solo lectura.
#
# El reparto es por cuentas totales, que es una aproximación: las que de
# verdad se borran son algo menos en los tramos antiguos, donde hay más
# cuentas legítimas. Para el objetivo, repartir la espera, vale de sobra.

cuantos = Integer(ENV.fetch("RANGOS", 4))
abort("RANGOS tiene que estar entre 2 y 16") unless cuantos.between?(2, 16)

filas = ActiveRecord::Base.connection.select_all(<<~SQL)
  SELECT grupo, min(id) AS desde, max(id) AS hasta, count(*) AS cuentas
    FROM (
      SELECT id, ntile(#{cuantos}) OVER (ORDER BY id) AS grupo
        FROM decidim_users
       WHERE deleted_at IS NULL
    ) repartidas
   GROUP BY grupo
   ORDER BY grupo
SQL

total = filas.sum { |f| f["cuentas"].to_i }
puts "#{total} cuentas repartidas en #{cuantos} rangos"
puts
puts format("  %-7s %-12s %-12s %10s", "proceso", "desde", "hasta", "cuentas")
filas.each do |f|
  puts format("  %-7s %-12s %-12s %10d", f["grupo"], f["desde"], f["hasta"], f["cuentas"])
end
puts

puts "Simulación, uno por rango:"
filas.each do |f|
  puts "  DESDE=#{f['desde']} HASTA=#{f['hasta']} bundle exec rails runner lib/scripts/cleanup_unverified_accounts.rb"
end
puts
puts "Ejecución real, cada una en su propia terminal o con nohup:"
filas.each do |f|
  puts "  APPLY=1 ADMIN_EMAIL=... DESDE=#{f['desde']} HASTA=#{f['hasta']} " \
       "bundle exec rails runner lib/scripts/cleanup_unverified_accounts.rb"
end
puts
puts "Cada proceso escribe su propio registro, con el rango en el nombre."
puts "El silencio del correo lleva una cuenta de procesos: no se reactiva hasta que sale el último."
nil
