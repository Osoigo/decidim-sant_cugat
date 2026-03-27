# frozen_string_literal: true

require "rails_helper"
require "decidim/accountability/test/factories"
require "decidim/meetings/test/factories"
require "decidim/proposals/test/factories"

describe "Homepage awesome map with accountability results", type: :system do
  let(:organization) do
    create(
      :organization,
      default_locale: :ca,
      available_locales: [:ca]
    )
  end

  let!(:participatory_process) { create(:participatory_process, :with_steps, organization: organization) }
  let!(:accountability_component) { create(:accountability_component, :published, participatory_space: participatory_process) }
  let!(:proposal_component) do
    create(
      :proposal_component,
      :with_geocoding_enabled,
      participatory_space: participatory_process,
      published_at: 1.day.ago
    )
  end
  let!(:meeting_component) do
    create(
      :meeting_component,
      participatory_space: participatory_process,
      published_at: 1.day.ago
    )
  end
  let!(:result) do
    create(
      :result,
      component: accountability_component,
      latitude: 41.47330,
      longitude: 2.07974,
      address: "Passeig de la Creu, 1-5"
    )
  end
  let!(:proposal) do
    create(
      :proposal,
      component: proposal_component,
      published_at: 1.day.ago,
      latitude: 41.47210,
      longitude: 2.08110,
      address: "Carrer Major, 10"
    )
  end
  let!(:meeting) do
    create(
      :meeting,
      :published,
      component: meeting_component,
      latitude: 41.47420,
      longitude: 2.08220,
      address: "Plaça de la Vila, 2"
    )
  end

  let!(:content_block) do
    create(
      :content_block,
      organization: organization,
      manifest_name: :awesome_map,
      scope_name: :homepage,
      settings: {
        map_height: 500,
        taxonomy_ids: []
      }
    )
  end

  before do
    switch_to_host(organization.host)
  end

  it "renders accountability results support assets in homepage map" do
    visit decidim.root_path

    expect(page).to have_selector("#awesome-map")
    expect(page).to have_selector("script#marker-result-popup", visible: false)
    expect(page.body).to include("results(first: 50")
    expect(page.body).to include(%("id":#{accountability_component.id}))
    expect(page.body).to include("Resultat")
    expect(result.latitude).to be_present
    expect(result.longitude).to be_present
  end

  it "keeps proposals and meetings available but hidden by default" do
    visit decidim.root_path

    expect(page).to have_selector(".awesome_map-component[data-layer='proposals']")
    expect(page).to have_selector(".awesome_map-component[data-layer='meetings']")

    proposal_toggle = page.find(:xpath, "//span[contains(@class, 'awesome_map-component') and @data-layer='proposals']/ancestor::label[1]//input", visible: :all)
    meeting_toggle = page.find(:xpath, "//span[contains(@class, 'awesome_map-component') and @data-layer='meetings']/ancestor::label[1]//input", visible: :all)

    expect(proposal_toggle).not_to be_checked
    expect(meeting_toggle).not_to be_checked
    expect(proposal.latitude).to be_present
    expect(meeting.latitude).to be_present
  end
end
