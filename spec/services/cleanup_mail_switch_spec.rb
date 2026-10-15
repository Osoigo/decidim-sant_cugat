# frozen_string_literal: true

require "rails_helper"

describe CleanupMailSwitch do
  describe "the delivery job guard" do
    let(:job) do
      Class.new do
        attr_reader :entregado

        def perform(*)
          @entregado = true
        end
      end.prepend(described_class::SaltarEntrega).new
    end

    it "delivers as usual when the switch is off" do
      allow(described_class).to receive(:silenciado?).and_return(false)

      job.perform

      expect(job.entregado).to be(true)
    end

    it "drops the delivery while the cleanup is silencing mail" do
      allow(described_class).to receive(:silenciado?).and_return(true)

      job.perform

      expect(job.entregado).to be_nil
    end
  end

  describe ".silenciado?" do
    it "is false when Redis cannot be reached, so a broken switch never blocks mail" do
      allow(Sidekiq).to receive(:redis).and_raise(StandardError)

      expect(described_class.silenciado?).to be(false)
    end
  end
end
