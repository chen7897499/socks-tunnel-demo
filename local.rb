require "eventmachine"
require "ipaddr"

LOCAL_SERVER_HOST = "127.0.0.1"
LOCAL_SERVER_PORT = "8081"
REMOTE_SERVER_HOST = "127.0.0.1"
REMOTE_SERVER_PORT = "8082"

class LocalConnection < EventMachine::Connection
  attr_accessor :server

  def send_encoded_data(data)
    return if data.nil? || data.length == 0
    # TODO: encode data
    send_data(data)
  end

  def receive_data(data)
    # TODO: decode data
    server.send_data(data)
  end

  def unbind
    server.close_connection_after_writing
  end
end

module LocalServer

  def post_init
    @fiber = Fiber.new do
      greeting
      loop { do_command }
    end
  end

  def receive_data(data)
    if @connection
      @connection.send_encoded_data(data.to_s)
    else
      @data = data
      @fiber = nil if @fiber.resume
    end
  end

  def unbind
    @connection.close_connection if @connection
  end

  private

    # IN
    # +----+----------+----------+
    # |VER | NMETHODS | METHODS  |
    # +----+----------+----------+
    # | 1  |    1     | 1 to 255 |
    # +----+----------+----------+
    #
    # OUT
    # +----+--------+
    # |VER | METHOD |
    # +----+--------+
    # | 1  |   1    |
    # +----+--------+
    def greeting
      ver = @data.unpack("C").first
      clear_data
      if ver == 5
        send_data "\x05\x00"  # NO AUTHENTICATION REQUIRED
      else
        send_data "\x05\xFF"  # NO ACCEPTABLE METHODS
      end
      Fiber.yield
    end

    # IN
    # +----+-----+-------+------+----------+----------+
    # |VER | CMD |  RSV  | ATYP | DST.ADDR | DST.PORT |
    # +----+-----+-------+------+----------+----------+
    # | 1  |  1  | X'00' |  1   | Variable |    2     |
    # +----+-----+-------+------+----------+----------+
    #
    # OUT
    # see the defination of reply_data
    def do_command
      _, cmd, _, atype, addr_length = @data.unpack("C5")
      header_length = 0

      case atype
      when 1, 4  # 1: ipv4, 4 bytes / 4: ipv6, 16 bytes
        ip_length = 4 * atype
        host = IPAddr.ntop @data[4, ip_length]
        port = @data[4 + ip_length, 2].unpack('S>').first
        header_length = ip_length + 6
      when 3     # domain name
        host = @data[5, addr_length]
        port = @data[5 + addr_length, 2].unpack('S>').first
        header_length = addr_length + 7
      else
        panic :address_type_not_supported
      end

      case cmd
      when 1
        send_data reply_data(:success)
        @connection = EventMachine.connect(REMOTE_SERVER_HOST, REMOTE_SERVER_PORT, LocalConnection)
        @connection.server = self
        @connection.send_encoded_data("#{host}:#{port}\n")
        @connection.send_encoded_data(@data[header_length, -1])
        clear_data
        Fiber.yield
      when 2, 3  # bind, udp
        panic :command_not_supported
      else
        panic :command_not_supported
      end
    end

    # +----+-----+-------+------+----------+----------+
    # |VER | REP |  RSV  | ATYP | BND.ADDR | BND.PORT |
    # +----+-----+-------+------+----------+----------+
    # | 1  |  1  | X'00' |  1   | Variable |    2     |
    # +----+-----+-------+------+----------+----------+
    def reply_data(type)
      @replies_hash ||= begin
        {
          success:                    0,
          command_not_supported:      7,
          address_type_not_supported: 8,
        }.map { |k, v| [k, ("\x05#{[v].pack('C')}\x00\x01\x00\x00\x00\x00\x00\x00")] }.to_h
      end
      @replies_hash[type]
    end

    def clear_data
      @data = nil
    end

    def panic(reply_type)
      send_data reply_data(reply_type)
      Fiber.yield
    end
end

EventMachine.run do
  puts "Start socks5 at #{LOCAL_SERVER_HOST}:#{LOCAL_SERVER_PORT}"
  EventMachine.start_server(LOCAL_SERVER_HOST, LOCAL_SERVER_PORT, LocalServer)
end
