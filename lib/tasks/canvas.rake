require 'rake/task_graph'
require 'parallel'

$canvas_tasks_loaded ||= false
unless $canvas_tasks_loaded
$canvas_tasks_loaded = true

def log_time(name, &block)
  puts "--> Starting: '#{name}'"
  time = Benchmark.realtime(&block)
  puts "--> Finished: '#{name}' in #{time.round(2)}s"
  time
end

def parallel_processes
  processes = (ENV['CANVAS_BUILD_CONCURRENCY'] || Parallel.processor_count).to_i
  puts "working in #{processes} processes"
  processes
end

namespace :canvas do
  desc "Compile javascript and css assets."
  task :compile_assets do |t, args|
    # opt out
    npm_install = ENV["COMPILE_ASSETS_NPM_INSTALL"] != "0"
    build_api_docs = ENV["COMPILE_ASSETS_API_DOCS"] != "0"
    build_css = ENV["COMPILE_ASSETS_CSS"] != "0"
    build_styleguide = ENV["COMPILE_ASSETS_STYLEGUIDE"] != "0"
    build_js = ENV["COMPILE_ASSETS_BUILD_JS"] != "0"
    build_prod_js = ENV['RAILS_ENV'] == 'production' || ENV['USE_OPTIMIZED_JS'] == 'true' || ENV['USE_OPTIMIZED_JS'] == 'True'
    # build dev bundles even in prod mode so you can debug with ?optimized_js=0
    # query string (except for on jenkins where we set JS_BUILD_NO_UGLIFY anyway
    # so there's no need for an unminified fallback)
    build_dev_js = !build_prod_js || ENV['JS_BUILD_NO_UGLIFY'] == "1"

    batches = Rake::TaskGraph.draw do
      task 'css:compile' => [ 'gulp:rev' ] if build_css
      task 'css:styleguide' if build_styleguide
      task 'doc:api' if build_api_docs
      task 'js:yarn_install' if npm_install
      task 'gulp:rev' do |name|
        { name: name, runner: -> { system('yarn run gulp rev') } }
      end

      task 'i18n:generate_js' => [
        # canvas_quizzes is quirky in that we can only extract its phrases from
        # its build artifacts and not from its source! this is unlike other
        # client apps
        'js:build_client_app[canvas_quizzes]'
      ] if build_js

      task 'js:build_client_app[canvas_quizzes]' => [ 'css:compile' ] do |name|
        {
          name: name,
          runner: -> { Rake::Task['js:build_client_app'].invoke('canvas_quizzes') }
        }
      end if build_js

      task 'js:webpack_development' => [
        # public/dist/brandable_css/brandable_css_bundles_with_deps.json needs
        # to exist before we run handlebars stuff, so we have to do this first
        'css:compile',
        'i18n:generate_js',
        'js:build_client_app[canvas_quizzes]',
      ] if build_js && build_dev_js

      task 'js:webpack_production' => [
        'css:compile',
        'i18n:generate_js',
        'js:build_client_app[canvas_quizzes]',
      ] if build_js && build_prod_js
    end

    batch_times = []
    real_time = Benchmark.realtime do
      batches.each do |tasks|
        batch_times += Parallel.map(tasks, :in_processes => parallel_processes) do |task|
          name, runner = if task.is_a?(Hash)
            task.values_at(:name, :runner)
          else
            [task, ->() { Rake::Task[task].invoke }]
          end

          log_time(name, &runner)
        end
      end
    end

    combined_time = batch_times.reduce(:+)

    puts (
      "Finished compiling assets in #{real_time.round(2)}s. " +
      "Parallelism saved #{(combined_time - real_time).round(2)}s " +
      "(#{(real_time.to_f / combined_time.to_f * 100.0).round(2)}%)"
    )
  end

  desc "Just compile css and js for development"
  task :compile_assets_dev do
    ENV["COMPILE_ASSETS_NPM_INSTALL"] = "0"
    ENV["COMPILE_ASSETS_STYLEGUIDE"] = "0"
    ENV["COMPILE_ASSETS_API_DOCS"] = "0"
    Rake::Task['canvas:compile_assets'].invoke
  end

  desc "Load config/dynamic_settings.yml into the configured consul cluster"
  task :seed_consul => [:environment] do
    def load_tree(root, tree)
      tree.each do |node, subtree|
        key = [root, node].compact.join('/')
        if Hash === subtree
          load_tree(key, subtree)
        else
          Imperium::KV.put(key, subtree, cas: 0)
        end
      end
    end

    load_tree(nil, ConfigFile.load('dynamic_settings'))
  end

  desc "Initialize vault"
  task :seed_vault => [:environment] do
    Canvas::Vault.api_client.sys.mount(Canvas::Vault.kv_mount, 'kv', 'Application secrets for canvas', {
      options: { version: 1 },
      config: {
        # In prod this is higher, but for dev, a low ttl is more useful
        default_lease_ttl: '10s'
      }
    })
  end
