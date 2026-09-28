class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "StoreBrief <noreply@storebrief.com>")
  layout "mailer"
end
