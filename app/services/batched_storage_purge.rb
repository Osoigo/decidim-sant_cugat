# frozen_string_literal: true

# Envoltura del servicio de ActiveStorage que agrupa los borrados en S3.
#
# Borrar una cuenta purga su avatar, y ActiveStorage lo hace de uno en uno:
# un DELETE del original más un LIST con borrado por lotes de las variantes
# antiguas que cuelgan de "variants/<clave>/". Medido contra S3 el 8 de
# octubre de 2026, 88 ms por avatar. Con los 104.218 avatares de producción
# son dos horas y media que el script se pasa esperando a Amazon, muy por
# encima del trabajo de base de datos.
#
# Esta envoltura se coloca en el registro de servicios en lugar del real,
# anota lo que habría que borrar y lo resuelve por tandas: los prefijos se
# listan en paralelo y las claves se borran de mil en mil, que es el máximo
# que admite delete_objects.
#
# Las claves se anotan en un fichero ANTES de enviarlas. Si el proceso muere
# a medio camino quedan objetos huérfanos en S3, que cuestan almacenamiento
# pero no rompen nada, y ese fichero permite barrerlos después.
#
# Solo cubre los borrados que pasan por este proceso. Las variantes con
# registro propio las purga Decidim con un trabajo por cada una en Sidekiq,
# que es asíncrono y no alarga la ventana de mantenimiento.
class BatchedStoragePurge
  MAXIMO_POR_PETICION = 1_000
  HILOS_DE_LISTADO = 16

  attr_reader :claves_borradas, :prefijos_resueltos, :peticiones

  def initialize(servicio, registro: nil, umbral: 5_000)
    @servicio = servicio
    @registro = registro
    @umbral = umbral
    @claves = []
    @prefijos = []
    @claves_borradas = 0
    @prefijos_resueltos = 0
    @peticiones = 0
    @cerrojo = Mutex.new
  end

  def delete(key)
    @cerrojo.synchronize { @claves << key }
    vaciar_si_se_acumula
  end

  def delete_prefixed(prefix)
    @cerrojo.synchronize { @prefijos << prefix }
    vaciar_si_se_acumula
  end

  # Resuelve lo acumulado. Devuelve cuántas claves se borraron.
  def vaciar
    claves, prefijos = tomar_pendientes
    claves.concat(listar(prefijos))
    claves.uniq!
    return 0 if claves.empty?

    anotar(claves)
    enviar(claves)
    @claves_borradas += claves.size
    claves.size
  end

  def pendientes
    @cerrojo.synchronize { @claves.size + @prefijos.size }
  end

  def respond_to_missing?(nombre, incluir_privados = false)
    @servicio.respond_to?(nombre, incluir_privados) || super
  end

  def method_missing(nombre, *args, **opciones, &bloque)
    return super unless @servicio.respond_to?(nombre)

    @servicio.public_send(nombre, *args, **opciones, &bloque)
  end

  private

  def vaciar_si_se_acumula
    vaciar if pendientes >= @umbral
    nil
  end

  def tomar_pendientes
    @cerrojo.synchronize do
      claves = @claves
      prefijos = @prefijos
      @claves = []
      @prefijos = []
      [claves, prefijos]
    end
  end

  # Un LIST por prefijo es inevitable, pero no tienen por qué ir en serie.
  def listar(prefijos)
    return [] if prefijos.empty?

    @prefijos_resueltos += prefijos.size
    reparto = [(prefijos.size / HILOS_DE_LISTADO.to_f).ceil, 1].max
    encontradas = []
    cerrojo = Mutex.new

    prefijos.each_slice(reparto).map do |lote|
      Thread.new do
        halladas = lote.flat_map { |prefijo| claves_bajo(prefijo) }
        cerrojo.synchronize { encontradas.concat(halladas) }
      end
    end.each(&:join)

    encontradas
  end

  def claves_bajo(prefijo)
    @servicio.bucket.objects(prefix: prefijo).map(&:key)
  rescue StandardError => e
    warn("AVISO: no se pudo listar #{prefijo} (#{e.class}); se borrará de una en una")
    []
  end

  def enviar(claves)
    claves.each_slice(MAXIMO_POR_PETICION) do |lote|
      @peticiones += 1
      cliente.delete_objects(
        bucket: @servicio.bucket.name,
        delete: { objects: lote.map { |clave| { key: clave } }, quiet: true }
      )
    end
  end

  def cliente
    @cliente ||= @servicio.client.client
  end

  def anotar(claves)
    return if @registro.nil?

    File.open(@registro, "a") { |f| claves.each { |clave| f.puts(clave) } }
  end
end
