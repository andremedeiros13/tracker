# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end

# Acrônimos do domínio — Tracker::GitHub (não Tracker::Github) e Tracker::Jira.
# HTTP entra pelo mesmo motivo: lib/tracker/http.rb define Tracker::HTTP.
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.acronym "GitHub"
  inflect.acronym "HTTP"
end
