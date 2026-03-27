Rails.application.config.to_prepare do
  Decidim::DecidimAwesome::ContentBlocks::MapCell.class_eval do
    def accountability_map_components
      @accountability_map_components ||= Decidim::Component.where(manifest_name: :accountability).published.filter do |component|
        component.organization == current_organization
      end
    end
  end
end
