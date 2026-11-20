Rails.application.config.to_prepare do
  manifest = Decidim.content_blocks.for(:homepage).find { |content_block| content_block.name == :awesome_map }
  next unless manifest
  next if manifest.settings.attributes.key?(:show_accountability_results)

  manifest.settings.attribute :show_accountability_results, type: :boolean, default: false
end
