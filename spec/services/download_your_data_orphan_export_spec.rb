# frozen_string_literal: true

require "rails_helper"
require "decidim/debates/test/factories"
require "decidim/comments/test/factories"
require "decidim/proposals/test/factories"

# La exportación real de «descargar mis datos» serializa todos los registros
# del usuario. Un registro huérfano (componente o commentable borrado) no debe
# abortar el job: se omite con un warn y el resto sale completo. Las
# exportaciones de administración/open data no cambian de comportamiento.
describe "Download your data export with orphan records" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization, default_locale: :ca, available_locales: [:ca]) }
  let(:user) { create(:user, :confirmed, organization:) }
  let(:orphan_component) { create(:debates_component, organization:) }
  let(:healthy_component) { create(:debates_component, organization:) }

  def delete_without_callbacks!(klass, id)
    ActiveRecord::Base.connection.execute("SET session_replication_role = replica")
    klass.where(id:).delete_all
  ensure
    ActiveRecord::Base.connection.execute("SET session_replication_role = DEFAULT")
  end

  def zip_entries(private_export)
    entries = {}
    Zip::InputStream.open(StringIO.new(private_export.file.download)) do |zip|
      while (entry = zip.get_next_entry)
        entries[entry.name] = zip.read
      end
    end
    entries
  end

  def entry_for(entries, prefix)
    entries.find { |name, _| name.start_with?(prefix) }&.last
  end

  let(:exporter) { Decidim::DownloadYourDataExporter.new(user, "download_your_data") }

  before { allow(Rails.logger).to receive(:warn).and_call_original }

  context "with an orphan debate and a healthy one" do
    let!(:orphan_debate) { create(:debate, component: orphan_component, author: user) }
    let!(:healthy_debate) { create(:debate, component: healthy_component, author: user) }

    before { delete_without_callbacks!(Decidim::Component, orphan_component.id) }

    it "exports without raising and keeps only the healthy debate" do
      private_export = nil
      expect { private_export = exporter.export }.not_to raise_error

      csv = entry_for(zip_entries(private_export), "decidim-debates-debate")
      expect(csv).to be_present
      ids = CSV.parse(csv, headers: true, col_sep: Decidim.default_csv_col_sep).map { |row| row["id"].to_i }
      expect(ids).to eq([healthy_debate.id])
    end

    it "logs a warning for the skipped record" do
      exporter.export

      expect(Rails.logger).to have_received(:warn)
        .with(/Decidim::Debates::Debate.*#{orphan_debate.id}.*NoMethodError/m).at_least(:once)
    end
  end

  context "with an orphan comment and a healthy one" do
    let(:proposals_component) { create(:proposal_component, organization:) }
    let!(:orphan_proposal) { create(:proposal, component: proposals_component) }
    let!(:healthy_proposal) { create(:proposal, component: proposals_component) }
    let!(:orphan_comment) { create(:comment, commentable: orphan_proposal, author: user) }
    let!(:healthy_comment) { create(:comment, commentable: healthy_proposal, author: user) }

    before { delete_without_callbacks!(Decidim::Proposals::Proposal, orphan_proposal.id) }

    it "exports without raising and keeps only the healthy comment" do
      private_export = nil
      expect { private_export = exporter.export }.not_to raise_error

      csv = entry_for(zip_entries(private_export), "decidim-comments-comment")
      expect(csv).to be_present
      ids = CSV.parse(csv, headers: true, col_sep: Decidim.default_csv_col_sep).map { |row| row["id"].to_i }
      expect(ids).to eq([healthy_comment.id])
    end
  end

  context "when the only debate is orphan" do
    let!(:orphan_debate) { create(:debate, component: orphan_component, author: user) }
    let!(:healthy_comment) do
      create(:comment, commentable: create(:proposal, component: create(:proposal_component, organization:)), author: user)
    end

    before { delete_without_callbacks!(Decidim::Component, orphan_component.id) }

    it "does not raise and still exports the other entities" do
      private_export = nil
      expect { private_export = exporter.export }.not_to raise_error

      entries = zip_entries(private_export)
      expect(entry_for(entries, "decidim-comments-comment")).to include(healthy_comment.id.to_s)
      expect(entries.keys).to include("README.md")
    end
  end

  describe "Decidim::DownloadYourDataExportJob" do
    let!(:orphan_debate) { create(:debate, component: orphan_component, author: user) }

    before { delete_without_callbacks!(Decidim::Component, orphan_component.id) }

    it "finishes and creates a PrivateExport with an attached file" do
      expect { Decidim::DownloadYourDataExportJob.perform_now(user) }
        .to change { user.private_exports.count }.by(1)

      expect(user.private_exports.last.file).to be_attached
    end
  end

  describe "admin exports with Decidim::Exporters::CSV" do
    let!(:orphan_debate) { create(:debate, component: orphan_component, author: user) }

    before { delete_without_callbacks!(Decidim::Component, orphan_component.id) }

    it "still raises on an orphan record (behaviour unchanged outside the data export)" do
      collection = Decidim::Debates::Debate.where(id: orphan_debate.id)
      csv_exporter = Decidim::Exporters::CSV.new(collection, Decidim::Debates::DebateSerializer)

      expect { csv_exporter.export }.to raise_error(NoMethodError)
    end
  end
end
