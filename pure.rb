#encoding: utf-8
lib_path = File.dirname(File.expand_path(__FILE__)) + '/lib'
$:.unshift lib_path

require 'rubygems'
require 'mongo'
require 'json'
require 'eventmachine'

host             = %w{ 192.168.10.223 27017 }
$mongo_connection = Mongo::MongoClient.new(host[0], host[1], :pool_size => 64)
$db               = $mongo_connection['data']

require 'async'

Async.host = '192.168.10.223'
Async.port = '27017'


class Server < EventMachine::Connection
 
  def receive_data(data)
    # $collection.find(:creator => 'mango_portal@joowing.com', :as => 'task_state_log').limit(1).each do |doc|
    #   send_data doc
    #   close_connection_after_writing
    # end

    cursor = $db['data'].find(
        { :creator => 'mango_portal@joowing.com', :as => 'task_state_log' }
    ).limit(1)

    # puts Thread.list.inspect

    Async::AsyncCursor.new(cursor: cursor).to_array do |data|
      send_data JSON.dump(data)
      close_connection_after_writing
    end
  end
end
 
EM.run do
  EM.next_tick do
  end
 
  EM.start_server '0.0.0.0', 4001, Server
end