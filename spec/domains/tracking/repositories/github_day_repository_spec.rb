# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::Repositories::GitHubDayRepository do
  let(:client) { instance_double(Tracker::GitHub::Client) }
  let(:dia) { Date.new(2026, 10, 22) }

  def repository
    described_class.new(client: client, org: "org", username: "eu")
  end

  # Shape real de /search/commits: `committer` na raiz é o usuário do GitHub
  # (sem data) e a data do commit vive em commit.committer.date.
  def commit_do_search(sha:, data:, mensagem: "feat: algo")
    {
      "sha" => sha,
      "html_url" => "https://github.com/org/repo/commit/#{sha}",
      "committer" => { "login" => "eu", "id" => 123 },
      "commit" => { "message" => mensagem, "committer" => { "date" => data } },
      "repository" => { "name" => "repo" }
    }
  end

  before do
    allow(client).to receive(:search_prs).and_return([])
    allow(client).to receive(:search_commits).and_return([])
  end

  describe "#dia (PRs)" do
    # Shape de /search/issues: o que o adapter usa é number, title, html_url,
    # created_at e repository_url. O merge vive em pull_request.merged_at.
    def pr_do_search(numero:, criado:, mergeado: nil, titulo: "CHEKOUT-1 algo")
      payload = {
        "number" => numero,
        "title" => titulo,
        "html_url" => "https://github.com/org/repo/pull/#{numero}",
        "created_at" => criado,
        "body" => "corpo",
        "repository_url" => "https://api.github.com/repos/org/repo"
      }
      payload["pull_request"] = { "merged_at" => mergeado } if mergeado
      payload
    end

    before do
      allow(client).to receive(:pull_request).and_return({})
      allow(client).to receive(:pull_reviews).and_return([])
    end

    it "traz o PR aberto no dia e ainda não mergeado" do
      allow(client).to receive(:search_prs)
        .with(/created:/).and_return([ pr_do_search(numero: 1, criado: "2026-10-22T10:00:00Z") ])
      allow(client).to receive(:search_prs).with(/merged:/).and_return([])

      expect(repository.dia(dia).pull_requests.map(&:number)).to eq([ 1 ])
    end

    it "descarta PR mergeado em outro dia (o bug do day sem teto)" do
      # Caso real: preview[30/10] trazia o PR mergeado em 04/11 porque a busca
      # era `merged:>=29/10` sem limite superior.
      allow(client).to receive(:search_prs)
        .with(/created:/).and_return([ pr_do_search(numero: 9, criado: "2026-11-04T10:00:00Z") ])
      allow(client).to receive(:search_prs).with(/merged:/).and_return([])

      expect(repository.dia(dia).pull_requests).to be_empty
    end

    # Caso real #1263: aberto 29/10 17:41 BRT, mergeado 03/11 10:58 BRT. Com a
    # regra "aberto OU mergeado", ele entrava na seção de 29/10 carregando o
    # rótulo "MERGEADO 10:58" — hora de outro dia, na data errada.
    it "PR aberto antes e mergeado depois entra só no dia do merge" do
      pr = pr_do_search(numero: 1263, criado: "2026-10-29T20:41:00Z", mergeado: "2026-11-03T13:58:00Z")
      allow(client).to receive(:search_prs).with(/created:/).and_return([ pr ])
      allow(client).to receive(:search_prs).with(/merged:/).and_return([ pr ])

      expect(repository.dia(Date.new(2026, 10, 29)).pull_requests).to be_empty
      expect(repository.dia(Date.new(2026, 11, 3)).pull_requests.map(&:number)).to eq([ 1263 ])
    end

    it "PR aberto em outro dia e não mergeado não entra" do
      allow(client).to receive(:search_prs)
        .with(/created:/).and_return([ pr_do_search(numero: 5, criado: "2026-10-19T10:00:00Z") ])
      allow(client).to receive(:search_prs).with(/merged:/).and_return([])

      expect(repository.dia(dia).pull_requests).to be_empty
    end

    it "a busca de PR tem teto de data, não só piso" do
      allow(client).to receive(:search_prs).and_return([])

      repository.dia(dia)

      # 21/10..23/10: piso (fuso) e teto (dia alvo em UTC).
      expect(client).to have_received(:search_prs).with(/created:2026-10-21\.\.2026-10-23/)
      expect(client).to have_received(:search_prs).with(/merged:2026-10-21\.\.2026-10-23/)
    end
  end

  describe "#dia (commits)" do    it "lê a data de commit.committer.date, não do committer da raiz" do
      allow(client).to receive(:search_commits).and_return([
        commit_do_search(sha: "abc1234", data: "2026-10-22T10:00:00Z")
      ])

      commits = repository.dia(dia).commits

      expect(commits.size).to eq(1)
      expect(commits.first.sha).to eq("abc1234")
      expect(commits.first.message).to eq("feat: algo")
    end

    it "descarta commit de outro dia (corte client-side no fuso local)" do
      allow(client).to receive(:search_commits).and_return([
        commit_do_search(sha: "velho", data: "2026-10-20T10:00:00Z")
      ])

      expect(repository.dia(dia).commits).to be_empty
    end

    it "commit sem data no payload é ignorado, sem derrubar a coleta" do
      allow(client).to receive(:search_commits).and_return([
        { "sha" => "sem-data", "html_url" => "u", "commit" => { "message" => "x" } }
      ])

      expect { repository.dia(dia) }.not_to raise_error
      expect(repository.dia(dia).commits).to be_empty
    end
  end
end
