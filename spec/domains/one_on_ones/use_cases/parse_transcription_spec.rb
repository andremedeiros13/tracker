# frozen_string_literal: true

require "rails_helper"

RSpec.describe OneOnOnes::UseCases::ParseTranscription do
  let(:parser) { described_class.new }

  describe "#call" do
    context "com a transcrição real do Meet (fixture do issue #3)" do
      let(:content) { Rails.root.join("spec/fixtures/transcricao-real.md").read }
      let(:resultado) { parser.call(content) }

      it "encontra a reunião principal (e ignora a transcrição crua como reunião separada)" do
        titulos = resultado[:meetings].map(&:title)

        expect(titulos.first).to eq("1:1 André / Spalenza")
      end

      it "extrai data, participantes e resumo da reunião principal" do
        meeting = resultado[:meetings].first

        expect(meeting.date).to eq(Date.new(2026, 9, 23))
        expect(meeting.participants).to eq([ "André Medeiros", "Rodolfo Spalenza" ])
        expect(meeting.summary).to include("Gestão de Débito Técnico")
        expect(meeting.summary).to include("Proibição do uso do modo automático")
      end

      it "extrai todos os action items dos checkboxes com dono (8 na transcrição real)" do
        itens = resultado[:action_items]

        expect(itens.size).to eq(8)
        expect(itens.map(&:owner).uniq).to contain_exactly("André Medeiros", "Rodolfo Spalenza")
      end

      it "extrai descrição sem escapes e sem o dono (7 do André, 1 do Rodolfo)" do
        itens = resultado[:action_items]
        assinar = itens.find { |i| i.description.include?("Newsletter") }

        expect(assinar.owner).to eq("André Medeiros")
        expect(assinar.description).to start_with("Assinar Newsletter:")
        expect(assinar.description).to include("newsletter AI Hero")
        expect(assinar.mine).to be(false)

        expect(itens.count { |i| i.owner == "André Medeiros" }).to eq(7)
        expect(itens.count { |i| i.owner == "Rodolfo Spalenza" }).to eq(1)
      end

      it "normaliza bold dos headers e do conteúdo" do
        meeting = resultado[:meetings].first

        expect(meeting.title).not_to include("**")
        expect(meeting.summary).not_to include("**")
        expect(resultado[:action_items].map(&:description)).to all(be_a(String))
      end

      it "não inclui os Detalhes e a transcrição crua no resumo" do
        summary = resultado[:meetings].first.summary

        expect(summary).not_to include("00:06:48")
        expect(summary).not_to include("Revise as anotações do Gemini")
      end
    end

    context "com conteúdo vazio" do
      it "retorna listas vazias" do
        resultado = parser.call("")

        expect(resultado).to eq({ meetings: [], action_items: [] })
      end
    end

    context "com uma única reunião simples (estrutura mínima)" do
      let(:content) do
        <<~MD
          set. 23, 2026

          ## **1:1 Teste**

          convidado [Maria Silva](mailto:maria@example.com)

          ### **Resumo**

          Tema discutido.

          ### **Próximas etapas**

          - [ ] \\[Maria Silva\\] Tarefa: fazer algo.
        MD
      end

      it "extrai a reunião e o action item com dono" do
        resultado = parser.call(content)

        expect(resultado[:meetings].size).to eq(1)
        expect(resultado[:meetings].first.participants).to eq([ "Maria Silva" ])
        expect(resultado[:action_items].size).to eq(1)
        expect(resultado[:action_items].first).to have_attributes(
          owner: "Maria Silva", description: "Tarefa: fazer algo.", mine: false
        )
      end
    end
  end
end
