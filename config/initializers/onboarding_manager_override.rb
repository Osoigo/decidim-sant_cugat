# Defensive backport for Decidim 0.30.x onboarding flow.
# Keeps behavior close to upstream while avoiding crashes when user is nil
# (e.g. verify_wo_registration paths reached without signed-in user).

module Decidim
  module OnboardingManagerDefensiveBackport
    private

    def onboarding_data
      return {} if user.blank?

      data = user.extended_data[Decidim::OnboardingManager::DATA_KEY]
      data.is_a?(Hash) ? data : {}
    end

    public

    def valid?
      return false if user.blank?
      return false if action.blank?

      permissions_holder.present?
    end
  end
end

Rails.application.config.to_prepare do
  if defined?(Decidim::OnboardingManager)
    Decidim::OnboardingManager.prepend(Decidim::OnboardingManagerDefensiveBackport)
  end
end
