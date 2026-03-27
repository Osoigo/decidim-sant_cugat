Rails.application.config.to_prepare do
  result_type = Decidim::Accountability::ResultType

  unless result_type.fields.key?("address")
    result_type.field :address, GraphQL::Types::String, "The address for this result", null: true
  end

  unless result_type.fields.key?("coordinates")
    result_type.field :coordinates, Decidim::Core::CoordinatesType, "The coordinates for this result", null: true
  end

  unless result_type.fields.key?("url")
    result_type.field :url, GraphQL::Types::String, "The URL for this result", null: true
  end

  result_type.class_eval do
    def coordinates
      return if object.latitude.blank? || object.longitude.blank?

      [object.latitude, object.longitude]
    end

    def url
      Decidim::ResourceLocatorPresenter.new(object).url
    end
  end
end
