# Enforce min_age in verify_wo_registration without forcing account registration.
# The age check is applied on form submission using verification metadata.

module Decidim
  module VerifyWoRegistration
    module MinAgeFormValidation
      extend ActiveSupport::Concern

      included do
        validate :validate_minimum_age_for_vote
      end

      private

      def validate_minimum_age_for_vote
        return if errors.any?

        min_age = minimum_age_for_vote
        return unless min_age.positive?

        birth_date = authorization_birth_date
        if birth_date.blank?
          errors.add(:authorizations, :minimum_age_not_met, min_age: min_age)
          return
        end

        errors.add(:authorizations, :minimum_age_not_met, min_age: min_age) if age_for(birth_date) < min_age
      end

      def minimum_age_for_vote
        handlers = component.permissions.dig("vote", "authorization_handlers")
        return 0 unless handlers.respond_to?(:values)

        handlers.values.filter_map do |handler|
          min_age = handler.dig("options", "min_age").to_i
          min_age if min_age.positive?
        end.max.to_i
      end

      def authorization_birth_date
        authorization_handlers.each do |handler|
          next unless handler.respond_to?(:metadata)

          metadata = handler.metadata
          next if metadata.blank?

          raw_date = metadata["date_of_birth"] || metadata[:date_of_birth]
          next if raw_date.blank?

          parsed = Date.iso8601(raw_date.to_s)
          return parsed if parsed
        rescue Date::Error, ArgumentError
          next
        end

        nil
      end

      def age_for(birth_date)
        now = Date.current
        extra_year = (now.month > birth_date.month) || (
          now.month == birth_date.month && now.day >= birth_date.day
        )

        now.year - birth_date.year - (extra_year ? 0 : 1)
      end
    end

    module MinAgeInvalidAlert
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
            flash.now[:alert] = if min_age_restriction_error?
                                  I18n.t("decidim.verify_wo_registration.min_age_restricted")
                                else
                                  I18n.t("impersonations.create.error", scope: "decidim.admin")
                                end
            render :new
          end
        end
      end

      private

      def min_age_restriction_error?
        @form.errors.details.fetch(:authorizations, []).any? { |error| error[:error] == :minimum_age_not_met }
      end
    end
  end
end

Rails.application.config.to_prepare do
  if defined?(Decidim::VerifyWoRegistration::VerifyWoRegistrationForm)
    Decidim::VerifyWoRegistration::VerifyWoRegistrationForm.include(Decidim::VerifyWoRegistration::MinAgeFormValidation)
  end

  if defined?(Decidim::VerifyWoRegistration::VerificationsController)
    Decidim::VerifyWoRegistration::VerificationsController.prepend(Decidim::VerifyWoRegistration::MinAgeInvalidAlert)
  end
end
