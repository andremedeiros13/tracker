# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Tracking::UseCases::RepairBragOrder do
  let(:dir) { Dir.mktmpdir }
  let(:client) { instance_double(Tracker::Notion::Client) }
  let(:logger) { instance_double(ActiveSupport::Logger, info: nil, warn: nil, error: nil) }
  let(:stdout) { StringIO.new }
  let(:ledger) { Tracker::Brag::BlockLedger.new(path: File.join(dir, "state.json"), page_id: "page-brag", logger:) }
  let(:dia21) { Date.new(2026, 10, 21) }
  let(:dia22) { Date.new(2026, 10, 22) }
  let(:sentinel) { Tracking::Renderers::BragBlocks::SENTINEL }

  before do
    allow(Rails).to receive(:root).and_return(Pathname.new(dir))
    allow(client).to receive(:delete_block) { { "object" => "block" } }
    allow(Tracking::UseCases::RebuildDayReport).to receive(:new).and_return(instance_double(Tracking::UseCases::RebuildDayReport, call: 1))
  end

  after { FileUtils.remove_entry(dir) }

  def bloco(id, type, texto)
    { "id" => id, "type" => type, type => { "rich_text" => [ { "plain_text" => texto } ] } }
  end

  def header(id, texto) = bloco(id, "heading_2", texto)
  def sentinela(id) = bloco(id, "paragraph", sentinel)
  def bullet(id, texto = id) = bloco(id, "bulleted_list_item", texto)

  # Página no estado do bug: conteúdo de 22 dentro da seção de 21, e o header
  # de 22 no fim da página (vazio).
  let(:pagina) do
    [
      header("h-21", "21/10/2026 — quarta"),
      sentinela("s-21"),
      bullet("b-22-card"),   # criado 22/10, caiu aqui
      bullet("b-21-card"),
      header("h-22", "22/10/2026 — quinta")
    ]
  end

  before do
    allow(client).to receive(:block_children).and_return(pagina)
    ledger.record(dia21, header_id: "h-21", sentinel_id: "s-21", blocks: [ { id: "b-21-card", signature: "s" } ])
    ledger.record(dia22, header_id: "h-22", sentinel_id: "s-21", blocks: [ { id: "b-22-card", signature: "s" } ])
  end

  def descrito(apply: false)
    described_class.new(client:, page_id: "page-brag", ledger:, logger:, stdout:, apply:)
  end

  it "em dry-run não apaga nem reconstrói nada" do
    descrito.call

    expect(client).not_to have_received(:delete_block)
    expect(Tracking::UseCases::RebuildDayReport).not_to have_received(:new)
    expect(stdout.string).to include("dry-run")
    expect(stdout.string).to include("22/10/2026")
  end

  it "aplica: apaga header, sentinel e corpo dos dias, e reconstrói em ordem decrescente" do
    ordem = []
    allow(Tracking::UseCases::RebuildDayReport).to receive(:new) do |*_args, **_kw|
      instance_double(Tracking::UseCases::RebuildDayReport).tap do |dbl|
        allow(dbl).to receive(:call) { |dia| ordem << dia; 1 }
      end
    end

    descrito(apply: true).call

    expect(client).to have_received(:delete_block).with("h-21")
    expect(client).to have_received(:delete_block).with("s-21")
    expect(client).to have_received(:delete_block).with("b-21-card")
    expect(client).to have_received(:delete_block).with("b-22-card")
    expect(client).to have_received(:delete_block).with("h-22")

    # Reconstrói do mais novo para o mais antigo (o primeiro entra no topo).
    expect(ordem).to eq([ dia22, dia21 ])
  end

  it "esquece o ledger dos dias reparados" do
    descrito(apply: true).call

    expect(ledger.day(dia21)).to be_nil
    expect(ledger.day(dia22)).to be_nil
  end

  it "nunca apaga bloco que não está em ledger nenhum (escrito à mão)" do
    manual = bullet("manual-1", "minha nota")
    allow(client).to receive(:block_children).and_return(pagina + [ manual ])

    descrito(apply: true).call

    expect(client).not_to have_received(:delete_block).with("manual-1")
  end

  it "grava backup do texto de cada seção antes de apagar" do
    descrito(apply: true).call

    caminho = File.join(dir, "storage/tracking/brag_2026-10-22-antes-do-repair.bak")
    expect(File).to exist(caminho)
    expect(File.read(caminho)).to include("22/10/2026")
  end
end
