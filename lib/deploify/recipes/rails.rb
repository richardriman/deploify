# Copyright 2006-2008 by Mike Bailey. All rights reserved.
# Copyright 2012 by Richard Riman. All rights reserved.

Capistrano::Configuration.instance(:must_exist).load do

  set(:deploy_to) { "/var/www/" + application }

  set :app_user_prefix, "app_"
  set(:app_user) { app_user_prefix + application }
  set :app_group_prefix, "app_"
  set(:app_group) { app_group_prefix + application }
  set(:app_user_homedir) { deploy_to }
  set :database_yml_in_scm, false
  set :app_symlinks, nil
  set :rails_env, "production"
  set :shared_dirs, []  # Array of directories that should be created under shared/
                        # and linked to in the project

  # hook into the default capistrano deploy tasks
  before "deploy:setup", :except => { :no_release => true } do
    top.deploify.rails.setup_perms
    top.deploify.rails.setup_paths
    top.deploify.rails.setup_shared_dirs
  end

  after "deploy:setup", :except => { :no_release => true } do
    top.deploify.rails.create_config_dir
    top.deploify.rails.config_gen
    top.deploify.rails.config
    top.deploify.rails.set_perms_and_make_writable_by_app

    top.deploify.rails.activate_services
    top.deploify.web.reload
    top.deploify.rails.setup_database
  end

  after "deploy:update_code", :roles => :app do
    top.deploify.rails.symlink_database_yml unless database_yml_in_scm
  end

  after "deploy:create_symlink", :roles => :app do
    top.deploify.rails.symlink_shared_dirs
    top.deploify.rails.set_perms_on_shared_and_release
    top.deploify.rails.set_perms_and_make_writable_by_app
    top.deploify.passenger.set_owner_of_environment_rb if app_server_type.to_s.eql?("passenger")
  end

  after :deploy, "deploy:cleanup"

  # If database.yml is not kept in scm and it is present in local
  # config dir then push it out to server.
  before "deploify:rails:symlink_database_yml", :roles => :app do
    top.deploify.rails.push_database_yml unless database_yml_in_scm
  end

  namespace :deploify do

    namespace :rails do

      desc "Create deployment group and add current user to it, create user and group for application to run as"
      task :setup_perms, :roles => [:app, :web] do
        _deploify.groupadd(group)
        _deploify.add_user_to_group(user, group)
        _deploify.groupadd(app_group)
        _deploify.add_user_to_group(user, app_group)
        # # we've just added ourself to a group - need to teardown connection
        # # so that next command uses new session where we belong in group
        _deploify.teardown_connections
        # create user and group for application to run as
        _deploify.useradd(app_user, :group => app_group, :homedir => false)
        # Set the primary group for the user the application runs as (in case
        # user already existed when previous command was run)
        sudo "usermod --gid #{app_group} --home #{app_user_homedir} #{app_user}"
      end

      # setup extra paths required for deployment
      task :setup_paths, :roles => [:app, :web] do
        _deploify.mkdir(deploy_to, :mode => 0775, :group => group, :via => :sudo)
        _deploify.mkdir(shared_path, :mode => 0775, :group => group, :via => :sudo)
        _deploify.mkdir("#{deploy_to}/releases", :mode => 0755, :group => group, :via => :sudo)
      end

      # create directories by the list of shared files and dirs
      # TODO: check, how this works with a files
      desc "Setup shared dirs"
      task :setup_shared_dirs, :roles => [:app, :web] do
        if shared_dirs.any?
          shared_dirs.each do |dir|
            _deploify.mkdir(File.join(shared_path, dir), :via => :sudo)
          end
        end
      end

      task :create_config_dir, :roles => :app do
        _deploify.mkdir(File.join(shared_path, "config"), :group => group, :mode => 0775, :via => :sudo)
      end

      desc "Generate config files for rails app."
      task :config_gen do
        top.deploify.web.config_gen_project
        top.deploify.app.config_gen_project
        top.deploify.monit.config_gen_project if use_monit
      end

      desc "Push out config files for rails app."
      task :config do
        top.deploify.web.config_project
        top.deploify.app.config_project
        top.deploify.monit.config_project if use_monit
      end

      desc "Activate web, app and monit (if used)"
      task :activate_services do
        top.deploify.web.activate
        top.deploify.app.activate
        top.deploify.monit.activate if use_monit
      end

      task :setup_database, :roles => :db do
        unless roles[:db].servers.empty? # Some apps don't use database!
          top.deploify.db.create_database
          top.deploify.db.grant_user_access_to_database
        end
      end

      desc "Symlink shared dirs"
      task :symlink_shared_dirs, :roles => :app do
        if shared_dirs
          shared_dirs.each do |dir|
            path = File.split(dir)[0]
            if path != '.'
              _deploify.mkdir(File.join(current_path, path))
            end
            run "#{sudo} test -d #{current_path}/#{dir} && mv #{current_path}/#{dir} #{current_path}/#{dir}.moved_by_deploify; exit 0"
            run "ln -nfs #{shared_path}/#{dir} #{current_path}/#{dir}"
          end
        end
      end

      task :set_perms_on_shared_and_release, :roles => :app do
        run "#{sudo} chgrp -R #{app_group} #{shared_path} #{release_path}"
        run "#{sudo} chown -Rf #{app_user}:#{app_group} #{release_path}/tmp/cache/assets; exit 0"
        run "#{sudo} chmod -R g+w #{shared_path} #{release_path}"
      end

      desc "set group ownership and permissions on dirs app server needs to write to"
      task :set_perms_and_make_writable_by_app, :roles => :app do
        dirs = %W(
          #{shared_path}/log
          #{shared_path}/pids
          #{shared_path}/uploads
          #{current_path}/tmp
          #{current_path}/public
        ).join(' ')
        run "#{sudo} chgrp -Rf #{app_group} #{dirs}; exit 0"
        run "#{sudo} chmod -Rf g+w #{dirs}; exit 0"
      end

      # database things

      set :db_host, "localhost"
      set :db_socket, "/var/run/mysqld/mysqld.sock"
      set(:db_adapter) do
        Capistrano::CLI.ui.ask("Enter database adapter") do |q|
          q.default = "mysql2"
        end
      end
      set(:db_user) { application[0..15] }
      set(:db_password) { Capistrano::CLI.ui.ask "Enter database password" }
      set(:db_name) { application }
      set :db_encoding, "utf8"

      desc "Link in the production database.yml"
      task :symlink_database_yml, :roles => :app do
        run "#{sudo} ln -nfs #{shared_path}/config/database.yml #{release_path}/config/database.yml"
      end

      desc "Copy database.yml to shared/config/database.yml. Useful if not kept in scm."
      task :push_database_yml, :roles => :app do
        database_yml = ERB.new <<-EOF
#{rails_env}:
  adapter:  #{db_adapter}
  username: #{db_user}
  password: #{db_password}
  database: #{db_name}
  encoding: #{db_encoding}
  host:     #{db_host}
  socket:   #{db_socket}
EOF
        std.su_put(database_yml.result, "#{shared_path}/config/database.yml", "/tmp/")
      end

    end # namespace :rails

    namespace :database do

      desc "Create database"
      task :create, :roles => :app do
        run "cd #{deploy_to}/current && rake db:create RAILS_ENV=#{rails_env}"
      end

      desc "Run database migrations"
      task :migrate, :roles => :app do
        run "cd #{deploy_to}/current && rake db:migrate RAILS_ENV=#{rails_env}"
      end

      desc "Run database migrations"
      task :schema_load, :roles => :app do
        run "cd #{deploy_to}/current && rake db:schema:load RAILS_ENV=#{rails_env}"
      end

      desc "Roll database back to previous migration"
      task :rollback, :roles => :app do
        run "cd #{deploy_to}/current && rake db:rollback RAILS_ENV=#{rails_env}"
      end

    end # namespace :database

  end # namespace :deploify

end
