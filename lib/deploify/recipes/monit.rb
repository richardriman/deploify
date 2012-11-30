# Copyright 2012 by Richard Riman. All rights reserved.

Capistrano::Configuration.instance(:must_exist).load do

  # we use monit primary to control passenger processes so the tasks
  # are restricted to :app. You may use it for other processes.
  # In this case, specify HOSTS=hostname on the command line or use:
  #   for_roles(:role_name) { top.deploify.monit.task_name }
  # in your recipes.

  set :monit_timeout_interval, 120
  set :monit_conf_dir, "/etc/monit/conf.d"
  # TODO
  # set :monit_alert_recipients, %w(monitoring@example.com)
  # set :monit_timeout_recipients, %w(monitoring@example.com)

  namespace :deploify do

    namespace :monit do

      PROJECT_CONFIG_FILES[:monit] = [
        { :template => "monit.conf.erb",
          :path => "monit.conf",
          :mode => 0644,
          :owner => "root:root" }
        ]

      desc <<-DESC
        Generate monit application config from template. Note that this does not
        push the config to the server, it merely generates required
        configuration files. These should be kept under source control.
      DESC
      task :config_gen_project do
        PROJECT_CONFIG_FILES[:monit].each do |file|
          _deploify.render_template(:monit, file)
        end
      end

      desc "Push application monit config files to server"
      task :config_project, :roles => :app do
        _deploify.push_configs(:monit, PROJECT_CONFIG_FILES[:monit])
      end

      desc "Start Monit"
      task :start, :roles => :app do
        send(run_method, "service monit start")
      end

      task :activate do
        top.deploify.monit.activate_project
      end

      desc "Activate application monit config and reload monit"
      task :activate_project, :roles => :app do
        run "#{sudo} ln -sf #{deploy_to}/monit/monit.conf #{monit_conf_dir}/#{application}"
        top.deploify.monit.reload
      end

      desc "Dectivate application monit config and reload monit"
      task :deactivate_project, :roles => :app do
        run "#{sudo} rm -f #{monit_conf_dir}/#{application}; exit 0"
        top.deploify.monit.reload
      end

      desc "Stop Monit"
      task :stop, :roles => :app  do
        send(run_method, "service monit stop")
      end

      desc "Restart Monit"
      task :restart, :roles => :app  do
        send(run_method, "service monit restart")
      end

      desc "Reload Monit"
      task :reload, :roles => :app  do
        send(run_method, "service monit restart")
      end

    end # namespace :monit

  end # namespace :deploify

end
