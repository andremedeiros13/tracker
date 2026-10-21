# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::Parsers::StatusChain do
  let(:chain) { described_class.new }

  describe "#call" do
    it "encadeia transições contíguas numa linha só" do
      transicoes = [
        [ "Prioritized", "To Do" ],
        [ "To Do", "In Progress" ],
        [ "In Progress", "Review" ]
      ]

      expect(chain.call(transicoes)).to eq([ "Prioritized → To Do → In Progress → Review" ])
    end

    it "descarta cadeia inteira dentro das colunas de entrada (higiene de board)" do
      expect(chain.call([ [ "Prioritized", "To Do" ] ])).to be_empty
      expect(chain.call([ [ "Backlog", "Prioritized" ], [ "Prioritized", "To Do" ] ])).to be_empty
    end

    it "mantém a cadeia quando o card avançou de verdade" do
      expect(chain.call([ [ "To Do", "In Progress" ] ])).to eq([ "To Do → In Progress" ])
    end

    it "separar cadeias quando há salto (não inventa ligação)" do
      transicoes = [ [ "To Do", "In Progress" ], [ "Review", "Ready for Deploy" ] ]

      expect(chain.call(transicoes)).to eq([ "To Do → In Progress", "Review → Ready for Deploy" ])
    end

    it "encadeia em ordem cronológica recebida" do
      transicoes = [ [ "Review", "Ready for Deploy" ], [ "Ready for Deploy", "Done" ] ]

      expect(chain.call(transicoes)).to eq([ "Review → Ready for Deploy → Done" ])
    end

    it "retorna vazio sem transições" do
      expect(chain.call([])).to be_empty
    end
  end
end
