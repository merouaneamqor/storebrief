class SyncController < ApplicationController
  def checklist_responses
    payload = params.permit(responses: [:delivery_id, :item_id, :completed, :notes, :client_uuid, :photo_data])
    results = []

    Array(payload[:responses]).each do |entry|
      delivery = find_delivery(entry[:delivery_id])
      next unless delivery

      item = delivery.checklist.checklist_items.find_by(id: entry[:item_id])
      next unless item

      response = delivery.checklist_item_responses.find_or_initialize_by(checklist_item: item)
      response.completed = ActiveModel::Type::Boolean.new.cast(entry[:completed])
      response.notes = entry[:notes]
      response.client_uuid = entry[:client_uuid] if entry[:client_uuid].present?
      attach_data_uri(response, entry[:photo_data]) if entry[:photo_data].present?
      response.save!
      delivery.complete_if_ready!
      results << { client_uuid: entry[:client_uuid], status: "ok", delivery_status: delivery.status }
    rescue ActiveRecord::RecordInvalid => e
      results << { client_uuid: entry[:client_uuid], status: "error", message: e.message }
    end

    render json: { results: results }
  end

  private

  def find_delivery(id)
    store = current_user.store_org_unit
    return nil unless store

    ChecklistDelivery.joins(:checklist)
                     .where(org_unit: store, checklists: { tenant_id: tenant_scope.id })
                     .find_by(id: id)
  end

  def attach_data_uri(response, data_uri)
    return unless data_uri.to_s.start_with?("data:")

    match = data_uri.match(/\Adata:(.*?);base64,(.+)\z/)
    return unless match

    io = StringIO.new(Base64.decode64(match[2]))
    response.photo.attach(io: io, filename: "sync-#{SecureRandom.hex(4)}.jpg", content_type: match[1].presence || "image/jpeg")
  end
end
