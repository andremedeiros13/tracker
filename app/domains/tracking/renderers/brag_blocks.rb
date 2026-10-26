# frozen_string_literal: true

require "digest"

module Tracking
  module Renderers
    # DayReport → blocks do Notion. Código puro: nada de rede, nada de formato
    # de API além do shape dos blocks (que é estável e documentado).
    #
    # Formato (decisão de 2026-10-21, "exemplo A"):
    #
    #   ## 21/10/2026 — quarta
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

      # Data do header ("21/10/2026") — formato único, compartilhado com o
      # leitor de seções (Tracker::Notion::PageDays), que usa o mesmo marcador
      # para achar a seção do dia quando o ledger não está disponível.
      def self.data_do_dia(day) = Tracker::Notion::PageDays.marker(day)

      # O header identifica o DIA — nada mais. A frente de trabalho (wave) não
      # entra aqui: ela é do card, e o card já aparece com título e estado no
      # próprio item. Antes o épico comum ia no header e precisava ser cortado;
      # o corte caía no meio da palavra ("Fluxo de captu…").
      def header(day)
        Tracker::Notion::Blocks.heading("#{self.class.data_do_dia(day)} — #{DIAS[day.to_date.wday]}")
      end

      # O MESMO conteúdo em texto puro, para o preview (rake tracking:preview e
      # TRACER_DRY_RUN). Mora aqui porque a copy é deste módulo: antes o use
      # case mantinha um segundo caminho de renderização em texto, e os dois
      # precisavam concordar sobre header, ordem e dia vazio.
      def preview(day, report)
        linhas = [ "== #{day.iso8601} ==", "## #{texto_do_bloco(header(day))}" ]
        items(report).each do |bloco|
          linhas << "• #{texto_do_bloco(bloco)}"
          Array(bloco.dig(bloco.fetch(:type).to_sym, :children)).each do |filho|
            linhas << "    - #{texto_do_bloco(filho)}"
          end
        end
        linhas.join("\n")
      end

      def sentinel
        Tracker::Notion::Blocks.paragrafo(SENTINEL, cor: "gray", italico: true)
      end

      def sem_atividade
        Tracker::Notion::Blocks.paragrafo("— sem atividade registrada —", cor: "gray")
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
        Tracker::Notion::Blocks.bullet(runs: texto_do_item(item), filhos: filhos_do_item(item))
      end

      # Texto plano de um bloco renderizado — a leitura da forma é do módulo
      # Notion::Blocks, o mesmo que a escreveu.
      def texto_do_bloco(bloco) = Tracker::Notion::Blocks.texto_de(bloco)

      # "#2301" para card, "PR #1216" para item sem card. Copy, portanto aqui —
      # antes vivia na entity e o domínio carregava formato de documento.
      def referencia_de(item)
        return "##{item.key.split('-').last}" if item.key

        "PR ##{item.pull_requests.first&.number}"
      end

      # "#2301 · " + título (link) + " — MERGEADO 16:48" (ou "card de Itallo").
      def texto_do_item(item)
        textos = [ Tracker::Notion::Blocks.run("#{referencia_de(item)} · ") ]
        # O link vai DENTRO de `text` — o construtor de blocos cuida disso.
        textos << Tracker::Notion::Blocks.run(item.title, link: item.url)
        if (sufixo = sufixo_de_estado(item))
          textos << Tracker::Notion::Blocks.run(" — #{sufixo}", negrito: true)
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
        partes << metricas_do_pr(pr) if metricas_do_pr(pr)
        partes << "aberto #{data_hora(pr.created_at, item_day(item))}"
        partes << "mergeado #{hora(pr.merged_at)}" if pr.merged_at
        partes.join(" · ")
      end

      # "14 commits · 17 arquivos · +1257/−55" — o peso da entrega, que o
      # título não conta. Nil quando o detalhe do PR não veio (falha de rede).
      def metricas_do_pr(pr)
        return unless pr.changed_files

        partes = []
        partes << "#{pr.commits} commit#{'s' unless pr.commits == 1}" if pr.commits
        partes << "#{pr.changed_files} arquivo#{'s' unless pr.changed_files == 1}"
        partes << "+#{pr.additions}/−#{pr.deletions}" if pr.additions && pr.deletions
        partes.join(" · ").presence
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
        grupo("Revisões que eu fiz", filhos)
      end

      # Estado de review → copy do documento. Falha alto: um estado novo sem
      # tradução é bug de código, não motivo para imprimir o símbolo cru.
      def estado_da_review(estado)
        ESTADOS_DE_REVIEW.fetch(estado.to_sym) { raise KeyError, "estado de review sem tradução: #{estado.inspect}" }
      end

      def bloco_de_commits(commits)
        filhos = commits.map { |commit| sub_bullet("#{commit.short_sha} #{commit.message} (#{commit.repo})") }
        grupo("Commits soltos", filhos)
      end

      # Bullet de título em negrito com os filhos por baixo — a forma das duas
      # seções de cauda (revisões dadas, commits soltos).
      def grupo(titulo, filhos)
        Tracker::Notion::Blocks.bullet(
          runs: [ Tracker::Notion::Blocks.run(titulo, negrito: true) ], filhos:
        )
      end

      def sub_bullet(linha) = Tracker::Notion::Blocks.bullet_texto(linha)

      def data_hora(instante, day)
        return hora(instante) if instante.to_date == day.to_date

        instante.strftime("%d/%m %H:%M")
      end

      def hora(instante) = instante&.strftime("%H:%M").to_s
    end
  end
end
