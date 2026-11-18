# frozen_string_literal: true

require "rails_helper"

describe Decidim::Exporters::CSV, "#headers_without_locales" do
  let(:serializer) do
    Class.new do
      def initialize(resource)
        @resource = resource
      end

      def run
        raise NoMethodError, "orphan" if @resource == :orphan

        { id: 1, title: "x" }
      end
    end
  end

  it "returns the keys of the first record when it serializes" do
    expect(described_class.new([:ok, :orphan], serializer).headers_without_locales).to eq([:id, :title])
  end

  it "skips records that fail to serialize" do
    expect(described_class.new([:orphan, :orphan, :ok], serializer).headers_without_locales).to eq([:id, :title])
  end

  it "returns [] and logs a warning when no record serializes" do
    allow(Rails.logger).to receive(:warn)

    expect(described_class.new([:orphan, :orphan], serializer).headers_without_locales).to eq([])
    expect(Rails.logger).to have_received(:warn).with(/orphan/)
  end

  it "returns [] for an empty collection" do
    expect(described_class.new([], serializer).headers_without_locales).to eq([])
  end

  it "only tries a bounded number of records" do
    collection = Array.new(30, :orphan) + [:ok]

    expect(described_class.new(collection, serializer).headers_without_locales).to eq([])
  end
end