end

namespace :lint do
  desc "lint controllers for bad render json calls."
  task :render_json do
    output = `script/render_json_lint`
    exit_status = $?.exitstatus
    puts output
    if exit_status != 0
      raise "lint:render_json test failed"
    else
      puts "lint:render_json test succeeded"
    end
  end
end

namespace :db do
  desc "Shows pending db migrations."
  task :pending_migrations => :environment do
    migrations = ActiveRecord::Base.connection.migration_context.migrations
    if CANVAS_RAILS5_2
      pending_migrations = ActiveRecord::Migrator.new(:up, migrations).pending_migrations
    else
      pending_migrations = ActiveRecord::Migrator.new(:up, migrations, ActiveRecord::Base.connection.schema_migration).pending_migrations
    end
    pending_migrations.each do |pending_migration|
      tags = pending_migration.tags
      tags = " (#{tags.join(', ')})" unless tags.empty?
      puts '  %4d %s%s' % [pending_migration.version, pending_migration.name, tags]
    end
  end

  desc "Shows skipped db migrations."
  task :skipped_migrations => :environment do
    migrations = ActiveRecord::Base.connection.migration_context.migrations
    if CANVAS_RAILS5_2
      skipped_migrations = ActiveRecord::Migrator.new(:up, migrations).skipped_migrations
    else
      skipped_migrations = ActiveRecord::Migrator.new(:up, migrations, ActiveRecord::Base.connection.schema_migration).skipped_migrations
    end
    skipped_migrations.each do |skipped_migration|
      tags = skipped_migration.tags
      tags = " (#{tags.join(', ')})" unless tags.empty?
      puts '  %4d %s%s' % [skipped_migration.version, skipped_migration.name, tags]
    end
  end

  namespace :migrate do
    desc "Run all pending predeploy migrations"
    task :predeploy => [:environment, :load_config] do
      migrations = ActiveRecord::Base.connection.migration_context.migrations
      migrations = migrations.select { |m| m.tags.include?(:predeploy) }
      if CANVAS_RAILS5_2
        ActiveRecord::Migrator.new(:up, migrations).migrate
      else
        ActiveRecord::Migrator.new(:up, migrations, ActiveRecord::Base.connection.schema_migration).migrate
      end
    end
  end

  namespace :test do
    desc "Drop and regenerate the test db by running migrations"
    task :reset => [:environment, :load_config] do
      raise "Run with RAILS_ENV=test" unless Rails.env.test?
      config = ActiveRecord::Base.configurations['test']
      queue = config['queue']
      ActiveRecord::Tasks::DatabaseTasks.drop(queue) if queue rescue nil
      ActiveRecord::Tasks::DatabaseTasks.drop(config) rescue nil
      Canvas::Cassandra::DatabaseBuilder.config_names.each do |cass_config|
        db = Canvas::Cassandra::DatabaseBuilder.from_config(cass_config)
        db.tables.each do |table|
          db.execute("DROP TABLE #{table}")
        end
      end
      ActiveRecord::Tasks::DatabaseTasks.create(queue) if queue
      ActiveRecord::Tasks::DatabaseTasks.create(config)
      ::ActiveRecord::Base.connection.schema_cache.clear!
      ::ActiveRecord::Base.descendants.each(&:reset_column_information)
      Rake::Task['db:migrate'].invoke
    end
  end
end

Switchman::Rake.filter_database_servers do |servers, block|
  ENV['REGION']&.split(',')&.each do |region|
    method = :"select!"
    if region[0] == '-'
      method = :"reject!"
      region = region[1..-1]
    end
    if region == 'self'
      servers.send(method, &:in_current_region?)
    else
      servers.send(method) { |server| server.in_region?(region) }
    end
  end
  block.call(servers)
end

%w{db:pending_migrations db:skipped_migrations db:migrate:predeploy}.each do |task_name|
  Switchman::Rake.shardify_task(task_name, categories: ->{ Shard.categories })
end

end
