require "eventmachine"

REMOTE_SERVER_PORT = "8082"

class RemoteConnection < EventMachine::Connection
  attr_accessor :server

  def receive_data(data)
    @server.send_encoded_data(data)
  end

  def unbind
    @server.close_connection_after_writing
  end
end

class RemoteServer < EventMachine::Connection
  def post_init
    @buffer = ""
  end

  def send_encoded_data(data)
    return if data.nil? || data.length == 0
    # TODO: encode data
    send_data(data)
  end

  def receive_data(data)
    # TODO: decode data
    if @buffer
      @buffer << data
      addr, rest = @buffer.split("\n", 2)
      if rest && rest.length > 0
        host, port = addr.split(":")
        port = port.nil? ? 80 : port.to_i
        @connection = EventMachine.connect(host, port, RemoteConnection)
        @connection.server = self
        @connection.send_data(rest) if rest.length > 0
        @buffer = nil
      end
    else
      @connection.send_data(data) if data && data.length > 0
    end
  rescue
    @connection.close_connection if @connection
    close_connection
  end

  def unbind
    @connection.close_connection if @connection
  end
end

EventMachine.run do
  puts "Starting server at 0.0.0.0:#{REMOTE_SERVER_PORT}"
  EventMachine.start_server('0.0.0.0', REMOTE_SERVER_PORT, RemoteServer)
end
