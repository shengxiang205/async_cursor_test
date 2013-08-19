#encoding: utf-8
module Async
  class SocketPool
    attr_reader :size

    def initialize(opt = {})
      @sockets       = []
      @waiting_queue = []
      @size          = (opt[:size] || 256).to_i
      @host          = opt[:host]
      @port          = opt[:port]
      @created       = 0
    end

    def checkout(&blk)
      if @sockets.size > 0
        socket = @sockets.shift
        EM.next_tick { blk.call(socket) }
      else
        if @created < @size
          socket = fork_new_socket
          EM.next_tick { blk.call(socket) }
        else
          @waiting_queue << blk
        end
      end
    end

    def checkin(socket)
      puts "Check in with buff: #{socket.buff.size}" if socket.buff.size > 0

      @sockets << socket
      if @waiting_queue.size > 0
        blk    = @waiting_queue.shift
        socket = @sockets.shift
        EM.next_tick { blk.call(socket); checkin(socket) }
      end
    end

    protected
    def fork_new_socket
      puts 'Create new socket'
      @created += 1
      EM.connect(@host, @port, Async::AsyncCursor::EMMongoSocket, { pool: self })
    end
  end
end