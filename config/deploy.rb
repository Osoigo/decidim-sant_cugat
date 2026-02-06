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
set :rvm_ruby_version, "ruby-3.3.4"

# NVM settings
set :nvm_type, :user # or :system, depends on your nvm setup
set :nvm_node, 'v18.20.8'
set :nvm_map_bins, %w{rails rake node npm yarn}

set :assets_manifest, 'public/decidim-packs/manifest.json'

# Passenger settings
set :passenger_restart_with_touch, false

# Hooks
before 'bundler:config', 'rvm1:install:ruby'
before 'deploy:assets:precompile', 'deploy:symlink:linked_files'
before 'deploy:assets:precompile', 'deploy:npm:install'
after 'deploy:publishing', 'sidekiq:restart'

namespace :deploy do
  namespace :npm do
    task :install do
      on roles(:web) do
        within release_path do
          execute :npm, 'install --silent --no-progress'
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

namespace :decidim do
  desc "Complete upgrade to Decidim 0.30 (run all necessary one-time tasks)"
  task :upgrade_to_0_30 do
    invoke 'decidim:set_proposal_categories'
    invoke 'decidim:clean_deleted_users'
    invoke 'decidim:fix_nickname_casing'
    invoke 'decidim:attachments_cleanup'
  end

  desc "Complete upgrade to Decidim 0.30 including taxonomy migration"
  task :upgrade_to_0_30_with_taxonomies do
    invoke 'decidim:taxonomies:migrate_all'
    invoke 'decidim:set_proposal_categories'
    invoke 'decidim:clean_deleted_users'
    invoke 'decidim:fix_nickname_casing'
    invoke 'decidim:attachments_cleanup'
  end

  desc "Clean orphaned attachment blobs"
  task :attachments_cleanup do
    on roles(:app) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :bundle, "exec rails decidim:upgrade:attachments_cleanup"
        end
      end
    end
  end

  desc "Clean deleted users metadata"
  task :clean_deleted_users do
    on roles(:app) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :bundle, "exec rails decidim:upgrade:clean:clean_deleted_users"
        end
      end
    end
  end

  desc "Fix nickname casing (convert to lowercase)"
  task :fix_nickname_casing do
    on roles(:app) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :bundle, "exec rails decidim:upgrade:fix_nickname_casing"
        end
      end
    end
  end

  desc "Set categories on proposal amendments"
  task :set_proposal_categories do
    on roles(:app) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :bundle, "exec rails decidim_proposals:upgrade:set_categories"
        end
      end
    end
  end

  namespace :taxonomies do
    desc "Create taxonomy migration plan"
    task :make_plan do
      on roles(:app) do
        within release_path do
          with rails_env: fetch(:rails_env) do
            execute :bundle, "exec rails decidim:taxonomies:make_plan"
          end
        end
      end
    end

    desc "Import all taxonomy plans"
    task :import_all_plans do
      on roles(:app) do
        within release_path do
          with rails_env: fetch(:rails_env) do
            execute :bundle, "exec rails decidim:taxonomies:import_all_plans"
          end
        end
      end
    end

    desc "Update metrics after taxonomy migration"
    task :update_all_metrics do
      on roles(:app) do
        within release_path do
          with rails_env: fetch(:rails_env) do
            execute :bundle, "exec rails decidim:taxonomies:update_all_metrics"
          end
        end
      end
    end

    desc "Full taxonomy migration workflow (make_plan + import + update_metrics)"
    task :migrate_all do
      invoke 'decidim:taxonomies:make_plan'
      invoke 'decidim:taxonomies:import_all_plans'
      invoke 'decidim:taxonomies:update_all_metrics'
    end
  end

  namespace :metrics do
    desc "Rebuild meetings metrics from a specific date (e.g., cap production decidim:metrics:rebuild_meetings[2019-01-01])"
    task :rebuild_meetings, :start_date do |task, args|
      on roles(:app) do
        within release_path do
          with rails_env: fetch(:rails_env) do
            start_date = args[:start_date] || '2019-01-01'
            execute :bundle, "exec rails decidim:metrics:rebuild[meetings,#{start_date}]"
          end
        end
      end
    end
  end
end


