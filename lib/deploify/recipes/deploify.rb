# Copyright 2012 by Richard Riman. All rights reserved.

require "bundler/capistrano"
require "rvm/capistrano"

Capistrano::Configuration.instance(:must_exist).load do

  # Set the value if not already set
  # This method is accessible to all recipe files
  # Defined and used by capistrano/deploy tasks
  def _cset(name, *args, &block)
    unless exists?(name)
      set(name, *args, &block)
    end
  end

  alias :default :_cset

  # we allways use bundler, so change rake call
  _cset :rake, lambda { "#{fetch(:bundle_cmd, "bundle")} exec rake" }

  default_run_options[:pty] = true

  set :local_template_dir, File.join("config", "templates")

  # The following two Constants contain details of the configuration
  # files used by each service. They're used when generating config
  # files from templates and when configs files are pushed out to servers.
  #
  # They are populated by the recipe file for each service
  #
  SYSTEM_CONFIG_FILES  = {} # e.g. httpd.conf
  PROJECT_CONFIG_FILES = {} # e.g. projectname-httpd-vhost.conf

  # deploify defines some generic recipes for common services
  # including web, app and database servers
  #
  # They default to my current favourites which you can override
  #
  # Service options
  CHOICES_WEBSERVER = [:nginx]
  CHOICES_APPSERVER = [:passenger, :thin] # :puma, :unicorn
  CHOICES_DATABASE  = [:mysql] # :mongodb
  #
  # Service defaults
  set :web_server_type, :nginx
  set :app_server_type, :passenger
  set :db_server_type,  :mysql

  # we always use RMV, but we must set :system, because RVM default is :user
  set :rvm_type, :system
  set(:rvm_ruby_string) do
    Capistrano::CLI.ui.choose do |menu|
      menu.prompt = "Please choose RVM Ruby version for this application"
      menu.choices("1.8.6", "1.8.7", "ree", "1.9.2", "1.9.3")
    end
  end

  set :use_monit, true

  # Prompt user for missing values if not supplied
  set(:application) do
    Capistrano::CLI.ui.ask "Enter name of project (no spaces)" do |q|
      q.validate = /^[0-9a-z_]*$/
    end
  end

  set(:domain) do
    Capistrano::CLI.ui.ask "Enter domain name for project" do |q|
      q.validate = /^[0-9a-z_\-\.]*$/
    end
  end

  # some tasks run commands requiring special user privileges on remote servers
  # these tasks will run the commands with:
  #   :invoke_command "command", :via => run_method
  # override this value if sudo is not an option
  # in that case, your use will need the correct privileges
  set :run_method, :sudo

  # deploy from TAG stuff

  set :deployable_without_tag, false              # only used WITHOUT multi-staging
  set :stages, %w(production staging)             # default stages (only used WITH multi-staging)
  set :stages_deployable_without_tag, %w(staging) # only used WITH multi-staging

  set(:branch) do
    unless exists?(:stage)
      # single stage configuration
      if deployable_without_tag
        tag = `git branch | grep '*' | awk '{ print $2 }'`.split[0]
      else
        tag = Capistrano::CLI.ui.ask("TAG to deploy (make sure to push the tag first): ")
      end
    else
      # multi-staging configuration
      if stages_deployable_without_tag.include?(fetch(:stage).to_s)
        tag = `git branch | grep '*' | awk '{ print $2 }'`.split[0]
      else
        tag = Capistrano::CLI.ui.ask("TAG from which we deploy on stage '#{fetch(:stage)}' (make sure to push the tag first): ")
      end
    end
  end

  # rails deploy stuff
  set :apps_root,     "/var/www" # parent dir for apps
  set(:deploy_to)     { File.join(apps_root, application) } # dir for current app
  set(:current_path)  { File.join(deploy_to, "current") }
  set(:shared_path)   { File.join(deploy_to, "shared") }

  # more rails deploy stuff
  set :user,  "deploy"  # user who is deploying
  set :group, "deploy"  # deployment group
  set(:web_server_aliases) { domain.match(/^www/) ? [] : ["www.#{domain}"] }

  # rails deploy GIT stuff
  set :scm, :git
  set :deploy_via, :remote_cache
  set :copy_exclude, ['.git', '.rvmrc']
  set(:repository) do
    Capistrano::CLI.ui.ask "Enter repository URL for project"
  end

  # webserver stuff
  set :force_domain_with_www, false

  on :load, "deploify:connect_canonical_tasks"

  namespace :deploify do

    task :connect_canonical_tasks do
      # link application specific recipes into canonical task names
      # e.g. deprec:web:restart => deprec:nginx:restart
      namespaces_to_connect = {
        :web  => :web_server_type,
        :app  => :app_server_type,
        :db   => :db_server_type
      }
      metaclass = class << self; self; end
      namespaces_to_connect.each do |server, choice|
        server_type = send(choice).to_sym
        if server_type != :none
          metaclass.send(:define_method, server) { namespaces[server] }
          namespaces[server] = deploify.send(server_type)
        end
      end
    end

  end # namespace :deploify

  namespace :deploy do

    task :start, :roles => :app, :except => { :no_release => true } do
      run "#{sudo} service #{app_server_type}-#{application} start"
    end

    task :stop, :roles => :app, :except => { :no_release => true } do
      run "#{sudo} service #{app_server_type}-#{application} stop"
    end

    task :restart, :roles => :app, :except => { :no_release => true } do
      run "#{sudo} service #{app_server_type}-#{application} graceful"
    end

    task :force_restart, :roles => :app, :except => { :no_release => true } do
      run "#{sudo} service #{app_server_type}-#{application} restart"
    end

  end # namespace :deploy

end
