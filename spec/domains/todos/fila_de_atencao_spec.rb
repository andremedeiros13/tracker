# frozen_string_literal: true

require "rails_helper"

RSpec.describe Todos::FilaDeAtencao do
  def todo(titulo:, status: :pendente, snoozed_until: nil, created_at: 1.hour.ago)
    Todos::Entities::Todo.new(
      page_id: "page-#{titulo}", title: titulo, origin: :manual, status:,
      snoozed_until:, created_at:, last_edited_time: created_at
    )
  end

  describe ".de" do
    it "só as pendências de agora: pendente e snoozed vencido" do
      todos = [
        todo(titulo: "agora"),
        todo(titulo: "futuro", status: :snoozed, snoozed_until: 1.hour.from_now),
        todo(titulo: "vencido", status: :snoozed, snoozed_until: 2.minutes.ago),
        todo(titulo: "concluida", status: :concluida)
      ]

      expect(described_class.de(todos).map(&:title)).to contain_exactly("agora", "vencido")
    end

    # FIFO pelo instante em que a tarefa entrou na fila: quem espera há mais
    # tempo vem primeiro. Uma snoozed que venceu agora entrou na fila AGORA —
    # fica atrás de quem já estava esperando.
    it "ordena por quando a tarefa entrou na fila (quem espera mais vem antes)" do
      todos = [
        todo(titulo: "entrou agora", status: :snoozed, snoozed_until: 2.minutes.ago, created_at: 5.hours.ago),
        todo(titulo: "esperando há 3h", created_at: 3.hours.ago),
        todo(titulo: "esperando há 1h", created_at: 1.hour.ago)
      ]

      expect(described_class.de(todos).map(&:title))
        .to eq([ "esperando há 3h", "esperando há 1h", "entrou agora" ])
    end

    it "aceita lista vazia" do
      expect(described_class.de([])).to eq([])
    end
  end
end
