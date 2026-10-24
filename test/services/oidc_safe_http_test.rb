require "test_helper"

class OidcSafeHttpTest < ActiveSupport::TestCase
  test "provider URLs reject plaintext local networks credentials fragments and alternate ports" do
    %w[http://idp.example.com https://127.0.0.1 https://10.0.0.1 https://169.254.169.254/latest https://[::1]/ https://[fec0::1]/ https://[::127.0.0.1]/ https://[::ffff:127.0.0.1]/ https://localhost https://idp.internal https://user:password@idp.example.com https://idp.example.com:8443 https://idp.example.com/#bad].each do |url|
      assert_raises(Oidc::Error, url) { Oidc::SafeHttp.uri(url) }
    end
    assert_equal "idp.example.com", Oidc::SafeHttp.uri("https://idp.example.com/tenant").hostname
  end

  test "every DNS answer must be public and the validated address is used for transport" do
    uri = Oidc::SafeHttp.uri("https://idp.example.com/keys")
    Resolv.stub(:getaddresses, [ "93.184.216.34", "127.0.0.1" ]) do
      assert_raises(Oidc::Error) { Oidc::SafeHttp.address_for(uri) }
    end
    Resolv.stub(:getaddresses, []) do
      assert_raises(Oidc::Error) { Oidc::SafeHttp.address_for(uri) }
    end
    Resolv.stub(:getaddresses, [ "93.184.216.34" ]) do
      assert_equal "93.184.216.34", Oidc::SafeHttp.address_for(uri)
    end
  end

  test "HTTP transport keeps proxy defaults verifies TLS limits bodies and never follows redirects" do
    response_class = Struct.new(:code, :body, :content_type) do
      def [](header)
        content_type if header == "content-type"
      end

      def read_body
        yield body
      end
    end
    transport_class = Struct.new(:ipaddr, :use_ssl, :verify_mode, :min_version, :open_timeout, :read_timeout, :write_timeout, :response, :request_count) do
      def request(request)
        self.request_count = request_count.to_i + 1
        yield response
      end
    end
    transport = transport_class.new
    transport.response = response_class.new("200", '{"keys":[]}', "application/json")
    factory = lambda do |*arguments|
      assert_equal [ "idp.example.com", 443 ], arguments # No proxy-disabling third argument.
      transport
    end
    Oidc::SafeHttp.stub(:address_for, "93.184.216.34") do
      Net::HTTP.stub(:new, factory) do
        assert_equal({ "keys" => [] }, Oidc::SafeHttp.json("https://idp.example.com/keys"))
        assert_equal "93.184.216.34", transport.ipaddr
        assert transport.use_ssl
        assert_equal OpenSSL::SSL::VERIFY_PEER, transport.verify_mode
        assert_operator transport.read_timeout, :<=, 5
        transport.response = response_class.new("302", "", "application/json")
        assert_raises(Oidc::Error) { Oidc::SafeHttp.json("https://idp.example.com/keys") }
        assert_equal 2, transport.request_count
        transport.response = response_class.new("200", "x" * (Oidc::SafeHttp::MAX_BYTES + 1), "application/json")
        assert_raises(Oidc::Error) { Oidc::SafeHttp.json("https://idp.example.com/keys") }
        transport.response = response_class.new("200", "<html>bad</html>", "text/html")
        assert_raises(Oidc::Error) { Oidc::SafeHttp.json("https://idp.example.com/keys") }
        transport.define_singleton_method(:request) { |_| raise Net::HTTPBadResponse, "bad provider response" }
        assert_raises(Oidc::Error) { Oidc::SafeHttp.json("https://idp.example.com/keys") }
      end
    end
  end
end
