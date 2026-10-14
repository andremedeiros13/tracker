# frozen_string_literal: true

namespace :tracking do
  desc "Coleta as entregas de hoje e appenda no Brag document (dedup incremental)"
  task report: :environment do
    novas = Tracking::UseCases::CollectTodaysDeliveries.new.call
    if novas.nil? || novas.zero?
      puts "Nada novo — Brag document em dia."
    else
      puts "#{novas} entrega#{novas > 1 ? "s" : ""} appendada#{novas > 1 ? "s" : ""} no Brag document."
    end
  end

  desc "Descobre o customfield 'Reviewer' no Jira (copie o id pro .env)"
  task discover_reviewer: :environment do
    Tracking::UseCases::DiscoverReviewer.new.call
  end
end
