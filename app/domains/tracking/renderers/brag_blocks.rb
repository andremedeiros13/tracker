# frozen_string_literal: true

require "digest"

module Tracking
  module Renderers
    # DayReport → blocks do Notion. Código puro: nada de rede, nada de formato
    # de API além do shape dos blocks (que é estável e documentado).
    #
    # Formato (decisão de 2026-10-21, "exemplo A"):
    #
    #   ## 21/10/2026 — quarta · [Motor][Wave2] Pagamento com até 3 cartões
    #   • #2301 · [Payments] T11 POST /payments/{id}/capture: cobrar… — MERGEADO 16:48
    #       PR #1216 · 14 commits · 17 arquivos · +1257/−55
    #       5 comentários meus · aprovado por Marivaldo
    #       Antes: a rota respondia 204 e não gravava nada…
    #       Fiz: grava a solicitação, chama o provedor…
    #   • #2332 · captured_at da Bill — card de Itallo
    #       movi Review → Ready for Deploy · aprovei o PR #1211
    #
    # Um item por card (não por evento de API), sem chave de dedup no texto.
    #
    # Este módulo é o dono da copy do documento. O adapter entrega estado de
    # domínio (`:approved`), não texto: antes o estado de review tinha mapa nos
    # dois lados — o adapter devolvia "Aprovado" e este arquivo mantinha o seu
    # próprio mapa para os mesmos estados.
    class BragBlocks
      SENTINEL = "gerado pelo Tracker — edições neste trecho são sobrescritas a cada ciclo"

      DIAS = %w[domingo segunda terça quarta quinta sexta sábado].freeze

      ESTADOS = {
        merged: "MERGEADO", done: "CONCLUÍDO", in_progress: "EM ANDAMENTO",
        moved: "card de", reviewed: "REVISADO", commented: "COMENTADO"
      }.freeze

      # Estados de review do GitHub → o que o leitor vê. O adapter entrega o
      # estado de domínio; a tradução é só daqui.
      ESTADOS_DE_REVIEW = {
        approved: "Aprovado",
        changes_requested: "Mudanças solicitadas",
        commented: "Comentou",
        dismissed: "Review dispensada"
      }.freeze

      # Assinatura do bloco: usado pelo ledger para saber se algo mudou. Exclui
      # `object` (constante) para não variar por detalhe de payload.
      def self.signature(block)
        conteudo = block.reject { |chave, _| chave == :object }
        "sha256:#{Digest::SHA256.hexdigest(JSON.generate(conteudo))}"
      end

      # Épico do header: cortado, senão um nome de 90 chars come a linha
      # inteira do dia ("[Motor][Wave2] Pagamento com até 3 cartões - Fluxo de
      # captura e gestão do ciclo de vida" → "[Motor][Wave2] Pagamento com até
      # 3 cartões"). O nome completo está em cada card, se precisar.
      EPICO_MAX = 60

      # Data do header ("21/10/2026") — formato único, compartilhado com o
      # leitor de seções (Tracker::Notion::PageDays), que usa o mesmo marcador
      # para achar a seção do dia quando o ledger não está disponível.
      def self.data_do_dia(day) = Tracker::Notion::PageDays.marker(day)

      def header(day, epic_note)
        texto = "#{self.class.data_do_dia(day)} — #{DIAS[day.to_date.wday]}"
        texto = "#{texto} · #{resumir(epic_note)}" if epic_note.present?
        paragrafo(texto, tipo: "heading_2", chave: :heading_2)
      end

      def resumir(texto)
        texto = texto.to_s.squish
        texto.length > EPICO_MAX ? "#{texto[0, EPICO_MAX - 1].rstrip}…" : texto
      end

      def sentinel
        {
          object: "block", type: "paragraph",
          paragraph: {
            rich_text: [ { type: "text", text: { content: SENTINEL },
                           annotations: { color: "gray", italic: true } } ]
          }
        }
      end

      def sem_atividade
        paragrafo("— sem atividade registrada —", cor: "gray")
      end

      # Body do dia: um bullet por item, com os sub-bullets de evidência. Dia
      # vazio ainda ganha um bloco (o "sem atividade"): a seção de um dia que
      # já existiu continua existindo.
      def items(report)
        return [ sem_atividade ] if report.vazio?

        blocos = report.work_items.map { |item| bloco_do_item(item) }
        blocos << bloco_de_reviews(report.given_reviews) if report.given_reviews.any?
        blocos << bloco_de_commits(report.commits) if report.commits.any?
        blocos.compact
      end

      private

      def bloco_do_item(item)
        filhos = filhos_do_item(item)
        {
          object: "block",
          type: "bulleted_list_item",
          bulleted_list_item: {
            rich_text: texto_do_item(item),
            children: filhos
          }
        }
      end

      # "#2301 · " + título (link) + " — MERGEADO 16:48" (ou "card de Itallo").
      def texto_do_item(item)
        textos = [ { type: "text", text: { content: "#{item.referencia} · " } } ]
        # O link vai DENTRO de `text` — ao lado, a API responde 400
        # ("rich_text[1].link should be not present").
        textos << { type: "text", text: { content: item.title, link: { url: item.url } } }
        if (sufixo = sufixo_de_estado(item))
          textos << { type: "text", text: { content: " — #{sufixo}" }, annotations: { bold: true } }
        end
        textos
      end

      def sufixo_de_estado(item)
        case item.outcome
        when :merged then "MERGEADO #{hora(item.outcome_at)}".strip
        when :done then "CONCLUÍDO"
        when :in_progress then "EM ANDAMENTO"
        when :moved then "card de #{item.owner_name || 'outra pessoa'}"
        else ESTADOS.fetch(item.outcome, "")
        end
      end

      # Linhas de evidência, na ordem em que o leitor quer: o que aconteceu,
      # com quem, por quê.
      def filhos_do_item(item)
        linhas = item.pull_requests.map { |pr| linha_do_pr(pr, item) }
        # Review que eu dei no card de outra pessoa vem antes da cadeia de
        # status: é o que eu fiz ali, não a coluna em que o card estava.
        linhas << item.reviews_given.map { |review| linha_da_review_dada(review) }.join(" · ") if item.reviews_given.any?
        linhas << linha_de_reviews(item)
        linhas << linha_de_status(item)
        linhas << "Antes: #{item.problema}" if item.problema.present?
        linhas << "Fiz: #{item.solucao}" if item.solucao.present?
        linhas.compact_blank.map { |linha| sub_bullet(linha) }
      end

      # "aprovei o PR #1211" — a review anexada à linha do card. O WorkItem
      # guarda a review, não esta linha: a copy é daqui.
      def linha_da_review_dada(review)
        "#{estado_da_review(review.state).downcase} o PR ##{review.pull_request.number}"
      end

      def linha_do_pr(pr, item)
        partes = [ "PR ##{pr.number}" ]
        partes << pr.metricas if pr.metricas
        partes << "aberto #{data_hora(pr.created_at, item_day(item))}"
        partes << "mergeado #{hora(pr.merged_at)}" if pr.merged_at
        partes.join(" · ")
      end

      def item_day(item) = (item.outcome_at || item.last_activity_at || Time.current).to_date

      def linha_de_reviews(item)
        partes = []
        partes << "#{item.comments_count} comentário#{'s' unless item.comments_count == 1} meu#{'s' unless item.comments_count == 1}" if item.comments_count.positive?
        partes << "aprovado por #{item.reviews_received.join(', ')}" if item.reviews_received.any?
        partes.join(" · ").presence
      end

      # Cadeia de status só em item NÃO concluído: no concluído ela é implícita.
      def linha_de_status(item)
        return if item.concluded? || item.status_chain.empty?

        item.status_chain.join(" · ")
      end

      def bloco_de_reviews(reviews)
        filhos = reviews.map do |review|
          sub_bullet("PR ##{review.pull_request.number} · #{review.pull_request.title} — #{estado_da_review(review.state)}")
        end
        {
          object: "block", type: "bulleted_list_item",
          bulleted_list_item: { rich_text: [ { type: "text", text: { content: "Revisões que eu fiz" },
                                               annotations: { bold: true } } ], children: filhos }
        }
      end

      # Estado de review → copy do documento. Falha alto: um estado novo sem
      # tradução é bug de código, não motivo para imprimir o símbolo cru.
      def estado_da_review(estado)
        ESTADOS_DE_REVIEW.fetch(estado.to_sym) { raise KeyError, "estado de review sem tradução: #{estado.inspect}" }
      end

      def bloco_de_commits(commits)
        filhos = commits.map { |commit| sub_bullet("#{commit.short_sha} #{commit.message} (#{commit.repo})") }
        {
          object: "block", type: "bulleted_list_item",
          bulleted_list_item: { rich_text: [ { type: "text", text: { content: "Commits soltos" },
                                               annotations: { bold: true } } ], children: filhos }
        }
      end

      def sub_bullet(linha)
        { object: "block", type: "bulleted_list_item",
          bulleted_list_item: { rich_text: [ { type: "text", text: { content: linha } } ] } }
      end

      def paragrafo(texto, tipo: "paragraph", chave: :paragraph, cor: nil)
        texto_rich = { type: "text", text: { content: texto } }
        texto_rich[:annotations] = { color: cor } if cor
        { object: "block", type: tipo, chave => { rich_text: [ texto_rich ] } }
      end

      def data_hora(instante, day)
        return hora(instante) if instante.to_date == day.to_date

        instante.strftime("%d/%m %H:%M")
      end

      def hora(instante) = instante&.strftime("%H:%M").to_s
    end
  end
end
