# frozen_string_literal: true

module Tracking
  module Entities
    # Uma review que EU dei no dia, em PR de outra pessoa. `state` já vem
    # traduzido ("Aprovado", "Mudanças solicitadas").
    GivenReview = Data.define(:pull_request, :state, :submitted_at)
  end
end
