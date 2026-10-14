# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::Repositories::GitHubDeliveryRepository do
  let(:client) { instance_double(Tracker::GitHub::Client) }
  let(:repository) { described_class.new(client: client, org: "ResultadosDigitais", username: "andremedeiros") }
  let(:dia) { Date.new(2026, 10, 14) }

  def pr(id:, title:, number: 7, repository_url: "https://api.github.com/repos/org/repo", created_at: "2026-10-14T10:00:00Z", updated_at: "2026-10-14T12:00:00Z")
    { "id" => id, "title" => title, "number" => number, "repository_url" => repository_url,
      "html_url" => "https://github.com/org/repo/pull/#{number}",
      "created_at" => created_at, "updated_at" => updated_at }
  end

  def review(id:, login:, submitted_at:, state: "APPROVED")
    { "id" => id, "state" => state, "submitted_at" => submitted_at, "user" => { "login" => login } }
  end

  def commit(sha:, message: "fix: algo", date: "2026-10-14T09:00:00Z", repo: "repo")
    { "sha" => sha, "html_url" => "https://github.com/org/#{repo}/commit/#{sha}",
      "repository" => { "name" => repo },
      "commit" => { "message" => message }, "committer" => { "date" => date } }
  end

  describe "#entregas_do_dia" do
    it "coleta PR aberto pelo engenheiro no dia" do
      allow(client).to receive(:authenticated_user).and_return({ "login" => "andremedeiros" })
      allow(client).to receive(:search_prs).and_return([ pr(id: 1, title: "Minha PR") ], [])
      allow(client).to receive(:search_commits).and_return([])

      entregas = repository.entregas_do_dia(dia)

      expect(entregas.size).to eq(1)
      expect(entregas.first).to have_attributes(
        source: :github, kind: :pr_aberto, external_id: "1",
        url: "https://github.com/org/repo/pull/7"
      )
    end

    it "coleta review feita pelo engenheiro no dia (filtro client-side por login)" do
      allow(client).to receive(:authenticated_user).and_return({ "login" => "andremedeiros" })
      allow(client).to receive(:search_prs).and_return([], [ pr(id: 2, title: "PR do colega") ])
      allow(client).to receive(:search_commits).and_return([])
      allow(client).to receive(:pull_reviews).and_return([
        review(id: "r1", login: "andremedeiros", submitted_at: "2026-10-14T11:00:00Z"),
        review(id: "r2", login: "outro", submitted_at: "2026-10-14T11:00:00Z")
      ])

      entregas = repository.entregas_do_dia(dia)

      expect(entregas.size).to eq(1)
      expect(entregas.first).to have_attributes(kind: :review, external_id: "r1", title: "Review: PR do colega")
    end

    it "exclui review pendente e de outro dia" do
      allow(client).to receive(:authenticated_user).and_return({ "login" => "andremedeiros" })
      allow(client).to receive(:search_prs).and_return([], [ pr(id: 2, title: "PR do colega") ])
      allow(client).to receive(:search_commits).and_return([])
      allow(client).to receive(:pull_reviews).and_return([
        review(id: "r1", login: "andremedeiros", submitted_at: "2026-10-14T11:00:00Z", state: "PENDING"),
        review(id: "r2", login: "andremedeiros", submitted_at: "2026-10-13T11:00:00Z")
      ])

      expect(repository.entregas_do_dia(dia)).to be_empty
    end

    it "coleta commits do engenheiro na org no dia" do
      allow(client).to receive(:authenticated_user).and_return({ "login" => "andremedeiros" })
      allow(client).to receive(:search_prs).and_return([], [])
      allow(client).to receive(:search_commits).and_return([ commit(sha: "abc123", message: "fix: algo\n\ncorpo") ])

      entregas = repository.entregas_do_dia(dia)

      expect(entregas.size).to eq(1)
      expect(entregas.first).to have_attributes(
        kind: :commit, external_id: "abc123", title: "Commit: repo — fix: algo"
      )
    end

    it "deduplica PR que aparece nas duas buscas (kind diferente, mesmo id)" do
      allow(client).to receive(:authenticated_user).and_return({ "login" => "andremedeiros" })
      allow(client).to receive(:search_prs).and_return([ pr(id: 1, title: "Minha PR") ], [])
      allow(client).to receive(:search_commits).and_return([])

      entregas = repository.entregas_do_dia(dia)

      expect(entregas.map(&:external_id)).to eq([ "1" ])
    end

    it "busca com os qualificadores corretos" do
      allow(client).to receive(:authenticated_user).and_return({ "login" => "andremedeiros" })
      allow(client).to receive(:search_prs).and_return([], [])
      allow(client).to receive(:search_commits).and_return([])

      repository.entregas_do_dia(dia)

      expect(client).to have_received(:search_prs).with("is:pr author:andremedeiros created:>=2026-10-14")
      expect(client).to have_received(:search_prs).with("is:pr reviewed-by:andremedeiros updated:>=2026-10-14")
      expect(client).to have_received(:search_commits).with("author:andremedeiros org:ResultadosDigitais committer-date:>=2026-10-14")
    end
  end
end
