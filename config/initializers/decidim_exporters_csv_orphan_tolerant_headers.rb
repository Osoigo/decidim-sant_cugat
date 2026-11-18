# frozen_string_literal: true

# Parche a retirar si Decidim lo corrige upstream (a fecha de 0.30.9 y de las
# ramas 0.31-stable y develop el código sigue igual).
#
# «Les meves dades» (/download_your_data) construye la ayuda serializando el
# PRIMER registro de cada entidad del usuario solo para obtener los nombres de
# columna. Si ese registro es huérfano (debate cuyo componente se borró,
# comentario cuyo commentable ya no existe) el serializador lanza un
# NoMethodError y la página responde 500. Aquí se prueba con los siguientes
# registros, hasta un tope, y si ninguno serializa se devuelve [] (la vista
# omite las entidades sin definiciones).
module Decidim
  module OrphanTolerantExporterHeaders
    MAX_RECORDS_TRIED = 25

    def headers_without_locales
      return @headers_without_locales if @headers_without_locales.present?

      super
    rescue StandardError => e
      @headers_without_locales = fallback_headers_without_locales(e)
    end

    private

    def fallback_headers_without_locales(first_error)
      last_error = first_error

      # `first(n)` sirve igual para relaciones ActiveRecord que para Arrays.
      collection.first(MAX_RECORDS_TRIED).drop(1).each do |resource|
        return @serializer.new(resource).run.keys
      rescue StandardError => e
        last_error = e
      end

      Rails.logger.warn(
        "[#{@serializer}] no record could be serialized to build the export help headers: " \
        "#{last_error.class}: #{last_error.message}"
      )
      []
    end
  end
end

Rails.application.config.to_prepare do
  Decidim::Exporters::CSV.prepend(Decidim::OrphanTolerantExporterHeaders)
end
