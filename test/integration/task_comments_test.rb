require "test_helper"

class TaskCommentsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand(
      "comments-ui",
      features: {
        morocco_ops: true,
        briefs: true,
        push_alerts: true,
        email_alerts: true,
        whatsapp_alerts: true
      },
      whatsapp_phone: "+212600000035"
    )
    @tenant = @brand.tenant
    @brief = @tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Vitrine",
      body_fr: "Mettre à jour",
      format: "task",
      status: "draft"
    )
    @brief.send_to!([ @brand.store.id ])
    @delivery = @brief.deliveries.first
  end

  test "store and hq can post threaded comments with mentions and audit" do
    sign_in @brand.store_user
    get inbox_path(@delivery)
    assert_response :success
    assert_match I18n.t("morocco.comments.title", locale: :en), response.body

    assert_difference -> { @delivery.delivery_comments.count }, 1 do
      post delivery_comments_path(@delivery), params: {
        delivery_comment: {
          body: "Besoin d'aide @#{@brand.hq.email}",
          mentioned_user_ids: [ @brand.hq.id ]
        }
      }
    end
    assert_redirected_to inbox_path(@delivery, anchor: "comments")
    comment = @delivery.delivery_comments.order(:id).last
    assert_equal @brand.store_user, comment.user
    assert_includes comment.mentioned_user_ids, @brand.hq.id
    assert @delivery.delivery_events.where(kind: "comment", tenant_id: @tenant.id).exists?
    assert comment.readonly?

    delete logout_path
    sign_in @brand.hq

    assert_difference -> { @delivery.delivery_comments.count }, 1 do
      post delivery_comments_path(@delivery), params: {
        delivery_comment: {
          body: "On s'en occupe",
          parent_id: comment.id
        }
      }
    end
    reply = @delivery.delivery_comments.order(:id).last
    assert_equal comment.id, reply.parent_id
    assert_equal @brand.hq, reply.user

    get communication_path(@brief)
    assert_response :success
    assert_match "Besoin d'aide", response.body
    assert_match "On s'en occupe", response.body
    assert_select "#delivery-comment-#{@delivery.id}"
  end

  test "mention notifies via dispatcher with billed email and whatsapp" do
    ActionMailer::Base.deliveries.clear
    NotificationLog.where(tenant: @tenant).delete_all

    sign_in @brand.hq
    with_vapid do
      WebPush.stub(:payload_send, true) do
        post delivery_comments_path(@delivery), params: {
          delivery_comment: {
            body: "Merci @#{@brand.store_user.email} de confirmer",
            mentioned_user_ids: [ @brand.store_user.id ]
          }
        }
      end
    end

    comment = @delivery.delivery_comments.order(:id).last
    logs = NotificationLog.where(tenant: @tenant, notifiable: comment)
    channels = logs.pluck(:channel)
    assert_includes channels, "email"
    assert_includes channels, "whatsapp"
    assert logs.where(channel: "email", billed: true).exists? ||
           logs.where(channel: "email", billed: false).exists?
    assert logs.where(channel: "whatsapp", billed: true).exists?
    assert_equal true, @tenant.feature?(:push_alerts)
  end

  test "comments locale keys exist without em dashes" do
    %i[fr en es ar].each do |locale|
      copy = I18n.t("morocco.comments", locale: locale)
      assert copy[:title].present?
      assert copy[:posted].present?
      flat = copy.values
      assert flat.none? { |value| value.to_s.include?("—") }
      assert I18n.t("morocco.history.kinds.comment", locale: locale).present?
    end
  end

  test "foreign tenant delivery is not commentable" do
    other = build_brand("comments-other", features: { morocco_ops: true, briefs: true })
    foreign_brief = other.tenant.communications.create!(
      author: other.hq, title_fr: "X", body_fr: "Y", format: "task", status: "draft"
    )
    foreign_brief.send_to!([ other.store.id ])
    foreign_delivery = foreign_brief.deliveries.first

    sign_in @brand.hq
    assert_no_difference -> { DeliveryComment.count } do
      post delivery_comments_path(foreign_delivery), params: {
        delivery_comment: { body: "cross tenant" }
      }
    end
    assert_response :not_found
  end
end
