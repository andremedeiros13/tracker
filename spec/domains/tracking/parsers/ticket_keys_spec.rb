# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracking::Parsers::TicketKeys do
  describe ".call" do
    it "acha a key no título e na primeira linha do corpo" do
      chaves = described_class.call(
        "CHEKOUT-2301 [Payments] Captura o valor reservado",
        ":ticket: [CHEKOUT-2301](https://rdstation.atlassian.net/browse/CHEKOUT-2301)"
      )

      expect(chaves).to eq([ "CHEKOUT-2301" ])
    end

    it "junta keys de vários textos, sem repetir" do
      chaves = described_class.call("CHEKOUT-2301 e CHEKOUT-2298", "de novo CHEKOUT-2301")

      expect(chaves).to eq([ "CHEKOUT-2301", "CHEKOUT-2298" ])
    end

    it "não casa coisas que não são card (UTF-8, HTTP-2, letras minúsculas)" do
      expect(described_class.call("UTF-8 e HTTP-2 e abc-12")).to be_empty
    end

    it "aceita key com número de um dígito? não — exige 2+ para evitar falso positivo" do
      expect(described_class.call("ENG-1")).to be_empty
      expect(described_class.call("ENG-12")).to eq([ "ENG-12" ])
    end

    it "tolera nil" do
      expect(described_class.call(nil, "", "ENG-12")).to eq([ "ENG-12" ])
    end
  end
end
