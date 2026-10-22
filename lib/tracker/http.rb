# frozen_string_literal: true

require "net/http"
require "json"

module Tracker
  # Transporte HTTP comum aos três clientes (Notion, Jira, GitHub).
  #
  # Antes cada cliente tinha a própria cópia de: montar o request, timeouts,
  # retry de 429 e mapeamento de erro — e as cópias divergiram (o GitHub, o de
  # rate limit mais apertado, ficou sem retry). A política mora aqui; cada
  # cliente só descreve método, URL, headers e qual erro levantar.
  #
  # Recebe a classe de erro do cliente (`error:`) porque Notion/Jira/GitHub têm
  # ApiError próprios que derivam de Tracker::Error — quem resgata a base cobre
  # os três.
  module HTTP
    # Sem timeout, um socket pendurado trava o ciclo inteiro do daemon (o
    # tracking ficou 199s num ciclo que normalmente leva 8s). 10s para abrir
    # e 30s para ler cobre com folga o payload do bulkfetch do Jira.
    TIMEOUT_ABERTURA = 10
    TIMEOUT_LEITURA = 30
    TENTATIVAS_429 = 2

    module_function

    # Devolve o JSON já parseado. Levanta `error` com (code, body) em qualquer
    # status não-2xx — inclusive quando o 429 sobrevive às tentativas.
    def call(method:, url:, headers: {}, body: nil, query: nil, error: Tracker::Error)
      uri = URI(url)
      uri.query = URI.encode_www_form(query) if query&.any?

      req = Net::HTTP.const_get(method).new(uri)
      headers.each { |chave, valor| req[chave] = valor }
      req["Content-Type"] ||= "application/json" if body
      req.body = JSON.generate(body) if body

      resposta = com_retry_429(error:) do
        Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                        open_timeout: TIMEOUT_ABERTURA, read_timeout: TIMEOUT_LEITURA) do |http|
          http.request(req)
        end
      end
      raise error.new(resposta.code, resposta.body) unless resposta.is_a?(Net::HTTPSuccess)

      JSON.parse(resposta.body)
    end

    # Honra Retry-After no 429 (rate limit): Notion Free 180 req/min, Jira
    # Cloud, GitHub search. O cliente decide o que fazer com o erro final.
    def com_retry_429(error:, max_tentativas: TENTATIVAS_429)
      tentativas = 0
      loop do
        resposta = yield
        return resposta unless resposta.code == "429"
        raise error.new(resposta.code, resposta.body) if tentativas >= max_tentativas

        sleep(resposta["Retry-After"]&.to_f || 1.0)
        tentativas += 1
      end
    end
  end
end
