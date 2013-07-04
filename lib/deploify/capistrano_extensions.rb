require "capistrano"
require "fileutils"

module Deploify

  DEPLOIFY_TEMPLATES_BASE = File.join(File.dirname(__FILE__), "templates")

  # Render template (usually a config file)
  #
  # Usually we render it to a file on the local filesystem.
  # This way, we keep a copy of the config file under source control.
  # We can make manual changes if required and push to new hosts.
  #
  # If the options hash contains :path then it's written to that path.
  # If it contains :remote => true, the file will instead be written to remote targets
  # If options[:path] and options[:remote] are missing, it just returns the rendered
  # template as a string (good for debugging).
  #
  # XXX I would like to get rid of :render_template_to_file
  # XXX Perhaps pass an option to this function to write to remote
  #
  def render_template(app, options={})
    template = options[:template]
    path = options[:path] || nil
    remote = options[:remote] || false
    mode = options[:mode] || 0755
    owner = options[:owner] || nil
    stage = exists?(:stage) ? fetch(:stage).to_s : ''
    # replace this with a check for the file
    unless template
      puts "render_template() requires a value for the template!"
      return false
    end

    # If local copies of deploifyy templates exist they will be used
    # If you don't specify the location with the local_template_dir option
    # it defaults to config/templates.
    # e.g. config/templates/nginx/nginx.conf.erb
    local_template = File.join(local_template_dir, app.to_s, template)
    if File.exists?(local_template)
      puts
      puts "Using local template (#{local_template})"
      template = ERB.new(IO.read(local_template), nil, '-')
    else
      template = ERB.new(IO.read(File.join(DEPLOIFY_TEMPLATES_BASE, app.to_s, template)), nil, '-')
    end
    rendered_template = template.result(binding)

    if remote
      # render to remote machine
      puts 'You need to specify a path to render the template to!' unless path
      exit unless path
      sudo "test -d #{File.dirname(path)} || #{sudo} mkdir -p #{File.dirname(path)}"
      std.su_put rendered_template, path, '/tmp/', :mode => mode
      sudo "chown #{owner} #{path}" if defined?(owner)
    elsif path
      # render to local file
      full_path = File.join('config', stage, app.to_s, path)
      path_dir = File.dirname(File.expand_path(full_path))
      if File.exists?(full_path)
        if IO.read(full_path) == rendered_template
          puts "[skip] Identical file exists (#{full_path})."
          return false
        elsif overwrite?(full_path, rendered_template)
          File.delete(full_path)
        else
          puts "[skip] Not overwriting #{full_path}"
          return false
        end
      end
      FileUtils.mkdir_p "#{path_dir}" unless File.directory?(path_dir)
      # added line above to make windows compatible
      # system "mkdir -p #{path_dir}" if ! File.directory?(path_dir)
      File.open(File.expand_path(full_path), 'w') { |f| f.write rendered_template }
      puts "[done] #{full_path} written"
    else
      # render to string
      return rendered_template
    end
  end

  # Copy configs to server(s). Note there is no :pull task. No changes should
  # be made to configs on the servers so why would you need to pull them back?
  def push_configs(app, files)
    app = app.to_s
    stage = exists?(:stage) ? fetch(:stage).to_s : ''

    files.each do |file|
      full_local_path = File.join('config', stage, app, file[:path])
      if File.exists?(full_local_path)
        # If the file path is relative we will prepend a path to this projects
        # own config directory for this service.
        if file[:path][0, 1] != '/'
          full_remote_path = File.join(deploy_to, app, file[:path])
        else
          full_remote_path = file[:path]
        end
        sudo "test -d #{File.dirname(full_remote_path)} || #{sudo} mkdir -p #{File.dirname(full_remote_path)}"
        std.su_put File.read(full_local_path), full_remote_path, '/tmp/', :mode => file[:mode]
        sudo "chown #{file[:owner]} #{full_remote_path}"
      else
        # Render directly to remote host.
        render_template(app, file.merge(:remote => true))
      end
    end
  end

  def overwrite?(full_path, rendered_template)
    if defined?(overwrite_all)
      return overwrite_all ? true : false
    end

    puts
    response = Capistrano::CLI.ui.ask "File exists (#{full_path}).
    Overwrite? ([y]es, [n]o, [d]iff)" do |q|
      q.default = 'n'
    end

    case response
      when 'y'
        return true
      when 'n'
        return false
      when 'd'
        require 'tempfile'
        tf = Tempfile.new("deprec_diff")
        tf.puts(rendered_template)
        tf.close
        puts
        puts "Running diff -u current_file new_file_if_you_overwrite"
        puts
        system "diff -u #{full_path} #{tf.path} | less"
        puts
        overwrite?(full_path, rendered_template)
    end
  end

  # create new user account on target system
  def useradd(user, options={})
    options[:shell] ||= "/bin/bash" # new accounts on ubuntu have been getting /bin/sh
    switches = ''
    switches += " --shell=#{options[:shell]} " if options[:shell]
    unless options[:homedir] == false
      switches += " --create-home "
      switches += " --home #{options[:homedir]} " if options[:homedir]
    end
    switches += " --gid #{options[:group]} " unless options[:group].nil?
    invoke_command "#{sudo} mkdir -p #{File.dirname(options[:homedir])}" if options[:homedir]
    invoke_command "grep '^#{user}:' /etc/passwd || #{sudo} /usr/sbin/useradd #{switches} #{user}", :via => run_method
  end

  # create a new group on target system
  def groupadd(group, options={})
    via = options.delete(:via) || run_method
    invoke_command "grep '#{group}:' /etc/group || #{sudo} /usr/sbin/groupadd #{group}", :via => via
  end

  # add group to the list of groups this user belongs to
  def add_user_to_group(user, group)
    invoke_command "groups #{user} | grep ' #{group} ' || #{sudo} /usr/sbin/usermod -G #{group} -a #{user}", :via => run_method
  end

  # create directory if it doesn't already exist
  # set permissions and ownership
  # XXX move mode, path and
  def mkdir(path, options={})
    via = options.delete(:via) || :run
    # XXX need to make sudo commands wrap the whole command (sh -c ?)
    # XXX removed the extra 'sudo' from after the '||' - need something else
    invoke_command "test -d #{path} || #{sudo if via == :sudo} mkdir -p #{path}"
    invoke_command "chmod #{sprintf("%3o",options[:mode] || 0755)} #{path}", :via => via if options[:mode]
    invoke_command "chown -R #{options[:owner]} #{path}", :via => via if options[:owner]
    groupadd(options[:group], :via => via) if options[:group]
    invoke_command "chgrp -R #{options[:group]} #{path}", :via => via if options[:group]
  end

  def install_deps(packages=[])
    apt.install({:base => Array(packages)}, :stable)
  end

  def teardown_connections
    sessions.keys.each do |server|
      sessions[server].close
      sessions.delete(server)
    end
  end

end

Capistrano.plugin :_deploify, Deploify
