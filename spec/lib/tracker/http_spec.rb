# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracker::HTTP do
  # ApiError dos clientes aceita (code, body) — o transporte repassa os dois.
  let(:erro) { Tracker::Notion::ApiError }

  def resposta(code: "200", body: {}, headers: {})
    classe = code == "200" ? Net::HTTPOK : Net::HTTPClientError
    double = instance_double(classe, code:, body: JSON.generate(body), is_a?: code == "200")
    allow(double).to receive(:[]).and_return(headers["Retry-After"])
    double
  end

  def stub_http(*respostas)
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:request).and_return(*respostas)
  end

  describe ".call" do
    it "devolve o body já parseado e manda os headers do cliente" do
      req = nil
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) { |r| req = r; resposta(body: { "ok" => true }) }

      corpo = described_class.call(method: :Get, url: "https://api.exemplo/v1/x",
                                   headers: { "X-Teste" => "1" }, error: erro)

      expect(corpo).to eq("ok" => true)
      expect(req["X-Teste"]).to eq("1")
    end

    it "serializa query e body em JSON" do
      req = nil
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) { |r| req = r; resposta }

      described_class.call(method: :Post, url: "https://api.exemplo/v1/x",
                           query: { page_size: 100 }, body: { a: 1 }, error: erro)

      expect(req.path).to include("page_size=100")
      expect(JSON.parse(req.body)).to eq("a" => 1)
      expect(req["Content-Type"]).to eq("application/json")
    end

    it "levanta a classe de erro do cliente em status não-2xx" do
      stub_http(resposta(code: "500", body: { "erro" => "boom" }))

      expect { described_class.call(method: :Get, url: "https://api.exemplo/x", error: erro) }
        .to raise_error(Tracker::Notion::ApiError, /500/)
    end

    it "honra Retry-After e tenta de novo no 429" do
      resposta_429 = resposta(code: "429", headers: { "Retry-After" => "0" })
      stub_http(resposta_429, resposta(body: { "ok" => true }))

      expect(described_class.call(method: :Get, url: "https://api.exemplo/x", error: erro))
        .to eq("ok" => true)
    end

    it "levanta erro quando o 429 sobrevive às tentativas" do
      resposta_429 = resposta(code: "429", headers: { "Retry-After" => "0" })
      stub_http(*Array.new(described_class::TENTATIVAS_429 + 1) { resposta_429 })

      expect { described_class.call(method: :Get, url: "https://api.exemplo/x", error: erro) }
        .to raise_error(Tracker::Notion::ApiError, /429/)
    end
  end
end
