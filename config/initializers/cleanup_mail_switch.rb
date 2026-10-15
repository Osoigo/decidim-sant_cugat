# frozen_string_literal: true

# Engancha el interruptor de CleanupMailSwitch al trabajo de entrega de
# ActionMailer. Tiene que cargarse en todos los procesos, web y workers, porque
# los correos que hay que callar durante la limpieza los genera Sidekiq.
Rails.application.config.to_prepare do
  ActionMailer::MailDeliveryJob.prepend(CleanupMailSwitch::SaltarEntrega)
end
