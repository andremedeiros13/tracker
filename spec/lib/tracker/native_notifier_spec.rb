# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracker::NativeNotifier do
  # O runner engole o shell-out: nenhum teste dispara um toast de verdade.
  let(:chamadas) { [] }
  let(:runner) { ->(*comando) { chamadas << comando; sucesso } }
  let(:sucesso) { true }

  def notifier(host_os:) = described_class.new(runner:, host_os:)

  describe "#notify" do
    it "Linux: notify-send com título e corpo" do
      expect(notifier(host_os: "linux-gnu").notify("Tracker", "3 pendências")).to be(true)

      expect(chamadas).to eq([ [ "notify-send", "Tracker", "3 pendências" ] ])
    end

    it "macOS: osascript com display notification" do
      notifier(host_os: "darwin23").notify("Tracker", "3 pendências")

      expect(chamadas.first.first).to eq("osascript")
      expect(chamadas.first.last).to include("display notification", "3 pendências", "Tracker")
    end

    it "Windows: toast via PowerShell" do
      notifier(host_os: "mingw32").notify("Tracker", "3 pendências")

      expect(chamadas.first.first).to eq("powershell")
      expect(chamadas.first.last).to include("ToastNotification")
    end

    # O bug: SO não reconhecido devolvia nil em silêncio — a notificação, que é
    # o produto, simplesmente não acontecia.
    it "SO desconhecido: não dispara e devolve false (em vez de nil silencioso)" do
      expect(notifier(host_os: "aix7").notify("Tracker", "x")).to be(false)
      expect(chamadas).to be_empty
    end

    it "comando que falha devolve false (o chamador pode logar)" do
      allow(runner).to receive(:call).and_return(false)

      expect(notifier(host_os: "linux-gnu").notify("Tracker", "x")).to be(false)
    end
  end

  describe "#platform" do
    it "reconhece as três plataformas suportadas" do
      expect(notifier(host_os: "linux-gnu").platform).to eq(:linux)
      expect(notifier(host_os: "darwin23").platform).to eq(:macos)
      expect(notifier(host_os: "mingw32").platform).to eq(:windows)
    end
  end
end
