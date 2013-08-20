#encoding: utf-8
lib_path = File.dirname(File.expand_path(__FILE__)) + '/lib'
$:.unshift lib_path

require 'rubygems'
require 'mongo'
require 'json'
require 'eventmachine'
require 'ruby-prof'
require 'ruby-prof/rack'

host             = %w{ 192.168.10.223 27017 }
$mongo_connection = Mongo::MongoClient.new(host[0], host[1], :pool_size => 64)
$db               = $mongo_connection['data']

require 'async'

Async.host = '192.168.10.223'
Async.port = '27017'

class Api
  def self.call(env)
    request = Rack::Request.new(env)

    if request.path =~ /profile/
      text = StringIO.new
      # result = RubyProf.stop
      # RubyProf::GraphHtmlPrinter.new(result).print(text)
      # RubyProf.start
      [200, {}, [ text.string ]]
    else
      cursor = $db['data'].find(
          { :creator => 'mango_portal@joowing.com', :as => 'task_state_log' }
      ).limit(1)

      # puts Thread.list.inspect

      Async::AsyncCursor.new(cursor: cursor).to_array do |data|
        env['async.callback'].call([200, {}, [JSON.dump(data)]])
      end

      #[-1, {}, []]
      throw(:async)
    end


  end
end

# RubyProf.start

run Api