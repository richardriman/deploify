# Copyright 2006-2008 by Mike Bailey. All rights reserved.
# Copyright 2012 by Richard Riman. All rights reserved.

Capistrano::Configuration.instance(:must_exist).load do

  set :nginx_vhost_dir,             "/etc/nginx/sites-available"
  set :nginx_enabled_vhost_dir,     "/etc/nginx/sites-enabled"
  set :nginx_client_max_body_size,  "100M"
  set :nginx_vhost_type,            :http_only
  set :nginx_vhost_listen_ip,       nil
  set :nginx_upstream_servers,      []
  # secured sites stuff
  set :nginx_secured_site,          false
  set :nginx_secure_user,           "developer"
  set(:nginx_secure_password) { Capistrano::CLI.password_prompt "Enter password for securing this site:" }

  set :ssl_certs_source_dir,        "config/ssl"

  namespace :deploify do

    namespace :nginx do

      CHOICES_VHOST_TYPES = [:http_only, :http_with_ssl, :http_force_ssl]

      PROJECT_CONFIG_FILES[:nginx] = [
        { :template => "logrotate.conf.erb",
          :path => "logrotate.conf",
          :mode => 0640,
          :owner => "root:root" }
        ]

      def project_config_files
        PROJECT_CONFIG_FILES[:nginx] + [{
          :template => "vhost_#{nginx_vhost_type}.conf.erb",
          :path => "vhost.conf",
          :mode => 0640,
          :owner => "root:root"
        }]
      end

      desc <<-DESC
        Generate nginx config from one of the templates depending on situation.
        Note that this does not push the config to the server, it merely generates
        required configuration files. These should be kept under source control.
        The can be pushed to the server with the :config task.
      DESC
      task :config_gen_project do
        set :nginx_upstream_name, Digest::SHA1.hexdigest(application)
        if nginx_upstream_servers.empty?
          if app_server_type.eql?(:passenger)
            set :nginx_upstream_servers, %W(unix:#{shared_path}/pids/#{app_server_type}.sock)
          elsif app_server_type.eql?(:thin)
            upstreams = []
            set :nginx_upstream_servers,
                (0..fetch(:thin_servers) - 1).collect { |idx| "unix:#{shared_path}/pids/#{app_server_type}.#{idx}.sock" }
          end
        end
        project_config_files.each do |file|
          _deploify.render_template(:nginx, file)
        end
      end

      desc "Push nginx config files to server, enable (symlink) vhost and logrotate"
      task :config_project, :roles => :web do
        _deploify.push_configs(:nginx, project_config_files)
        if [:http_with_ssl, :http_force_ssl].include?(nginx_vhost_type)
          set(:nginx_vhost_listen_ip) do
            require "resolv"
            server_ip = Resolv.getaddress(find_servers(:roles => :web).first.host)
            Capistrano::CLI.ui.ask "Enter IP for Nginx zone (needed for scenarios with SSL support) [#{server_ip}]" do |q|
              q.default = server_ip
            end
          end
          # SSL is demanded, push certificates
          target_path = "#{deploy_to}/nginx/#{rails_env}"
          std.su_put(File.read("#{ssl_certs_source_dir}/#{rails_env}.crt"), "#{target_path}.crt", "/tmp", :mode => 0600)
          std.su_put(File.read("#{ssl_certs_source_dir}/#{rails_env}.key"), "#{target_path}.key", "/tmp", :mode => 0600)
        end
        top.deploify.nginx.generate_htaccess_file if nginx_secured_site
      end

      desc "Generate .htaccess file for site securing"
      task :generate_htaccess_file, :roles => :web do
        pwd = `openssl passwd -apr1 #{nginx_secure_password}`
        std.su_put("#{nginx_secure_user}:#{pwd}", "#{deploy_to}/nginx/.htaccess", "/tmp", :mode => 0644)
      end

      desc "Activate nginx application vhost and logrotate"
      task :activate, :roles => :web do
        # logrotate
        run "#{try_sudo} ln -sf #{deploy_to}/nginx/logrotate.conf /etc/logrotate.d/nginx-#{application}"
        # nginx
        run "#{try_sudo} ln -sf #{deploy_to}/nginx/vhost.conf #{nginx_vhost_dir}/#{application}"
        run "#{try_sudo} ln -sf #{nginx_vhost_dir}/#{application} #{nginx_enabled_vhost_dir}/#{application}"
      end

      desc "Start Nginx"
      task :start, :roles => :web do
        # Nginx returns error code if you try to start it when it's already running.
        # We don't want this to kill Capistrano.
        send(run_method, "service nginx start; exit 0")
      end

      desc "Stop Nginx"
      task :stop, :roles => :web do
        # Nginx returns error code if you try to stop when it's not running.
        # We don't want this to kill Capistrano.
        send(run_method, "service nginx stop; exit 0")
      end

      desc "Restart Nginx"
      task :restart, :roles => :web do
        # Nginx returns error code if you try to reload when it's not running.
        # We don't want this to kill Capistrano.
        send(run_method, "service nginx restart; exit 0")
      end

      desc "Reload Nginx"
      task :reload, :roles => :web do
        # Nginx returns error code if you try to reload when it's not running.
        # We don't want this to kill Capistrano.
        send(run_method, "service nginx reload; exit 0")
      end

    end # namespace :nginx

  end # namespace :deploify

end
