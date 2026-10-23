# frozen_string_literal: true

module Tracker
  module Notion
    # Valida as propriedades de um Database contra o schema esperado (ADR
    # 0001: valida no boot e falha cedo se divergir).
    #
    # O schema vem por injeção — é o chamador que sabe QUAL database está
    # sendo validado (hoje só o To-Dos, mas o validador não é do domínio
    # Todos: ele é do transporte do Notion).
    class SchemaValidator
      def initialize(client:, expected:)
        @client = client
        @expected = expected
      end

      # `expected` é { papel => { notion:, type:, options: } }; comparamos o
      # nome que o schema declara com o que a API devolve.
      def validate!
        atual = @client.retrieve_database.fetch("properties")
        divergencias = []
        @expected.each do |papel, esperado|
          nome = esperado.fetch(:notion)
          if (prop = atual[nome]).nil?
            divergencias << "propriedade '#{nome}' (#{papel}) ausente"
            next
          end
          if prop["type"] != esperado[:type].to_s
            divergencias << "propriedade '#{nome}': tipo '#{prop["type"]}' != '#{esperado[:type]}'"
          end
          next unless (esperadas = esperado[:options]&.keys)

          opcoes_atuais = (prop.dig(prop["type"], "options") || []).map { |opcao| opcao["name"] }
          if (faltando = esperadas - opcoes_atuais).any?
            divergencias << "propriedade '#{nome}': opções ausentes #{faltando.join(", ")}"
          end
        end
        return if divergencias.empty?

        raise SchemaError, "Database do Notion diverge do schema esperado:\n#{divergencias.join("\n")}"
      end
    end
  end
end
