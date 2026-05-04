# frozen_string_literal: true

require "rails_helper"

describe Decidim::Meetings::Admin::CopyMeeting do
  subject(:command) { described_class.new(form, meeting) }

  let(:organization) { double("organization") }
  let(:component) { double("component") }
  let(:current_user) { double("current_user") }
  let(:questionnaire) { double("questionnaire") }
  let(:taxonomizations) { [double("taxonomization")] }
  let(:meeting) do
    double(
      "meeting",
      organization: organization,
      component: component,
      private_meeting: false,
      transparent: true,
      online_meeting_url: nil,
      iframe_embed_type: "none",
      iframe_access_level: "all",
      comments_enabled: true,
      comments_start_time: nil,
      comments_end_time: nil,
      registration_url: nil,
      type_of_meeting: "online",
      registrations_enabled: false,
      available_slots: nil,
      registration_terms: nil,
      reserved_slots: nil,
      customize_registration_email: false,
      registration_form_enabled: false,
      registration_email_custom_content: nil
    )
  end
  let(:traceability) { double("traceability") }

  let(:form) do
    double(
      invalid?: false,
      title: { ca: "Reunio copiada" },
      description: { ca: "Descripcio copiada" },
      location: { ca: "Ubicacio" },
      location_hints: { ca: "Pistes" },
      start_time: 1.day.from_now,
      end_time: 1.day.from_now + 1.hour,
      address: "Carrer Major, 1",
      latitude: 41.47,
      longitude: 2.08,
      taxonomizations: taxonomizations,
      services_to_persist: [],
      current_user: current_user,
      questionnaire: questionnaire,
      private_meeting: false,
      transparent: true,
      current_organization: organization,
      online_meeting_url: nil,
      iframe_embed_type: "none",
      iframe_access_level: "all",
      comments_enabled: true,
      comments_start_time: nil,
      comments_end_time: nil,
      registration_type: "on_this_platform",
      registration_url: nil,
      type_of_meeting: "online"
    )
  end

  before do
    allow(Decidim).to receive(:traceability).and_return(traceability)
    allow(Decidim::ContentProcessor).to receive(:parse_with_processor) do |_processor, content, current_organization:|
      double(rewrite: content)
    end
  end

  it "passes taxonomizations to the copied meeting creation" do
    expect(traceability)
      .to receive(:create!)
      .with(
        Decidim::Meetings::Meeting,
        current_user,
        hash_including(
          taxonomizations: taxonomizations,
          component: component,
          questionnaire: questionnaire
        )
      )

    command.send(:copy_meeting!)
  end
end