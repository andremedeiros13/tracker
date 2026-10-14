# frozen_string_literal: true

# Scheduler do daemon (spec §3.1): thread dentro do `rails server` que dispara
# `Todos::UseCases::NotifyPendingTodos` no intervalo configurado por ENV vars
# (TRACER_NOTIFY_*), respeitando o período ativo. Thread daemon — morre com o
# processo do servidor.
#
# Desabilitável em testes/console: Tracker::Scheduler.disabled = true
module Tracker
  class Scheduler
    class << self
      attr_accessor :disabled
    end
    self.disabled = false

    INTERVALO_MINIMO_SEGUNDOS = 60

    def start
      Thread.new do
        Thread.current.name = "tracker-scheduler"
        loop do
          disparar_se_no_periodo
          sleep intervalo_segundos
        rescue StandardError => e
          Rails.logger.error("[tracker-scheduler] #{e.class}: #{e.message}")
        end
      end
    end

    private

    def intervalo_segundos
      [ ENV.fetch("TRACER_NOTIFY_INTERVAL_MINUTES", "45").to_i * 60, INTERVALO_MINIMO_SEGUNDOS ].max
    end

    def disparar_se_no_periodo
      return unless periodo_ativo?

      Todos::UseCases::NotifyPendingTodos.new.call
      coletar_entregas
    end

    # Ciclo do Tracking: coleta as entregas do dia e appenda no Brag document
    # (dedup incremental). Resgatado — nunca derruba o ciclo de notificação.
    def coletar_entregas
      Tracking::UseCases::CollectTodaysDeliveries.new.call
    rescue StandardError => e
      Rails.logger.error("[tracker-scheduler] tracking: #{e.class}: #{e.message}")
    end

    def periodo_ativo?
      agora = Time.current
      inicio = parse_hora(ENV.fetch("TRACER_NOTIFY_ACTIVE_START", "09:00"))
      fim = parse_hora(ENV.fetch("TRACER_NOTIFY_ACTIVE_END", "18:00"))
      agora.between?(agora.change(hour: inicio.first, min: inicio.last),
                     agora.change(hour: fim.first, min: fim.last))
    end

    def parse_hora(hora)
      hora.split(":").map(&:to_i)
    end
  end
end

Rails.application.config.after_initialize do
  next if defined?(Rails::Console) || Rails.env.test? || Tracker::Scheduler.disabled

  Tracker::Scheduler.new.start
end
