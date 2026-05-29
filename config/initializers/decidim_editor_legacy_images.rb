# Defensive backport for Decidim 0.30.x rich text editor.
# Legacy HTML stores standalone <img> tags while the new Tiptap editor
# rehydrates images only when they are wrapped in `div[data-image]`.

module Decidim
  module LegacyEditorImageNormalizer
    module_function

    def normalize(content)
      case content
      when Hash
        content.transform_values { |value| normalize(value) }
      when String
        return content unless content.include?("<img")

        fragment = Nokogiri::HTML::DocumentFragment.parse(content)
        changed = normalize_image_paragraphs(fragment)

        fragment.css("img[src]:not([src^='data:'])").each do |image|
          next if image.ancestors.any? { |ancestor| ancestor.element? && ancestor.key?("data-image") }

          image.replace(build_editor_image_wrapper(image.dup, fragment.document))
          changed = true
        end

        changed ? fragment.to_html : content
      else
        content
      end
    end

    def normalize_image_paragraphs(fragment)
      changed = false

      fragment.css("p").each do |paragraph|
        next if paragraph.ancestors.any? { |ancestor| ancestor.element? && ancestor.key?("data-image") }

        images = paragraph.css("img[src]:not([src^='data:'])")
        next if images.empty?

        meaningful_children = paragraph.children.reject { |node| node.text? && node.text.strip.empty? }
        next unless meaningful_children.all? { |node| images.include?(node) }

        replacement = Nokogiri::HTML::DocumentFragment.parse("")
        images.each do |image|
          replacement.add_child(build_editor_image_wrapper(image.dup, fragment.document))
        end

        paragraph.replace(replacement)
        changed = true
      end

      changed
    end

    def build_editor_image_wrapper(image, document)
      wrapper = Nokogiri::XML::Node.new("div", document)
      wrapper["class"] = "editor-content-image"
      wrapper["data-image"] = ""
      wrapper.add_child(image)
      wrapper
    end
  end

  module FormBuilderLegacyEditorImages
    def editor(name, options = {})
      value = if options.key?(:value)
        options[:value]
      elsif object.respond_to?(name)
        object.public_send(name)
      end

      return super(name, options) unless value.is_a?(String) || value.is_a?(Hash)

      super(name, options.merge(value: LegacyEditorImageNormalizer.normalize(value)))
    end
  end
end

Rails.application.config.to_prepare do
  if defined?(Decidim::FormBuilder)
    Decidim::FormBuilder.prepend(Decidim::FormBuilderLegacyEditorImages)
  end
end
