require 'socket'
require 'stringio'
require 'rack/utils'

module Rack
  module Handler
    class KidGloves
      attr_accessor :app

      def self.run(app, options={}, &block)
        new(app, options).listen(&block)
      end

      def initialize(app, options={})
        @app = app
        @host = options[:Host] || '0.0.0.0'
        @port = options[:Port] || 8089
        @server = nil
      end

      # Start a server and go into an infinite accept loop.
      def listen(&block)
        start(&block)
        loop { accept }
      ensure
        stop
      end

      # Start the server but don't go into the accept loop. The #accept method
      # can then be used to process single connections.
      def start
        log "Starting server on #{@host}:#{@port}"
        @server = TCPServer.new(@host, @port)
        yield @server if block_given?
      end

      # Stop a server started with #start.
      def stop
        if @server && !@server.closed?
          @server.close
          @server = nil
          true
        end
      end

      # Test whether the server is currently running.
      def running?
        !@server.nil?
      end

      # Accept and process a single connection / request. The server must be
      # running before this method is called.
      def accept
        socket = @server.accept
        socket.sync = true
        log "#{socket.peeraddr[2]} (#{socket.peeraddr[3]})"

        req = {}

        # parse the request line
        request = socket.gets
        method, path, version = request.split(" ")
        req["REQUEST_METHOD"] = method
        info, query = path.split("?")
        req["PATH_INFO"] = info
        req["QUERY_STRING"] = query

        # parse the headers
        while (line = socket.gets)
          line.strip!
          break if line.size == 0
          key, val = line.split(": ")
          key = key.upcase.gsub('-', '_')
          key = "HTTP_#{key}" if !%w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
          req[key] = val
        end

        # parse the body
        body = ''
        if (len = req['CONTENT_LENGTH']) && ["POST", "PUT"].member?(method)
          body = socket.read(len.to_i)
        end

        # process the request
        process_request(req, body, socket)
      ensure
        socket.close if socket && !socket.closed?
      end

      def log(message)
        $stderr.puts message
      end

      def status_message(code)
        Rack::Utils::HTTP_STATUS_CODES[code]
      end

      def process_request(request, input_body, socket)
        env = {}.replace(request)
        env["HTTP_VERSION"] ||= env["SERVER_PROTOCOL"]
        env["QUERY_STRING"] ||= ""
        env["SCRIPT_NAME"] = ""

        rack_input = StringIO.new(input_body)
        rack_input.set_encoding(Encoding::BINARY) if rack_input.respond_to?(:set_encoding)

        env.update({"rack.version" => [1,0],
                     "rack.input" => rack_input,
                     "rack.errors" => $stderr,
                     "rack.multithread" => true,
                     "rack.multiprocess" => true,
                     "rack.run_once" => false,

                     "rack.url_scheme" => ["yes", "on", "1"].include?(env["HTTPS"]) ? "https" : "http"
                   })
        status, headers, body = app.call(env)
        begin
          socket.write("HTTP/1.1 #{status} #{status_message(status)}\r\n")
          headers.each do |k, vs|
            vs.split("\n").each { |v| socket.write("#{k}: #{v}\r\n")}
          end
          socket.write("\r\n")
          body.each { |s| socket.write(s) }
        ensure
          body.close if body.respond_to? :close
        end
      end
    end
  end
end
