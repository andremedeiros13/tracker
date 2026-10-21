# frozen_string_literal: true

module Tracking
  module Parsers
    # Corpo de PR desta org segue um template fixo:
    #   :ticket: [CHEKOUT-2301](url)
    #   # :construction: Problema
    #   ...
    #   # :white_check_mark: Solução
    #   ...
    #   # :wrench: Setup
    #
    # É daqui que sai o "Antes"/"Fiz" do Brag — o corpo do PR diz o que
    # mudou; a descrição do ticket só diz o que foi pedido. Código puro,
    # sem rede (a diretriz do projeto proíbe IA; nada é resumido por modelo,
    # só recortado).
    class PullRequestBody
      # Cabeçalhos do template. O emoji chega como shortcode (:construction:)
      # ou como caractere — o parser aceita os dois.
      SECOES = {
        problema: %r{\A#\s*(?::construction:|🏗️?|🚧)?\s*Problema\s*\z}i,
        solucao: %r{\A#\s*(?::white_check_mark:|✅)?\s*Solução\s*\z}i,
        setup: %r{\A#\s*(?::wrench:|🔧)?\s*Setup\s*\z}i,
        testes: %r{\A#\s*(?::test_tube:|🧪)?\s*Cenários de Testes\s*\z}i
      }.freeze

      # Teto por seção: o Brag é registro escaneável, não o PR inteiro. 450
      # corta menos no meio de uma ideia do que 280 (que partia frases ao meio
      # nos PRs reais de 2026-10-21).
      LIMITE = 450

      def call(body)
        secoes = dividir(body.to_s)
        {
          problema: recortar(secoes[:problema]),
          solucao: recortar(secoes[:solucao])
        }
      end

      private

      # Divide o corpo nas seções do template. Tudo antes do primeiro
      # cabeçalho reconhecido (a linha do :ticket:, por exemplo) é descartado.
      def dividir(body)
        secoes = {}
        atual = nil
        body.each_line do |linha|
          linha = linha.rstrip
          cabecalho = SECOES.find { |_, regex| linha.match?(regex) }&.first
          if cabecalho
            atual = cabecalho
            secoes[atual] ||= []
          elsif linha.start_with?("# ")
            atual = nil # outro cabeçalho de nível 1 fecha a seção conhecida
          elsif atual
            secoes[atual] << linha
          end
        end
        secoes.transform_values { |linhas| linhas.join("\n").strip }
      end

      # Primeira frase + até 2 bullets, cortado em LIMITE. A primeira frase de
      # "Problema" costuma ser o resumo inteiro ("O POST responde 204 e não
      # grava nada"); os bullets são as decisões.
      #
      # Tabelas ("| Mudança | Arquivo |") não cabem num bullet do Brag e viram
      # lixo de pipe — são descartadas antes de escolher a frase.
      def recortar(texto)
        return if texto.blank?

        linhas = texto.lines.map(&:rstrip).reject { |l| l.strip.start_with?("|") }
        corpo = linhas.join("\n")
        return if corpo.blank?

        paragrafos = corpo.split(/\n{2,}/)
        primeira = limpar_md(paragrafos.first.to_s.squish)
        frase = primeira.split(/(?<=[.!?])\s+/).first.to_s
        bullets = paragrafos.flat_map { |p| p.lines.map(&:strip) }
                            .select { |l| l.start_with?("- ", "* ") }.first(2)
                            .map { |l| limpar_md(l.sub(/\A[-*]\s+/, "")) }
        partes = [ frase, *bullets ].reject(&:blank?)
        # " · " entre a frase e os bullets: sem isso, "…criada. - Elegibilidade:"
        # — o hífen do markdown vira lixo no meio do bullet do Notion.
        texto_final = partes.join(" · ").squish
        texto_final.length > LIMITE ? "#{texto_final[0, LIMITE - 1].rstrip}…" : texto_final
      end

      # O corpo do PR é markdown; o Brag mostra texto puro (negrito e código
      # apareceriam como asteriscos/backticks literais no Notion).
      def limpar_md(texto)
        texto.gsub(/\*\*|__/, "").delete("`").gsub(/\s+/, " ").strip
      end
    end
  end
end
