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

  describe "counting the processes that are silencing" do
    let(:redis) do
      Class.new do
        def initialize = @datos = {}
        def incr(clave) = @datos[clave] = @datos.fetch(clave, 0) + 1
        def decr(clave) = @datos[clave] = @datos.fetch(clave, 0) - 1
        def get(clave) = @datos[clave]&.to_s
        def del(clave) = @datos.delete(clave)
        def expire(_clave, _segundos) = true
      end.new
    end

    before { allow(Sidekiq).to receive(:redis) { |&bloque| bloque.call(redis) } }

    it "silences while at least one process is still working" do
      described_class.silenciar!
      described_class.silenciar!

      expect(described_class.reactivar!).to eq(1)
      expect(described_class.silenciado?).to be(true)
    end

    it "restores mail only when the last one leaves" do
      2.times { described_class.silenciar! }
      2.times { described_class.reactivar! }

      expect(described_class.silenciado?).to be(false)
      expect(described_class.procesos_silenciando).to eq(0)
    end

    it "never goes below zero if someone releases twice" do
      described_class.silenciar!
      described_class.reactivar!

      expect(described_class.reactivar!).to eq(0)
      expect(described_class.silenciado?).to be(false)
    end
  end

  describe ".silenciado?" do
    it "is false when Redis cannot be reached, so a broken switch never blocks mail" do
      allow(Sidekiq).to receive(:redis).and_raise(StandardError)

      expect(described_class.silenciado?).to be(false)
    end
  end
end
