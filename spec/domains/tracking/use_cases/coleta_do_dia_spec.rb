# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::UseCases::ColetaDoDia do
  let(:dia) { Date.new(2026, 10, 21) }
  let(:logger) { instance_double(ActiveSupport::Logger, error: nil) }
  let(:jira) { instance_double(Tracking::Repositories::JiraDayRepository) }
  let(:github) { instance_double(Tracking::Repositories::GitHubDayRepository) }
  let(:coleta) { described_class.new(jira:, github:, logger:) }

  def jira_day(cards: [])
    Tracking::Entities::JiraDay.new(cards:)
  end

  def card(key: "CHEKOUT-1")
    Tracking::Entities::Card.new(
      id: "id-#{key}", key:, title: "card", url: "u",
      status: "Em andamento", status_category: "indeterminate",
      mine: true, assignee_name: "André", reporter_name: "R"
    )
  end

  before do
    allow(jira).to receive(:dia).and_return(jira_day(cards: [ card ]))
    allow(github).to receive(:dia).and_return(Tracking::Entities::GitHubDay.new)
  end

  describe "#call" do
    it "as duas fontes ok: resultado completo com o dia inteiro" do
      resultado = coleta.call(dia)

      expect(resultado).to be_completo
      expect(resultado.jira.cards.size).to eq(1)
      expect(resultado.falhas).to be_empty
    end

    it "falha do Jira: incompleto, mas o GitHub vem" do
      allow(jira).to receive(:dia).and_raise(Tracker::Jira::ApiError.new("500", "fora"))

      resultado = coleta.call(dia)

      expect(resultado).not_to be_completo
      expect(resultado.falhas).to eq([ :jira ])
      expect(resultado.jira.cards).to be_empty
      expect(logger).to have_received(:error).with(a_string_including("jira"))
    end

    it "falha do GitHub: incompleto, mas o Jira vem" do
      allow(github).to receive(:dia).and_raise(Tracker::GitHub::ApiError.new("502", "fora"))

      resultado = coleta.call(dia)

      expect(resultado.falhas).to eq([ :github ])
      expect(resultado.jira.cards.size).to eq(1)
    end

    it "as duas falhando: as duas fontes ficam registradas" do
      allow(jira).to receive(:dia).and_raise(Tracker::Jira::ApiError.new("500", "x"))
      allow(github).to receive(:dia).and_raise(Tracker::GitHub::ApiError.new("502", "y"))

      resultado = coleta.call(dia)

      expect(resultado.falhas).to contain_exactly(:jira, :github)
    end

    it "KeyError (ENV faltando) também vira falha da fonte, não exceção" do
      allow(jira).to receive(:dia).and_raise(KeyError, "TRACER_X")

      expect { coleta.call(dia) }.not_to raise_error
      expect(coleta.call(dia).falhas).to eq([ :jira ])
    end
  end
end
