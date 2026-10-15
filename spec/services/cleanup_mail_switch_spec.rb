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

    # Sin stubbear nada: mientras esta rama esté desplegada no sale un correo,
    # y no hace falta que nadie encienda ninguna bandera.
    it "drops it by default, because this branch keeps mail off while it is deployed" do
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

    it "counts the processes that are still working" do
      described_class.silenciar!
      described_class.silenciar!

      expect(described_class.reactivar!).to eq(1)
      expect(described_class.procesos_silenciando).to eq(1)
    end

    it "goes back to zero when the last one leaves" do
      2.times { described_class.silenciar! }
      2.times { described_class.reactivar! }

      expect(described_class.procesos_silenciando).to eq(0)
    end

    it "never goes below zero if someone releases twice" do
      described_class.silenciar!
      described_class.reactivar!

      expect(described_class.reactivar!).to eq(0)
      expect(described_class.procesos_silenciando).to eq(0)
    end

    # La cuenta es para la traza. Si decidiera, el correo volvería en cuanto
    # saliera el último proceso, con los avisos de la ocultación aún en cola.
    it "does not bring mail back when it empties" do
      described_class.silenciar!
      described_class.reactivar!

      expect(described_class.silenciado?).to be(true)
    end
  end

  describe ".silenciado?" do
    it "stays silent while this branch is deployed" do
      expect(described_class.silenciado?).to be(true)
    end

    it "stays silent without asking Redis, so a Redis outage cannot let mail out" do
      allow(Sidekiq).to receive(:redis).and_raise(StandardError)

      expect(described_class.silenciado?).to be(true)
      expect(Sidekiq).not_to have_received(:redis)
    end
  end
end
