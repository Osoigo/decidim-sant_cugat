Rails.application.config.to_prepare do
  Decidim::DecidimAwesome::ContentBlocks::MapCell.class_eval do
    alias_method :original_all_taxonomies, :all_taxonomies unless method_defined?(:original_all_taxonomies)
    alias_method :original_global_map_components, :global_map_components unless method_defined?(:original_global_map_components)

    def show_accountability_results?
      settings.respond_to?(:show_accountability_results) && settings.show_accountability_results
    end

    def accountability_map_components
      @accountability_map_components ||= Decidim::Component.where(manifest_name: :accountability).published.filter do |component|
        component.organization == current_organization
      end
    end

    def all_taxonomies
      return [] if show_accountability_results?

      original_all_taxonomies
    end

    def global_map_components
      return [] if show_accountability_results?

      original_global_map_components
    end
  end
end
