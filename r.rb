# -*- encoding: utf-8 -*-
module Rails
  class <<self
    def root
      File.expand_path(__FILE__).split('/')[0..-2].join('/')
    end
  end
end

puts Rails.root

rails_env = ENV['RAILS_ENV'] || 'production'

worker_processes 1 # assuming four CPU cores
Rainbows! do
  use :EventMachine
  # worker_connections 64
end

preload_app true
working_directory Rails.root


pid 'tmp/pids/rainbows.pid'
stderr_path 'log/rainbows.log'
stdout_path 'log/rainbows.log'

listen 31025, :tcp_nopush => false


#worker_processes 8
timeout 30

if GC.respond_to?(:copy_on_write_friendly=)
  GC.copy_on_write_friendly = true
end

before_exec do |server|
  ENV['BUNDLE_GEMFILE'] = "#{Rails.root}/Gemfile"
end

before_fork do |server, worker|
  old_pid = "#{Rails.root}/tmp/pids/rainbows.pid.oldbin"
  if File.exists?(old_pid) && server.pid != old_pid
    begin
      Process.kill("QUIT", File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
      puts "Send 'QUIT' signal to rainbows error!"
    end
  end
end
