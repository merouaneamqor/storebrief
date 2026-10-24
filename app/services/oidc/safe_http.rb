require "net/http"
require "resolv"
require "ipaddr"
require "timeout"

module Oidc
  # Public HTTPS only. Keep environment proxy and CA settings; never follow redirects.
  class SafeHttp
    BLOCKED = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8 2001:db8::/32 64:ff9b::/96 2002::/16].map { |range| IPAddr.new(range) }.freeze
    GLOBAL_IPV6 = IPAddr.new("2000::/3")
    MAX_BYTES = 1.megabyte

    def self.uri(value)
      parsed = URI.parse(value.to_s)
      unless parsed.is_a?(URI::HTTPS) && parsed.host.present? && parsed.port == 443 && parsed.userinfo.nil? && parsed.fragment.nil? && value.to_s.bytesize <= 2048
        raise Error
      end
      raise Error if parsed.host.match?(/(?:\A|\.)(?:localhost|local|internal)\z/i)
      begin
        raise Error unless public_ip?(IPAddr.new(parsed.hostname))
      rescue IPAddr::InvalidAddressError
        # DNS names are resolved and checked at request time.
      end
      parsed
    rescue URI::InvalidURIError
      raise Error
    end

    def self.public_ip?(address)
      address = address.native if address.ipv4_mapped?
      return false if address.ipv6? && !GLOBAL_IPV6.include?(address)

      BLOCKED.none? { |range| range.include?(address) }
    end

    def self.address_for(uri)
      addresses = Timeout.timeout(3) { Resolv.getaddresses(uri.hostname) }
      raise Error if addresses.empty? || addresses.any? { |address| !public_ip?(IPAddr.new(address)) }

      addresses.first
    rescue Resolv::ResolvError, Timeout::Error, IPAddr::InvalidAddressError
      raise Error
    end

    def self.json(url, form: nil, credentials: nil)
      uri = self.uri(url)
      ip = address_for(uri)
      http = Net::HTTP.new(uri.hostname, uri.port) # :ENV proxy is the default.
      http.ipaddr = ip
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.min_version = OpenSSL::SSL::TLS1_2_VERSION
      http.open_timeout = 4
      http.read_timeout = 5
      http.write_timeout = 5
      request = form ? Net::HTTP::Post.new(uri.request_uri) : Net::HTTP::Get.new(uri.request_uri)
      request["Accept"] = "application/json"
      request.set_form_data(form) if form
      request.basic_auth(*credentials.map { |value| URI.encode_www_form_component(value) }) if credentials
      body = +""
      Timeout.timeout(12) do
        http.request(request) do |response|
          raise Error unless response.code == "200" && response["content-type"].to_s.match?(%r{\Aapplication/(?:json|jwk-set\+json)(?:;|\z)}i)

          response.read_body do |chunk|
            raise Error if body.bytesize + chunk.bytesize > MAX_BYTES

            body << chunk
          end
        end
      end
      JSON.parse(body)
    rescue JSON::ParserError, IOError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::ProtocolError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
      raise Error
    end
  end
end
