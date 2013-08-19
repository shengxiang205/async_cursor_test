#encoding: utf-8
module Async
  def self.host
    @host
  end

  def self.host=(value)
    @host = value
  end

  def self.port
    @port
  end

  def self.port=(port)
    @port = port
  end

  autoload :SocketPool, 'async/socket_pool'
  autoload :AsyncCursor, 'async/async_cursor'
end
