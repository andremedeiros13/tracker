# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::UseCases::RebuildDayReport do
  let(:dia) { Date.new(2026, 10, 21) }
  let(:logger) { instance_double(ActiveSupport::Logger, info: nil, error: nil) }
  let(:jira) { instance_double(Tracking::Repositories::JiraDayRepository) }
  let(:github) { instance_double(Tracking::Repositories::GitHubDayRepository) }
  let(:brag) { instance_double(Tracking::Repositories::BragDocumentRepository) }
  let(:stdout) { StringIO.new }
  let(:card) do
    { "id" => "id-1", "key" => "CHEKOUT-1", "title" => "card", "url" => "u",
      "status" => "Em andamento", "status_category" => "indeterminate",
      "assignee" => "André", "assignee_id" => "acc-eu", "reporter" => "R",
      "epic" => nil, "description" => nil }
  end
  let(:changelog) do
    { "CHEKOUT-1" => [ Tracking::Entities::Activity.new(
      kind: :changelog, author_id: "acc-eu", at: Time.zone.parse("#{dia} 10:00"),
      status_items: [ { from: "To Do", to: "In Progress" } ]
    ) ] }
  end

  def use_case(**opts)
    described_class.new(jira: jira, github: github, brag: brag, logger: logger, stdout: stdout, **opts)
  end

  before do
    # O use case monta BuildDayReport/ledger sem injeção quando não os recebe;
    # ambos leem ENV (no app real vem do .env).
    stub_const("ENV", ENV.to_h.merge(
      "JIRA_ACCOUNT_ID" => "acc-eu",
      "TRACER_NOTION_BRAG_PAGE_ID" => "page-brag"
    ))
    allow(jira).to receive(:dia).and_return(
      Tracking::Entities::JiraDay.new(cards: [ card ], activities: changelog)
    )
    allow(github).to receive(:dia).and_return(Tracking::Entities::GitHubDay.new)
    allow(brag).to receive(:rebuild).and_return(:reescrito)
  end

  describe "#call" do
    it "reescreve a seção do dia no Brag (caminho normal escreve)" do
      expect(use_case.call(dia)).to eq(1)
      expect(brag).to have_received(:rebuild).with(dia, hash_including(:header, :sentinel, :blocos))
    end

    it "com dry_run não toca no Notion e imprime" do
      expect(use_case(dry_run: true).call(dia)).to eq(0)

      expect(brag).not_to have_received(:rebuild)
      expect(stdout.string).to include("#1 · card")
    end

    it "dia sem atividade e sem ledger não cria seção vazia" do
      allow(jira).to receive(:dia).and_return(Tracking::Entities::JiraDay.new)
      ledger = instance_double(Tracker::Brag::BlockLedger, day: nil)
      uc = described_class.new(jira: jira, github: github, brag: brag, logger: logger,
                               stdout: stdout, ledger: ledger, dry_run: false)

      expect(uc.call(dia)).to eq(0)
      expect(brag).not_to have_received(:rebuild)
    end

    it "falha do Jira não impede o registro do GitHub" do
      allow(jira).to receive(:dia).and_raise(Tracker::Jira::ApiError.new("500", "fora"))
      # Com Jira vazio mas GitHub com PR, ainda há o que escrever.
      allow(github).to receive(:dia).and_return(
        Tracking::Entities::GitHubDay.new(pull_requests: [
          Tracking::Entities::PullRequest.new(
            number: 42, title: "chore: sem ticket", url: "u", repo: "o/r",
            created_at: Time.zone.parse("#{dia} 10:00")
          )
        ])
      )

      expect(use_case.call(dia)).to eq(1)
      expect(logger).to have_received(:error).with(a_string_including("jira"))
      expect(brag).to have_received(:rebuild)
    end

    it "sem Jira e sem GitHub configurados ainda monta o relatório do dia" do
      allow(jira).to receive(:dia).and_return(Tracking::Entities::JiraDay.new)
      allow(github).to receive(:dia).and_return(Tracking::Entities::GitHubDay.new)
      ledger = instance_double(Tracker::Brag::BlockLedger, day: { blocks: [] })
      uc = described_class.new(jira: jira, github: github, brag: brag, logger: logger,
                               stdout: stdout, ledger: ledger, dry_run: false)

      expect(uc.call(dia)).to eq(1)
    end

    it "reconstrói ontem antes do meio-dia e só hoje depois" do
      agora = Time.zone.local(2026, 10, 21, 10, 0)
      # O dia de ontem já tem seção no ledger: é o que autoriza reescrevê-la
      # mesmo que a coleta de ontem venha vazia.
      ledger = instance_double(Tracker::Brag::BlockLedger, day: { blocks: [] })
      uc = described_class.new(jira: jira, github: github, brag: brag, logger: logger,
                               stdout: stdout, ledger: ledger)

      uc.call(agora)
      expect(brag).to have_received(:rebuild).with(Date.new(2026, 10, 20), anything)
      expect(brag).to have_received(:rebuild).with(Date.new(2026, 10, 21), anything)
    end

    it "depois do meio-dia reconstrói só hoje" do
      ledger = instance_double(Tracker::Brag::BlockLedger, day: { blocks: [] })
      uc = described_class.new(jira: jira, github: github, brag: brag, logger: logger,
                               stdout: stdout, ledger: ledger)

      uc.call(Time.zone.local(2026, 10, 21, 15, 0))

      expect(brag).to have_received(:rebuild).once
      expect(brag).to have_received(:rebuild).with(Date.new(2026, 10, 21), anything)
    end
  end
end
