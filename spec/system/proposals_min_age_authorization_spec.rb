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

  before do
    allow_any_instance_of(CensusAuthorizationHandler).to receive(:response).and_return({ "res" => 1, "barri" => "", "consellBarri" => "" })
    allow(Decidim::VerifyWoRegistration::ApplicationHelper).to receive(:verify_wo_registration_custom_modal?).and_return(true)
    switch_to_host(organization.host)
  end

  context "when a registered user with age restriction votes" do
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

  context "when an unregistered visitor votes without age restriction" do
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

    let(:verify_wo_registration_path) do
      Decidim::VerifyWoRegistration::Engine.routes.url_helpers.new_verification_path(
        component_id: component.id,
        redirect_url: Decidim::ResourceLocatorPresenter.new(participatory_process).path,
        votable_gid: "gid://decidim/Dummy/1"
      )
    end

    context "when the visitor is underage" do
      it "blocks the verification and prevents voting" do
        expect(Decidim::User.where(organization: organization, managed: true).count).to eq(0)
        expect(Decidim::Authorization.where(name: CensusAuthorizationHandler.handler_name).count).to eq(0)

        expect { visit verify_wo_registration_path }.not_to raise_error

        find("input[name*='[document_number]']").set("12345678A")
        find("select[name*='[date_of_birth(3i)]'] option[value='12']").select_option
        find("select[name*='[date_of_birth(2i)]'] option[value='1']").select_option
        find("select[name*='[date_of_birth(1i)]'] option[value='2000']").select_option
        find("form[action='#{decidim_verify_wo_registration.verifications_path}'] button[type='submit']", match: :first).click

        expect(page).to have_current_path(decidim_verify_wo_registration.verifications_path, ignore_query: true)
        expect(page).to have_content("Ho sentim, la teva edat és inferior a la requerida per a aquesta activitat.")
        expect(Decidim::User.where(organization: organization, managed: true).count).to eq(0)
        expect(Decidim::Authorization.where(name: CensusAuthorizationHandler.handler_name).count).to eq(0)
      end
    end

    context "when the visitor meets the minimum age" do
      it "allows verification and creates a vote session" do
        expect(Decidim::User.where(organization: organization, managed: true).count).to eq(0)
        expect(Decidim::Authorization.where(name: CensusAuthorizationHandler.handler_name).count).to eq(0)

        expect { visit verify_wo_registration_path }.not_to raise_error

        find("input[name*='[document_number]']").set("12345678A")
        find("select[name*='[date_of_birth(3i)]'] option[value='12']").select_option
        find("select[name*='[date_of_birth(2i)]'] option[value='1']").select_option
        find("select[name*='[date_of_birth(1i)]'] option[value='1955']").select_option
        find("form[action='#{decidim_verify_wo_registration.verifications_path}'] button[type='submit']", match: :first).click

        expect(page).to have_current_path(Decidim::ResourceLocatorPresenter.new(participatory_process).path, ignore_query: true)
        expect(Decidim::User.where(organization: organization, managed: true).count).to eq(1)
        expect(Decidim::Authorization.where(name: CensusAuthorizationHandler.handler_name).count).to eq(1)
      end
    end
  end
end
