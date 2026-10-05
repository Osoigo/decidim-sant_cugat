# frozen_string_literal: true

# Oculta la URL personal y el texto de presentación en el perfil público de las
# cuentas sin verificar ni actividad. El criterio está en
# ProfileDetailsVisibility; aquí solo se enchufa a la celda de perfil de
# Decidim, que es la única que publica esos dos campos. La API GraphQL no los
# expone, así que no hay más superficie pública que cubrir.
module Decidim
  module HideUnverifiedProfileDetails
    # Sobrescribe la delegación de Decidim::ProfileCell: al devolver nil, la
    # celda deja de añadir el elemento del enlace a los detalles del perfil.
    def personal_url
      profile_details_visible? ? super : nil
    end

    private

    def description
      profile_details_visible? ? super : ""
    end

    def profile_details_visible?
      return @profile_details_visible if defined?(@profile_details_visible)

      @profile_details_visible = ProfileDetailsVisibility.visible_for?(profile_holder)
    end
  end
end

Rails.application.config.to_prepare do
  Decidim::ProfileCell.prepend(Decidim::HideUnverifiedProfileDetails)
end
