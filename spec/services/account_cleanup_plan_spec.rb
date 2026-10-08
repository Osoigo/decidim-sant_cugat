# frozen_string_literal: true

require "rails_helper"
require "decidim/proposals/test/factories"
require "decidim/comments/test/factories"
require "decidim/assemblies/test/factories"

describe AccountCleanupPlan do
  subject(:decision) do
    user # la cuenta tiene que existir antes de calcular el plan
    described_class.new.decisions[user.id]
  end

  let(:organization) { create(:organization, default_locale: :ca, available_locales: [:ca]) }
  let(:component) { create(:proposal_component, organization:) }
  let(:user) { create(:user, :confirmed, organization:) }

  context "when the account belongs to the administration" do
    let(:user) { create(:user, :admin, :confirmed, organization:) }

    it { is_expected.to eq(:gestion) }
  end

  context "when the account holds a role in an assembly" do
    before { create(:assembly_user_role, user:, assembly: create(:assembly, organization:)) }

    it { is_expected.to eq(:gestion) }
  end

  context "when the account was created by voting without registering" do
    let(:user) { create(:user, :confirmed, :managed, organization:) }

    it { is_expected.to eq(:gestionada) }
  end

  context "when the account holds a census verification" do
    before { create(:authorization, name: "census_authorization_handler", user:) }

    it { is_expected.to eq(:verificada) }
  end

  context "when the verification was revoked but left a trace in the history", versioning: true do
    before { create(:authorization, name: "census_authorization_handler", user:).destroy! }

    it "still counts as verified" do
      expect(decision).to eq(:verificada)
    end
  end

  context "when the account is older than the verification history and took part" do
    let(:user) { create(:user, :confirmed, organization:, created_at: Time.zone.parse("2019-05-04"), personal_url: nil, about: "") }

    before { create(:proposal_vote, author: user, proposal: create(:proposal, component:)) }

    it "is kept: before November 2020 a revoked verification left no trace" do
      expect(decision).to eq(:participo)
    end
  end

  context "when the same participation happened after the history starts" do
    let(:user) { create(:user, :confirmed, organization:, created_at: Time.zone.parse("2025-03-01"), personal_url: nil, about: "") }

    before { create(:proposal_vote, author: user, proposal: create(:proposal, component:)) }

    it "is not kept by date, and lands in the group the council has to decide on" do
      expect(decision).to eq(:pendiente)
    end
  end

  context "when the account has content and a personal url" do
    let(:user) { create(:user, :confirmed, organization:, personal_url: "https://example.org/spam") }

    before { create(:comment, author: user, commentable: create(:proposal, component:)) }

    it { is_expected.to eq(:bloquear) }
  end

  context "when the account has content and a disposable email domain" do
    let(:user) { create(:user, :confirmed, organization:, email: "veina@leacore.com") }

    before { create(:comment, author: user, commentable: create(:proposal, component:)) }

    it { is_expected.to eq(:bloquear) }
  end

  context "when the account has content and commercial wording in the name" do
    let(:user) { create(:user, :confirmed, organization:, name: "Maharana Cab Delhi") }

    before { create(:comment, author: user, commentable: create(:proposal, component:)) }

    it { is_expected.to eq(:bloquear) }
  end

  context "when the account has content and no spam signal" do
    let(:user) { create(:user, :confirmed, organization:, name: "Mireia Puig", personal_url: nil, about: "") }

    before { create(:comment, author: user, commentable: create(:proposal, component:)) }

    it { is_expected.to eq(:pendiente) }
  end

  context "when the account has nothing at all" do
    it { is_expected.to eq(:borrar) }
  end

  context "when the account is already blocked" do
    let(:user) { create(:user, :confirmed, :blocked, organization:) }

    it { is_expected.to eq(:ya_bloqueada) }
  end

  describe "#verification_breakdown" do
    it "separates a live authorization from one that only survives in the history", versioning: true do
      vigente = create(:user, :confirmed, organization:)
      revocada = create(:user, :confirmed, organization:)
      create(:authorization, name: "census_authorization_handler", user: vigente)
      create(:authorization, name: "census_authorization_handler", user: revocada).destroy!

      desglose = described_class.new.verification_breakdown

      expect(desglose[:total]).to eq(2)
      expect(desglose[:con_autorizacion_vigente]).to eq(1)
      expect(desglose[:solo_por_historial]).to eq(1)
    end
  end

  describe "#counts" do
    before do
      create(:user, :confirmed, organization:)
      create(:user, :confirmed, :admin, organization:)
    end

    it "adds up to the accounts in scope" do
      plan = described_class.new

      expect(plan.counts.values.sum).to eq(Decidim::User.where(deleted_at: nil).count)
    end
  end
end
