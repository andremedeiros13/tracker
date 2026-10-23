# frozen_string_literal: true

require "rails_helper"

RSpec.describe Todos::UseCases::NotifyPendingTodos do
  let(:notifier) { instance_double(Tracker::NativeNotifier) }

  # Fake in-memory do adapter — mesma interface: devolve as candidatas, sem
  # filtrar nem ordenar (isso é da FilaDeAtencao, não do adapter).
  let(:fake_repository) do
    Class.new do
      def initialize(todos) = @todos = todos

      def notification_candidates = @todos
    end
  end

  def todo(titulo:, origem: :manual, status: :pendente, snoozed_until: nil)
    Todos::Entities::Todo.new(
      page_id: "page-#{titulo}", title: titulo, origin: origem, status:,
      snoozed_until:, created_at: 1.hour.ago, last_edited_time: 1.hour.ago
    )
  end

  describe "#call" do
    it "dispara UMA notificação com o resumo das pendências" do
      pendencias = [
        todo(titulo: "a", origem: :via_jira),
        todo(titulo: "b", origem: :via_jira),
        todo(titulo: "c", origem: :manual)
      ]
      use_case = described_class.new(database: fake_repository.new(pendencias), notifier: notifier)

      expect(notifier).to receive(:notify)
        .with("Tracker", "3 pendências: via Jira (2), manual")

      resumo = use_case.call
      expect(resumo).to eq("3 pendências: via Jira (2), manual")
    end

    it "não notifica quando não há pendências" do
      sem_pendencias = [
        todo(titulo: "concluida", status: :concluida),
        todo(titulo: "snoozed", status: :snoozed, snoozed_until: 1.hour.from_now)
      ]
      use_case = described_class.new(database: fake_repository.new(sem_pendencias), notifier: notifier)

      expect(notifier).not_to receive(:notify)
      expect(use_case.call).to be_nil
    end

    it "snoozed vencido entra no ciclo" do
      pendencias = [ todo(titulo: "a", snoozed_until: 1.minute.ago, status: :snoozed) ]
      use_case = described_class.new(database: fake_repository.new(pendencias), notifier: notifier)

      expect(notifier).to receive(:notify).with("Tracker", "1 pendência: manual")
      use_case.call
    end
  end
end
