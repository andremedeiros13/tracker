# frozen_string_literal: true

module Todos
  module UseCases
    # O ciclo do daemon: agrega as pendências (não-snoozed) e dispara **uma**
    # notificação nativa com o resumo — "3 pendências: code review, 1-on-1, manual".
    # Resumo único por ciclo (decisão #7): quebra o hiperfoco sem bombardear.
    #
    # O que conta como pendência agora, e em que ordem, é da FilaDeAtencao —
    # o adapter só devolve as rows candidatas.
    class NotifyPendingTodos
      def initialize(database: Repositories::TodoDatabase.new, notifier: Tracker::NativeNotifier.new)
        @database = database
        @notifier = notifier
      end

      def call
        pendencias = FilaDeAtencao.de(@database.notification_candidates)
        return if pendencias.empty?

        resumo = "#{pendencias.size} pendência#{pendencias.size > 1 ? 's' : ''}: #{resumo_das_origens(pendencias)}"
        # Notificação que não sai é falha do ciclo, não silêncio: devolve false
        # e o log do job fica com o motivo.
        Rails.logger.warn("[todos] notificação não foi disparada (#{resumo})") unless @notifier.notify("Tracker", resumo)
        resumo
      end

      private

      def resumo_das_origens(pendencias)
        origens = pendencias.map(&:origin).tally
                        .sort_by { |_, count| -count }
                        .map { |origem, count| "#{label_da_origem(origem)}#{count > 1 ? " (#{count})" : ''}" }
        origens.join(", ")
      end

      def label_da_origem(origem)
        { manual: "manual", via_jira: "via Jira", via_transcricao: "1-on-1" }.fetch(origem, origem)
      end
    end
  end
end
