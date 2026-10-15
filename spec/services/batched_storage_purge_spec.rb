# frozen_string_literal: true

require "rails_helper"

describe BatchedStoragePurge do
  # Un servicio con la misma forma que el de S3: bucket con name y objects,
  # y client.client con delete_objects.
  let(:objetos) { Hash.new { |h, k| h[k] = [] } }
  let(:borrados) { [] }
  let(:peticiones) { [] }

  let(:cliente) do
    lista = peticiones
    acumulado = borrados
    Class.new do
      define_method(:delete_objects) do |bucket:, delete:|
        lista << delete[:objects].size
        acumulado.concat(delete[:objects].map { |o| o[:key] })
        bucket
      end
    end.new
  end

  let(:servicio) do
    almacen = objetos
    envoltorio = Struct.new(:client).new(cliente)
    cubo = Class.new do
      define_method(:name) { "cubo-de-prueba" }
      define_method(:objects) do |prefix:|
        almacen[prefix].map { |clave| Struct.new(:key).new(clave) }
      end
    end.new
    doble = Object.new
    doble.define_singleton_method(:bucket) { cubo }
    doble.define_singleton_method(:client) { envoltorio }
    doble.define_singleton_method(:url) { |clave, **| "https://ejemplo/#{clave}" }
    doble
  end

  subject(:purga) { described_class.new(servicio, umbral: 100) }

  it "does not touch S3 until it is flushed" do
    purga.delete("una")
    purga.delete("otra")

    expect(borrados).to be_empty
    expect(purga.pendientes).to eq(2)
  end

  it "sends everything it collected in one request" do
    purga.delete("una")
    purga.delete("otra")

    expect(purga.vaciar).to eq(2)
    expect(borrados).to contain_exactly("una", "otra")
    expect(peticiones).to eq([2])
  end

  it "never asks S3 for more than a thousand keys at a time" do
    2_500.times { |i| purga.delete("clave-#{i}") }
    purga.vaciar

    expect(peticiones).to all(be <= described_class::MAXIMO_POR_PETICION)
    expect(peticiones.sum).to eq(2_500)
  end

  it "resolves prefixes by listing them and deletes what it finds" do
    objetos["variants/abc/"] = ["variants/abc/uno", "variants/abc/dos"]
    purga.delete("abc")
    purga.delete_prefixed("variants/abc/")

    purga.vaciar

    expect(borrados).to contain_exactly("abc", "variants/abc/uno", "variants/abc/dos")
    expect(purga.prefijos_resueltos).to eq(1)
  end

  it "flushes by itself once too much has piled up, and loses nothing" do
    120.times { |i| purga.delete("clave-#{i}") }

    expect(borrados.size).to eq(100)   # se vació sola al alcanzar el umbral
    expect(purga.pendientes).to eq(20) # y lo que vino después sigue en cola

    purga.vaciar

    expect(borrados.size).to eq(120)
  end

  it "writes the keys down before sending them, so a crash leaves a trail" do
    registro = Tempfile.new("claves")
    con_registro = described_class.new(servicio, registro: registro.path)
    con_registro.delete("una")
    con_registro.delete("otra")
    con_registro.vaciar

    expect(File.read(registro.path).split("\n")).to contain_exactly("una", "otra")
  end

  it "delegates anything that is not a deletion to the real service" do
    expect(purga.url("una")).to eq("https://ejemplo/una")
    expect(purga).to respond_to(:url)
  end

  it "counts a flush with nothing pending as zero and stays quiet" do
    expect(purga.vaciar).to eq(0)
    expect(peticiones).to be_empty
  end
end
