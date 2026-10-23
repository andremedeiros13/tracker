# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracker::Notion::PageDays do
  let(:client) { instance_double(Tracker::Notion::Client) }
  let(:page_days) { described_class.new(client: client, page_id: "page-1") }
  let(:dia) { Date.new(2026, 10, 21) }

  def bloco(id:, type: "bulleted_list_item", texto: "conteúdo")
    { "id" => id, "type" => type, type => { "rich_text" => [ { "plain_text" => texto } ] } }
  end

  def header(id: "h1", texto: "21/10/2026 — quarta")
    bloco(id:, type: "heading_2", texto:)
  end

  before do
    allow(client).to receive(:block_children).and_return([
      header(id: "h1", texto: "20/10/2026 — terça"),
      bloco(id: "b-ontem", texto: "ontem"),
      header(id: "h2", texto: "21/10/2026 — quarta"),
      bloco(id: "b1", texto: "hoje 1"),
      bloco(id: "b2", texto: "hoje 2"),
      header(id: "h3", texto: "22/10/2026 — quinta"),
      bloco(id: "b-amanha")
    ])
  end

  describe "#section" do
    it "coleta header + blocos do dia, parando no próximo header" do
      expect(page_days.section(dia).map { |b| b.fetch("id") }).to eq(%w[h2 b1 b2])
    end

    it "funciona em página decrescente (a seção termina no dia ANTERIOR)" do
      allow(client).to receive(:block_children).and_return([
        header(id: "h2", texto: "21/10/2026 — quarta"),
        bloco(id: "b1"),
        header(id: "h1", texto: "20/10/2026 — terça"),
        bloco(id: "b-ontem")
      ])

      expect(page_days.section(dia).map { |b| b.fetch("id") }).to eq(%w[h2 b1])
    end

    it "aceita uma leitura já feita em `blocks:` (sem ir ao client)" do
      leitura = [ header(id: "h2", texto: "21/10/2026 — quarta"), bloco(id: "b1") ]

      expect(page_days.section(dia, blocks: leitura).map { |b| b.fetch("id") }).to eq(%w[h2 b1])
      expect(client).not_to have_received(:block_children)
    end

    it "com prefixo: casa o header com dia da semana (formato do Brag)" do
      expect(page_days.section(dia, prefixo: true).first.fetch("id")).to eq("h2")
    end

    it "exato: não casa header com sufixo extra (formato do 1-on-1)" do
      expect(page_days.section(dia, prefixo: false)).to be_empty
    end

    it "dia sem seção devolve vazio" do
      expect(page_days.section(Date.new(2020, 1, 1))).to be_empty
    end
  end

  describe "#day_of / #section_days" do
    it "lê a data do header, ignorando o sufixo (dia da semana e épico)" do
      expect(page_days.day_of(header(texto: "21/10/2026 — quarta · [Motor][Wave2] Pagamento")))
        .to eq(dia)
    end

    it "devolve nil para header sem data e para bloco que não é header" do
      expect(page_days.day_of(header(texto: "sem data aqui"))).to be_nil
      expect(page_days.day_of(bloco(id: "b1"))).to be_nil
    end

    it "lista as datas na ordem em que aparecem na página" do
      expect(page_days.section_days).to eq([ Date.new(2026, 10, 20), dia, Date.new(2026, 10, 22) ])
    end
  end

  describe "#header_exists?" do
    it "é verdadeiro para o header exato do dia" do
      allow(client).to receive(:block_children).and_return([ header(texto: "21/10/2026") ])

      expect(page_days.header_exists?(dia)).to be(true)
    end

    it "não confunde o header de outro dia" do
      expect(page_days.header_exists?(Date.new(2020, 1, 1))).to be(false)
    end
  end

  describe "#ids_after" do
    it "devolve os blocos abaixo do sentinel até o próximo header" do
      allow(client).to receive(:block_children).and_return([
        header,
        bloco(id: "sentinel", type: "paragraph"),
        bloco(id: "b1"), bloco(id: "b2"),
        header(id: "h3", texto: "22/10/2026 — quinta"),
        bloco(id: "b-amanha")
      ])

      expect(page_days.ids_after(dia, "sentinel")).to eq(%w[b1 b2])
    end
  end

  describe "#text" do
    it "extrai plain_text do payload da API" do
      expect(page_days.text(header)).to eq("21/10/2026 — quarta")
    end

    it "também aceita rich_text no shape do renderer (chaves símbolo)" do
      bloco_renderer = { "type" => "paragraph",
                         "paragraph" => { rich_text: [ { text: { content: "olá" } } ] } }

      expect(page_days.text(bloco_renderer)).to eq("olá")
    end
  end

  describe ".marker" do
    it "é o formato único de data das duas pages" do
      expect(described_class.marker(dia)).to eq("21/10/2026")
    end
  end
end
