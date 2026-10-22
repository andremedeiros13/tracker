# frozen_string_literal: true

require "rails_helper"

RSpec.describe OneOnOnes::UseCases::ImportTranscription do
  let(:dir) { Dir.mktmpdir }
  let(:meetings) { instance_double(OneOnOnes::Repositories::MeetingRepository) }
  let(:todos) { instance_double(Todos::Repositories::TodoDatabase) }
  let(:logger) { instance_double(ActiveSupport::Logger, error: nil, debug: nil) }
  let(:me) { "André" }
  let(:use_case) do
    described_class.new(dir: dir, parser: OneOnOnes::UseCases::ParseTranscription.new,
                        meetings: meetings, todos: todos, logger: logger, me: me)
  end

  def soltar_transcricao(conteudo = Rails.root.join("spec/fixtures/transcricao-real.md").read)
    arquivo = File.join(dir, "transcricao-teste.md")
    File.write(arquivo, conteudo)
    arquivo
  end

  before do
    allow(meetings).to receive(:append)
    allow(todos).to receive(:create)
  end

  after { FileUtils.remove_entry(dir) }

  describe "#call" do
    it "importa o arquivo solto na pasta: resumo na page 1-on-1" do
      soltar_transcricao

      use_case.call

      expect(meetings).to have_received(:append).with(
        satisfy { |m| m.title == "1:1 André / Spalenza" },
        satisfy { |itens| itens.size == 8 }
      )
    end

    it "cria To-Dos só dos action items meus (matching parcial)" do
      soltar_transcricao

      titulos = []
      allow(todos).to receive(:create) { |titulo| titulos << titulo }
      use_case.call

      expect(todos).to have_received(:create).exactly(7).times
      expect(titulos).to all(start_with("André Medeiros:"))
      expect(titulos).not_to include(start_with("Rodolfo Spalenza:"))
    end

    it "cria os To-Dos com origem via_transcricao (label vem do schema)" do
      soltar_transcricao

      use_case.call

      expect(todos).to have_received(:create).with(anything, origin: :via_transcricao).exactly(7).times
    end

    it "move o arquivo para importados/ (nunca re-importa)" do
      arquivo = soltar_transcricao

      use_case.call

      expect(File.exist?(arquivo)).to be(false)
      expect(File.exist?(File.join(dir, "importados", "transcricao-teste.md"))).to be(true)
    end

    it "não re-importa arquivo já importado (dedup)" do
      soltar_transcricao
      use_case.call

      use_case.call

      expect(meetings).to have_received(:append).once
      expect(todos).to have_received(:create).exactly(7).times
    end

    it "não cria To-Do quando o nome do usuário não está configurado" do
      use_case_sem_me = described_class.new(dir: dir, parser: OneOnOnes::UseCases::ParseTranscription.new,
                                            meetings: meetings, todos: todos, logger: logger, me: nil)
      soltar_transcricao

      use_case_sem_me.call

      expect(todos).not_to have_received(:create)
      expect(meetings).to have_received(:append).once
    end

    it "não derruba o ciclo quando o Notion falha (erro resgatado e logado)" do
      soltar_transcricao
      allow(meetings).to receive(:append).and_raise(Tracker::Notion::ApiError.new("401", "unauthorized"))

      resultado = use_case.call

      expect(resultado).to eq(0)
      expect(logger).to have_received(:error).with(a_string_including("Notion API 401"))
    end

    it "é no-op quando a pasta não está configurada" do
      use_case_sem_dir = described_class.new(dir: nil, parser: OneOnOnes::UseCases::ParseTranscription.new,
                                             meetings: meetings, todos: todos, logger: logger, me: me)

      expect(use_case_sem_dir.call).to eq(0)
      expect(meetings).not_to have_received(:append)
    end

    it "move arquivo sem reuniões parseáveis (não importa lixo)" do
      arquivo = soltar_transcricao("texto qualquer sem estrutura")

      resultado = use_case.call

      expect(resultado).to eq(0)
      expect(meetings).not_to have_received(:append)
      expect(File.exist?(File.join(dir, "importados", "transcricao-teste.md"))).to be(true)
    end
  end
end
