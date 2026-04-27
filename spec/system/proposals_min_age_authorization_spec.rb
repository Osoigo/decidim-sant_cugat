# frozen_string_literal: true

require "rails_helper"
require "decidim/proposals/test/factories"

describe "Proposals vote authorization by minimum age", type: :system, with_authorization_workflows: ["census_authorization_handler"] do
  around do |example|
    previous_server_port = Capybara.server_port
    Capybara.server_port = 31_337
    example.run
  ensure
    Capybara.server_port = previous_server_port
  end

  let(:organization) do
    create(
      :organization,
      default_locale: :ca,
      available_locales: [:ca],
      available_authorizations: ["census_authorization_handler"]
    )
  end

  let(:participatory_process) { create(:participatory_process, :with_steps, organization: organization, published_at: 1.day.ago) }
  let(:component) do
    create(
      :proposal_component,
      :with_votes_enabled,
      participatory_space: participatory_process,
      published_at: 1.day.ago,
      permissions: {
        "vote" => {
          "authorization_handlers" => {
            "census_authorization_handler" => {
              "options" => {
                "district" => "",
                "district_council" => "",
                "min_age" => "65"
              }
            }
          }
        }
      }
    )
  end

  let(:proposal) { create(:proposal, component: component, published_at: 1.day.ago) }
  let(:user) { create(:user, :confirmed, locale: :ca, organization: organization) }

  let!(:authorization) do
    create(
      :authorization,
      name: CensusAuthorizationHandler.handler_name,
      user: user,
      granted_at: 2.seconds.ago,
      metadata: {
        "date_of_birth" => 64.years.ago.to_date.iso8601,
        "district" => "",
        "district_council" => ""
      }
    )
  end

  before do
    switch_to_host(organization.host)
    login_as user, scope: :user
    visit Decidim::ResourceLocatorPresenter.new(proposal).path
  end

  it "blocks voting actions restricted to 65+ users" do
    within "#proposal-#{proposal.id}-vote-button" do
      find("button, a", match: :first).click
    end

    expect(page).to have_content("65")
    expect(page).to have_content("La participació està restringida a les persones de 65 anys o més")
    expect(Decidim::Proposals::ProposalVote.where(proposal: proposal, author: user).count).to eq(0)
  end
end
