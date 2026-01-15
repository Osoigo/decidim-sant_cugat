# -*- coding: utf-8 -*-
# frozen_string_literal: true
require "rails_helper"
require "decidim/dev/test/authorization_shared_examples"

describe CensusAuthorizationHandler do
  let(:subject) { handler }
  let(:handler) { described_class.from_params(params) }
  let(:date_of_birth) { Date.civil(1987, 9, 17) }
  let(:document_number) { "12345678A" }
  let(:organization) { create(:organization, available_locales: [:ca], default_locale: :ca) }
  let(:user) { create(:user, locale: :ca, organization: organization) }
  let(:params) do
    {
      user: user,
      date_of_birth: date_of_birth,
      document_number: document_number
    }
  end

  describe "document_number" do
    context "when it is present" do
      let(:document_number) { "12345678a" }

      it "returns it in upper case" do
        expect(subject.document_number).to eq("12345678A")
      end
    end

    context "when it is nil" do
      let(:document_number) { nil }

      it "returns nil" do
        expect(subject.document_number).to eq(nil)
      end
    end

    context "with a NIE" do
      let(:document_number) { "Z1234567R" }

      before do
        allow(handler)
          .to receive(:response)
          .and_return(JSON.parse("{ \"res\": 1 }"))
      end

      it "is valid" do
        expect(subject).to be_valid
      end
    end
  end

  context "when user is too young" do
    let(:date_of_birth) { 13.years.ago.to_date }

    before do
      allow(handler)
        .to receive(:response)
              .and_return(JSON.parse("{ \"res\": 1 }"))
    end

    it { is_expected.not_to be_valid }

    it "has an error in the date of birth" do
      subject.valid?
      expect(subject.errors[:date_of_birth]).to be_present
    end
  end

  context "with a valid response" do
    before do
      allow(handler)
        .to receive(:response)
        # the Webservice returns values with some trailing spaces
        .and_return(JSON.parse("{ \"res\": 1, \"barri\":\" 2 \",\"consellBarri\":\" 1 \" }"))
    end

    it_behaves_like "an authorization handler"

    describe "metadata" do
      it "includes the district" do
        expect(handler.metadata[:district]).to eq("2")
      end

      it "includes the district council" do
        expect(handler.metadata[:district_council]).to eq("1")
      end
    end

    describe "document_number" do
      context "when it isn't present" do
        let(:document_number) { nil }

        it { is_expected.not_to be_valid }
      end

      context "with an invalid format" do
        let(:document_number) { "(╯°□°）╯︵ ┻━┻" }

        it { is_expected.not_to be_valid }
      end
    end

    describe "date_of_birth" do
      context "when it isn't present" do
        let(:date_of_birth) { nil }

        it { is_expected.not_to be_valid }
      end
    end

    context "when everything is fine" do
      it { is_expected.to be_valid }
    end
  end

  context "unique_id" do
    it "generates a different ID for a different document number" do
      handler.document_number = "ABC123"
      unique_id1 = handler.unique_id

      handler.document_number = "XYZ456"
      unique_id2 = handler.unique_id

      expect(unique_id1).to_not eq(unique_id2)
    end

    it "generates the same ID for the same document number" do
      handler.document_number = "ABC123"
      unique_id1 = handler.unique_id

      handler.document_number = "ABC123"
      unique_id2 = handler.unique_id

      expect(unique_id1).to eq(unique_id2)
    end

    it "hashes the document number" do
      handler.document_number = "ABC123"
      unique_id = handler.unique_id

      expect(unique_id).to_not include(handler.document_number)
    end
  end

  context "with an invalid response" do
    context "with an invalid response code" do
      before do
        allow(handler)
          .to receive(:response)
          .and_return(JSON.parse("{ \"res\": 2}"))
      end

      it { is_expected.to_not be_valid }
    end

    context "with an invalid json format" do
      before do
        allow(handler)
          .to receive(:response)
          .and_return("</not valid json>")
      end

      it { is_expected.to_not be_valid }
    end
  end
end
