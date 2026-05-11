# Baseline override copied from Decidim 0.30.5 to keep a clean diff for the patch.

module Decidim
  module OnboardingManager0305Base
    private

    # Copied from Decidim::OnboardingManager#onboarding_data (v0.30.5)
    def onboarding_data
      user.extended_data[Decidim::OnboardingManager::DATA_KEY] || {}
    end

    public

    # Copied from Decidim::OnboardingManager#valid? (v0.30.5)
    def valid?
      return if action.blank?

      permissions_holder.present?
    end
  end
end

Rails.application.config.to_prepare do
  if defined?(Decidim::OnboardingManager)
    Decidim::OnboardingManager.prepend(Decidim::OnboardingManager0305Base)
  end
end
