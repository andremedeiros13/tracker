require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Log em STDOUT para o journald (o daemon roda como unit do systemd). O
  # default do Rails escreveria um arquivo sem rotação em :debug — em um
  # processo de longa duração isso vira disco cheio.
  config.logger = ActiveSupport::Logger.new($stdout)
  config.log_level = ENV.fetch("TRACER_LOG_LEVEL", "info").to_sym
  config.log_tags = [ :pid ]

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
