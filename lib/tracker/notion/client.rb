# frozen_string_literal: true

require "net/http"
require "json"

module Tracker
  module Notion
    # Cliente HTTP puro do Notion (ADR 0001 — sem gem de terceiro no seam).
    # A superfície usada é pequena: GET database, POST query, POST pages,
    # POST/GET blocks, (PATCH page).
    class Client
      # Sem timeout, um socket pendurado trava o ciclo inteiro do daemon (o
      # tracking ficou 199s num ciclo que normalmente leva 8s). 10s para abrir
      # e 30s para ler cobre com folga o payload do bulkfetch do Jira.
      TIMEOUT_ABERTURA = 10
      TIMEOUT_LEITURA = 30
      BASE = "https://api.notion.com/v1"
      VERSION = "2022-06-28"

      def initialize(token:, database_id:)
        @token = token
        @database_id = database_id
      end

      def self.from_env
        new(token: ENV.fetch("TRACER_NOTION_TOKEN"),
            database_id: ENV.fetch("TRACER_NOTION_DATABASE_ID"))
      end

      def retrieve_database
        request(:Get, "/databases/#{@database_id}")
      end

      # Paginação por cursor (has_more/start_cursor, 100/página — API Free).
      def query_database(filter: nil)
        pages = []
        cursor = nil
        loop do
          body = request(:Post, "/databases/#{@database_id}/query",
                         body: { page_size: 100, start_cursor: cursor, filter: }.compact)
          pages.concat(body.fetch("results"))
          break unless body.fetch("has_more")
          cursor = body.fetch("next_cursor")
        end
        pages
      end

      # Cria uma row no database (POST /pages) — o OneOnOnes usa para criar
      # To-Dos dos action items das transcrições.
      def create_page(database_id:, properties:)
        request(:Post, "/pages", body: { parent: { database_id: }, properties: })
      end

      # Appenda blocks filhos na page (PATCH /blocks/{page_id}/children) — o
      # Tracking usa para adicionar header/bullets no Brag document.
      # PATCH e não POST: no workspace do usuário, o POST nesse path responde
      # 400 invalid_request_url em toda page (anomalia da API, testada em
      # 2026-10-15 com curl e Net::HTTP); o PATCH no mesmo path appenda.
      #
      # `after:` insere logo depois do block indicado (validado em 2026-10-21
      # contra a API, versão 2022-06-28 — nessa versão o parâmetro se chama
      # "after", não "position"). Sem ele, appenda no fim da page.
      def append_block_children(page_id, children, after: nil)
        body = { children: }
        body[:after] = after if after
        request(:Patch, "/blocks/#{page_id}/children", body:)
      end

      # Move um block para a lixeira (DELETE /blocks/{id}). Os filhos vão
      # junto (verificado em 2026-10-21 numa page de rascunho: depois do
      # DELETE do pai, /blocks/{pai}/children responde 404).
      # Idempotente para quem chama: 404 (já não existe) conta como sucesso.
      def delete_block(block_id)
        request(:Delete, "/blocks/#{block_id}")
      rescue ApiError => e
        raise unless e.message.include?("404")

        { "object" => "block", "id" => block_id, "in_trash" => true }
      end

      # Paginação por cursor (has_more/start_cursor, 100/página — API Free).
      def block_children(page_id)
        blocks = []
        cursor = nil
        loop do
          body = request(:Get, "/blocks/#{page_id}/children",
                         query: { page_size: 100, start_cursor: cursor }.compact)
          blocks.concat(body.fetch("results"))
          break unless body.fetch("has_more")
          cursor = body.fetch("next_cursor")
        end
        blocks
      end

      private

      def request(method, path, body: nil, query: nil)
        uri = URI("#{BASE}#{path}")
        uri.query = URI.encode_www_form(query) if query&.any?
        req = Net::HTTP.const_get(method).new(uri)
        req["Authorization"] = "Bearer #{@token}"
        req["Notion-Version"] = VERSION
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body) if body

        resposta = com_retry_429 { Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT_ABERTURA, read_timeout: TIMEOUT_LEITURA) { |http| http.request(req) } }
        raise ApiError.new(resposta.code, resposta.body) unless resposta.is_a?(Net::HTTPSuccess)

        JSON.parse(resposta.body)
      end

      # Honra Retry-After no 429 (rate limit — API Free: 180 req/min).
      def com_retry_429(max_tentativas: 2)
        tentativas = 0
        loop do
          resposta = yield
          return resposta unless resposta.code == "429"
          raise ApiError.new(resposta.code, resposta.body) if tentativas >= max_tentativas

          sleep(resposta["Retry-After"]&.to_f || 1.0)
          tentativas += 1
        end
      end
    end
  end
end
