# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracker::GitHub::Client do
  let(:client) { described_class.new(token: "gho_tok") }

  def http_success(body)
    instance_double(Net::HTTPOK, code: "200", body: JSON.generate(body), is_a?: true)
  end

  def stub_request(respostas)
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:request).and_return(*respostas)
  end

  describe "#search_prs" do
    it "busca com type:pr no qualificador" do
      req = nil
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) { |r| req = r; http_success({ "items" => [] }) }

      client.search_prs("is:pr author:@me created:>=2026-10-14")

      expect(req.path).to include("q=")
      expect(URI.decode_www_form_component(req.path)).to include("is:pr author:@me created:>=2026-10-14 type:pr")
    end
  end

  describe "#search_commits" do
    it "busca commits com o qualificador dado" do
      req = nil
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) { |r| req = r; http_success({ "items" => [] }) }

      client.search_commits("author:me org:org committer-date:>=2026-10-14")

      expect(URI.decode_www_form_component(req.path)).to include("author:me org:org committer-date:>=2026-10-14")
    end
  end

  describe "#pull_reviews" do
    it "chama o endpoint de reviews do PR" do
      req = nil
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) { |r| req = r; http_success([]) }

      client.pull_reviews("org", "repo", 7)

      expect(req.path).to include("/repos/org/repo/pulls/7/reviews")
    end
  end

  describe "rate limit" do
    it "honra 429 com Retry-After em vez de estourar (o cliente antes pulava o retry)" do
      retry_after = instance_double(Net::HTTPClientError, code: "429", body: "{}", is_a?: false)
      allow(retry_after).to receive(:[]).with("Retry-After").and_return("0")
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request).and_return(retry_after, http_success({ "items" => [] }))

      expect(client.search_prs("is:pr author:me")).to eq([])
    end
  end

  describe ".from_env" do
    it "levanta erro claro sem GITHUB_TOKEN e sem gh CLI" do
      allow(described_class).to receive(:token_do_gh).and_return(nil)

      expect { described_class.from_env }.to raise_error(
        Tracker::Error, /GITHUB_TOKEN ausente e gh CLI sem auth/
      )
    end

    it "usa o token do gh CLI como fallback" do
      allow(described_class).to receive(:token_do_gh).and_return("gho_fallback")

      expect(described_class.from_env).to be_a(described_class)
    end
  end
end
