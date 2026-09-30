class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "Vazivo <noreply@vazivo.com>")
  layout "mailer"
end
