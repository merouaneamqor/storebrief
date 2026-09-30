require "test_helper"

class WhatsappNotifierTest < ActiveSupport::TestCase
  test "sending a checklist logs a stubbed WhatsApp message for store phones" do
    brand = build_brand("whatsapp-on", store_locale: "ar", whatsapp_phone: "+212600000000")
    checklist = send_checklist(brand)

    log = NotificationLog.find_by!(channel: "whatsapp", notifiable: checklist)
    assert_equal "stubbed", log.status
    assert_equal brand.store_user, log.user
    assert_equal "+212600000000", log.phone
    assert_includes log.message, "/checklists/deliveries/#{checklist.checklist_deliveries.first.id}"
    assert_includes log.message, "قائمة تحقق جديدة"
  end

  test "no WhatsApp log when the flag is off or the store has no phone" do
    off = build_brand("whatsapp-off", features: { whatsapp_alerts: false }, whatsapp_phone: "+212600000001")
    no_phone = build_brand("whatsapp-nophone")

    send_checklist(off)
    send_checklist(no_phone)

    assert_equal 0, NotificationLog.where(channel: "whatsapp").count
  end

  private

  def send_checklist(brand)
    checklist = brand.tenant.checklists.create!(author: brand.hq, title_fr: "Ouverture", title_ar: "فتح", status: "draft")
    checklist.checklist_items.create!(position: 0, title_fr: "Vitrine", requires_photo: false)
    checklist.send_to!([ brand.store.id ])
    checklist
  end
end
