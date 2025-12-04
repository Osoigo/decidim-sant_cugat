Rails.application.config.to_prepare do
  Decidim::Accountability::Result.class_eval do
    def reported_content_url(options = {})
      Decidim::Accountability::Engine.routes.url_helpers.result_path(
        {
          assembly_slug: component.participatory_space.slug,
          component_id: component.id,
          id: id
        }.merge(options)
      )
    end
  end
end
