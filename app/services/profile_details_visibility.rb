# frozen_string_literal: true

# Decide si el perfil público de una cuenta muestra su URL personal y su texto
# de presentación.
#
# Solo se muestran cuando la cuenta está verificada contra el censo, es de
# gestión, o ha participado de alguna forma. El análisis de cuentas de
# septiembre de 2026 encontró que el 99 % de las cuentas de spam existía
# únicamente para publicar un enlace en un perfil sin ninguna actividad, frente
# al 0,1 % de las cuentas verificadas. Ocultar ese enlace deja esas cuentas sin
# valor para quien las crea y no afecta a quien participa.
class ProfileDetailsVisibility
  AUTHOR_TYPE = "Decidim::UserBaseEntity"

  def self.visible_for?(profile_holder)
    new(profile_holder).visible?
  end

  def initialize(profile_holder)
    @profile_holder = profile_holder
  end

  # Los grupos de usuarios y cualquier perfil que no sea una cuenta de
  # participante se muestran como siempre: esta medida solo afecta a las
  # cuentas personales.
  def visible?
    return true unless user.is_a?(Decidim::User)
    return true if trusted?

    verified? || participated?
  end

  private

  attr_reader :profile_holder

  alias user profile_holder

  # Administración, cuentas oficializadas, cuentas gestionadas por
  # impersonación y cualquier cuenta con rol en la organización.
  def trusted?
    user.admin? || user.managed? || user.officialized? || user.roles.present?
  end

  # Cualquier verificación, vigente o pendiente, contra el censo o cualquier
  # otro método que se configure en el futuro.
  def verified?
    exists?(Decidim::Authorization.where(decidim_user_id: user.id))
  end

  # Señales de participación, de la más barata y frecuente a la más rara. La
  # primera que se cumple corta la cadena de consultas.
  def participated?
    exists?(Decidim::ActionLog.where(decidim_user_id: user.id)) ||
      exists?(authored(Decidim::Comments::Comment)) ||
      exists?(authored(Decidim::Coauthorship)) ||
      exists?(Decidim::Proposals::ProposalVote.where(decidim_author_id: user.id)) ||
      exists?(Decidim::Budgets::Order.where(decidim_user_id: user.id)) ||
      exists?(Decidim::Meetings::Registration.where(decidim_user_id: user.id)) ||
      exists?(Decidim::Forms::Answer.where(decidim_user_id: user.id)) ||
      exists?(authored(Decidim::Endorsement))
  end

  def authored(klass)
    klass.where(decidim_author_type: AUTHOR_TYPE, decidim_author_id: user.id)
  end

  def exists?(relation)
    relation.reorder(nil).exists?
  end
end
