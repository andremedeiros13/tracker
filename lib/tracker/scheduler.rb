# frozen_string_literal: true

module Tracker
  # Scheduler do daemon: jobs independentes, cada um com o próprio intervalo e
  # janela de horário.
  #
  # Antes era um ciclo único (notify + tracking + one-ones) no intervalo da
  # notificação, 09:00–18:00. Isso obrigava o Tracking a rodar com a mesma
  # cadência de um lembrete e a parar às 18h (justo quando o dia termina), e
  # a varredura larga do Jira — 60 s e ~600 MB — rodava junto.
  #
  # O loop acorda a cada TICK e pergunta a cada job se está na hora. `tick(now)`
  # recebe o relógio, então testar cadência não exige sleep.
  class Scheduler
    TICK_SECONDS = 60

    class << self
      attr_writer :disabled

      def disabled?
        @disabled == true
      end
    end

    # Um job: janela + intervalo + o que rodar. `once_per_day` roda no máximo
    # uma vez por dia dentro da janela (a varredura de segurança).
    class Job
      attr_reader :nome
      attr_accessor :proximo_em, :ultimo_sucesso_em

      def initialize(nome:, intervalo_minutos:, janela: nil, once_per_day: false, run:, logger: Rails.logger)
        @nome = nome
        @intervalo = intervalo_minutos.to_i * 60
        @janela = janela && janela.map { |h| hora_para_minutos(h) }
        @once_per_day = once_per_day
        @run = run
        @logger = logger
        @proximo_em = nil
        @ultimo_sucesso_em = nil
      end

      def due?(agora)
        return false unless na_janela?(agora)
        return false if @once_per_day && @ultimo_sucesso_em&.to_date == agora.to_date
        return true if @proximo_em.nil?

        agora >= @proximo_em
      end

      def executar(agora)
        @run.call
        @ultimo_sucesso_em = agora
        @proximo_em = agora + @intervalo
      rescue StandardError => e
        @logger.error("[tracker-scheduler] #{@nome}: #{e.class}: #{e.message}")
        # Backoff numa falha: não martela a API a cada tick.
        @proximo_em = agora + [ @intervalo, 300 ].min
      end

      private

      def na_janela?(agora)
        return true if @janela.nil?

        minutos = agora.hour * 60 + agora.min
        inicio, fim = @janela
        minutos.between?(inicio, fim)
      end

      def hora_para_minutos(hora)
        horas, minutos = hora.to_s.split(":").map(&:to_i)
        horas * 60 + minutos
      end
    end

    def initialize(jobs:, logger: Rails.logger, tick: TICK_SECONDS, clock: -> { Time.current })
      @jobs = jobs
      @logger = logger
      @tick = tick
      @clock = clock
    end

    def self.from_env
      new(jobs: [
        Job.new(nome: :notify, run: -> { Todos::UseCases::NotifyPendingTodos.new.call },
                intervalo_minutos: ENV.fetch("TRACER_NOTIFY_INTERVAL_MINUTES", "45"),
                janela: [ ENV.fetch("TRACER_NOTIFY_ACTIVE_START", "09:00"),
                          ENV.fetch("TRACER_NOTIFY_ACTIVE_END", "18:00") ]),
        Job.new(nome: :tracking, run: -> { Tracking::UseCases::RebuildDayReport.new.call },
                intervalo_minutos: ENV.fetch("TRACER_TRACKING_INTERVAL_MINUTES", "30"),
                janela: [ ENV.fetch("TRACER_TRACKING_ACTIVE_START", "08:00"),
                          ENV.fetch("TRACER_TRACKING_ACTIVE_END", "23:50") ]),
        # Rede de segurança: uma vez por dia, com o filtro largo do Jira, para
        # pegar card que o filtro estreito não vê (JQL não aceita "comment
        # CHANGED BY"). É a única execução de ~60 s/600 MB do dia.
        Job.new(nome: :jira_sweep,
                run: -> { Tracking::UseCases::RebuildDayReport.new(filtro: "largo").call(Date.current) },
                intervalo_minutos: 24 * 60, once_per_day: true,
                janela: [ ENV.fetch("TRACER_JIRA_SWEEP_AT", "23:40"), "23:59" ]),
        Job.new(nome: :one_on_ones, run: -> { OneOnOnes::UseCases::ImportTranscription.new.call },
                intervalo_minutos: ENV.fetch("TRACER_ONE_ON_ONES_INTERVAL_MINUTES", "45"),
                janela: [ ENV.fetch("TRACER_ONE_ON_ONES_ACTIVE_START", "08:00"),
                          ENV.fetch("TRACER_ONE_ON_ONES_ACTIVE_END", "23:50") ])
      ])
    end

    def start
      Thread.new do
        Thread.current.name = "tracker-scheduler"
        loop do
          tick(@clock.call)
          sleep @tick
        end
      end
    end

    # Roda os jobs devidos. Cada um é resgatado dentro de Job#executar — um
    # erro no Jira não impede a notificação.
    def tick(agora = @clock.call)
      devidos = @jobs.select { |job| job.due?(agora) }
      return if devidos.empty?

      @logger.info("[tracker] tick #{devidos.map(&:nome).join(',')}")
      devidos.each { |job| job.executar(agora) }
    end

    private

    attr_reader :logger
  end
end
