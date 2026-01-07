# config valid for current version and patch releases of Capistrano
lock "~> 3.20.0"

set :application, "decidim"
set :repo_url, "git@github.com:Osoigo/decidim-sant_cugat.git"

# Default branch is :master
# ask :branch, `git rev-parse --abbrev-ref HEAD`.chomp

# Default deploy_to directory is /var/www/my_app_name
set :deploy_to, "/var/www/decidim"

# Default value for :format is :airbrussh.
set :format, :airbrussh

# You can configure the Airbrussh format using :format_options.
# These are the defaults.
set :format_options, command_output: true, log_file: "log/capistrano.log", color: :auto, truncate: :auto

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
append :linked_files, ".env"

# Default value for linked_dirs is []
append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "storage", ".bundle"

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for local_user is ENV['USER']
# set :local_user, -> { `git config user.name`.chomp }

# Default value for keep_releases is 5
# set :keep_releases, 5

# Uncomment the following to require manually verifying the host key before first deploy.
# set :ssh_options, verify_host_key: :secure

# RVM settings (rvm1-capistrano3)
set :rvm_type, :user # Use user-specific RVM installation (in debian's home)
set :rvm_install_ruby, :install # Automatically install Ruby if not present
set :rvm_autolibs_flag, "read-only" # Use system libraries

# NVM settings
set :nvm_type, :user # or :system, depends on your nvm setup
set :nvm_node, 'v18.20.8'
set :nvm_map_bins, %w{rails rake node npm yarn}

set :assets_manifest, 'public/decidim-packs/manifest.json'

# Passenger settings
set :passenger_restart_with_touch, false

# Hooks
before 'deploy:assets:precompile', 'deploy:symlink:linked_files'
before 'deploy:assets:precompile', 'deploy:yarn:install'
after 'deploy:publishing', 'sidekiq:restart'
after 'deploy:migrate', 'deploy:decidim_0_29_release_update_tasks'

namespace :deploy do
  namespace :yarn do
    task :install do
      on roles(:web) do
        within release_path do
          execute :yarn, 'install --ignore-engines'
        end
      end
    end
  end

  desc "Run Decidim 0.29 release update tasks"
  task :decidim_0_29_release_update_tasks do
    on roles(:app) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          info "Running Decidim 0.29 upgrade tasks..."
          execute :rake, 'decidim:upgrade'
          execute :rake, 'decidim:upgrade:clean:invalid_records'
          execute :rake, 'decidim:upgrade:clean:fix_orphan_categorizations'
          execute :rake, 'decidim:upgrade:attachments_cleanup'
          execute :rake, 'decidim_proposals:upgrade:set_categories'
          execute :rake, 'decidim:upgrade:clean:clean_deleted_users'
          execute :rake, 'decidim:upgrade:fix_nickname_casing'
          execute :rake, 'decidim:upgrade:clean:hidden_resources'
          info "Decidim 0.29 upgrade tasks completed!"
        end
      end
    end
  end
end

Rake::Task["deploy:assets:backup_manifest"].clear

namespace :deploy do
  namespace :assets do
    desc "Backup the custom manifest file"
    task :backup_manifest do
      on roles(fetch(:assets_roles)) do
        within release_path do
          manifest_path = File.join(release_path, fetch(:assets_manifest))
          backup_dir = "#{release_path}/assets_manifest_backup"
          execute :mkdir, "-p", backup_dir
          if test("[ -f #{manifest_path} ]")
            execute :cp, manifest_path, backup_dir
          else
            error "Custom Rails assets manifest file not found at #{manifest_path}."
            exit 1
          end
        end
      end
    end
  end
end

namespace :sidekiq do
  desc "Restart Sidekiq (user systemd)"
  task :restart do
    on roles(:worker) do |host|
      execute :systemctl, "--user restart sidekiq"
    end
  end

  desc "Stop Sidekiq (user systemd)"
  task :stop do
    on roles(:worker) do |host|
      execute :systemctl, "--user stop sidekiq"
    end
  end

  desc "Start Sidekiq (user systemd)"
  task :start do
    on roles(:worker) do |host|
      execute :systemctl, "--user start sidekiq"
    end
  end
end

