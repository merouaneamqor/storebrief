module Bilingual
  extend ActiveSupport::Concern

  class_methods do
    def bilingual_fields(*fields)
      fields.each do |field|
        define_method(field) do
          localized_value(field)
        end
      end
    end
  end

  def localized_value(field, locale: I18n.locale)
    fr = public_send(:"#{field}_fr")
    ar = public_send(:"#{field}_ar")
    locale.to_s == "ar" && ar.present? ? ar : fr
  end
end
