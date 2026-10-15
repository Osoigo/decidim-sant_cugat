# frozen_string_literal: true

require "rails_helper"

describe AccountNicknameRepair do
  let(:organization) { create(:organization, default_locale: :ca, available_locales: [:ca]) }
  let(:user) { create(:user, :confirmed, organization:) }

  context "when the nickname already passes the current validation" do
    it "leaves it alone" do
      expect { described_class.call(user) }.not_to change { user.reload.nickname }
      expect(described_class.call(user)).to be(false)
    end
  end

  context "when the nickname is a legacy one that no longer validates" do
    before { user.update_columns(nickname: "nom amb accent ò") }

    it "replaces it with a valid one" do
      expect(described_class.call(user)).to be(true)
      expect(user.reload.nickname).to eq("u#{user.id}")
      expect(user.nickname).to match(described_class::VALIDO)
    end

    it "lets the account be destroyed afterwards, which is the whole point" do
      described_class.call(user)

      form = Decidim::DeleteAccountForm.from_params(delete_reason: "prueba").with_context(current_user: user.reload)
      expect { Decidim::DestroyAccount.call(form) }.not_to raise_error
      expect(user.reload.deleted_at).not_to be_nil
    end
  end

  context "when the account has no nickname at all" do
    before { user.update_columns(nickname: "") }

    it "gives it one" do
      expect(described_class.call(user)).to be(true)
      expect(user.reload.nickname).to eq("u#{user.id}")
    end
  end

  context "when the replacement nickname is already taken" do
    let(:other) { create(:user, :confirmed, organization:) }

    before do
      user.update_columns(nickname: "nom.amb.punts")
      other.update_columns(nickname: "u#{user.id}")
    end

    it "adds a suffix instead of colliding" do
      expect(described_class.call(user)).to be(true)
      expect(user.reload.nickname).to start_with("u#{user.id}-")
      expect(user.nickname).to match(described_class::VALIDO)
    end
  end

  context "when the account was created by voting without registering" do
    let(:user) { create(:user, :confirmed, :managed, organization:) }

    it "is left alone: Decidim skips the validation for those" do
      expect(described_class.call(user)).to be(false)
    end
  end
end
