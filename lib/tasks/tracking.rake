# frozen_string_literal: true

namespace :tracking do
  desc "Coleta o dia e reconstrói a seção no Brag document (idempotente)"
  task :rebuild, [ :date ] => :environment do |_, args|
    dia = args[:date] ? Date.parse(args[:date]) : Date.current
    mudou = Tracking::UseCases::RebuildDayReport.new.call(dia)
    puts mudou.positive? ? "Brag atualizado (#{mudou} dia(s))." : "Nada mudou — Brag em dia."
  end

  desc "Imprime o dia como vai ficar no Brag, SEM escrever no Notion"
  task :preview, [ :date ] => :environment do |_, args|
    dia = args[:date] ? Date.parse(args[:date]) : Date.current
    Tracking::UseCases::RebuildDayReport.new(dry_run: true).call(dia)
  end

  desc "Adota a seção antiga do dia (backup em storage/ + sentinel + ledger)"
  task :adopt, [ :date ] => :environment do |_, args|
    dia = args[:date] ? Date.parse(args[:date]) : Date.current
    Tracking::BragDocument.new.adopt(dia)
  end

  desc "Conserta o Brag fora de ordem (dry-run; APPLY=1 aplica) — DESTRUTIVO"
  task repair_order: :environment do
    Tracking::BragDocument.new.repair_order(apply: ENV["APPLY"] == "1")
  end

  desc "Descobre o customfield 'Reviewer' no Jira (copie o id pro .env)"
  task discover_reviewer: :environment do
    Tracking::UseCases::DiscoverReviewer.new.call
  end
end
