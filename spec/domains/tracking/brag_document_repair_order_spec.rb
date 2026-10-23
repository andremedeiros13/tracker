# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Tracking::BragDocument, "#repair_order" do
  let(:dir) { Dir.mktmpdir }
  let(:client) { instance_double(Tracker::Notion::Client) }
  let(:logger) { instance_double(ActiveSupport::Logger, info: nil, warn: nil, error: nil) }
  let(:stdout) { StringIO.new }
  let(:ledger) { Tracker::Brag::BlockLedger.new(path: File.join(dir, "state.json"), page_id: "page-brag", logger:) }
  let(:brag) { described_class.new(client:, page_id: "page-brag", ledger:, logger:, stdout:) }
  # O rebuild de produção coleta o dia na rede; aqui ele é um no-op que só
  # registra a ordem — a migração é o que está sob teste, não a coleta.
  let(:reconstruidos) { [] }
  let(:rebuild) { ->(dia) { reconstruidos << dia } }
  let(:dia21) { Date.new(2026, 10, 21) }
  let(:dia22) { Date.new(2026, 10, 22) }
  let(:sentinel) { Tracking::Renderers::BragBlocks::SENTINEL }

  before do
    allow(Rails).to receive(:root).and_return(Pathname.new(dir))
    allow(client).to receive(:delete_block) { { "object" => "block" } }
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

  it "em dry-run não apaga nem reconstrói nada" do
    brag.repair_order

    expect(client).not_to have_received(:delete_block)
    expect(stdout.string).to include("dry-run")
    expect(stdout.string).to include("22/10/2026")
  end

  it "em dry-run devolve os dias que seriam reconstruídos, em ordem decrescente" do
    expect(brag.repair_order).to eq([ dia22, dia21 ])
  end

  it "aplica: apaga o que está no ledger dos dias e reconstrói em ordem decrescente" do
    brag.repair_order(apply: true, rebuild:)

    # Só o que o ledger conhece. Header e sentinel são do rewrite, não do
    # repair: apagá-los aqui deixaria a página sem âncora se o rebuild falhar.
    expect(client).to have_received(:delete_block).with("b-21-card")
    expect(client).to have_received(:delete_block).with("b-22-card")
    expect(client).not_to have_received(:delete_block).with("h-21")
    expect(client).not_to have_received(:delete_block).with("s-21")
    expect(reconstruidos).to eq([ dia22, dia21 ])
  end

  it "esquece o ledger dos dias reparados" do
    brag.repair_order(apply: true, rebuild:)

    expect(ledger.day(dia21)).to be_nil
    expect(ledger.day(dia22)).to be_nil
  end

  it "nunca apaga bloco que não está em ledger nenhum (escrito à mão)" do
    manual = bullet("manual-1", "minha nota")
    allow(client).to receive(:block_children).and_return(pagina + [ manual ])

    brag.repair_order(apply: true, rebuild:)

    expect(client).not_to have_received(:delete_block).with("manual-1")
  end

  it "grava backup do texto de cada seção antes de apagar" do
    brag.repair_order(apply: true, rebuild:)

    caminho = File.join(dir, "storage/tracking/brag_2026-10-22-antes-do-repair.bak")
    expect(File).to exist(caminho)
    expect(File.read(caminho)).to include("22/10/2026")
  end

  it "um bloco que falha ao apagar não aborta o reparo" do
    allow(client).to receive(:delete_block) do |id|
      # 500 e não 404: o 404 é tratado como sucesso, então não exercitaria o
      # resgate que garante o resto do reparo.
      raise Tracker::Notion::ApiError.new("500", "fora") if id == "b-21-card"

      { "object" => "block" }
    end

    expect { brag.repair_order(apply: true, rebuild:) }.not_to raise_error
  end

  it "página sem seção de dia: não faz nada" do
    allow(client).to receive(:block_children).and_return([])

    expect(brag.repair_order(apply: true, rebuild:)).to eq([])
    expect(stdout.string).to include("nada a reparar")
  end
end
