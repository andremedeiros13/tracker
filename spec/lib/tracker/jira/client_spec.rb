# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracker::Jira::Client do
  let(:client) { described_class.new(email: "me@example.com", token: "tok", site: "https://jira.example.com") }

  def http_success(body)
    # "[]" mock para o Retry-After do 429 (nil — sem retry no teste).
    resposta = instance_double(Net::HTTPOK, code: "200", body: JSON.generate(body), is_a?: true)
    allow(resposta).to receive(:[]).and_return(nil)
    resposta
  end

  def stub_request(respostas)
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:request).and_return(*respostas)
  end

  describe "#search" do
    it "busca por JQL e retorna os issues" do
      stub_request([ http_success({ "issues" => [ { "key" => "ENG-1" } ], "isLast" => true }) ])

      expect(client.search("updated >= -2d")).to eq([ { "key" => "ENG-1" } ])
    end

    it "pagina por nextPageToken" do
      stub_request([
        http_success({ "issues" => [ { "key" => "ENG-1" } ], "isLast" => false, "nextPageToken" => "t2" }),
        http_success({ "issues" => [ { "key" => "ENG-2" } ], "isLast" => true })
      ])

      expect(client.search("jql")).to eq([ { "key" => "ENG-1" }, { "key" => "ENG-2" } ])
    end

    it "autentica com Basic email:token" do
      req = nil
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) { |r| req = r; http_success({ "issues" => [], "isLast" => true }) }

      client.search("jql")

      expect(req["Authorization"]).to eq("Basic #{[ "me@example.com:tok" ].pack("m0")}")
    end
  end

  describe "#changelog" do
    it "pagina por isLast/nextPage" do
      stub_request([
        http_success({ "values" => [ { "id" => "1" } ], "isLast" => false, "nextPage" => "n2" }),
        http_success({ "values" => [ { "id" => "2" } ], "isLast" => true })
      ])

      expect(client.changelog("ENG-1").map { |e| e["id"] }).to eq([ "1", "2" ])
    end
  end

  describe "#discover_fields" do
    it "busca custom fields com type=custom" do
      req = nil
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) { |r| req = r; http_success({ "values" => [] }) }

      client.discover_fields(query: "Reviewer")

      expect(req.path).to include("type=custom")
      expect(req.path).to include("query=Reviewer")
    end
  end

  describe ".configurado?" do
    it "é falso sem credenciais" do
      with_env(JIRA_EMAIL: nil, JIRA_API_TOKEN: nil) do
        expect(described_class.configurado?).to be_falsey
      end
    end

    it "é verdadeiro com credenciais" do
      with_env(JIRA_EMAIL: "me@example.com", JIRA_API_TOKEN: "tok") do
        expect(described_class.configurado?).to be_truthy
      end
    end
  end

  private

  def with_env(vars)
    anteriores = vars.to_h { |k, v| [ k.to_s, ENV[k.to_s] ] }
    vars.each { |k, v| ENV[k.to_s] = v }
    yield
  ensure
    anteriores.each { |k, v| ENV[k] = v }
  end
end
