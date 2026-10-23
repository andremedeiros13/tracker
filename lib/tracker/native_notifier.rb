# frozen_string_literal: true

module Tracker
  # Notificador nativo do S.O. — shell-out para os comandos nativos de cada
  # plataforma, sem gem/biblioteca de notificação (decisão do mapa: notificações
  # nativas via comandos do S.O. diretos).
  #
  #   notify-send (Linux) | osascript -e 'display notification ...' (macOS)
  #   PowerShell toast (Windows)
  #
  # Devolve true quando o comando foi disparado com sucesso e false quando o
  # sistema operacional não tem um comando (ou o comando falhou). Antes o
  # retorno de `system` era descartado e um SO não reconhecido devolvia nil sem
  # nenhum log — a notificação, que é o produto, podia simplesmente não
  # acontecer. Quem chama decide o que fazer com o false (o ciclo loga).
  class NativeNotifier
    # `runner` é o shell-out; `host_os` decide a plataforma. Injetados para o
    # teste não precisar disparar um toast de verdade nem fingir RbConfig.
    def initialize(runner: nil, host_os: nil)
      @runner = runner || ->(*comando) { system(*comando) }
      @host_os = host_os
    end

    def notify(title, body)
      comando = comando_para(title, body)
      return false if comando.nil?

      @runner.call(*comando) ? true : false
    end

    # Notificação de teste na primeira execução (bin/setup) — o usuário concede
    # permissão na hora (macOS/Windows pedem permissão na 1ª notificação).
    def self.test!
      new.notify("Tracker", "Notificações funcionando! O Tracker vai lembrar você das pendências.")
    end

    def platform
      @platform ||= case host_os
      when /linux/   then :linux
      when /darwin/  then :macos
      when /mswin|mingw|cygwin/ then :windows
      end
    end

    private

    def host_os = @host_os || RbConfig::CONFIG["host_os"]

    def comando_para(title, body)
      case platform
      when :linux   then [ "notify-send", title, body ]
      when :macos   then [ "osascript", "-e", "display notification \"#{body}\" with title \"#{title}\"" ]
      when :windows then [ "powershell", "-NoProfile", "-Command", toast_powershell(title, body) ]
      end
    end

    def toast_powershell(title, body)
      <<~PS
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $text = $template.GetElementsByTagName("text")
        $text.Item(0).AppendChild($template.CreateTextNode("#{title}")) | Out-Null
        $text.Item(1).AppendChild($template.CreateTextNode("#{body}")) | Out-Null
        $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Tracker").Show($toast)
      PS
    end
  end
end
