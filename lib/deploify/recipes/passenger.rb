# Copyright 2006-2008 by Mike Bailey. All rights reserved.
# Copyright 2012 by Richard Riman. All rights reserved.

Capistrano::Configuration.instance(:must_exist).load do

  set :passenger_mode, :standalone
  set :passenger_max_pool_size, 2   # in standalone mode means max. instances, but as nginx/apache module
                                    # this means size of the entire application pool
  set :passenger_min_instances, 1   # specifies minimum instances for application

  set :passenger_port, nil          # standalone mode only: application port,
                                    # if not specified, passenger is started as unix socket

  set :passenger_spawn_method, "smart-lv2" # smart-lv2 | smart | conservative

  # TODO: passenger as a nginx/apache module
  # TODO: passenger installation on server

  namespace :deploify do

    namespace :passenger do

      SYSTEM_CONFIG_FILES[:passenger] = [
        { :template => "passengerctl-lib.erb",
          :path => "/usr/local/lib/passengerctl",
          :mode => 0644,
          :owner => "root:root" }
        ]

      PROJECT_CONFIG_FILES[:passenger] = [
        { :template => "passengerctl.erb",
          :path => "passengerctl",
          :mode => 0754,
          :owner => "root:root" },

        { :template => "logrotate.conf.erb",
          :path => "logrotate.conf",
          :mode => 0644,
          :owner => "root:root" }
        ]

      desc "Install Passenger"
      task :install, :roles => :app do
        # TODO: install passenger things, there's only configuration part yet
        config_gen_system
        config_system
      end

      desc "Generate Passenger configs (system & project level)."
      task :config_gen do
        # config_gen_system
        config_gen_project
      end

      desc "Generate Passenger configs (system level) from template."
      task :config_gen_system do
        SYSTEM_CONFIG_FILES[:passenger].each do |file|
          _deploify.render_template(:passenger, file)
        end
      end

      desc "Generate Passenger configs (project level) from template."
      task :config_gen_project do
        PROJECT_CONFIG_FILES[:passenger].each do |file|
          _deploify.render_template(:passenger, file)
        end
      end

      desc "Push Passenger config files (system & project level) to server"
      task :config, :roles => :app do
        # config_system
        config_project
      end

      desc "Push Passenger configs (system level) to server"
      task :config_system, :roles => :app do
        # TODO: passenger as nginx/apache module
        _deploify.push_configs(:passenger, SYSTEM_CONFIG_FILES[:passenger])
      end

      desc "Push Passenger configs (project level) to server"
      task :config_project, :roles => :app do
        _deploify.push_configs(:passenger, PROJECT_CONFIG_FILES[:passenger])
        # TODO: passenger as nginx/apache module
        symlink_logrotate_config
      end

      task :activate, :roles => :app do
        # activate_system
        activate_project
      end

      task :activate_project, :roles => :app do
        # TODO: passenger as nginx/apache module
        case passenger_mode
        when :standalone
          symlink_and_activate_passengerctl
          top.deploify.app.restart
        end
        top.deploify.web.reload
      end

      task :symlink_and_activate_passengerctl, :roles => :app do
        run "#{try_sudo} ln -sf #{deploy_to}/passenger/passengerctl /etc/init.d/passenger-#{application}"
        run "#{try_sudo} update-rc.d passenger-#{application} defaults"
      end

      task :symlink_logrotate_config, :roles => :app do
        run "#{try_sudo} ln -sf #{deploy_to}/passenger/logrotate.conf /etc/logrotate.d/passenger-#{application}"
      end

      # Passenger runs Rails as the owner of this file.
      task :set_owner_of_environment_rb, :roles => :app do
        unless passenger_mode.eql?(:standalone)
          run "#{sudo} chown #{app_user} #{current_path}/config/environment.rb"
        end
      end

      desc "Restart Application"
      task :restart, :roles => :app do
        run "test -d #{current_path} && #{sudo} service passenger-#{application} restart; exit 0"
      end

    end # namespace :passenger

  end # namespace :deploify

end
