# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracker::Notion::Client do
  let(:client) { described_class.new(token: "tok", database_id: "db-1") }

  def http_success(body)
    resposta = instance_double(Net::HTTPOK, code: "200", body: JSON.generate(body), is_a?: true)
    allow(resposta).to receive(:[]).and_return(nil)
    resposta
  end

  def http_error(code, body)
    resposta = instance_double(Net::HTTPNotFound, code: code, body: JSON.generate(body), is_a?: false)
    allow(resposta).to receive(:[]).and_return(nil)
    resposta
  end

  def stub_request(respostas)
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:request).and_return(*respostas)
  end

  describe "#delete_block" do
    it "manda DELETE no path do block" do
      req = nil
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) { |r| req = r; http_success({ "object" => "block" }) }

      client.delete_block("blk-1")

      expect(req.method).to eq("DELETE")
      expect(req.path).to eq("/v1/blocks/blk-1")
    end

    it "trata 404 como sucesso (o block já não existe)" do
      stub_request([ http_error("404", { "code" => "object_not_found" }) ])

      expect { client.delete_block("blk-1") }.not_to raise_error
    end

    it "propaga erros de outros status" do
      stub_request([ http_error("500", { "code" => "internal" }) ])

      expect { client.delete_block("blk-1") }.to raise_error(Tracker::Notion::ApiError)
    end
  end

  describe "#append_block_children" do
    it "põe `after` no body quando dado" do
      req = nil
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) { |r| req = r; http_success({ "results" => [] }) }

      client.append_block_children("page-1", [ { object: "block" } ], after: "blk-0")

      expect(JSON.parse(req.body)).to include("after" => "blk-0")
    end

    it "não manda `after` quando ausente" do
      req = nil
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) { |r| req = r; http_success({ "results" => [] }) }

      client.append_block_children("page-1", [ { object: "block" } ])

      expect(JSON.parse(req.body)).not_to have_key("after")
    end

    it "manda `position` no body quando dado (inserção no topo)" do
      req = nil
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) { |r| req = r; http_success({ "results" => [] }) }

      client.append_block_children("page-1", [ { object: "block" } ], position: { type: "start" })

      expect(JSON.parse(req.body)).to include("position" => { "type" => "start" })
    end

    it "não manda `position` quando ausente" do
      req = nil
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) { |r| req = r; http_success({ "results" => [] }) }

      client.append_block_children("page-1", [ { object: "block" } ], after: "blk-0")

      expect(JSON.parse(req.body)).not_to have_key("position")
    end
  end
end
