# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::UseCases::BuildDayReport do
  let(:account_id) { "acc-eu" }
  let(:use_case) { described_class.new(account_id: account_id) }
  let(:dia) { Date.new(2026, 10, 21) }

  # --- builders de payload cru (shapes reais do Jira/GitHub) -----------------

  def card(key:, title: "Resumo", status: "Em andamento", category: "indeterminate",
           assignee_id: account_id, assignee: "André", epic: "[Motor][Wave2] Pagamento")
    {
      "id" => "id-#{key}", "key" => key, "title" => title,
      "url" => "https://jira/browse/#{key}", "status" => status,
      "status_category" => category, "assignee" => assignee,
      "assignee_id" => assignee_id, "reporter" => "Marivaldo",
      "epic" => epic, "description" => nil
    }
  end

  # Shape do bulkfetch: author = accountId, created = epoch ms.
  def transicao(de:, para:, hora: "10:00", author: account_id, id: "c1")
    {
      "id" => id, "author" => author,
      "created" => (Time.zone.parse("#{dia} #{hora}") .to_f * 1000).to_i,
      "items" => [ { "fieldId" => "status", "fromString" => de, "toString" => para } ]
    }
  end

  def jira_day(cards:, changelogs: {}, comments: {})
    Tracking::Entities::JiraDay.new(cards: cards, changelogs: changelogs, comments: comments)
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
      changelog = { "id-CHEKOUT-2301" => [ transicao(de: "To Do", para: "In Progress") ] }
      pr_ = pr(title: "CHEKOUT-2301 [Payments] Captura", merged_at: "#{dia} 16:48", approvals: [ "Marivaldo" ])

      report = use_case.call(dia, jira: jira_day(cards: [ card ], changelogs: changelog),
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
      card = card(key: "CHEKOUT-2332", assignee_id: "acc-itallo", assignee: "Itallo")
      changelog = { "id-CHEKOUT-2332" => [ transicao(de: "Review", para: "Ready for Deploy") ] }

      item = use_case.call(dia, jira: jira_day(cards: [ card ], changelogs: changelog)).work_items.first

      expect(item).to have_attributes(outcome: :moved, mine: false, owner_name: "Itallo")
    end

    it "higiene de board (Prioritized → To Do) não vira item" do
      card = card(key: "CHEKOUT-9")
      changelog = { "id-CHEKOUT-9" => [ transicao(de: "Prioritized", para: "To Do", id: "c9") ] }

      report = use_case.call(dia, jira: jira_day(cards: [ card ], changelogs: changelog))

      expect(report.work_items).to be_empty
    end

    it "card sem transição minha hoje e sem comentário meu não entra" do
      card = card(key: "CHEKOUT-8")
      changelog = { "id-CHEKOUT-8" => [ transicao(de: "To Do", para: "In Progress", hora: "10:00", author: "acc-outro") ] }

      expect(use_case.call(dia, jira: jira_day(cards: [ card ], changelogs: changelog)).work_items).to be_empty
    end

    it "conta os comentários meus do dia no card" do
      card = card(key: "CHEKOUT-7")
      comentarios = { "CHEKOUT-7" => [ { author_id: account_id, created_at: Time.zone.parse("#{dia} 16:46") } ] }

      item = use_case.call(dia, jira: jira_day(cards: [ card ], comments: comentarios)).work_items.first

      expect(item.comments_count).to eq(1)
      expect(item.status_chain).to be_empty
    end

    it "PR sem card vira item próprio" do
      report = use_case.call(dia, github: github_day(pull_requests: [ pr(title: "chore: sem ticket", number: 42) ]))

      expect(report.work_items.map(&:referencia)).to eq([ "PR #42" ])
    end

    it "aceita card cujo PR foi aberto noutro dia e mergeado hoje" do
      card = card(key: "CHEKOUT-2298")
      changelog = { "id-CHEKOUT-2298" => [ transicao(de: "Review", para: "Done") ] }
      pr_ = pr(title: "CHEKOUT-2298 outbox", merged_at: "#{dia} 14:29", created_at: "2026-10-20 17:38")

      item = use_case.call(dia, jira: jira_day(cards: [ card ], changelogs: changelog),
                                github: github_day(pull_requests: [ pr_ ])).work_items.first

      expect(item.outcome).to eq(:merged)
    end

    it "usa o épico no header só quando todos os cards compartilham" do
      cards = [ card(key: "CHEKOUT-1"), card(key: "CHEKOUT-2") ]
      changelog = {
        "id-CHEKOUT-1" => [ transicao(de: "To Do", para: "In Progress", id: "c1") ],
        "id-CHEKOUT-2" => [ transicao(de: "To Do", para: "In Progress", id: "c2") ]
      }

      report = use_case.call(dia, jira: jira_day(cards: cards, changelogs: changelog))
      expect(report.epic_note).to eq("[Motor][Wave2] Pagamento")
    end

    it "sem épico comum quando os cards são de frentes diferentes" do
      cards = [ card(key: "CHEKOUT-1", epic: "Épico A"), card(key: "CHEKOUT-2", epic: "Épico B") ]
      changelog = {
        "id-CHEKOUT-1" => [ transicao(de: "To Do", para: "In Progress", id: "c1") ],
        "id-CHEKOUT-2" => [ transicao(de: "To Do", para: "In Progress", id: "c2") ]
      }

      expect(use_case.call(dia, jira: jira_day(cards: cards, changelogs: changelog)).epic_note).to be_nil
    end

    it "ordena: concluídos, em andamento, cards de outros" do
      cards = [
        card(key: "CHEKOUT-1", assignee_id: "acc-itallo", assignee: "Itallo"),
        card(key: "CHEKOUT-2"),
        card(key: "CHEKOUT-3"),
        card(key: "CHEKOUT-4", status: "Concluído", category: "done")
      ]
      changelog = {
        "id-CHEKOUT-1" => [ transicao(de: "Review", para: "Deploy", id: "c1") ],
        "id-CHEKOUT-2" => [ transicao(de: "To Do", para: "In Progress", id: "c2", hora: "09:00") ],
        "id-CHEKOUT-3" => [ transicao(de: "To Do", para: "In Progress", id: "c3", hora: "15:00") ],
        "id-CHEKOUT-4" => [ transicao(de: "Review", para: "Done", id: "c4") ]
      }

      referencia = use_case.call(dia, jira: jira_day(cards: cards, changelogs: changelog)).work_items.map(&:referencia)

      expect(referencia).to eq([ "#4", "#3", "#2", "#1" ])
    end

    it "dia sem nada devolve relatório vazio" do
      expect(use_case.call(dia)).to be_vazio
    end
  end
end
