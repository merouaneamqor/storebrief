require "test_helper"

class TaskDeadlineAttachmentsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("task-deadline")
    @zone = Vazivo::Schedule::ZONE
  end

  def task_params(extra = {})
    {
      title_fr: "Refaire la vitrine",
      body_fr: "Suivre le planogramme joint.",
      format: "task"
    }.merge(extra)
  end

  test "form exposes the deadline field and file input for tasks" do
    sign_in(@brand.hq)
    get new_communication_path
    assert_response :success
    assert_select "input[type=datetime-local][name='communication[due_at]']"
    assert_select "input[type=file][name='communication[attachments][]']"
  end

  test "HQ creates a task with a deadline and attachments and the store sees them" do
    sign_in(@brand.hq)
    due_local = (@zone.now + 3.days).change(hour: 15, min: 30, sec: 0)

    assert_difference -> { @brand.tenant.communications.count }, 1 do
      post communications_path, params: {
        communication: task_params(
          due_at: due_local.strftime("%Y-%m-%dT%H:%M"),
          attachments: [
            fixture_file_upload("notice.pdf", "application/pdf"),
            fixture_file_upload("window.jpg", "image/jpeg")
          ]
        ),
        org_unit_ids: [ @brand.store.id ],
        commit: "send"
      }
    end

    task = @brand.tenant.communications.order(:id).last
    assert_equal "sent", task.status
    assert_equal 2, task.attachments.count
    assert_equal due_local.to_i, task.due_at.to_i
    delivery = task.deliveries.find_by!(org_unit: @brand.store)
    assert_equal due_local.to_i, delivery.due_at.to_i

    reset!
    host! "localhost"
    sign_in(@brand.store_user)
    get inbox_path(delivery)
    assert_response :success
    assert_select ".brief-attachments a", text: /notice\.pdf/
    assert_select ".brief-attachments a", text: /window\.jpg/
  end

  test "without a deadline the default falls back to Schedule.default_due" do
    sign_in(@brand.hq)
    post communications_path, params: {
      communication: task_params(due_at: ""),
      org_unit_ids: [ @brand.store.id ],
      commit: "send"
    }

    task = @brand.tenant.communications.order(:id).last
    assert_equal "sent", task.status
    assert task.due_at > Time.current
    assert_in_delta Vazivo::Schedule.default_due(@brand.tenant).to_f, task.due_at.to_f, 2.days.to_f
    assert_equal task.due_at.to_i, task.deliveries.first.due_at.to_i
  end

  test "HQ edits a draft task deadline and attachments" do
    sign_in(@brand.hq)
    post communications_path, params: {
      communication: task_params(due_at: "2030-01-10T10:00",
                                 attachments: [ fixture_file_upload("notice.pdf", "application/pdf") ]),
      commit: "draft"
    }
    task = @brand.tenant.communications.order(:id).last
    assert_equal 10, task.due_at.in_time_zone(@zone).hour
    assert_equal 1, task.attachments.count

    get edit_communication_path(task)
    assert_select "input[type=datetime-local][value='2030-01-10T10:00']"

    patch communication_path(task), params: {
      communication: {
        due_at: "2030-01-12T16:45",
        remove_attachment_ids: [ task.attachments.first.id ],
        attachments: [ fixture_file_upload("window.jpg", "image/jpeg") ]
      },
      commit: "draft"
    }
    local = task.reload.due_at.in_time_zone(@zone)
    assert_equal [ 2030, 1, 12, 16, 45 ], [ local.year, local.month, local.day, local.hour, local.min ]
    assert_equal [ "window.jpg" ], task.attachments.map { |a| a.filename.to_s }
  end

  test "server rejects disallowed content types on task attachments" do
    sign_in(@brand.hq)
    assert_no_difference -> { @brand.tenant.communications.count } do
      post communications_path, params: {
        communication: task_params(attachments: [ fixture_file_upload("notes.txt", "text/plain") ]),
        commit: "draft"
      }
    end
    assert_response :unprocessable_entity
  end

  test "server rejects oversized task attachments" do
    sign_in(@brand.hq)
    original = Communication::ATTACHMENT_MAX_BYTES
    Communication.send(:remove_const, :ATTACHMENT_MAX_BYTES)
    Communication.const_set(:ATTACHMENT_MAX_BYTES, 1.kilobyte)
    begin
      assert_no_difference -> { @brand.tenant.communications.count } do
        post communications_path, params: {
          communication: task_params(attachments: [ fixture_file_upload("window.jpg", "image/jpeg") ]),
          commit: "draft"
        }
      end
      assert_response :unprocessable_entity
    ensure
      Communication.send(:remove_const, :ATTACHMENT_MAX_BYTES)
      Communication.const_set(:ATTACHMENT_MAX_BYTES, original)
    end
  end

  test "news briefs still cannot carry attachments" do
    sign_in(@brand.hq)
    post communications_path, params: {
      communication: task_params(format: "news", attachments: [ fixture_file_upload("notice.pdf", "application/pdf") ]),
      commit: "draft"
    }
    assert_equal 0, @brand.tenant.communications.order(:id).last.attachments.count
  end
end
