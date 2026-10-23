# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracker::Scheduler do
  let(:logger) { instance_double(ActiveSupport::Logger, info: nil, error: nil) }
  let(:agora) { Time.zone.local(2026, 10, 21, 10, 0) }

  def job(nome: :x, intervalo: 30, janela: nil, once_per_day: false, &bloco)
    Tracker::Scheduler::Job.new(nome: nome, intervalo_minutos: intervalo,
                                janela: janela && Tracker::Scheduler::Janela.parse(*janela),
                                once_per_day: once_per_day, run: bloco || -> { }, logger: logger)
  end

  describe Tracker::Scheduler::Janela do
    it "inclui as horas da faixa e exclui as de fora" do
      janela = described_class.parse("09:00", "18:00")

      expect(janela).to be_include(Time.zone.local(2026, 10, 21, 9, 0))
      expect(janela).to be_include(Time.zone.local(2026, 10, 21, 18, 0))
      expect(janela).not_to be_include(Time.zone.local(2026, 10, 21, 8, 59))
      expect(janela).not_to be_include(Time.zone.local(2026, 10, 21, 18, 1))
    end

    it "sem as duas pontas não restringe horário" do
      expect(described_class.parse(nil, "18:00")).to be_nil
    end
  end

  describe Tracker::Scheduler::Job do
    it "roda quando o intervalo venceu" do
      j = job(intervalo: 30)

      expect(j.due?(agora)).to be(true)
      j.executar(agora)
      expect(j.due?(agora + 29.minutes)).to be(false)
      expect(j.due?(agora + 30.minutes)).to be(true)
    end

    it "respeita a janela de horário" do
      j = job(janela: [ "09:00", "18:00" ], intervalo: 60)
      j.executar(Time.zone.local(2026, 10, 21, 9, 0))

      expect(j.due?(Time.zone.local(2026, 10, 21, 19, 0))).to be(false)
      expect(j.due?(Time.zone.local(2026, 10, 22, 9, 5))).to be(true)
    end

    it "once_per_day não repete no mesmo dia" do
      j = job(janela: [ "23:40", "23:59" ], once_per_day: true)

      j.executar(Time.zone.local(2026, 10, 21, 23, 40))

      expect(j.due?(Time.zone.local(2026, 10, 21, 23, 50))).to be(false)
      expect(j.due?(Time.zone.local(2026, 10, 22, 23, 41))).to be(true)
    end

    it "falha não derruba o loop e agenda backoff" do
      j = job(intervalo: 60) { raise "boom" }

      expect { j.executar(agora) }.not_to raise_error
      expect(j.due?(agora + 4.minutes)).to be(false)
      expect(j.due?(agora + 5.minutes)).to be(true)
    end
  end

  describe "#tick" do
    it "roda só os jobs devidos" do
      rodou = []
      notif = job(nome: :notify, janela: [ "09:00", "18:00" ], intervalo: 45) { rodou << :notify }
      track = job(nome: :tracking, janela: [ "08:00", "23:50" ], intervalo: 30) { rodou << :tracking }
      scheduler = described_class.new(jobs: [ notif, track ], logger: logger)

      scheduler.tick(agora)

      expect(rodou).to contain_exactly(:notify, :tracking)
    end

    it "um job que falha não impede o outro" do
      rodou = []
      quebra = job(nome: :quebra) { raise "boom" }
      funciona = job(nome: :funciona) { rodou << :funciona }
      scheduler = described_class.new(jobs: [ quebra, funciona ], logger: logger)

      scheduler.tick(agora)

      expect(rodou).to eq([ :funciona ])
      expect(logger).to have_received(:error).with(a_string_including("quebra"))
    end

    it "não loga nem roda nada fora de todas as janelas" do
      j = job(janela: [ "09:00", "18:00" ], intervalo: 45)
      scheduler = described_class.new(jobs: [ j ], logger: logger)

      scheduler.tick(Time.zone.local(2026, 10, 21, 3, 0))

      expect(logger).not_to have_received(:info)
    end
  end
end
