# Copyright 2006-2008 by Mike Bailey. All rights reserved.
# Copyright 2012 by Richard Riman. All rights reserved.

Capistrano::Configuration.instance(:must_exist).load do

  set :mysql_admin_user, "deploy"
  set(:mysql_admin_pass) { Capistrano::CLI.password_prompt "Enter database password for '#{mysql_admin_user}':" }

  namespace :deploify do

    namespace :mysql do

      desc "Start Mysql"
      task :start, :roles => :db do
        send(run_method, "service mysql start")
      end

      desc "Stop Mysql"
      task :stop, :roles => :db do
        send(run_method, "service mysql stop")
      end

      desc "Restart Mysql"
      task :restart, :roles => :db do
        send(run_method, "service mysql restart")
      end

      desc "Reload Mysql"
      task :reload, :roles => :db do
        send(run_method, "service mysql reload")
      end

      desc "Create a database"
      task :create_database, :roles => :db do
        cmd = "CREATE DATABASE IF NOT EXISTS #{db_name}"
        run "mysql -u #{mysql_admin_user} -p -e '#{cmd}'" do |channel, stream, data|
          if data =~ /^Enter password:/
             channel.send_data "#{mysql_admin_pass}\n"
           end
        end
      end

      desc "Grant user access to database"
      task :grant_user_access_to_database, :roles => :db do
        cmd = "GRANT ALL PRIVILEGES ON #{db_name}.* TO '#{db_user}'@localhost IDENTIFIED BY '#{db_password}';"
        run "mysql -u #{mysql_admin_user} -p #{db_name} -e \"#{cmd}\"" do |channel, stream, data|
          if data =~ /^Enter password:/
             channel.send_data "#{mysql_admin_pass}\n"
           end
        end
      end

      desc "removes dump folders on server & local machine"
      task :clean_dump_folders do
        run "rm -rf #{deploy_to}/db/dump"
        system "rm -rf db/dump"
      end

      desc "creates and gives rights to dump folders on server"
      task :prepare_dump_folders do
        run "sudo mkdir -p #{deploy_to}/db/dump"
        run "sudo chmod 777 -R #{deploy_to}/db"
        run "rm -rf #{deploy_to}/db/dump/#{application}#{defined?(stage) ? '_'+stage : ''}"
      end

      desc "dumps server db and downloads & restores db on local machine"
      task :download do
        prepare_dump_folders
        run "mysqldump -u#{application} -p#{db_password} #{application}#{defined?(stage) ? '_'+stage : ''} > #{deploy_to}/db/dump/dump.sql"
        system "scp #{user}@#{server_ip}:#{deploy_to}/db/dump/dump.sql db/dump"
        system "mysql -uroot -p #{application}_development < db/dumpdump.sql"
        clean_dump_folders
      end

    end # namespace :mysql

  end # namespace :deploify

end

#
# Setup replication
#

# setup user for repl
# GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%.yourdomain.com' IDENTIFIED BY 'slavepass';

# get current position of binlog
# mysql> FLUSH TABLES WITH READ LOCK;
# Query OK, 0 rows affected (0.00 sec)
#
# mysql> SHOW MASTER STATUS;
# +------------------+----------+--------------+------------------+
# | File             | Position | Binlog_Do_DB | Binlog_Ignore_DB |
# +------------------+----------+--------------+------------------+
# | mysql-bin.000012 |      296 |              |                  |
# +------------------+----------+--------------+------------------+
# 1 row in set (0.00 sec)
#
# # get current data
# mysqldump --all-databases --master-data >dbdump.db
#
# UNLOCK TABLES;


# Replication Features and Issues
# http://dev.mysql.com/doc/refman/5.0/en/replication-features.html
