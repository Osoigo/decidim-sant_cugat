# frozen_string_literal: true

# It allows to set a list of valid
# - districts
# - district_councils
# - minimum age
# for an authorization.
class CensusActionAuthorizer < Decidim::Verifications::DefaultActionAuthorizer
  attr_reader :allowed_districts, :allowed_district_councils, :minimum_age

  # Overrides the parent class method, but it still uses it to keep the base behavior
  def authorize
    # Remove the additional setting from the options hash to avoid to be considered missing.
    @allowed_districts ||= options.delete("district")&.split(/[\W,;]+/)
    @allowed_district_councils ||= options.delete("district_council")&.split(/[\W,;]+/)
    @minimum_age ||= options.delete("min_age")&.to_i

    status_code, data = *super

    extra_explanations = []
    if minimum_age.present? && status_code == :ok
      if authorized_birth_date.blank?
        status_code = :incomplete
        data = { fields: ["date_of_birth"], action: :reauthorize, cancel: true }
      elsif authorized_age < minimum_age
        status_code = :unauthorized
        extra_explanations << { key: "extra_explanation.minimum_age",
                                params: { scope: "decidim.verifications.census_authorization",
                                          min_age: minimum_age } }
      end
    end

    if allowed_districts.present?
      # Does not authorize users with different districts
      if status_code == :ok && !allowed_districts.member?(authorization.metadata['district'])
        status_code = :unauthorized
        data[:fields] = { 'district' => authorization.metadata['district'] }
        # Adds an extra message to inform the user the additional restriction for this authorization
        extra_explanations << { key: "extra_explanation.districts",
                                params: { scope: "decidim.verifications.census_authorization",
                                          count: allowed_districts.count,
                                          districts: allowed_districts.join(", ") } }
      end
    end

    if allowed_district_councils.present?
      # Does not authorize users with different districts
      if status_code == :ok && !allowed_district_councils.member?(authorization.metadata['district_council'])
        status_code = :unauthorized
        data[:fields] = { 'district_council' => authorization.metadata['district_council'] }
        # Adds an extra message to inform the user the additional restriction for this authorization
        extra_explanations << { key: "extra_explanation.district_councils",
                                params: { scope: "decidim.verifications.census_authorization",
                                          count: allowed_district_councils.count,
                                          districts: allowed_district_councils.join(", ") } }
      end
    end

    data[:extra_explanation] = extra_explanations if extra_explanations.any?

    [status_code, data]
  end

  private

  def authorized_birth_date
    @authorized_birth_date ||= begin
      raw_date = authorization.metadata["date_of_birth"]
      Date.iso8601(raw_date) if raw_date.present?
    rescue Date::Error
      nil
    end
  end

  def authorized_age
    return nil if authorized_birth_date.blank?

    now = Date.current
    extra_year = (now.month > authorized_birth_date.month) || (
      now.month == authorized_birth_date.month && now.day >= authorized_birth_date.day
    )

    now.year - authorized_birth_date.year - (extra_year ? 0 : 1)
  end
end
