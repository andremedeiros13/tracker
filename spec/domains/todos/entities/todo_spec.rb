# frozen_string_literal: true

require "rails_helper"

RSpec.describe Todos::Entities::Todo do
  def todo(status: :pendente, snoozed_until: nil)
    described_class.new(
      page_id: "page-1", title: "Tarefa", origin: :manual, status:,
      snoozed_until:, created_at: 1.hour.ago, last_edited_time: 1.hour.ago
    )
  end

  describe "#lembrete_ativo?" do
    it "pendente é lembrete ativo" do
      expect(todo).to be_lembrete_ativo
    end

    it "snoozed com horário no futuro não é" do
      expect(todo(status: :snoozed, snoozed_until: 1.hour.from_now)).not_to be_lembrete_ativo
    end

    it "snoozed vencido volta a ser lembrete ativo" do
      expect(todo(status: :snoozed, snoozed_until: 2.minutes.ago)).to be_lembrete_ativo
    end

    # "Em andamento" sem data de snooze é estado que o Notion aceita. Antes
    # estourava NoMethodError em nil e derrubava o ciclo inteiro.
    it "snoozed sem data de snooze lembra (não derruba o predicado)" do
      expect(todo(status: :snoozed, snoozed_until: nil)).to be_lembrete_ativo
    end

    it "concluída nunca é" do
      expect(todo(status: :concluida)).not_to be_lembrete_ativo
    end
  end

  describe "imutabilidade" do
    it "é uma Data — sem escrita de estado" do
      expect(todo).to be_frozen
      expect { todo.status = :concluida }.to raise_error(NoMethodError)
    end
  end
end
