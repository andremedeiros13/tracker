# frozen_string_literal: true

module Tracker
  module Notion
    # Cliente HTTP do Notion (ADR 0001 — sem gem de terceiro no seam).
    # A superfície usada é pequena: GET database, POST query, POST pages,
    # POST/GET blocks, (PATCH page). Timeouts, retry de 429 e mapeamento de
    # erro ficam no transporte comum (Tracker::HTTP).
    #
    # É TRANSPORTE: cada operação recebe o id do recurso. Antes o
    # `database_id` vinha no construtor e só `query_database`/`retrieve_database`
    # o usavam — `from_env` exigia `TRACER_NOTION_DATABASE_ID`, então o ciclo
    # do Brag (que só escreve numa page) morria por uma variável que nunca
    # usava. Quem conhece o recurso é o repositório do domínio.
    class Client
      BASE = "https://api.notion.com/v1"
      VERSION = "2022-06-28"

      def initialize(token:)
        @token = token
      end

      def self.from_env = new(token: ENV.fetch("TRACER_NOTION_TOKEN"))

      def retrieve_database(database_id)
        request(:Get, "/databases/#{database_id}")
      end

      # Paginação por cursor (has_more/start_cursor, 100/página — API Free).
      def query_database(database_id, filter: nil)
        pages = []
        cursor = nil
        loop do
          body = request(:Post, "/databases/#{database_id}/query",
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
      # Onde os children entram na page:
      #   `after: id`             → logo depois daquele block
      #   `position: {type: "start"}` → topo da page
      #   nada                   → fim da page
      # Os dois parâmetros não podem ir juntos na mesma chamada.
      #
      # `position` foi validado em 2026-10-23 contra a API na versão que
      # fixamos (2022-06-28): `start` insere no topo preservando a ordem do
      # lote, e `after_block` insere depois de um block (404 se o id não
      # existir). `after` continua aceito, marcado como deprecated.
      def append_block_children(page_id, children, after: nil, position: nil)
        body = { children: }
        body[:after] = after if after
        body[:position] = position if position
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
        Tracker::HTTP.call(
          method:, url: "#{BASE}#{path}", query:, body:,
          headers: { "Authorization" => "Bearer #{@token}", "Notion-Version" => VERSION },
          error: ApiError
        )
      end
    end
  end
end
