# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::UseCases::BuildDayReport do
  let(:use_case) { described_class.new }
  let(:dia) { Date.new(2026, 10, 21) }

  # --- builders de entity (o contrato do seam) -------------------------------

  # O adapter já resolveu `mine`: o domínio não conhece account id.
  def card(key:, title: "Resumo", status: "Em andamento", category: "indeterminate",
           mine: true, assignee: "André")
    Tracking::Entities::Card.new(
      id: "id-#{key}", key: key, title: title, url: "https://jira/browse/#{key}",
      status: status, status_category: category, mine: mine,
      assignee_name: assignee, reporter_name: "Marivaldo",
      description: nil
    )
  end

  # Shape que o adapter entrega: atividade já normalizada (sem epoch ms nem
  # author cru — isso é responsabilidade do JiraDayRepository).
  def transicao(de:, para:, hora: "10:00", mine: true, id: "c1")
    Tracking::Entities::Activity.new(
      kind: :changelog, mine: mine, at: Time.zone.parse("#{dia} #{hora}"),
      status_items: [ { from: de, to: para } ]
    )
  end

  def comentario(mine: true, hora: "16:46")
    Tracking::Entities::Activity.new(
      kind: :comment, mine: mine, at: Time.zone.parse("#{dia} #{hora}")
    )
  end

  def jira_day(cards:, activities: {})
    Tracking::Entities::JiraDay.new(cards: cards, activities: activities)
  end

  def pr(number: 1, title: "CHEKOUT-2301 captura", body: "# Problema\n\nNada grava.\n\n# Solução\n\nGrava.",
         merged_at: nil, created_at: "#{dia} 09:00", approvals: [])
    Tracking::Entities::PullRequest.new(
      number: number, title: title, url: "https://github.com/o/r/pull/#{number}",
      repo: "o/r", body: body,
      created_at: Time.zone.parse(created_at.to_s),
      merged_at: merged_at && Time.zone.parse(merged_at.to_s),
      commits: 14, changed_files: 17, additions: 1257, deletions: 55,
      approvals: approvals
    )
  end

  def github_day(pull_requests: [], given_reviews: [], commits: [])
    Tracking::Entities::GitHubDay.new(pull_requests: pull_requests, given_reviews: given_reviews, commits: commits)
  end

  # --------------------------------------------------------------------------

  describe "#call" do
    it "liga o PR ao card pela key e usa o corpo do PR como contexto" do
      card = card(key: "CHEKOUT-2301")
      changelog = { "CHEKOUT-2301" => [ transicao(de: "To Do", para: "In Progress") ] }
      pr_ = pr(title: "CHEKOUT-2301 [Payments] Captura", merged_at: "#{dia} 16:48", approvals: [ "Marivaldo" ])

      report = use_case.call(dia, jira: jira_day(cards: [ card ], activities: changelog),
                                  github: github_day(pull_requests: [ pr_ ]))

      item = report.work_items.first
      expect(report.work_items.size).to eq(1)
      expect(item).to have_attributes(
        key: "CHEKOUT-2301", outcome: :merged, problema: "Nada grava.", solucao: "Grava.",
        reviews_received: [ "Marivaldo" ]
      )
      expect(item.status_chain).to eq([ "To Do → In Progress" ])
    end

    it "card de outro que eu só movi vira :moved (não é minha entrega)" do
      card = card(key: "CHEKOUT-2332", mine: false, assignee: "Itallo")
      changelog = { "CHEKOUT-2332" => [ transicao(de: "Review", para: "Ready for Deploy") ] }

      item = use_case.call(dia, jira: jira_day(cards: [ card ], activities: changelog)).work_items.first

      expect(item).to have_attributes(outcome: :moved, mine: false, owner_name: "Itallo")
    end

    it "higiene de board (Prioritized → To Do) não vira item" do
      card = card(key: "CHEKOUT-9")
      changelog = { "CHEKOUT-9" => [ transicao(de: "Prioritized", para: "To Do", id: "c9") ] }

      report = use_case.call(dia, jira: jira_day(cards: [ card ], activities: changelog))

      expect(report.work_items).to be_empty
    end

    it "card sem transição minha hoje e sem comentário meu não entra" do
      card = card(key: "CHEKOUT-8")
      changelog = { "CHEKOUT-8" => [ transicao(de: "To Do", para: "In Progress", hora: "10:00", mine: false) ] }

      expect(use_case.call(dia, jira: jira_day(cards: [ card ], activities: changelog)).work_items).to be_empty
    end

    it "conta os comentários meus do dia no card" do
      card = card(key: "CHEKOUT-7")
      comentarios = { "CHEKOUT-7" => [ comentario ] }

      item = use_case.call(dia, jira: jira_day(cards: [ card ], activities: comentarios)).work_items.first

      expect(item.comments_count).to eq(1)
      expect(item.status_chain).to be_empty
    end

    it "changelog de campo que não é status não conta como comentário" do
      card = card(key: "CHEKOUT-6")
      mudanca_de_descricao = {
        "CHEKOUT-6" => [
          Tracking::Entities::Activity.new(
            kind: :changelog, mine: true, at: Time.zone.parse("#{dia} 11:00")
          )
        ]
      }

      expect(use_case.call(dia, jira: jira_day(cards: [ card ], activities: mudanca_de_descricao)).work_items)
        .to be_empty
    end

    it "PR sem card vira item próprio" do
      report = use_case.call(dia, github: github_day(pull_requests: [ pr(title: "chore: sem ticket", number: 42) ]))

      item = report.work_items.first
      expect(item.key).to be_nil
      expect(item.pull_requests.map(&:number)).to eq([ 42 ])
    end

    it "aceita card cujo PR foi aberto noutro dia e mergeado hoje" do
      card = card(key: "CHEKOUT-2298")
      changelog = { "CHEKOUT-2298" => [ transicao(de: "Review", para: "Done") ] }
      pr_ = pr(title: "CHEKOUT-2298 outbox", merged_at: "#{dia} 14:29", created_at: "2026-10-20 17:38")

      item = use_case.call(dia, jira: jira_day(cards: [ card ], activities: changelog),
                                github: github_day(pull_requests: [ pr_ ])).work_items.first

      expect(item.outcome).to eq(:merged)
    end

    it "ordena: concluídos, em andamento, cards de outros" do
      cards = [
        card(key: "CHEKOUT-1", mine: false, assignee: "Itallo"),
        card(key: "CHEKOUT-2"),
        card(key: "CHEKOUT-3"),
        card(key: "CHEKOUT-4", status: "Concluído", category: "done")
      ]
      changelog = {
        "CHEKOUT-1" => [ transicao(de: "Review", para: "Deploy", id: "c1") ],
        "CHEKOUT-2" => [ transicao(de: "To Do", para: "In Progress", id: "c2", hora: "09:00") ],
        "CHEKOUT-3" => [ transicao(de: "To Do", para: "In Progress", id: "c3", hora: "15:00") ],
        "CHEKOUT-4" => [ transicao(de: "Review", para: "Done", id: "c4") ]
      }

      chaves = use_case.call(dia, jira: jira_day(cards: cards, activities: changelog)).work_items.map(&:key)

      expect(chaves).to eq(%w[CHEKOUT-4 CHEKOUT-3 CHEKOUT-2 CHEKOUT-1])
    end

    it "dia sem nada devolve relatório vazio" do
      expect(use_case.call(dia)).to be_vazio
    end
  end
end
