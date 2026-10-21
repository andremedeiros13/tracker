# frozen_string_literal: true

# Boot do daemon: a lógica vive em lib/tracker/scheduler.rb (testável sem
# Rails). Aqui só o hook que liga a thread depois da aplicação subir.
#
# Desligado em testes, no console, e quando TRACER_DISABLE_SCHEDULER=1 (usado
# pelo `rails runner` avulso para não disparar um ciclo junto).
Rails.application.config.after_initialize do
  next if defined?(Rails::Console) || Rails.env.test?
  next if ENV["TRACER_DISABLE_SCHEDULER"] == "1"
  next if Tracker::Scheduler.disabled?

  Tracker::Scheduler.from_env.start
end
