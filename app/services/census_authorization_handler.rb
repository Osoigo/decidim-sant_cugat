# frozen_string_literal: true
require "digest/md5"

# Checks the authorization against the census for Sant Cugat.
#
# This class performs a check against the official census database in order
# to verify the citizen's residence.
class CensusAuthorizationHandler < Decidim::AuthorizationHandler
  include ActionView::Helpers::SanitizeHelper

  attribute :date_of_birth, Date
  attribute :document_number, String

  validates :date_of_birth, presence: true
  validates :document_number, format: { with: /\A[A-z0-9]*\z/ }, presence: true

  validate :over_14
  validate :check_response

  def document_number
    return unless super

    super.to_s.upcase
  end

  # If you need to store any of the defined attributes in the authorization you
  # can do it here.
  #
  # You must return a Hash that will be serialized to the authorization when
  # it's created, and available though authorization.metadata
  def metadata
    {
      district_council: response["consellBarri"]&.strip,
      district: response["barri"]&.strip,
      date_of_birth: date_of_birth&.iso8601,
      document_number: document_number,
    }
  end

  def unique_id
    Digest::MD5.hexdigest(
      "#{document_number}-#{Rails.application.secrets.secret_key_base}"
    )
  end

  private

  # Internal: Checks for the response status. It is valid only when the `"res"` field
  # is `1`. All other values imply some different kind of errors, but in order to not
  # leak private data we will not care about them.
  #
  # Returns nothing.
  def check_response
    errors.add(:base, :invalid) unless response.present? && response["res"] == 1
  end

  def sanitized_date_of_birth
    @sanitized_date_of_birth ||= date_of_birth.strftime("%Y%m%d")
  end

  def response
    return nil if date_of_birth.blank? || document_number.blank?

    return @response if defined?(@response)

    connection = Faraday.new(Rails.application.secrets.dig(:census, :url), ssl: { verify: false }) do |builder|
      builder.request :authorization, :basic, Rails.application.secrets.dig(:census, :auth_user), Rails.application.secrets.dig(:census, :auth_pass)
    end

    response = connection.get do |request|
      request.params = request_params
    end

    @response ||= JSON.parse(response.body)
    Rails.logger.debug("Census responded with: #{@response["res"]}")
    @response
  rescue JSON::ParserError => exception
    Rails.logger.warn("Something went wrong while connecting to the census endpoint: #{exception.message}")
    nil
  end

  def request_params
    {
      data: sanitized_date_of_birth,
      nif: document_number
    }
  end

  def over_14
    errors.add(:date_of_birth, I18n.t("census_authorization_handler.age_under_14")) unless age && age >= 14
  end

  def age
    return nil if date_of_birth.blank?

    now = Date.current
    extra_year = (now.month > date_of_birth.month) || (
      now.month == date_of_birth.month && now.day >= date_of_birth.day
    )

    now.year - date_of_birth.year - (extra_year ? 0 : 1)
  end
end
