# frozen_string_literal: true

require "rails_helper"

describe "Signup form hardening", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization, default_locale: :ca, available_locales: [:ca]) }
  let(:params) do
    {
      user: {
        name: "Veïna de Sant Cugat",
        email: "veina@example.org",
        password: "Fulls de Castanyer 2026",
        tos_agreement: "1",
        newsletter: "0"
      }
    }
  end

  before { host! organization.host }

  it "serves the signup page: the timing check must not block the form itself" do
    get "/users/sign_up"

    expect(response).to have_http_status(:ok)
  end

  it "rejects a signup sent without ever loading the form" do
    expect { post "/users", params: }.not_to change(Decidim::User, :count)

    expect(response).to have_http_status(:found)
  end

  it "rejects a signup sent in under five seconds" do
    get "/users/sign_up"

    expect { post "/users", params: }.not_to change(Decidim::User, :count)
  end

  it "accepts the same signup once five seconds have passed" do
    get "/users/sign_up"

    travel 6.seconds do
      expect { post "/users", params: }.to change(Decidim::User, :count).by(1)
    end
  end

  it "keeps rejecting addresses from disposable domains" do
    get "/users/sign_up"
    disposable = params.deep_dup
    disposable[:user][:email] = "veina@leacore.com"

    travel 6.seconds do
      expect { post "/users", params: disposable }.not_to change(Decidim::User, :count)
    end
  end
end
