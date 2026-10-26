# frozen_string_literal: true

require "json"
require "fileutils"

module Tracker
  module Brag
    # Ledger local dos blocks que o Tracker escreveu no Brag document.
    #
    # Existe porque o Brag é reconstruído (delete + rewrite), não appendado:
    # para apagar só o que é nosso — e nunca um parágrafo escrito à mão — o
    # daemon precisa lembrar os ids que criou. O Notion continua sendo a fonte
    # da verdade do documento; isto guarda só ids + assinaturas do que geramos
    # (ADR 0002 — não é estado de domínio; ver docs/adr/0002-ledger-local-do-brag.md).
    #
    # Um dia é uma entrada: header (âncora cronológica, nunca apagado), o
    # sentinel (parágrafo que avisa que o trecho é gerado) e os blocks do dia,
    # cada um com a assinatura do conteúdo renderizado.
    class BlockLedger
      VERSION = 1

      def initialize(path: Rails.root.join("storage/tracking/brag_state.json"), page_id: nil, logger: Rails.logger)
        @path = path
        @lock_path = "#{path}.lock"
        @page_id = page_id
        @logger = logger
      end

      # Serializa quem escreve no Brag. O daemon e um `rake tracking:rebuild`
      # rodando ao mesmo tempo (ou dois ticks sobrepostos) reescreviam a mesma
      # seção em paralelo — o resultado foram sentinels duplicados e ids no
      # ledger sem assinatura.
      #
      # Espera no máximo `timeout` (default 5s): o ciclo roda a cada 30 min, então
      # é melhor desistir e tentar no próximo tick do que segurar a thread do
      # scheduler atrás de um `rake` interativo. Devolve nil quando não pega.
      def with_lock(timeout: 5)
        FileUtils.mkdir_p(File.dirname(@lock_path))
        File.open(@lock_path, File::RDWR | File::CREAT, 0o644) do |arquivo|
          inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          until arquivo.flock(File::LOCK_EX | File::LOCK_NB)
            if Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio > timeout
              @logger.info("[tracking] Brag em uso por outro processo — pulando este ciclo")
              return nil
            end
            sleep 0.2
          end
          yield
        end
      end

      # Estado do dia: { header_id:, header_signature:, sentinel_id:, blocks: [{ id:, signature: }] } ou nil.
      def day(date)
        entrada = read.fetch("days", {})[chave(date)]
        return if entrada.nil?

        entrada.transform_keys(&:to_sym).merge(
          blocks: Array(entrada["blocks"]).map { |b| b.transform_keys(&:to_sym) }
        )
      end

      # Grava (ou substitui) o estado do dia. Escrita atômica: um tmp no mesmo
      # diretório + rename — o rename é atômico no mesmo filesystem, então um
      # kill no meio nunca deixa o arquivo pela metade.
      #
      # `header_signature` assina o TEXTO do header: sem ela, uma mudança só de
      # header (o corpo igual) não era detectada e o formato antigo ficava.
      def record(date, header_id:, sentinel_id: nil, blocks: [], header_signature: nil)
        estado = read
        estado["days"] ||= {}
        estado["days"][chave(date)] = {
          "header_id" => header_id,
          "header_signature" => header_signature,
          "sentinel_id" => sentinel_id,
          "blocks" => blocks.map { |b| { "id" => b.fetch(:id), "signature" => b[:signature] } },
          "rebuilt_at" => Time.current.iso8601
        }
        write(estado)
        day(date)
      end

      def forget(date)
        estado = read
        estado.fetch("days", {}).delete(chave(date))
        write(estado)
      end

      private

      def chave(date)
        date.to_date.iso8601
      end

      # Ledger ausente, corrompido ou de outra page ⇒ vazio (o repositório cai
      # no fallback por convenção, que nunca apaga bloco desconhecido).
      def read
        return vazio unless File.exist?(@path)

        estado = JSON.parse(File.read(@path))
        return vazio unless estado["version"] == VERSION
        return vazio if @page_id && estado["page_id"] && estado["page_id"] != @page_id

        estado.merge("page_id" => estado["page_id"] || @page_id).compact
      rescue JSON::ParserError, SystemCallError => e
        @logger.warn("[tracking] ledger ilegível (#{e.class}) — reconstruindo por convenção")
        vazio
      end

      def vazio
        { "version" => VERSION, "page_id" => @page_id, "days" => {} }.compact
      end

      def write(estado)
        FileUtils.mkdir_p(File.dirname(@path))
        tmp = "#{@path}.tmp"
        File.write(tmp, JSON.pretty_generate(estado))
        File.rename(tmp, @path)
      rescue SystemCallError => e
        # Falha de ledger não pode derrubar o ciclo — o próximo cai no fallback.
        @logger.error("[tracking] ledger: #{e.class}: #{e.message}")
      end
    end
  end
end
