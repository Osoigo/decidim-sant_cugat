# -*- coding: utf-8 -*-
# frozen_string_literal: true
require "rails_helper"

describe CensusActionAuthorizer do
  subject { described_class.new(authorization, options, nil, nil).authorize }

  let(:organization) { create(:organization, available_locales: [:ca], default_locale: :ca) }
  let(:user) { create(:user, nickname: 'authorizing_user', locale: :ca, organization: organization) }
  let(:authorization) {}
  let(:options) { {} }

  context "when there is no authorization" do
    it "does not grant authorization" do
      expect(subject).to eq([:missing, {action: :authorize}])
    end
  end

  context "when authorization is pending" do
    let(:authorization) { create(:authorization, :pending, user: user) }

    it "does not grant authorization" do
      expect(subject).to eq([:pending, action: :resume])
    end
  end

  describe "when authorization is valid" do
    context "without options" do
      let(:authorization) { create(:authorization, :granted, user: user) }

      it "grants authorization" do
        expect(subject).to eq([:ok, {}])
      end
    end

    context "with district option" do
      context "when a single value has been setted" do
        let(:options) { {'district' => '1'} }

        context "when the selected district matches with authorization" do
          let(:authorization) { create(:authorization, :granted, user: user, metadata: {'district' => '1'}) }

          it "grants authorization" do
            expect(subject).to eq([:ok, {}])
          end
        end

        context "when the selected district does not match authorization" do
          let(:authorization) { create(:authorization, :granted, user: user, metadata: {'district' => '2'}) }

          it "doesn't grant authorization" do
            expected_data= {
              :extra_explanation=> [{
                :key=>"extra_explanation.districts",
                :params=> {:count=>1, :districts=>"1", :scope=>"decidim.verifications.census_authorization"}
              }],
              fields: {'district'=>'2'}
            }

            expect(subject).to eq([:unauthorized, expected_data])
          end
        end
      end

      context "when multiples values have been setted" do
        let(:options) { {'district' => '1, 2,3; 4'} }

        context "when any of the listed districts matches with authorization" do
          let(:authorization) { create(:authorization, :granted, user: user, metadata: {'district' => '2'}) }

          it "grants authorization" do
            expect(subject).to eq([:ok, {}])
          end
        end

        context "when none of the listed districts match with the authorization" do
          let(:authorization) { create(:authorization, :granted, user: user, metadata: {'district' => '5'}) }

          it "doesn't grant authorization" do
            expected_data= {
              :extra_explanation=> [{
                :key=>"extra_explanation.districts",
                :params=> {:count=>4, :districts=>"1, 2, 3, 4", :scope=>"decidim.verifications.census_authorization"}
              }],
              :fields=>{"district"=>"5"}
            }

            expect(subject).to eq([:unauthorized, expected_data])
          end
        end
      end
    end

    context "with district_council option" do
      context "when a single value has been setted" do
        let(:options) { {'district_council' => '1'} }

        context "when the selected district_council matches with authorization" do
          let(:authorization) { create(:authorization, :granted, user: user, metadata: {'district_council' => '1'}) }

          it "grants authorization" do
            expect(subject).to eq([:ok, {}])
          end
        end

        context "when the selected district_council does not match authorization" do
          let(:authorization) { create(:authorization, :granted, user: user, metadata: {'district_council' => '2'}) }

          it "doesn't grant authorization" do
            expected_data= {
              :extra_explanation=> [{
                :key=>"extra_explanation.district_councils",
                :params=> {:count=>1, :districts=>"1", :scope=>"decidim.verifications.census_authorization"}
              }],
              fields: {'district_council'=>'2'}
            }

            expect(subject).to eq([:unauthorized, expected_data])
          end
        end
      end

      context "when multiples values have been setted" do
        let(:options) { {'district_council' => '1, 2,3; 4'} }

        context "when any of the listed districts matches with authorization" do
          let(:authorization) { create(:authorization, :granted, user: user, metadata: {'district_council' => '2'}) }

          it "grants authorization" do
            expect(subject).to eq([:ok, {}])
          end
        end

        context "when none of the listed districts match with the authorization" do
          let(:authorization) { create(:authorization, :granted, user: user, metadata: {'district_council' => '7'}) }

          it "doesn't grant authorization" do
            expected_data= {
              :extra_explanation=> [{
                :key=>"extra_explanation.district_councils",
                :params=> {:count=>4, :districts=>"1, 2, 3, 4", :scope=>"decidim.verifications.census_authorization"}
              }],
              fields: {'district_council'=>'7'}
            }

            expect(subject).to eq([:unauthorized, expected_data])
          end
        end
      end
    end

    context "with both district and district_council options" do
        let(:options) { {'district' => '1,2,3,4', 'district_council' => '5,6,7,8'} }

        context "when authorization matches with the listed district and district_council" do
          let(:authorization) { create(:authorization, :granted, user: user, metadata: {'district' => '1', 'district_council' => '8'}) }

          it "grants authorization" do
            expect(subject).to eq([:ok, {}])
          end
        end
    end
  end
end
