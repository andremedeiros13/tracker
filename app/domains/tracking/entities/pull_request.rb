# frozen_string_literal: true

module Tracking
  module Entities
    # Um PR do engenheiro que aparece no dia — aberto, atualizado ou mergeado.
    # Só os campos que o Brag mostra; `my_comment_rounds` é quantas reviews
    # COMMENTED eu deixei no meu próprio PR (rodadas de ajuste).
    #
    # O peso da entrega ("14 commits · 17 arquivos · +1257/−55") é copy do
    # renderer — aqui ficam os números, não a frase.
    PullRequest = Data.define(
      :number, :title, :url, :repo, :body,
      :created_at, :merged_at,
      :commits, :changed_files, :additions, :deletions,
      :my_comment_rounds, :approvals
    ) do
      def initialize(body: nil, merged_at: nil, commits: nil, changed_files: nil,
                     additions: nil, deletions: nil, my_comment_rounds: 0,
                     approvals: [], **resto)
        super(body: body, merged_at: merged_at, commits: commits, changed_files: changed_files,
              additions: additions, deletions: deletions, my_comment_rounds: my_comment_rounds,
              approvals: Array(approvals), **resto)
      end

      def merged? = !merged_at.nil?
    end
  end
end
