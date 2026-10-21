# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Tracker::Brag::BlockLedger do
  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "tracking", "brag_state.json") }
  let(:logger) { instance_double(ActiveSupport::Logger, warn: nil, error: nil, info: nil) }
  let(:ledger) { described_class.new(path: path, page_id: "page-brag", logger: logger) }
  let(:dia) { Date.new(2026, 10, 21) }

  after { FileUtils.remove_entry(dir) }

  describe "#record / #day" do
    it "faz round-trip do estado do dia" do
      ledger.record(dia, header_id: "h-1", sentinel_id: "s-1", blocks: [ { id: "b-1", signature: "sha1" } ])

      estado = ledger.day(dia)

      expect(estado).to include(header_id: "h-1", sentinel_id: "s-1")
      expect(estado[:blocks]).to eq([ { id: "b-1", signature: "sha1" } ])
    end

    it "preserva os outros dias ao gravar" do
      ledger.record(Date.new(2026, 10, 20), header_id: "h-0", blocks: [])
      ledger.record(dia, header_id: "h-1", blocks: [])

      expect(ledger.day(Date.new(2026, 10, 20))[:header_id]).to eq("h-0")
      expect(ledger.day(dia)[:header_id]).to eq("h-1")
    end

    it "retorna nil para dia desconhecido" do
      expect(ledger.day(dia)).to be_nil
    end

    it "grava de forma atômica (não deixa tmp para trás)" do
      ledger.record(dia, header_id: "h-1", blocks: [])

      expect(File).to exist(path)
      expect(File).not_to exist("#{path}.tmp")
    end
  end

  describe "fallback" do
    it "trata arquivo corrompido como vazio e avisa" do
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "{ isso não é json")

      expect(ledger.day(dia)).to be_nil
      expect(logger).to have_received(:warn).with(a_string_including("ledger ilegível"))
    end

    it "ignora ledger de outra page" do
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.generate({ "version" => 1, "page_id" => "outra", "days" => { "2026-10-21" => { "header_id" => "x" } } }))

      expect(ledger.day(dia)).to be_nil
    end

    it "ignora versão desconhecida" do
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.generate({ "version" => 99, "page_id" => "page-brag", "days" => { "2026-10-21" => { "header_id" => "x" } } }))

      expect(ledger.day(dia)).to be_nil
    end
  end

  describe "#with_lock" do
    it "executa o bloco quando o lock está livre" do
      expect(ledger.with_lock { :feito }).to eq(:feito)
    end

    it "desiste rápido quando outro processo segura o lock" do
      FileUtils.mkdir_p(File.dirname(path))
      outro = File.open("#{path}.lock", File::RDWR | File::CREAT)
      outro.flock(File::LOCK_EX | File::LOCK_NB)
      comecou = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      resultado = ledger.with_lock(timeout: 0.5) { :nunca }

      decorrido = Process.clock_gettime(Process::CLOCK_MONOTONIC) - comecou
      expect(resultado).to be_nil
      expect(decorrido).to be < 3
    ensure
      outro&.flock(File::LOCK_UN)
      outro&.close
    end
  end

  describe "#forget" do
    it "remove só o dia indicado" do
      ledger.record(dia, header_id: "h-1", blocks: [])
      ledger.record(Date.new(2026, 10, 20), header_id: "h-0", blocks: [])

      ledger.forget(dia)

      expect(ledger.day(dia)).to be_nil
      expect(ledger.day(Date.new(2026, 10, 20))).not_to be_nil
    end
  end
end
