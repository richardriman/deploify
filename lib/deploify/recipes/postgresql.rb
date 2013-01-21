# Copyright 2006-2008 by Mike Bailey. All rights reserved.
# Copyright 2012 by Richard Riman. All rights reserved.

Capistrano::Configuration.instance(:must_exist).load do

  set :postgresql_admin_user, "postgres"
  set(:postgresql_admin_pass) { Capistrano::CLI.password_prompt "Enter database password for '#{postgresql_admin_user}':" }

  before "deploify:postgresql:create_database", "deploify:postgresql:create_user"

  namespace :deploify do

    namespace :postgresql do

      desc "Start PostgreSQL"
      task :start, :roles => :db do
        send(run_method, "service postgresql start")
      end

      desc "Stop PostgreSQL"
      task :stop, :roles => :db do
        send(run_method, "service postgresql stop")
      end

      desc "Restart PostgreSQL"
      task :restart, :roles => :db do
        send(run_method, "service postgresql restart")
      end

      desc "Reload PostgreSQL"
      task :reload, :roles => :db do
        send(run_method, "service postgresql reload")
      end

      desc "Create a PostgreSQL user"
      task :create_user, :roles => :db do
        run "#{sudo} su - postgres -c 'createuser -P -D -A -E #{db_user}; exit 0'" do |channel, stream, data|
          if data =~ /^Enter password for new/
            channel.send_data "#{db_password}\n"
          end
          if data =~ /^Enter it again:/
            channel.send_data "#{db_password}\n"
          end
          if data =~ /^Shall the new role be allowed to create more new roles?/
            channel.send_data "n\n"
          end
        end
      end

      desc "Create a PostgreSQL database"
      task :create_database, :roles => :db do
        run "#{sudo} su - postgres -c 'createdb -O #{db_user} #{db_name}; exit 0'"
      end

      desc "Grant user access to database"
      task :grant_user_access_to_database, :roles => :db do
        # "GRANT ALL PRIVILEGES ON DATABASE jerry to tom;"
        # run "#{sudo} what's the command for this using #{db_user} #{db_name}\'"
      end

    end # namespace :postgresql

  end # namespace :deploify

end
