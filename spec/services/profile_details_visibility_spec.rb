# frozen_string_literal: true

require "rails_helper"
require "decidim/proposals/test/factories"
require "decidim/comments/test/factories"

describe ProfileDetailsVisibility do
  subject { described_class.visible_for?(profile_holder) }

  let(:organization) { create(:organization, available_locales: [:ca], default_locale: :ca) }
  let(:user) { create(:user, :confirmed, organization:) }
  let(:profile_holder) { user }

  context "when the account has neither verification nor activity" do
    it { is_expected.to be(false) }
  end

  context "when the account is verified against the census" do
    before { create(:authorization, name: "census_authorization_handler", user:) }

    it { is_expected.to be(true) }
  end

  context "when the verification is still pending" do
    before { create(:authorization, :pending, name: "census_authorization_handler", user:) }

    it "counts as verified: the person already identified themselves" do
      expect(subject).to be(true)
    end
  end

  context "when the account has commented" do
    before do
      component = create(:proposal_component, organization:)
      proposal = create(:proposal, component:)
      create(:comment, author: user, commentable: proposal)
    end

    it { is_expected.to be(true) }
  end

  context "when the account has authored a proposal" do
    before do
      component = create(:proposal_component, organization:)
      create(:proposal, component:, users: [user])
    end

    it { is_expected.to be(true) }
  end

  context "when the account has an entry in the action log" do
    before { create(:action_log, user:, organization:) }

    it { is_expected.to be(true) }
  end

  context "when the account belongs to the administration" do
    let(:user) { create(:user, :admin, :confirmed, organization:) }

    it { is_expected.to be(true) }
  end

  context "when the account is officialized" do
    let(:user) { create(:user, :confirmed, :officialized, organization:) }

    it { is_expected.to be(true) }
  end

  context "when the profile belongs to a user group" do
    let(:profile_holder) { create(:user_group, organization:) }

    it "is left untouched: the measure only covers personal accounts" do
      expect(subject).to be(true)
    end
  end

  context "when there is no profile holder" do
    let(:profile_holder) { nil }

    it { is_expected.to be(true) }
  end
end
