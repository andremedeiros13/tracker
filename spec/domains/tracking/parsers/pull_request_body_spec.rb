# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::Parsers::PullRequestBody do
  let(:parser) { described_class.new }

  # Recorte do corpo real do PR #1216 (ResultadosDigitais/totvs-pay).
  def corpo_1216
    <<~MD
      :ticket: [CHEKOUT-2301](https://rdstation.atlassian.net/browse/CHEKOUT-2301)
      :memo: [Techdoc da frente 2, seção 4.7 (CHEKOUT-2278)](https://rdstation.atlassian.net/browse/CHEKOUT-2278)

      # :construction: Problema

      O CHEKOUT-2307 entregou a porta da captura com um `{}` que não captura nada: a rota responde `204` e não grava nada. Quem reservou o valor no cartão (`capture: false` nas rotas de criação) não tem como cobrá-lo depois, e a venda fica `authorized` para sempre.

      # :white_check_mark: Solução

      A rota passa a registrar a solicitação de captura e a chamar o provedor dentro do próprio HTTP, respondendo `202` com a operação criada.

      | Situação | Resposta |
      | --- | --- |
      | Venda `authorized` com `capture: false` | `202` |

      - **Elegibilidade:** `PaymentIntent#capturable?` no model de contexto.
      - **Concorrência:** `payment_intent.with_lock` cobre a busca por chave.

      # :wrench: Setup

      Nenhuma dependência nova.
    MD
  end

  describe "#call" do
    it "extrai a primeira frase e os bullets de Problema e Solução" do
      secoes = parser.call(corpo_1216)

      expect(secoes[:problema]).to start_with("O CHEKOUT-2307 entregou a porta da captura com um {} que não captura nada")
      expect(secoes[:solucao]).to include("Elegibilidade:")
      expect(secoes[:solucao]).to include("Concorrência:")
      expect(secoes[:solucao]).not_to include("Venda `authorized` com `capture: false`") # tabela fora
      expect(secoes[:solucao]).not_to include("Nenhuma dependência nova") # Setup fora
    end

    it "tolera cabeçalho sem emoji" do
      secoes = parser.call("# Problema\n\nNada grava.\n\n# Solução\n\nGrava.")

      expect(secoes).to eq(problema: "Nada grava.", solucao: "Grava.")
    end

    it "retorna nil quando a seção não existe" do
      secoes = parser.call("# :construction: Problema\n\nSó isso.")

      expect(secoes[:problema]).to eq("Só isso.")
      expect(secoes[:solucao]).to be_nil
    end

    it "retorna nil para corpo vazio ou sem template" do
      expect(parser.call("")).to eq(problema: nil, solucao: nil)
      expect(parser.call("texto solto")).to eq(problema: nil, solucao: nil)
    end

    it "corta no limite para o Brag continuar escaneável" do
      # Uma única frase longa (sem ponto no meio) — o corte é o teto.
      texto = "#{"a" * 500}."

      secao = parser.call("# Problema\n\n#{texto}")[:problema]

      expect(secao.length).to be <= described_class::LIMITE
      expect(secao).to end_with("…")
    end

    it "fica só na primeira frase (o resto do parágrafo não entra)" do
      secao = parser.call("# Problema\n\nPrimeira. Segunda frase não entra.")[:problema]

      expect(secao).to eq("Primeira.")
    end
  end
end
