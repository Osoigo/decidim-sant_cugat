# Baseline override copied from Decidim 0.30.5 to keep a clean diff for the patch.

module Decidim
  module VerifyWoRegistration
    module VerificationsController0305Base
      # Copied from Decidim::VerifyWoRegistration::VerificationsController#create (v0.30.5)
      def create
        @form = form(VerifyWoRegistrationForm).from_params(form_params)

        DoVerifyWoRegistration.call(@form) do
          on(:ok) do |user|
            flash[:notice] = I18n.t("verify_wo_registration.create.success", minutes: ::Decidim::ImpersonationLog::SESSION_TIME_IN_MINUTES)

            sign_in(user)
            redirect_to @form.redirect_url
          end

          on(:use_registered_user) do
            flash.now[:alert] = I18n.t("verify_wo_registration.create.use_registered_user")
            render :new
          end

          on(:invalid) do
            flash.now[:alert] = I18n.t("impersonations.create.error", scope: "decidim.admin")
            render :new
          end
        end
      end
    end
  end
end

Rails.application.config.to_prepare do
  if defined?(Decidim::VerifyWoRegistration::VerificationsController)
    Decidim::VerifyWoRegistration::VerificationsController.prepend(Decidim::VerifyWoRegistration::VerificationsController0305Base)
  end
end
