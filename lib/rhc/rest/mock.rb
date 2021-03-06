module RHC::Rest::Mock

  def self.start
    RHC::Helpers.warn "Running in mock mode"
    MockRestClient.new.tap do |c|
      d = c.add_domain("test1")
      app = d.add_application('app1', 'carttype1')
      app.cartridges[0].display_name = "A display name"
      app.add_cartridge('mockcart2')
      app2 = d.add_application('app2', 'carttype2', true)
    end
  end

  module Helpers

    def mock_date_1
      '2013-02-21T01:00:01Z'
    end

    def mock_user
      "test_user"
    end

    def mock_user_auth
      respond_to?(:user_auth) ? self.user_auth : {:user => username, :password => password}
    end

    def credentials_for(with_auth)
      if with_auth == true
        [respond_to?(:username) ? self.username : mock_user, respond_to?(:password) ? self.password : mock_pass]
      elsif with_auth
        with_auth.values_at(:user, :password)
      end
    end

    def expect_authorization(with_auth)
      username, password = credentials_for(with_auth)
      lambda{ |r|
        !username || (r.headers['Authorization'] == "Basic #{["#{username}:#{password}"].pack('m').tr("\n", '')}")
      }
    end

    def stub_api_request(method, uri, with_auth=true)
      api = stub_request(method, mock_href(uri, with_auth))
      api.with(&lambda{ |r| request.headers['Authorization'] == "Bearer #{with_auth[:token]}" }) if with_auth.respond_to?(:[]) && with_auth[:token]
      api.with(&expect_authorization(with_auth))
      api.with(&user_agent_header)
    end

    def stub_api(auth=false, authorizations=false)
      stub_api_request(:get, 'broker/rest/api', auth).
        to_return({
          :body => {
            :data => mock_response_links(authorizations ? mock_api_with_authorizations : mock_real_client_links),
            :supported_api_versions => [1.0, 1.1, 1.2, 1.3, 1.4],
          }.to_json
        })
    end
    def stub_api_v12(auth=false)
      stub_api_request(:get, 'broker/rest/api', auth).
        to_return({
          :body => {
            :data => mock_response_links(mock_real_client_links),
            :supported_api_versions => [1.0, 1.1, 1.2],
          }.to_json
        })
    end
    def stub_user(auth=mock_user_auth)
      stub_api_request(:get, 'broker/rest/user', auth).to_return(simple_user(username))
    end
    def stub_add_key(name='default')
      stub_api_request(:post, 'broker/rest/user/keys', mock_user_auth).
        with(:body => hash_including({:name => name, :type => 'ssh-rsa'})).
        to_return({:status => 201, :body => {}.to_json})
    end
    def stub_update_key(name)
      stub_api_request(:put, "broker/rest/user/keys/#{name}", mock_user_auth).
        with(:body => hash_including({:type => 'ssh-rsa'})).
        to_return({:status => 200, :body => {}.to_json})
    end
    def stub_add_key_error(name, message, code=422)
      stub_api_request(:post, "broker/rest/user/keys", mock_user_auth).
        with(:body => hash_including({:type => 'ssh-rsa'})).
        to_return({:status => code, :body => {:messages => [{:text => message, :field => 'name', :severity => 'error'}]}.to_json})
    end
    def stub_create_domain(name)
      stub_api_request(:post, 'broker/rest/domains', mock_user_auth).
        with(:body => hash_including({:id => name})).
        to_return(new_domain(name))
    end
    def stub_authorizations
      stub_api_request(:get, 'broker/rest/user/authorizations', mock_user_auth).
        to_return({
          :status => 200,
          :body => {
            :type => 'authorizations',
            :data => [
              {
                :note => 'an_authorization',
                :token => 'a_token_value',
                :created_at => mock_date_1,
                :expires_in_seconds => 60,
                :scopes => 'session read'
              }
            ]
          }.to_json
        })
    end
    def stub_delete_authorizations
      stub_api_request(:delete, 'broker/rest/user/authorizations', mock_user_auth).
        to_return(:status => 204)
    end
    def stub_delete_authorization(token)
      stub_api_request(:delete, "broker/rest/user/authorizations/#{token}", mock_user_auth).
        to_return(:status => 204)
    end
    def stub_add_authorization(params)
      stub_api_request(:post, 'broker/rest/user/authorizations', mock_user_auth).
        with(:body => hash_including(params)).
        to_return(new_authorization(params))
    end
    def stub_no_keys
      stub_api_request(:get, 'broker/rest/user/keys', mock_user_auth).to_return(empty_keys)
    end
    def stub_mock_ssh_keys(name='test')
      stub_api_request(:get, 'broker/rest/user/keys', mock_user_auth).
        to_return({
          :body => {
            :type => 'keys',
            :data => [
              {
                :name => name,
                :type => pub_key.split[0],
                :content => pub_key.split[1],
  #              :links => mock_response_links([
  #                ['UPDATE', "broker/rest/user/keys/#{name}", 'put']
  #              ]),
              }
            ],
          }.to_json
        })
    end
    def stub_one_key(name)
      stub_api_request(:get, 'broker/rest/user/keys', mock_user_auth).
        to_return({
          :body => {
            :type => 'keys',
            :data => [
              {
                :name => name,
                :type => 'ssh-rsa',
                :content => rsa_key_content_public,
                :links => mock_response_links([
                  ['UPDATE', "broker/rest/user/keys/#{name}", 'put']
                ]),
              }
            ],
          }.to_json
        })
    end
    def stub_no_domains
      stub_api_request(:get, 'broker/rest/domains', mock_user_auth).to_return(empty_domains)
    end
    def stub_one_domain(name)
      stub_api_request(:get, 'broker/rest/domains', mock_user_auth).
        to_return({
          :body => {
            :type => 'domains',
            :data => [{:id => name, :links => mock_response_links([
              ['LIST_APPLICATIONS', "broker/rest/domains/#{name}/applications", 'get'],
              ['ADD_APPLICATION', "broker/rest/domains/#{name}/applications", 'post'],
            ])}],
          }.to_json
        })
    end
    def stub_one_application(domain_name, name, *args)
      stub_api_request(:get, "broker/rest/domains/#{domain_name}/applications", mock_user_auth).
        to_return({
          :body => {
            :type => 'applications',
            :data => [{
              :domain_id => domain_name,
              :id => 1,
              :name => name,
              :app_url => "http://#{name}-#{domain_name}.rhcloud.com",
              :links => mock_response_links([
              ]),
            }],
          }.to_json
        })
      stub_relative_application(domain_name,name, *args)
    end

    def stub_relative_application(domain_name, app_name, body = {}, status = 200)
      url = client_links['LIST_DOMAINS']['relative'] rescue "broker/rest/domains"
      stub_api_request(:any, "#{url}/#{domain_name}/applications/#{app_name}").
        to_return({
          :body   => {
            :type => 'application',
            :data => {
              :domain_id         => domain_name,
              :name              => app_name,
              :id                => 1,
              :links             => mock_response_links(mock_app_links(domain_name,app_name)),
            }
          }.merge(body).to_json,
          :status => status
        })
    end

    def stub_simple_carts
      stub_api_request(:get, 'broker/rest/cartridges', mock_user_auth).to_return(simple_carts)
    end

    def define_exceptional_test_on_wizard
      RHC::Wizard.module_eval <<-EOM
      private
      def test_and_raise
        raise
      end
      EOM
    end

    def empty_keys
      empty_response_list('keys')
    end
    def empty_domains
      empty_response_list('domains')
    end

    def empty_response_list(type)
      {
        :body => {
          :type => type,
          :data => [],
        }.to_json
      }
    end

    def new_domain(name)
      {
        :status => 201,
        :body => {
          :type => 'domain',
          :data => {
            :id => name,
            :links => mock_response_links([
            ])
          },
        }.to_json
      }
    end
    def simple_carts
      {
        :body => {
          :type => 'cartridges',
          :data => [
            {:name => 'mock_standalone_cart-1', :type => 'standalone', :tags => ['cartridge'], :display_name => 'Mock1 Cart'},
            {:name => 'mock_standalone_cart-2', :type => 'standalone', :description => 'Mock2 description'},
            {:name => 'mock_embedded_cart-1', :type => 'embedded', :tags => ['scheduled'], :display_name => 'Mock1 Embedded Cart'},
            {:name => 'premium_cart-1', :type => 'standalone', :tags => ['premium'], :display_name => 'Premium Cart', :usage_rate_usd => '0.02'},
          ],
        }.to_json
      }
    end
    def simple_user(login)
      {
        :body => {
          :type => 'user',
          :data => {
            :login => login,
            :plan_id =>        respond_to?(:user_plan_id) ? self.user_plan_id : nil,
            :consumed_gears => respond_to?(:user_consumed_gears) ? self.user_consumed_gears : 0,
            :max_gears =>      respond_to?(:user_max_gears) ? self.user_max_gears : 3,
            :capabilities =>   respond_to?(:user_capabilities) ? self.user_capabilities : {:gear_sizes => ['small', 'medium']},
            :links => mock_response_links([
              ['ADD_KEY', "broker/rest/user/keys",   'POST'],
              ['LIST_KEYS', "broker/rest/user/keys", 'GET'],
            ])
          },
        }.to_json
      }
    end
    def new_authorization(params)
      {
        :status => 201,
        :body => {
          :type => 'authorization',
          :data => {
            :note => params[:note],
            :token => 'a_token_value',
            :scopes => (params[:scope] || "userinfo").gsub(/,/, ' '),
            :expires_in => (params[:expires_in] || 60).to_i,
            :expires_in_seconds => (params[:expires_in] || 60).to_i,
            :created_at => mock_date_1,
          },
        }.to_json
      }
    end

    def mock_pass
      "test pass"
    end

    def mock_uri
      "test.domain.com"
    end

    # Creates consistent hrefs for testing
    def mock_href(relative="", with_auth=false)
      server = respond_to?(:server) ? self.server : mock_uri
      uri_string = server
      "https://#{uri_string}/#{relative}"
    end

    # This formats link lists for JSONification
    def mock_response_links(links)
      link_set = {}
      links.each do |link|
        operation = link[0]
        href      = link[1]
        method    = link[2]
        # Note that the 'relative' key/value pair below is a convenience for testing;
        # this is not used by the API classes.
        link_set[operation] = { 'href' => mock_href(href), 'method' => method, 'relative' => href }
      end
      link_set
    end

    def mock_app_links(domain_id='test_domain',app_id='test_app')
      [['ADD_CARTRIDGE',   "domains/#{domain_id}/apps/#{app_id}/carts/add", 'post'],
       ['LIST_CARTRIDGES', "domains/#{domain_id}/apps/#{app_id}/carts/",    'get' ],
       ['GET_GEAR_GROUPS', "domains/#{domain_id}/apps/#{app_id}/gear_groups", 'get' ],
       ['START',           "domains/#{domain_id}/apps/#{app_id}/start",     'post'],
       ['STOP',            "domains/#{domain_id}/apps/#{app_id}/stop",      'post'],
       ['RESTART',         "domains/#{domain_id}/apps/#{app_id}/restart",   'post'],
       ['THREAD_DUMP',     "domains/#{domain_id}/apps/#{app_id}/event",     'post'],
       ['ADD_ALIAS',       "domains/#{domain_id}/apps/#{app_id}/event",     'post'],
       ['REMOVE_ALIAS',    "domains/#{domain_id}/apps/#{app_id}/event",     'post'],
       ['LIST_ALIASES',    "domains/#{domain_id}/apps/#{app_id}/aliases",   'get'],
       ['DELETE',          "domains/#{domain_id}/apps/#{app_id}/delete",    'post']]
    end

    def mock_cart_links(domain_id='test_domain',app_id='test_app',cart_id='test_cart')
      [['START',   "domains/#{domain_id}/apps/#{app_id}/carts/#{cart_id}/start",   'post'],
       ['STOP',    "domains/#{domain_id}/apps/#{app_id}/carts/#{cart_id}/stop",    'post'],
       ['RESTART', "domains/#{domain_id}/apps/#{app_id}/carts/#{cart_id}/restart", 'post'],
       ['DELETE',  "domains/#{domain_id}/apps/#{app_id}/carts/#{cart_id}/delete",  'post']]
    end

    def mock_client_links
      [['GET_USER',        'user/',       'get' ],
       ['ADD_DOMAIN',      'domains/add', 'post'],
       ['LIST_DOMAINS',    'domains/',    'get' ],
       ['LIST_CARTRIDGES', 'cartridges/', 'get' ]]
    end
    def mock_real_client_links
      [['GET_USER',        "broker/rest/user",       'GET'],
       ['LIST_DOMAINS',    "broker/rest/domains",    'GET'],
       ['ADD_DOMAIN',      "broker/rest/domains",    'POST'],
       ['LIST_CARTRIDGES', "broker/rest/cartridges", 'GET'],
      ]
    end
    def mock_api_with_authorizations
      mock_real_client_links.concat([
        ['LIST_AUTHORIZATIONS', "broker/rest/user/authorizations", 'GET'],
        ['ADD_AUTHORIZATION',   "broker/rest/user/authorizations", 'POST'],
        ['SHOW_AUTHORIZATION',  "broker/rest/user/authorizations/:id", 'GET'],
      ])
    end

    def mock_domain_links(domain_id='test_domain')
      [['ADD_APPLICATION',   "domains/#{domain_id}/apps/add", 'post'],
       ['LIST_APPLICATIONS', "domains/#{domain_id}/apps/",    'get' ],
       ['UPDATE',            "domains/#{domain_id}/update",   'post'],
       ['DELETE',            "domains/#{domain_id}/delete",   'post']]
    end

    def mock_key_links(key_id='test_key')
      [['UPDATE', "user/keys/#{key_id}/update", 'post'],
       ['DELETE', "user/keys/#{key_id}/delete", 'post']]
    end

    def mock_user_links
      [['ADD_KEY',   'user/keys/add', 'post'],
       ['LIST_KEYS', 'user/keys/',    'get' ]]
    end

    def mock_alias_links(domain_id='test_domain',app_id='test_app',alias_id='test.foo.com')
      [['DELETE',   "domains/#{domain_id}/apps/#{app_id}/aliases/#{alias_id}/delete", 'post'],
       ['GET',      "domains/#{domain_id}/apps/#{app_id}/aliases/#{alias_id}",        'get' ],
       ['UPDATE',   "domains/#{domain_id}/apps/#{app_id}/aliases/#{alias_id}/update", 'post' ]]
    end

    def mock_cartridge_response(cart_count=1)
      carts = []
      while carts.length < cart_count
        carts << {
          :name  => "mock_cart_#{carts.length}",
          :type  => "mock_cart_#{carts.length}_type",
          :links => mock_response_links(mock_cart_links('mock_domain','mock_app',"mock_cart_#{carts.length}"))
        }
      end

      carts = carts[0] if cart_count == 1
      type  = cart_count == 1 ? 'cartridge' : 'cartridges'

      return {
        :body   => {
          :type => type,
          :data => carts
        }.to_json,
        :status => 200
      }
    end

    def mock_alias_response(count=1)
      aliases = count.times.inject([]) do |arr, i|
         arr << {:id  => "www.alias#{i}.com"}
      end

      return {
        :body   => {
          :type => count == 1 ? 'alias' : 'aliases',
          :data => aliases
        }.to_json,
        :status => 200
      }
    end

    def mock_gear_groups_response()
      groups = [{}]
      type  = 'gear_groups'

      return {
        :body   => {
          :type => type,
          :data => groups
        }.to_json,
        :status => 200
      }
    end
  end

  class MockRestClient < RHC::Rest::Client
    include Helpers

    def initialize(config=RHC::Config, version=1.0)
      obj = self
      if RHC::Rest::Client.respond_to?(:stub)
        RHC::Rest::Client.stub(:new) { obj }
      else
        RHC::Rest::Client.instance_eval do
          @obj = obj
          def new(*args)
            @obj
          end
        end
      end
      @domains = []
      @user = MockRestUser.new(client, config.username)
      @api = MockRestApi.new(client, config)
      @version = version
    end

    def api
      @api
    end

    def user
      @user
    end

    def domains
      @domains
    end

    def api_version_negotiated
      @version
    end

    def cartridges
      premium_embedded = MockRestCartridge.new(self, "premium_cart", "embedded")
      premium_embedded.usage_rate = 0.05

      [MockRestCartridge.new(self, "mock_cart-1", "embedded"), # code should sort this to be after standalone
       MockRestCartridge.new(self, "mock_standalone_cart-1", "standalone"),
       MockRestCartridge.new(self, "mock_standalone_cart-2", "standalone"),
       MockRestCartridge.new(self, "mock_unique_standalone_cart-1", "standalone"),
       MockRestCartridge.new(self, "jenkins-1.4", "standalone"),
       MockRestCartridge.new(self, "mock_cart-2", "embedded"),
       MockRestCartridge.new(self, "unique_mock_cart-1", "embedded"),
       MockRestCartridge.new(self, "jenkins-client-1.4", "embedded"),
       premium_embedded
      ]
    end

    def add_domain(id)
      d = MockRestDomain.new(self, id)
      @domains << d
      d
    end

    def sshkeys
      @user.keys
    end

    def add_key(name, type, content)
      @user.add_key(name, type, content)
    end

    def delete_key(name)
      @user.keys.delete_if { |key| key.name == name }
    end

    # Need to mock this since we are not registering HTTP requests when adding apps to the mock domain
    def find_application(domain, name, options = {})
      find_domain(domain).applications.each do |app|
        return app if app.name.downcase == name.downcase
      end

      raise RHC::Rest::ApplicationNotFoundException.new("Application #{name} does not exist")
    end

    def find_application_gear_groups(domain, name, options = {})
      find_domain(domain).applications.each do |app|
        return app.gear_groups if app.name.downcase == name.downcase
      end

      raise RHC::Rest::ApplicationNotFoundException.new("Application #{name} does not exist")
    end
  end

  class MockRestApi < RHC::Rest::Api
    include Helpers

    def initialize(client, config)
      @client = client
      @client_api_versions = RHC::Rest::Client::CLIENT_API_VERSIONS
      @server_api_versions = @client_api_versions
      self.attributes = {:links => mock_response_links(mock_client_links)}
    end
  end

  class MockRestUser < RHC::Rest::User
    include Helpers
    def initialize(client, login)
      super({}, client)
      @login = login
      @keys = [
        MockRestKey.new(client, 'mockkey1', 'ssh-rsa', 'AAAAB3NzaC1yc2EAAAADAQABAAABAQDNK8xT3O+kSltmCMsSqBfAgheB3YFJ9Y0ESJnFjFASVxH70AcCQAgdQSD/r31+atYShJdP7f0AMWiQUTw2tK434XSylnZWEyIR0V+j+cyOPdVQlns6D5gPOnOtweFF0o18YulwCOK8Q1H28GK8qyWhLe0FcMmxtKbbQgaVRvQdXZz4ThzutCJOyJm9xVb93+fatvwZW76oLLvfFJcJSOK2sgW7tJM2A83bm4mwixFDF7wO/+C9WA+PgPKJUIjvy1gZjBhRB+3b58vLOnYhPOgMNruJwzB+wJ3pg8tLJEjxSbHyyoi6OqMBs4BVV7LdzvwTDxEjcgtHVvaVNXgO5iRX'),
        MockRestKey.new(client, 'mockkey2', 'ssh-dsa', 'AAAAB3NzaC1kc3MAAACBAPaaFj6Xjrjd8Dc4AAkJe0HigqaXMxj/87xHoV+nPgerHIceJWhPUWdW40lSASrgpAV9Eq4zzD+L19kgYdbMw0vSX5Cj3XtNOsow9MmMxFsYjTxCv4eSs/rLdGPaYZ5GVRPDu8tN42Bm8lj5o+ky3HzwW+mkQMZwcADQIgqtn6QhAAAAFQCirDfIMf/JoMOFf8CTnsTKWw/0zwAAAIAIQp6t2sLIp1d2TBfd/qLjOJA10rPADcnhBzWB/cd/oFJ8a/2nmxeSPR5Ov18T6itWqbKwvZw2UC0MrXoYbgcfVNP/ym1bCd9rB5hu1sg8WO4JIxA/47PZooT6PwTKVxHuENEzQyJL2o6ZJq+wuV0taLvm6IaM5TAZuEJ2p4TC/gAAAIBpLcVXZREa7XLY55nyidt/+UC+PxpjhPHOHbzL1OvWEaumN4wcJk/JZPppgXX9+WDkTm1SD891U0cXnGMTP0OZOHkOUHF2ZcfUe7p9kX4WjHs0OccoxV0Lny6MC4DjalJyaaEbijJHSUX3QlLcBOlPHJWpEpvWQ9P8AN4PokiGzA==')
      ]
    end

    def keys
      @keys
    end

    def add_key(name, type, content)
      @keys << MockRestKey.new(client, name, type, content)
    end
  end

  class MockRestDomain < RHC::Rest::Domain
    include Helpers
    def initialize(client, id)
      super({}, client)
      @id = id
      @applications = []
      self.attributes = {:links => mock_response_links(mock_domain_links('mock_domain_0'))}
    end

    def update(id)
      @id = id
      self
    end

    def destroy
      raise RHC::Rest::ClientErrorException.new("Applications must be empty.") unless @applications.empty?
      client.domains.delete_if { |d| d.id == @id }

      @applications = nil
    end

    def add_application(name, type=nil, scale=nil, gear_profile='default', git_url=nil)
      if type.is_a?(Hash)
        scale = type[:scale]
        gear_profile = type[:gear_profile]
        git_url = type[:initial_git_url]
        type = Array(type[:cartridges] || type[:cartridge])
      end
      a = MockRestApplication.new(client, name, type, self, scale, gear_profile, git_url)
      builder = @applications.find{ |app| app.cartridges.map(&:name).any?{ |s| s =~ /^jenkins-[\d\.]+$/ } }
      a.building_app = builder.name if builder
      @applications << a
      a.add_message("Success")
      a
    end

    def applications(*args)
      @applications
    end
  end

  class MockRestGearGroup < RHC::Rest::GearGroup
    include Helpers
    def initialize(client=nil)
      super({}, client)
      @cartridges = [{'name' => 'fake_geargroup_cart-0.1'}]
      @gears = [{'state' => 'started', 'id' => 'fakegearid', 'ssh_url' => 'ssh://fakegearid@fakesshurl.com'}]
      @gear_profile = 'small'
    end
  end

  class MockRestAlias < RHC::Rest::Alias
    include Helpers

    def initialize(client, id, has_private_ssl_certificate=false, certificate_added_at=nil)
      super({}, client)
      @id = id
      @has_private_ssl_certificate = has_private_ssl_certificate
      @certificate_added_at = certificate_added_at
    end

    def add_certificate(ssl_certificate_content, private_key_content, pass_phrase)
      if (client.api_version_negotiated >= 1.4)
        @has_private_ssl_certificate = true
        @certificate_added_at = Time.now
      else
        raise RHC::Rest::SslCertificatesNotSupported, "The server does not support SSL certificates for custom aliases."
      end
    end

    def delete_certificate
      if (client.api_version_negotiated >= 1.4)
        @has_private_ssl_certificate = false
        @certificate_added_at = nil
      else
        raise RHC::Rest::SslCertificatesNotSupported, "The server does not support SSL certificates for custom aliases."
      end
    end

    def destroy
      puts @application.inspect
      puts self.inspect
      @application.aliases.delete self
    end
  end

  class MockRestApplication < RHC::Rest::Application
    include Helpers
    def fakeuuid
      "fakeuuidfortests#{@name}"
    end

    def initialize(client, name, type, domain, scale=nil, gear_profile='default', initial_git_url=nil)
      super({}, client)
      @name = name
      @domain = domain
      @cartridges = []
      @creation_time = Date.new(2000, 1, 1).strftime('%Y-%m-%dT%H:%M:%S%z')
      @uuid = fakeuuid
      @initial_git_url = initial_git_url
      @git_url = "git:fake.foo/git/#{@name}.git"
      @app_url = "https://#{@name}-#{@domain.id}.fake.foo/"
      @ssh_url = "ssh://#{@uuid}@127.0.0.1"
      @aliases = []
      @gear_profile = gear_profile
      if scale
        @scalable = true
      end
      self.attributes = {:links => mock_response_links(mock_app_links('mock_domain_0', 'mock_app_0')), :messages => []}
      self.gear_count = 5
      types = Array(type)
      cart = add_cartridge(types.first, false) if types.first
      if scale
        cart.supported_scales_to = (cart.scales_to = -1)
        cart.supported_scales_from = (cart.scales_from = 2)
        cart.current_scale = 2
        cart.scales_with = "haproxy-1.4"
        prox = add_cartridge('haproxy-1.4')
        prox.collocated_with = [types.first]
      end
      types.drop(1).each{ |c| add_cartridge(c, false) }
      @framework = types.first
    end

    def destroy
      @domain.applications.delete self
    end

    def add_cartridge(name, embedded=true)
      type = embedded ? "embedded" : "standalone"
      c = MockRestCartridge.new(client, name, type, self)
      c.properties << {'name' => 'prop1', 'value' => 'value1', 'description' => 'description1' }
      @cartridges << c
      c.messages << "Cartridge added with properties"
      c
    end

    def gear_groups
      # we don't have heavy interaction with gear groups yet so keep this simple
      @gear_groups ||= [MockRestGearGroup.new(client)]
    end

    def cartridges
      @cartridges
    end

    def start
      @app
    end

    def stop(*args)
      @app
    end

    def restart
      @app
    end

    def reload
      @app
    end

    def tidy
      @app
    end

    def add_alias(app_alias)
      @aliases << MockRestAlias.new(@client, app_alias)
    end

    def remove_alias(app_alias)
      @aliases.delete_if {|x| x.id == app_alias}
    end

    def aliases
      @aliases
    end
  end

  class MockRestCartridge < RHC::Rest::Cartridge
    include Helpers

    attr_accessor :usage_rate

    def initialize(client, name, type, app=nil, properties=[{'type' => 'cart_data', 'name' => 'connection_url', 'value' => "http://fake.url" }])
      super({}, client)
      @name = name
      @type = type
      @app = app
      @properties = properties.each(&:stringify_keys!)
      @status_messages = [{"message" => "started", "gear_id" => "123"}]
      @scales_from = 1
      @scales_to = 1
      @current_scale = 1
      @gear_profile = 'small'
      @additional_gear_storage = 5
      @usage_rate = 0.0
    end

    def destroy
      @app.cartridges.delete self
    end

    def status
      @status_messages
    end

    def start
      @status_messages = [{"message" => "started", "gear_id" => "123"}]
      @app
    end

    def stop
      @status_messages = [{"message" => "stopped", "gear_id" => "123"}]
      @app
    end

    def restart
      @status_messages = [{"message" => "started", "gear_id" => "123"}]
      @app
    end

    def reload
      @app
    end

    def set_scales(values)
      values.delete_if{|k,v| v.nil? }
      @scales_from = values[:scales_from] if values[:scales_from]
      @scales_to = values[:scales_to] if values[:scales_to]
      self
    end

    def set_storage(values)
      @additional_gear_storage = values[:additional_gear_storage] if values[:additional_gear_storage]
      self
    end
  end

  class MockRestKey < RHC::Rest::Key
    include Helpers
    def initialize(client, name, type, content)
      super({}, client)
      @name    = name
      @type    = type
      @content = content
    end
  end
end

