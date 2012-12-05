# Copyright 2012 by Richard Riman. All rights reserved.

Capistrano::Configuration.instance(:must_exist).load do

  set :thin_applications_dir, "/var/www"
  set :thin_servers,          2
  set :thin_port,             nil # port is optional, if not specified, thin is started as unix socket

  namespace :deploify do

    namespace :thin do

      SYSTEM_CONFIG_FILES[:thin] = [
        { :template => "thinctl-lib.erb",
          :path => "/usr/local/lib/thinctl",
          :mode => 0644,
          :owner => "root:root" }
        ]

      PROJECT_CONFIG_FILES[:thin] = [
        { :template => "thinctl.erb",
          :path => "thinctl",
          :mode => 0754,
          :owner => "root:root" },

        { :template => "logrotate.conf.erb",
          :path => "logrotate.conf",
          :mode => 0644,
          :owner => "root:root" }
        ]

      desc "Install Thin"
      task :install, :roles => :app do
        run "rvm gemset use global && gem install thin --no-ri --no-rdoc"
        config_gen_system
        config_system
      end

      desc "Generate Thin configs (system & project level)."
      task :config_gen do
        # config_gen_system
        config_gen_project
      end

      desc "Generate Thin configs (system level) from template."
      task :config_gen_system do
        SYSTEM_CONFIG_FILES[:thin].each do |file|
          rfdeploy.render_template(:thin, file)
        end
      end

      desc "Generate Thin configs (project level) from template."
      task :config_gen_project do
        PROJECT_CONFIG_FILES[:thin].each do |file|
          rfdeploy.render_template(:thin, file)
        end
      end

      desc "Push Thin config files (system & project level) to server"
      task :config, :roles => :app do
        # config_system
        config_project
      end

      desc "Push Thin configs (system level) to server"
      task :config_system, :roles => :app do
        rfdeploy.push_configs(:thin, SYSTEM_CONFIG_FILES[:thin])
      end

      desc "Push Thin configs (project level) to server"
      task :config_project, :roles => :app do
        rfdeploy.push_configs(:thin, PROJECT_CONFIG_FILES[:thin])
        symlink_logrotate_config
      end

      task :activate, :roles => :app do
        activate_project
      end

      task :activate_project, :roles => :app do
        symlink_and_activate_thinctl
        top.rf_deploy.app.restart
        top.rf_deploy.web.reload
      end

      task :symlink_and_activate_thinctl, :roles => :app do
        run "#{try_sudo} ln -sf #{deploy_to}/thin/thinctl /etc/init.d/thin-#{application}"
        run "#{try_sudo} update-rc.d thin-#{application} defaults"
      end

      task :symlink_logrotate_config, :roles => :app do
        run "#{try_sudo} ln -sf #{deploy_to}/thin/logrotate.conf /etc/logrotate.d/thin-#{application}"
      end

      desc "Restart Application"
      task :restart, :roles => :app do
        run "test -d #{current_path} && #{sudo} service thin-#{application} restart; exit 0"
      end

    end # namespace :thin

  end # namespace :deploify

end
