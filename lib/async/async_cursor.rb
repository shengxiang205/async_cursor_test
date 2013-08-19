#encoding: utf-8
module Async
  class AsyncCursor
    EMSockets = {}

    def self.pool(host, port)
      EMSockets["#{host}:#{port}"] ||= Async::SocketPool.new(host: host, port: port)
    end

    module EMMongoSocket
      BINARY_ENCODING = Encoding.find("binary")

      attr_reader :queue
      attr_reader :buff

      def initialize(opt = {})
        @queue   = EventMachine::Queue.new
        @buff    = ''.force_encoding(BINARY_ENCODING)
        @running = false
        @pool    = opt[:pool]
        @proc    = nil
      end

      def post_init
      end

      def add_processor(proc)
        @proc = proc

        unless @buff.empty?
          EM.next_tick { @proc.call(@buff) if @proc }
        end
      end

      def remove_processor(proc)
        @proc = nil if @proc == proc
      end

      def checkin
        @pool.checkin(self)
      end

      def receive_data(data)
        if data
          @buff << data

          unless @buff.empty?
            @proc.call(@buff) if @proc
          end
        end
      end

      def unbind

      end
    end


  

    class NetworkUtil
      include Mongo::Networking

      def initialize
        @id_lock = Mutex.new
      end
    end

    attr_reader :cursor
    attr_reader :status

    def initialize(opt = {})
      @cursor       = opt[:cursor]
      @status       = :pending
      @cached_data  = []
      @em_socket    = nil
      @network_util = NetworkUtil.new
      @n_received   = 0
      @cursor_id    = nil
      @returned     = 0

      @limit      = @cursor.instance_variable_get('@limit')
      @batch_size = @cursor.instance_variable_get('@batch_size')
    end

    def send_get_more(&blk)
      # puts "Get More"
      message = BSON::ByteBuffer.new([0, 0, 0, 0])

      db_name         = @cursor.instance_variable_get('@db').name
      collection_name = @cursor.instance_variable_get('@collection').name
      # DB name.
      BSON::BSON_RUBY.serialize_cstr(message, "#{db_name}.#{collection_name}")


      # Number of results to return.
      if @limit > 0
        limit = @limit - @returned
        if @batch_size > 0
          limit = limit < @batch_size ? limit : @batch_size
        end
        message.put_int(limit)
      else
        message.put_int(@batch_size)
      end

      # Cursor id.
      message.put_long(@cursor_id)

      checkout_em_socket do |em_socket|
        receive_message(Mongo::Constants::OP_GET_MORE, message, em_socket) do |results, recivied, cursor_id|
          @n_received += recivied
          @cursor_id  = cursor_id

          @returned    += @n_received
          @cached_data += results

          @status = :running


          if cursor_id.nil?
            # When returned this, it means cursor is invalid
            @status = :done

          end
          close_cursor_if_query_complete(em_socket)

          blk.call
        end
      end
    end

    def to_array(&blk)
      done_proc = proc do
        if @status == :done
          blk.call(@cached_data)
        else
          send_get_more(&done_proc)
        end
      end

      if @status == :pending
        send_initializing_query(&done_proc)
      elsif @status == :running
        send_get_more(&done_proc)
      elsif @status == :done
        blk.call(@cached_data)
      else
        raise "Status error!"
      end

    end

    def close_cursor_if_query_complete(em_socket = nil)
      if @limit > 0 && @returned >= @limit
        @status = :done
        em_socket.buff.clear if em_socket
      end
    end

    def send_initializing_query(&blk)
      message = @cursor.send :construct_query_message
      # puts "M: #{message}"
      # puts "Initialize Query"

      checkout_em_socket do |em_socket|
        receive_message(Mongo::Constants::OP_QUERY, message, em_socket) do |results, recivied, cursor_id|
          #puts "Results: #{results.inspect}, Received: #{recivied}, CursorID: #{cursor_id}"

          @n_received = recivied
          @cursor_id  = cursor_id

          @returned    += @n_received
          @cached_data += results

          @status = :running

          close_cursor_if_query_complete(em_socket)

          blk.call
        end
      end
    end

    def checkout_em_socket(&blk)
      host, port = cursor.instance_variable_get(:@connection).
          instance_variable_get(:@manager).instance_variable_get(:@primary)

      self.class.pool(Async.host, Async.port).checkout do |s|
        blk.call(s)
      end
    end

    def receive_message(operation, message, em_socket, &blk)
      request_id = @network_util.send(:add_message_headers, message, operation)
      # puts "Message: #{message.inspect}"
      packed_message = message.to_s

      result = ''
      em_socket.send_data(packed_message)

      receive(em_socket, request_id) do |docs, number_received, cursor_id|
        blk.call(docs, number_received, cursor_id)

        em_socket.checkin
      end
    end

    def receive(em_socket, cursor_id, exhaust=false, &blk)
      receive_header(em_socket, cursor_id, exhaust) do
        receive_response_header(em_socket) do |number_received, cursor_id|
          read_documents(number_received, em_socket) do |docs, n_received|
            blk.call(docs, n_received, cursor_id)
          end
        end
      end
    end

    def receive_header(em_socket, expected_response, exhaust, &blk)
      receive_message_on_socket(16, em_socket) do |header|
        response_to = header.unpack('VVV')[2]
        if !exhaust && expected_response != response_to
          raise Mongo::ConnectionFailure, "Expected response #{expected_response} but got #{response_to}"
        end

        #unless header.size == Mongo::Networking::STANDARD_HEADER_SIZE
        #  raise "Short read for DB response header: " +
        #            "expected #{Mongo::Networking::STANDARD_HEADER_SIZE} bytes, saw #{header.size}"
        #end

        blk.call if block_given?
      end
    end

    def receive_response_header(em_socket, &blk)
      receive_message_on_socket(Mongo::Networking::RESPONSE_HEADER_SIZE, em_socket) do |header_buf|
        #if header_buf.length != Mongo::Networking::RESPONSE_HEADER_SIZE
        #  raise "Short read for DB response header; " +
        #            "expected #{Mongo::Networking::RESPONSE_HEADER_SIZE} bytes, saw #{header_buf.length}"
        #end

        # unpacks to flags, cursor_id_a, cursor_id_b, starting_from, number_remaining
        flags, cursor_id_a, cursor_id_b, _, number_remaining = header_buf.unpack('VVVVV')

        begin
          @network_util.send(:check_response_flags, flags)
          cursor_id = (cursor_id_b << 32) + cursor_id_a
          blk.call(number_remaining, cursor_id) if block_given?
        rescue => e
          puts "Error: #{e.to_s}"
          blk.call(0, nil) if block_given?
        end
      end
    end

    def read_documents(number_received, em_sock, &blk)
      if number_received == 0
        blk.call([], 0)
      end

      docs             = []
      number_remaining = number_received

      read_processor = proc do |doc|
        number_remaining -= 1
        docs << doc

        if number_remaining > 0
          read_one_documents(em_sock, &read_processor)
        else
          blk.call(docs, number_received)
        end
      end

      read_one_documents(em_sock, &read_processor)

    end

    def read_one_documents(em_socket, &blk)
      receive_message_on_socket(4, em_socket) do |buf|
        size = buf.unpack('V')[0]
        receive_message_on_socket(size - 4, em_socket) do |buf2|
          buf << buf2
          blk.call(BSON::BSON_CODER.deserialize(buf))
        end
      end
    end

    def receive_message_on_socket(size, em_socket, &blk)
      #puts "Size: #{size}, EMSocket: #{em_socket.queue}"
      process_proc = proc do |data|
        # puts "Receive data size: #{data.size}"
        # puts "Required data size: #{size}"
        if data.size >= size
          sized_data = data[0..(size - 1)]

          if data.size > size
            left_data = data[size..(data.size - 1)]
            data.clear
            data << left_data
          elsif data.size == size
            data.clear
          end

          begin
            EM.next_tick { blk.call(sized_data) }
          rescue => e
            raise e
          ensure
            em_socket.remove_processor(process_proc)
          end


        end
      end

      em_socket.add_processor(process_proc)
    end
  end
end