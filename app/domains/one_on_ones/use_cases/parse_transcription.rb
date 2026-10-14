# frozen_string_literal: true

module OneOnOnes
  module UseCases
    # Parser nativo da transcrição do Meet ("Anotações do Gemini") — código
    # puro, sem IA/LLM (PRD) e sem rede/IO. A estrutura do export é regular:
    # múltiplas reuniões por arquivo (delimitadas por data + `## título`),
    # `### Resumo`/`### Decisões` (temas), `### Próximas etapas` (checkboxes
    # com dono entre colchetes), `### Detalhes` + transcrição crua (ignorada
    # — fica no arquivo original).
    class ParseTranscription
      # Data que abre uma reunião: "set. 23, 2026" (formato do Meet, meses
      # abreviados em pt-BR).
      DATA_REUNIAO = /\A\w{3}\.? \d{1,2}, \d{4}\z/

      # "set." é abreviação pt-BR — Date.parse só entende "Sep".
      MESES_PT_BR = {
        "jan" => "Jan", "fev" => "Feb", "mar" => "Mar", "abr" => "Apr",
        "mai" => "May", "jun" => "Jun", "jul" => "Jul", "ago" => "Aug",
        "set" => "Sep", "out" => "Oct", "nov" => "Nov", "dez" => "Dec"
      }.freeze

      SECAO_RESUMO = "Resumo"
      SECAO_DECISOES = "Decisões"
      SECAO_PROXIMAS = "Próximas etapas"

      def call(content)
        linhas = content.lines.map(&:rstrip)
        reunioes = dividir_em_reunioes(linhas)

        resultado = reunioes.map do |trecho|
          meeting = reuniao_do(trecho)
          [ meeting, action_items_do(trecho, meeting) ]
        end

        {
          meetings: resultado.map(&:first),
          action_items: resultado.flat_map(&:last)
        }
      end

      private

      def dividir_em_reunioes(linhas)
        reunioes = []
        atual = nil
        linhas.each do |linha|
          if linha.match?(DATA_REUNIAO)
            reunioes << atual if atual
            atual = [ linha ]
          elsif atual
            atual << linha
          end
        end
        reunioes << atual if atual
        reunioes
      end

      def reuniao_do(trecho)
        titulo_linha = trecho.find { |l| l.match?(/\A## /) }
        data = trecho.first
        Entities::Meeting.new(
          date: parse_data(data),
          title: limpar_md(titulo_linha&.sub(/\A## /, "") || "Reunião"),
          participants: trecho.flat_map { |l| l.scan(/\[([^\]]+)\]\(mailto:/).map(&:first) }.uniq,
          summary: limpar_md(resumo_do(trecho).join("\n").strip),
          source_file: nil
        )
      end

      # Resumo = conteúdo de Resumo + Decisões, até Próximas etapas ou outra
      # seção; Detalhes e transcrição crua ficam no arquivo original.
      def resumo_do(trecho)
        resumo = []
        secao = nil
        trecho.drop(1).each do |linha|
          case secao_titulo(linha)
          when SECAO_RESUMO, SECAO_DECISOES
            secao = :capturar
          when SECAO_PROXIMAS
            break
          when nil, "" then nil
          else
            break if secao_titulo(linha)
            break if linha.match?(/\A#{Regexp.escape("### **00")}/) # timestamps da transcrição crua
          end

          resumo << linha if secao == :capturar
        end
        resumo
      end

      # Action items: checkboxes "- [ ] \[Nome\] Título: descrição" — o
      # export escapa os colchetes (barra invertida literal).
      def action_items_do(trecho, meeting)
        dentro = false
        trecho.filter_map do |linha|
          secao = secao_titulo(linha)
          if secao
            dentro = secao == SECAO_PROXIMAS
            next
          end
          next unless dentro

          match = linha.match(/\A- \[[ x]\] \\?\[([^\]]+)\\?\]\s*(.+)\z/)
          next unless match

          Entities::ActionItem.new(
            meeting: meeting,
            description: limpar_md(match[2].strip),
            owner: limpar_md(match[1].strip),
            mine: false
          )
        end
      end

      # Título da seção: "### **Resumo**" → "Resumo" (o export usa bold).
      def secao_titulo(linha)
        linha.match(/\A### \*?\*?([^*]+)\*?\*?\s*$/)&.captures&.first&.strip
      end

      # Normaliza bold/escapes do export do Meet (o export escapa `\[`/`\]`
      # e a captura do regex deixa a barra invertida residual no fim).
      def limpar_md(texto)
        texto.gsub("**", "").gsub("\\[", "[").gsub("\\]", "]").delete("\\")
      end

      def parse_data(valor)
        data = valor.strip.sub(/\A(\w{3})\.? /) { "#{MESES_PT_BR.fetch(Regexp.last_match(1).downcase, Regexp.last_match(1))} " }
        Date.parse(data)
      end
    end
  end
end
