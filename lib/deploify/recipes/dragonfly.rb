# Copyright 2012 by Richard Riman. All rights reserved.

# TODO
#insted images folder I should use dragonfly config

Capistrano::Configuration.instance(:must_exist).load do

  namespace :deploify do

    namespace :dragonfly do

      #synchronizes local files with server files
      task :upload do
        target_folder = "#{deploy_to}/shared/public/images"
        source_folder = "public/images"
        run "mkdir -p #{target_folder}"
        run "sudo chmod 777 -R #{target_folder}"
        system "rsync -e ssh -av #{source_folder}/* #{user}@#{server_ip}:#{target_folder}"
      end

      #synchronizes server files with local files
      task :download do
        source_folder = "#{deploy_to}/shared/public/images"
        target_folder = "public/images"
        system "mkdir -p public/system/dragonfly/development"
        system "rsync -e ssh -av #{user}@#{server_ip}:#{source_folder}/* #{target_folder}"
      end

    end # namespace :dragonfly

  end # namespace :deploify

end
