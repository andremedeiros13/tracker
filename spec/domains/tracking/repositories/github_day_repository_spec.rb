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

  describe "#dia (commits)" do
    it "lê a data de commit.committer.date, não do committer da raiz" do
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
