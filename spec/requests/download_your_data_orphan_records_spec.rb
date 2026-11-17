# frozen_string_literal: true

require "rails_helper"
require "decidim/debates/test/factories"
require "decidim/comments/test/factories"
require "decidim/proposals/test/factories"

# La página «Les meves dades» construye la ayuda serializando el primer
# registro de cada entidad del usuario. Un registro huérfano (componente o
# commentable borrado) no debe tumbar la página con un 500.
describe "Download your data with orphan records", type: :request do
  include Warden::Test::Helpers

  let(:organization) { create(:organization, default_locale: :ca, available_locales: [:ca]) }
  let(:user) { create(:user, :confirmed, organization:) }
  let(:debates_component) { create(:debates_component, organization:) }
  let(:proposals_component) { create(:proposal_component, organization: debates_component.organization) }

  before do
    host! organization.host
    login_as user, scope: :user
  end

  after { Warden.test_reset! }

  # Borra el componente sin callbacks ni FKs: deja el decidim_component_id colgando.
  def orphan_component!(component)
    ActiveRecord::Base.connection.execute("SET session_replication_role = replica")
    Decidim::Component.where(id: component.id).delete_all
  ensure
    ActiveRecord::Base.connection.execute("SET session_replication_role = DEFAULT")
  end

  def delete_without_callbacks!(record)
    ActiveRecord::Base.connection.execute("SET session_replication_role = replica")
    record.class.where(id: record.id).delete_all
  ensure
    ActiveRecord::Base.connection.execute("SET session_replication_role = DEFAULT")
  end

  context "when the user authored a debate whose component was deleted" do
    let!(:debate) { create(:debate, component: debates_component, author: user) }

    before { orphan_component!(debates_component) }

    it "still renders the page" do
      get "/download_your_data"

      expect(response).to have_http_status(:ok)
    end
  end

  context "when the user wrote a comment whose root commentable was deleted" do
    let!(:proposal) { create(:proposal, component: proposals_component) }
    let!(:comment) { create(:comment, commentable: proposal, author: user) }

    before { delete_without_callbacks!(proposal) }

    it "still renders the page" do
      get "/download_your_data"

      expect(response).to have_http_status(:ok)
    end
  end

  context "when the first debate is orphan and a later one is healthy" do
    let(:healthy_component) { create(:debates_component, organization:) }
    let!(:orphan_debate) { create(:debate, component: debates_component, author: user) }
    let!(:healthy_debate) { create(:debate, component: healthy_component, author: user) }

    before { orphan_component!(debates_component) }

    it "falls back to the healthy debate to document the columns" do
      get "/download_your_data"

      expect(response).to have_http_status(:ok)
      expect(response.body).to match(%r{<h4>debates</h4>\s*<ul>\s*<li>\s*<b>id</b>})
    end
  end
end
