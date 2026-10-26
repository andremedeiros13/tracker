# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::UseCases::RebuildDayReport do
  let(:dia) { Date.new(2026, 10, 21) }
  let(:logger) { instance_double(ActiveSupport::Logger, info: nil, error: nil, warn: nil) }
  let(:jira) { instance_double(Tracking::Repositories::JiraDayRepository) }
  let(:github) { instance_double(Tracking::Repositories::GitHubDayRepository) }
  let(:brag) { instance_double(Tracking::BragDocument) }
  let(:stdout) { StringIO.new }
  let(:card) do
    Tracking::Entities::Card.new(
      id: "id-1", key: "CHEKOUT-1", title: "card", url: "u",
      status: "Em andamento", status_category: "indeterminate",
      mine: true, assignee_name: "André", reporter_name: "R",
      description: nil
    )
  end
  let(:activities) do
    { "CHEKOUT-1" => [ Tracking::Entities::Activity.new(
      kind: :changelog, mine: true, at: Time.zone.parse("#{dia} 10:00"),
      status_items: [ { from: "To Do", to: "In Progress" } ]
    ) ] }
  end

  def use_case(**opts)
    described_class.new(jira:, github:, brag:, logger:, stdout:, **opts)
  end

  before do
    allow(jira).to receive(:dia).and_return(
      Tracking::Entities::JiraDay.new(cards: [ card ], activities:)
    )
    allow(github).to receive(:dia).and_return(Tracking::Entities::GitHubDay.new)
    allow(brag).to receive(:rewrite).and_return(:reescrito)
  end

  describe "#call" do
    it "manda o BragDocument reescrever a seção do dia" do
      expect(use_case.call(dia)).to eq(1)
      expect(brag).to have_received(:rewrite).with(dia, an_instance_of(Tracking::Entities::DayReport))
    end

    it "quando o conteúdo não mudou, não conta como dia atualizado" do
      allow(brag).to receive(:rewrite).and_return(:sem_mudanca)

      expect(use_case.call(dia)).to eq(0)
    end

    it "com dry_run não escreve: pede o preview ao módulo do Brag e imprime" do
      allow(brag).to receive(:preview).and_return("== 2026-10-21 ==\n## 21/10/2026 — quarta\n• #1 · card")

      expect(use_case(dry_run: true).call(dia)).to eq(0)

      expect(brag).not_to have_received(:rewrite)
      expect(brag).to have_received(:preview).with(dia, an_instance_of(Tracking::Entities::DayReport))
      expect(stdout.string).to include("• #1 · card")
      expect(stdout.string).to include("## 21/10/2026 — quarta")
    end

    # O bug que esta regra corrige: a falha virava dia vazio, o rewrite via a
    # assinatura mudar e apagava do Brag os bullets do Jira. Melhor deixar o
    # dia como estava do que gravar metade dele.
    it "falha do Jira não reescreve o dia (não apaga a metade do Jira no Brag)" do
      allow(jira).to receive(:dia).and_raise(Tracker::Jira::ApiError.new("500", "fora"))

      expect(use_case.call(dia)).to eq(0)
      expect(brag).not_to have_received(:rewrite)
      expect(logger).to have_received(:error).with(a_string_including("jira"))
      expect(logger).to have_received(:warn).with(a_string_including("coleta incompleta"))
    end

    it "falha do GitHub também segura o dia" do
      allow(github).to receive(:dia).and_raise(Tracker::GitHub::ApiError.new("502", "fora"))

      expect(use_case.call(dia)).to eq(0)
      expect(brag).not_to have_received(:rewrite)
    end

    it "reconstrói ontem antes do meio-dia e só hoje depois" do
      allow(brag).to receive(:rewrite).and_return(:sem_mudanca)

      use_case.call(Time.zone.local(2026, 10, 21, 10, 0))

      expect(brag).to have_received(:rewrite).with(Date.new(2026, 10, 20), anything)
      expect(brag).to have_received(:rewrite).with(Date.new(2026, 10, 21), anything)
    end

    it "depois do meio-dia reconstrói só hoje" do
      use_case.call(Time.zone.local(2026, 10, 21, 15, 0))

      expect(brag).to have_received(:rewrite).once
      expect(brag).to have_received(:rewrite).with(Date.new(2026, 10, 21), anything)
    end
  end
end
