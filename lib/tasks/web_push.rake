# frozen_string_literal: true

namespace :web_push do
  desc "Generate VAPID keys for Web Push and print ENV lines"
  task vapid: :environment do
    require "web-push"

    keys = WebPush.generate_key
    puts <<~ENV
      # Add these to .env / production secrets:
      VAPID_PUBLIC_KEY=#{keys.public_key}
      VAPID_PRIVATE_KEY=#{keys.private_key}
      VAPID_SUBJECT=mailto:support@storebrief.app
    ENV
  end
end
