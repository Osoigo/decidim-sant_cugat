# frozen_string_literal: true

require "rails_helper"

describe "Unverified profile details", type: :system do
  let(:organization) { create(:organization, default_locale: :ca, available_locales: [:ca]) }
  let(:personal_url) { "https://example.org/spam" }
  let(:about) { "Visita la meva web" }
  let(:user) do
    create(:user, :confirmed, organization:, personal_url:, about:)
  end

  before do
    switch_to_host(organization.host)
    visit decidim.profile_path(user.nickname)
  end

  context "when the account has neither verification nor activity" do
    it "keeps the profile page but publishes neither the personal url nor the about text" do
      expect(page).to have_content(user.name)
      expect(page).to have_content(user.nickname)
      expect(page).to have_no_link(personal_url, href: personal_url)
      expect(page).to have_no_content(about)
    end
  end

  context "when the account is verified against the census" do
    let!(:authorization) { create(:authorization, name: "census_authorization_handler", user:) }

    it "publishes both" do
      visit decidim.profile_path(user.nickname)

      expect(page).to have_link(personal_url, href: personal_url)
      expect(page).to have_content(about)
    end
  end
end
