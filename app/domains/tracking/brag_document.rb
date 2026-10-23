# frozen_string_literal: true

module Tracking
  # A seção do dia no Brag document (page no Notion — ADR 0001).
  #
  # Um módulo para a seção inteira: recebe o DayReport e cuida de header,
  # sentinel, ledger, locks e lotes da API. Antes o chamador precisava montar
  # header/sentinel/blocos e consultar o ledger por fora só para decidir se
  # valia escrever — três colaboradores para uma decisão.
  #
  # O documento é RECONSTRUÍDO, não appendado: o valor do dia só se conhece
  # quando o dia acaba (o PR das 11h pode mergear às 18h), então append
  # incremental congela o registro no primeiro ciclo e mostra "PR aberto"
  # para sempre. A cada mudança, a seção do dia é reescrita inteira.
  #
  # ORDEM: decrescente — o dia mais recente fica no topo (decisão de
  # 2026-10-23). Um dia novo entra antes da primeira seção existente; se ele
  # já for o mais antigo (backfill), entra no fim. A seção de um dia pode
  # terminar num header de data ANTERIOR, então nada aqui pode assumir
  # "crescente" ao ler a página.
  #
  # Cada seção tem o SEU sentinel, logo abaixo do header: é o que define onde
  # a seção daquele dia começa e impede que a escrita de um dia caia dentro de
  # outro. (Um sentinel único para a página fazia o ciclo de um dia novo
  # inserir os bullets abaixo do sentinel do dia anterior — bug de 22 e
  # 23/10/2026.)
  #
  # Quem manda apagar é o ledger (Tracker::Brag::BlockLedger): só os ids que
  # nós criamos. Um bloco escrito à mão na seção não está no ledger e nunca é
  # tocado. Sem ledger confiável, cai no fallback por convenção — que só assume
  # posse quando o sentinel está lá.
  class BragDocument
    # Teto de children por chamada da API do Notion.
    LOTE_DE_BLOCKS = 100

    # Client, page e ledger são resolvidos sob demanda: `preview` só renderiza
    # texto e não deve exigir token nem page configurada (o `rake
    # tracking:preview` roda numa máquina que só quer ver o dia).
    def initialize(client: nil, page_id: nil, ledger: nil,
                   renderer: Renderers::BragBlocks.new,
                   logger: Rails.logger,
                   stdout: $stdout)
      @client = client
      @page_id = page_id
      @ledger = ledger
      @renderer = renderer
      @logger = logger
      @stdout = stdout
    end

    # O MESMO conteúdo de `rewrite`, em texto puro — o dono da copy responde
    # pelas duas formas. Nenhum request: é o caminho do `rake tracking:preview`
    # e do TRACER_DRY_RUN, que existem justamente para ler antes de escrever.
    def preview(day, report) = @renderer.preview(day, report)

    # Reescreve a seção do dia com o conteúdo do report.
    #
    # Devolve:
    #   :sem_atividade — dia vazio e sem seção no ledger: não cria seção vazia
    #                    para um dia que nunca teve atividade.
    #   :sem_mudanca   — a assinatura de todos os blocos bate com o ledger:
    #                    NENHUM request de escrita acontece (é o que faz um
    #                    ciclo de 30 min sem novidade custar quase nada).
    #   :reescrito     — apagou o que era nosso e escreveu de novo.
    #   nil            — outro processo segurava o lock: nada foi feito, o
    #                    próximo ciclo tenta (não é erro).
    def rewrite(day, report)
      blocos = @renderer.items(report)
      assinaturas = blocos.map { |bloco| Renderers::BragBlocks.signature(bloco) }

      # Lock entre processos: o daemon e um rake rodando junto (ou dois ticks
      # sobrepostos) reescreviam a mesma seção em paralelo.
      ledger.with_lock do
        estado = ledger.day(day)
        next :sem_atividade if report.vazio? && estado.nil?
        # Comparar ANTES de ler a página: o caminho de "nada mudou" (a maioria
        # dos ciclos) não faz nenhum request.
        next :sem_mudanca if inalterado?(estado, assinaturas)

        rewrite_section(day, report, blocos, assinaturas, estado)
        :reescrito
      end
    end

    # Migração única: marca a seção de um dia que já existe (escrita no formato
    # antigo, um bullet por evento) como gerada pelo Tracker, para que o
    # rewrite possa apagá-la e reescrever no formato novo.
    #
    # Só roda por rake, nunca pelo scheduler — é destrutiva. Antes de tocar no
    # Notion, grava o texto atual em storage/tracking/brag_<dia>.bak.
    def adopt(day)
      secao = page_days.section(day)
      if secao.nil? || secao.empty?
        @stdout.puts("Nenhuma seção em #{Renderers::BragBlocks.data_do_dia(day)} — o rebuild cria uma nova.")
        return 0
      end

      caminho = Tracker::Brag::Backup.section(day, secao.blocks)
      @stdout.puts("Backup: #{caminho}")
      ledger.record(day, header_id: secao.header_id,
                         blocks: secao.body.map { |b| { id: b.fetch("id") } })
      @stdout.puts("Seção de #{Renderers::BragBlocks.data_do_dia(day)} adotada (#{secao.body.size} blocks). Backup em storage/tracking/.")
      secao.body.size
    end

    # Apaga da página todos os blocks que o ledger conhece, de qualquer dia.
    # Base do `repair_order`: a posse é a mesma, então quem sabe apagar é este
    # módulo — o chamador não repete o laço nem o resgate de erro.
    def forget(days)
      ledger.with_lock do
        days.each do |day|
          apagar_do_dia(ledger.day(day))
          ledger.forget(day)
        end
      end
      days.size
    end

    # Conserta a página que ficou fora de ordem (Bug de 22–23/10/2026: o
    # conteúdo de um dia novo caía dentro da seção do dia anterior, numa
    # página crescente).
    #
    # Mora aqui, e não num use case, porque é a mesma posse que o `rewrite`
    # usa: o lock, o backup, o "só apaga o que é nosso" e o resgate de erro
    # por bloco já vivem neste módulo. O chamador (rake) não recombina
    # PageDays + BragDocument + Backup + RebuildDayReport.
    #
    # DESTRUTIVA: dry-run por default; `apply: true` apaga, faz backup em
    # storage/tracking/ e reconstrói do mais novo para o mais antigo (a
    # primeira seção entra no topo e cada seguinte logo depois da anterior, o
    # que produz a ordem decrescente).
    #
    # Devolve a lista de dias que seriam/foram reconstruídos.
    #
    # `rebuild` é injetável: o caminho de produção coleta o dia (rede) e
    # reescreve; o teste passa um lambda e não toca em Jira nem GitHub. Sem
    # isso, testar a migração exigiria rede.
    def repair_order(days: nil, apply: false, rebuild: nil)
      secoes = page_days.sections
      alvos = (days || secoes.map(&:day).compact).sort.reverse

      if alvos.empty?
        @stdout.puts("Nenhuma seção de dia no Brag — nada a reparar.")
        return []
      end

      imprimir_plano(secoes, alvos, apply:)
      return alvos unless apply

      secoes.each do |secao|
        caminho = Tracker::Brag::Backup.section(secao.day, secao.blocks, suffix: "-antes-do-repair")
        @stdout.puts("Backup: #{caminho}")
      end
      forget(alvos)

      reconstruir = rebuild || ->(dia) { UseCases::RebuildDayReport.new(brag: self).call(dia) }
      alvos.each { |dia| reconstruir.call(dia) }
      @stdout.puts("Reparado: #{alvos.map { |d| Renderers::BragBlocks.data_do_dia(d) }.join(', ')}.")
      alvos
    end

    private

    def client = @client ||= Tracker::Notion::Client.from_env

    def page_id = @page_id ||= ENV.fetch("TRACER_NOTION_BRAG_PAGE_ID")

    def ledger = @ledger ||= Tracker::Brag::BlockLedger.new(page_id:)

    def page_days = @page_days ||= Tracker::Notion::PageDays.new(client:, page_id:)

    # O plano da migração é o que o engenheiro lê antes de aplicar — ordem
    # atual vs. pretendida. Sem ele, `repair_order` seria destrutivo e mudo.
    def imprimir_plano(secoes, alvos, apply:)
      @stdout.puts("== Brag: ordem atual ==")
      secoes.each { |secao| @stdout.puts("  #{Renderers::BragBlocks.data_do_dia(secao.day)}") }
      @stdout.puts("== Ordem pretendida (decrescente) ==")
      alvos.each { |dia| @stdout.puts("  #{Renderers::BragBlocks.data_do_dia(dia)}") }
      @stdout.puts("Dias a esquecer e reconstruir: #{alvos.size}")
      @stdout.puts("(dry-run — rode com APPLY=1 para aplicar)") unless apply
    end

    # Caminho de escrita: com a página lida uma única vez, decide os ids da
    # seção (header, sentinel), apaga o que é nosso e escreve de novo.
    def rewrite_section(day, report, blocos, assinaturas, estado)
      blocks = page_days.blocks
      secao = page_days.section(day, blocks:)

      header_id = estado&.dig(:header_id) || secao&.header_id
      # Sentinel é POR DIA: procurado só dentro da seção. Sem isso, o dia novo
      # pegava o sentinel do dia anterior e escrevia dentro da seção dele.
      sentinel_id = estado&.dig(:sentinel_id) || sentinel_da_secao(secao)

      # Posição do header da seção nova, mantendo a página decrescente: topo se
      # o dia é o mais recente, depois do fim da seção vizinha se está no meio,
      # fim da página se é mais antigo que todos. Ver `posicao_da_secao`.
      unless header_id
        header_id = criar(@renderer.header(day, report.epic_note), **posicao_da_secao(day, blocks))
      end
      sentinel_id ||= criar(@renderer.sentinel, after: header_id)

      # Sem ledger mas com sentinel, a seção é nossa: adota os blocos que já
      # estão lá a partir do sentinel (é o que impede o rebuild de
      # ACRESCENTAR uma cópia quando o ledger some/é apagado). A adoção
      # devolve os ids; não relê o ledger para descobri-los.
      ids_apagar = estado ? Array(estado[:blocks]).map { |b| b[:id] } : adotar_sem_ledger(day, header_id, sentinel_id, secao)

      apagar(ids_apagar)
      criados = escrever(blocos, after: sentinel_id)
      ledger.record(day, header_id: header_id, sentinel_id: sentinel_id,
                         blocks: pares(criados, assinaturas))
    end

    # Sentinel do dia já presente na seção (o ledger pode não ter o id se uma
    # escrita falhou no meio). Antes procurava na página inteira e pegava o de
    # outro dia.
    def sentinel_da_secao(secao)
      return nil if secao.nil?

      secao.body.find { |block| sentinel?(block) }&.fetch("id")
    end

    # É o parágrafo que avisa que o trecho abaixo é gerado? A convenção
    # inteira de posse depende desta resposta, então ela mora aqui — quem
    # precisar dela pergunta a este módulo, não reimplementa o predicado.
    def sentinel?(block)
      Tracker::Notion::PageDays.block?(block, "paragraph") &&
        Tracker::Notion::PageDays.text_of(block).include?(Renderers::BragBlocks::SENTINEL)
    end

    # Argumentos de posicionamento para o header de uma seção nova, mantendo a
    # página em ordem decrescente.
    #
    # A seção entra logo DEPOIS do fim da seção do próximo dia mais novo que
    # ela (o menor `d > day`): é o vizinho imediato na ordem decrescente. Se
    # esse vizinho for a última seção da página, o efeito é append no fim —
    # que é o caso do backfill de um dia mais antigo que todos. Se não existe
    # dia mais novo (página vazia, ou o dia é o mais recente), entra no topo.
    def posicao_da_secao(day, blocks)
      secoes = page_days.sections(blocks:)
      vizinho = secoes.map(&:day).compact.select { |d| d > day.to_date }.min
      return { position: { type: "start" } } if vizinho.nil?

      ultimo = secoes.find { |secao| secao.day == vizinho }&.last_id
      return { position: { type: "start" } } if ultimo.nil?

      { position: { type: "after_block", after_block: { id: ultimo } } }
    end

    # Seção nossa (tem sentinel) mas o ledger sumiu: os blocos abaixo do
    # sentinel, até o próximo header, passam a ser propriedade nossa e serão
    # reescritos. O que estiver abaixo do sentinel é, por contrato, gerado —
    # quem escreve à mão escreve ANTES do sentinel ou num bloco próprio.
    #
    # Devolve os ids a apagar (em vez de gravar no ledger e obrigar quem chama
    # a reler o arquivo 40 linhas depois).
    def adotar_sem_ledger(day, header_id, sentinel_id, secao)
      ids = ids_abaixo_do_sentinel(secao, sentinel_id)
      return [] if ids.empty?

      @logger.warn("[tracking] ledger ausente para #{day.iso8601}: adotando #{ids.size} block(s) da seção")
      ledger.record(day, header_id: header_id, sentinel_id: sentinel_id,
                         blocks: ids.map { |id| { id: id } })
      ids
    end

    # Ids dos blocos da seção que ficam abaixo do sentinel. Escopado à seção:
    # um sentinel de outro dia não pode fazer a adoção cair na seção dele.
    def ids_abaixo_do_sentinel(secao, sentinel_id)
      return [] if secao.nil? || sentinel_id.nil?

      viu = false
      secao.blocks.each_with_object([]) do |block, ids|
        if block.fetch("id") == sentinel_id
          viu = true
        elsif viu
          ids << block.fetch("id")
        end
      end
    end

    # Liga id criado → assinatura do bloco que o originou. `zip` (não
    # each_with_index) para nunca gravar signature nil: se a API devolver
    # mais ids que blocos enviados, zip trunca em vez de inventar pares.
    def pares(criados, assinaturas)
      criados.zip(assinaturas).reject { |id, assinatura| assinatura.nil? || id.nil? }
             .map { |id, assinatura| { id: id, signature: assinatura } }
    end

    def inalterado?(estado, assinaturas)
      return false if estado.nil?

      Array(estado[:blocks]).map { |b| b[:signature] } == assinaturas
    end

    def criar(bloco, after: nil, position: nil)
      client.append_block_children(page_id, [ bloco ], after:, position:).fetch("results").first.fetch("id")
    end

    # Apaga só o que é nosso. `delete_block` trata 404 como sucesso (o bloco
    # pode ter sido apagado à mão no Notion). O DELETE do pai leva os filhos
    # junto (verificado contra a API em 2026-10-21). Um bloco que falha não
    # interrompe os outros: o ciclo seguinte reconstrói.
    def apagar_do_dia(estado)
      apagar(Array(estado&.dig(:blocks)).map { |bloco| bloco.fetch(:id) })
    end

    def apagar(ids)
      ids.each do |id|
        client.delete_block(id)
      rescue Tracker::Notion::ApiError => e
        @logger.warn("[tracking] não deu para apagar block #{id}: #{e.message}")
      end
    end

    # Escreve em lotes de 100. Cada lote entra DEPOIS do último bloco criado
    # (não sempre depois do mesmo `after`, senão o segundo lote cairia antes
    # do primeiro e o dia sairia em ordem invertida).
    def escrever(blocos, after:)
      ids = []
      blocos.each_slice(LOTE_DE_BLOCKS) do |lote|
        resposta = client.append_block_children(page_id, lote, after:)
        novos = Array(resposta["results"]).map { |b| b.fetch("id") }
        ids.concat(novos)
        after = novos.last
      end
      ids
    end
  end
end
