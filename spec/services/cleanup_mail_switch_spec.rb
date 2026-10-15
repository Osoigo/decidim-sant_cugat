# frozen_string_literal: true

require "rails_helper"

describe CleanupMailSwitch do
  describe "the delivery job guard" do
    # Misma firma que ActionMailer::MailDeliveryJob#perform: tres posicionales
    # y argumentos con nombre. Si el módulo no los reenvía tal cual, esto falla.
    let(:job) do
      Class.new do
        attr_reader :recibido

        def perform(mailer, metodo, entrega, args:, kwargs: nil, params: nil)
          @recibido = { mailer:, metodo:, entrega:, args:, kwargs:, params: }
        end
      end.prepend(described_class::SaltarEntrega).new
    end

    def entregar
      job.perform("Decidim::BlockUserMailer", "notify", "deliver_now", args: [1, "motivo"], params: nil)
    end

    it "passes every argument through when the switch is off, keywords included" do
      allow(described_class).to receive(:silenciado?).and_return(false)

      entregar

      expect(job.recibido).to include(mailer: "Decidim::BlockUserMailer", metodo: "notify", args: [1, "motivo"])
    end

    it "drops the delivery while the cleanup is silencing mail" do
      allow(described_class).to receive(:silenciado?).and_return(true)

      entregar

      expect(job.recibido).to be_nil
    end
  end

  describe ".silenciado?" do
    it "is false when Redis cannot be reached, so a broken switch never blocks mail" do
      allow(Sidekiq).to receive(:redis).and_raise(StandardError)

      expect(described_class.silenciado?).to be(false)
    end
  end
end
