# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::UseCases::CollectTodaysDeliveries do
  let(:brag) { instance_double(Tracking::Repositories::BragDocumentRepository) }
  let(:logger) { instance_double(ActiveSupport::Logger, error: nil, debug: nil) }
  let(:use_case) { described_class.new(jira: jira_repo, github: github_repo, brag: brag, logger: logger) }

  let(:jira_repo) { instance_double(Tracking::Repositories::JiraDeliveryRepository) }
  let(:github_repo) { instance_double(Tracking::Repositories::GitHubDeliveryRepository) }

  def entrega(source:, external_id:)
    Tracking::Entities::Delivery.new(
      source: source, kind: :card_movido, title: "título",
      url: "https://example.com", occurred_at: Time.current, external_id: external_id
    )
  end

  before do
    allow(brag).to receive(:entregas_existentes).and_return([])
    allow(brag).to receive(:append)
  end

  describe "#call" do
    it "appenda as entregas coletadas no Brag document" do
      allow(jira_repo).to receive(:entregas_do_dia).and_return([ entrega(source: :jira, external_id: "ENG-1") ])
      allow(github_repo).to receive(:entregas_do_dia).and_return([])

      use_case.call

      expect(brag).to have_received(:append).with(Date.current, [ satisfy { |e| e.external_id == "ENG-1" } ])
    end

    it "não appenda entrega já registrada (dedup contra o Brag document)" do
      allow(jira_repo).to receive(:entregas_do_dia)
        .and_return([ entrega(source: :jira, external_id: "ENG-1"), entrega(source: :jira, external_id: "ENG-2") ])
      allow(github_repo).to receive(:entregas_do_dia).and_return([])
      allow(brag).to receive(:entregas_existentes).and_return([ { external_id: "ENG-1", texto: "..." } ])

      use_case.call

      expect(brag).to have_received(:append).with(Date.current, [ satisfy { |e| e.external_id == "ENG-2" } ])
    end

    it "não appenda nada quando não há entregas" do
      allow(jira_repo).to receive(:entregas_do_dia).and_return([])
      allow(github_repo).to receive(:entregas_do_dia).and_return([])

      use_case.call

      expect(brag).not_to have_received(:append)
    end

    it "não derruba o ciclo quando a coleta do Jira falha (credencial, API)" do
      allow(jira_repo).to receive(:entregas_do_dia).and_raise(Tracker::Jira::ApiError.new("401", "unauthorized"))
      allow(github_repo).to receive(:entregas_do_dia).and_return([ entrega(source: :github, external_id: "123") ])

      use_case.call

      expect(brag).to have_received(:append).with(Date.current, [ satisfy { |e| e.external_id == "123" } ])
    end
  end
end
