class DemoRequestMailer < ApplicationMailer
  def received(demo_request)
    @demo_request = demo_request
    mail(
      to: ENV.fetch("DEMO_REQUEST_TO", "demos@storebrief.local"),
      subject: "[StoreBrief] Demo request — #{demo_request.company}"
    )
  end
end
