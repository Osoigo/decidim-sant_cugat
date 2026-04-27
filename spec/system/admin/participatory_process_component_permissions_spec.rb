# frozen_string_literal: true

require "rails_helper"

describe "Participatory process component permissions", type: :system do
  let(:organization) do
    create(
      :organization,
      default_locale: :ca,
      available_locales: [:ca],
      available_authorizations: ["census_authorization_handler"]
    )
  end

  let(:admin) { create(:user, :admin, :confirmed, organization: organization) }
  let(:participatory_process) { create(:participatory_process, organization: organization) }
  let(:component) do
    create(
      :component,
      manifest_name: "proposals",
      participatory_space: participatory_process,
      permissions: {
        "vote" => {
          "authorization_handlers" => {
            "census_authorization_handler" => {
              "options" => {
                "district" => "",
                "district_council" => ""
              }
            }
          }
        }
      }
    )
  end

  before do
    switch_to_host(organization.host)
    login_as admin, scope: :user

    admin_proxy = Decidim::EngineRouter.admin_proxy(participatory_process)
    visit admin_proxy.edit_component_permissions_path(component_id: component.id)
  end

  it "stores min_age for census authorization handler" do
    within ".vote-permission" do
      find("input[name$='[min_age]']:not([disabled])", visible: :all).set("65")
    end

    within "form[id^='new_component_permissions']" do
      click_button "Enviar"
    end

    expect(component.reload.permissions.dig("vote", "authorization_handlers", "census_authorization_handler", "options", "min_age")).to eq("65")
  end
end
