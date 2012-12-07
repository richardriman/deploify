# Copyright 2012 by Richard Riman. All rights reserved.

Capistrano::Configuration.instance(:must_exist).load do

  namespace :deploify do

    namespace :mongodb do

      #removes dump folders on server & local machine
      task :clean_dump_folders do
        run "rm -rf #{deploy_to}/db/dump"
        system "rm -rf db/dump"
      end

      #creates and gives rights to dump folders on server
      task :prepare_dump_folders do
        run "sudo mkdir -p #{deploy_to}/db/dump"
        run "sudo chmod 777 -R #{deploy_to}/db"
        run "rm -rf #{deploy_to}/db/dump/#{application_base_name}_#{stage}"
      end

      #dumps local db and uploads & restores db on server
      task :upload do
        prepare_dump_folders
        system "mongodump -d #{application_base_name}_development -o db/dump"
        system "scp -Cr db/dump/ #{user}@#{server_ip}:#{deploy_to}/db"
        run "mv #{deploy_to}/db/dump/#{application_base_name}_development #{deploy_to}/db/dump/#{application_base_name}_#{stage}"
        run "mongorestore --drop -d #{application_base_name}_#{stage} #{deploy_to}/db/dump/#{application_base_name}_#{stage}"
        clean_dump_folders
      end

      #dumps server db and downloads & restores db on local machine
      task :download do
        prepare_dump_folders
        run "mongodump -d #{application_base_name}_#{stage} -o #{deploy_to}/db/dump"
        system "scp -Cr #{user}@#{server_ip}:#{deploy_to}/db/dump db"
        system "mv db/dump/#{application_base_name}_#{stage} db/dump/#{application_base_name}_development"
        system "mongorestore --drop -d #{application_base_name}_development db/dump/#{application_base_name}_development"
        clean_dump_folders
      end

    end # namespace :mongodb

  end # namespace :deploify

end
