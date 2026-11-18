# frozen_string_literal: true

# Parche a retirar si Decidim lo corrige upstream.
#
# La exportación real de «descargar mis datos»
# (Decidim::DownloadYourDataExporter#data_and_attachments_for_user) serializa
# todos los registros del usuario con Decidim::Exporters::CSV. Un registro
# huérfano (debate cuyo componente se borró, comentario cuyo commentable ya no
# existe) hace que el serializador lance NoMethodError, el job falla entero y
# el usuario no recibe su zip.
#
# Alcance: SOLO «descargar mis datos». Decidim::Exporters::CSV se queda tal
# cual, porque lo usan también las exportaciones de administración y open
# data, donde un fallo no debe convertirse en un fichero con filas ausentes
# sin aviso. Para ello se usa una subclase que omite (con Rails.logger.warn) los
# registros que no se pueden serializar, y se hace que solo el exportador de
# «descargar mis datos» la utilice.
module Decidim
  module Exporters
    class OrphanTolerantCSV < CSV
      private

      def processed_collection
        @processed_collection ||= collection.filter_map do |resource|
          flatten(@serializer.new(resource).run).deep_dup
        rescue StandardError => e
          Rails.logger.warn(
            "[DownloadYourData] skipped #{resource.class.name}##{resource.try(:id)} " \
            "(not serializable, probably orphan): #{e.class}: #{e.message}"
          )
          nil
        end
      end
    end
  end

  module OrphanTolerantDownloadYourDataExporter
    private

    # Misma lógica que la de la gema (decidim-core, download_your_data_exporter.rb),
    # salvo que, para el formato CSV, usa Exporters::OrphanTolerantCSV.
    def data_and_attachments_for_user
      return super unless export_format.to_s == Decidim::DownloadYourDataExporter::DEFAULT_EXPORT_FORMAT

      export_data = []
      export_attachments = []

      download_your_data_entities.each do |object|
        klass = Object.const_get(object)
        exporter = Exporters::OrphanTolerantCSV.new(klass.user_collection(user), klass.export_serializer)
        export_data << [klass.model_name.name.parameterize.pluralize, exporter.export]
        attachments = klass.download_your_data_images(user)
        export_attachments << [klass.model_name.name.parameterize.pluralize, attachments.flatten] unless attachments.nil?
      end

      [export_data, export_attachments]
    end
  end
end

Rails.application.config.to_prepare do
  Decidim::DownloadYourDataExporter.prepend(Decidim::OrphanTolerantDownloadYourDataExporter)
end
