# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::Renderers::BragBlocks do
  let(:renderer) { described_class.new }
  let(:dia) { Date.new(2026, 10, 21) }

  def pr(number: 1216, merged_at: "2026-10-21 16:48", created_at: "2026-10-21 08:54",
         approvals: [], body: "# Problema\n\nNada grava.\n\n# Solução\n\nGrava.")
    Tracking::Entities::PullRequest.new(
      number: number, title: "CHEKOUT-2301 captura", url: "https://github.com/o/r/pull/#{number}",
      repo: "o/r", body: body, created_at: Time.zone.parse(created_at),
      merged_at: merged_at && Time.zone.parse(merged_at),
      commits: 14, changed_files: 17, additions: 1257, deletions: 55, approvals: approvals
    )
  end

  def item(**over)
    padrao = {
      key: "CHEKOUT-2301", title: "[Payments] T11 captura", url: "https://jira/browse/CHEKOUT-2301",
      mine: true, outcome: :merged, outcome_at: Time.zone.parse("2026-10-21 16:48"),
      status_chain: [], pull_requests: [ pr(approvals: [ "marivaldo" ]) ],
      reviews_received: [ "marivaldo" ], problema: "Nada grava.", solucao: "Grava.",
      last_activity_at: Time.zone.parse("2026-10-21 16:48")
    }
    Tracking::Entities::WorkItem.new(**padrao.merge(over))
  end

  def report(work_items: [ item ], given_reviews: [], commits: [], epic_note: nil)
    Tracking::Entities::DayReport.new(date: dia, epic_note: epic_note,
                                      work_items: work_items, given_reviews: given_reviews,
                                      commits: commits)
  end

  def texto(bloco, tipo = :bulleted_list_item)
    bloco[tipo][:rich_text].map { |t| t[:text][:content] }.join
  end

  describe "#header" do
    it "usa a data por extenso e o épico quando há" do
      bloco = renderer.header(dia, "[Motor][Wave2] Pagamento")

      expect(texto(bloco, :heading_2)).to eq("21/10/2026 — quarta · [Motor][Wave2] Pagamento")
    end

    it "corta o épico longo (o nome completo está em cada card)" do
      epico = "[Motor][Wave2] Pagamento com até 3 cartões - Fluxo de captura e gestão do ciclo de vida"

      expect(texto(renderer.header(dia, epico), :heading_2)).to end_with("…")
    end

    it "sem épico, só a data" do
      expect(texto(renderer.header(dia, nil), :heading_2)).to eq("21/10/2026 — quarta")
    end
  end

  describe "#items" do
    it "um bullet por item, com o estado em negrito e o título como link" do
      bloco = renderer.items(report).first
      textos = bloco[:bulleted_list_item][:rich_text]

      expect(textos[0][:text][:content]).to eq("#2301 · ")
      # O link vai DENTRO de text — ao lado, a API do Notion responde 400.
      expect(textos[1][:text]).to include(link: { url: "https://jira/browse/CHEKOUT-2301" })
      expect(textos[1]).not_to have_key(:link)
      expect(textos[2][:annotations]).to eq(bold: true)
      expect(textos[2][:text][:content]).to eq(" — MERGEADO 16:48")
    end

    it "nunca põe link ao lado de text (validação da API do Notion)" do
      blocos = renderer.items(report)

      blocos.each do |bloco|
        rich = bloco[:bulleted_list_item][:rich_text]
        rich.each { |run| expect(run).not_to have_key(:link) }
        Array(bloco[:bulleted_list_item][:children]).each do |filho|
          filho[:bulleted_list_item][:rich_text].each { |run| expect(run).not_to have_key(:link) }
        end
      end
    end

    it "não mostra chave de dedup no texto (regressão do formato antigo)" do
      tudo = renderer.items(report).map { |b| texto(b) }.join(" ")

      expect(tudo).not_to match(/\w+-\d+:\d+:\w+/)
    end

    it "card de outra pessoa diz de quem é" do
      bloco = renderer.items(report(work_items: [ item(outcome: :moved, mine: false, owner_name: "Itallo", pull_requests: []) ])).first

      expect(texto(bloco)).to end_with("— card de Itallo")
    end

    it "mostra Antes/Fiz vindos do corpo do PR" do
      linhas = renderer.items(report).first[:bulleted_list_item][:children].map { |c| texto(c) }

      expect(linhas).to include("Antes: Nada grava.", "Fiz: Grava.")
    end

    it "cadeia de status só em item não concluído" do
      concluido = renderer.items(report).first
      andamento = renderer.items(report(work_items: [ item(outcome: :in_progress, status_chain: [ "To Do → In Progress" ]) ])).first

      expect(concluido[:bulleted_list_item][:children].map { |c| texto(c) }.join).not_to include("To Do →")
      expect(andamento[:bulleted_list_item][:children].map { |c| texto(c) }).to include("To Do → In Progress")
    end

    it "métricas e reviews recebidas na linha do PR" do
      linhas = renderer.items(report).first[:bulleted_list_item][:children].map { |c| texto(c) }

      expect(linhas.first).to include("PR #1216 · 14 commits · 17 arquivos · +1257/−55")
      expect(linhas).to include("aprovado por marivaldo")
    end

    it "respeita o teto de 2 níveis de aninhamento" do
      blocos = renderer.items(report)

      blocos.each do |bloco|
        Array(bloco[:bulleted_list_item][:children]).each do |filho|
          expect(filho[:bulleted_list_item][:children]).to be_nil
        end
      end
    end

    it "mostra a review anexada ao card como linha de evidência" do
      review = Tracking::Entities::GivenReview.new(
        pull_request: pr(number: 1211), state: :approved,
        submitted_at: Time.zone.parse("2026-10-21 10:00")
      )

      linhas = renderer.items(report(work_items: [ item(reviews_given: [ review ]) ]))
                      .first[:bulleted_list_item][:children].map { |c| texto(c) }

      expect(linhas).to include("aprovado o PR #1211")
    end

    it "agrupa as revisões que eu fiz" do
      review = Tracking::Entities::GivenReview.new(
        pull_request: pr(number: 1211), state: :approved,
        submitted_at: Time.zone.parse("2026-10-21 10:00")
      )

      bloco = renderer.items(report(given_reviews: [ review ])).last

      expect(texto(bloco)).to eq("Revisões que eu fiz")
      expect(texto(bloco[:bulleted_list_item][:children].first)).to include("PR #1211", "Aprovado")
    end

    # A copy do documento é do renderer: o adapter entrega o estado de domínio.
    it "traduz cada estado de review para a copy do documento" do
      textos = Tracking::Renderers::BragBlocks::ESTADOS_DE_REVIEW.map do |estado, copy|
        review = Tracking::Entities::GivenReview.new(
          pull_request: pr(number: 1), state: estado,
          submitted_at: Time.zone.parse("2026-10-21 10:00")
        )
        bloco = renderer.items(report(given_reviews: [ review ])).last
        [ copy, texto(bloco[:bulleted_list_item][:children].first) ]
      end

      textos.each { |copy, linha| expect(linha).to end_with(copy) }
    end

    it "falha alto em estado de review sem tradução" do
      review = Tracking::Entities::GivenReview.new(
        pull_request: pr(number: 1), state: :inventado,
        submitted_at: Time.zone.parse("2026-10-21 10:00")
      )

      expect { renderer.items(report(given_reviews: [ review ])) }
        .to raise_error(KeyError, /inventado/)
    end

    it "um dia vazio ainda ganha o bloco 'sem atividade'" do
      blocos = renderer.items(report(work_items: []))

      expect(blocos.size).to eq(1)
      expect(texto(blocos.first, :paragraph)).to eq("— sem atividade registrada —")
    end

    it "agrupa commits soltos" do
      commit = Tracking::Entities::Commit.new(sha: "abcdef1234567", message: "fix: algo",
                                              url: "https://github.com/o/r/commit/abc", repo: "r",
                                              committed_at: Time.zone.parse("2026-10-21 10:00"))

      bloco = renderer.items(report(commits: [ commit ])).last

      expect(texto(bloco)).to eq("Commits soltos")
      expect(texto(bloco[:bulleted_list_item][:children].first)).to eq("abcdef1 fix: algo (r)")
    end
  end

  describe "#preview" do
    it "é o mesmo conteúdo dos blocos: header, itens e sub-bullets" do
      texto_preview = renderer.preview(dia, report)

      expect(texto_preview).to include("== 2026-10-21 ==")
      expect(texto_preview).to include("## 21/10/2026 — quarta")
      expect(texto_preview).to include("• #2301 · [Payments] T11 captura — MERGEADO 16:48")
      expect(texto_preview).to include("    - Antes: Nada grava.")
    end

    it "dia vazio mostra o 'sem atividade', como os blocos" do
      expect(renderer.preview(dia, report(work_items: [])))
        .to include("• — sem atividade registrada —")
    end
  end

  describe ".signature" do
    it "muda quando o conteúdo muda e é estável quando não" do
      a = renderer.items(report).first
      b = renderer.items(report).first
      c = renderer.items(report(work_items: [ item(title: "outro título") ])).first

      expect(described_class.signature(a)).to eq(described_class.signature(b))
      expect(described_class.signature(a)).not_to eq(described_class.signature(c))
    end
  end
end
