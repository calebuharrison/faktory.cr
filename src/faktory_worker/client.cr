require "uri"
require "socket"
require "random"
require "json"

module Faktory
  abstract class Client

    @location : URI
    @labels   : Array(String)
    @socket   : TCPSocket

    def initialize(debug : Bool = false)
      @debug = debug
      @location = uri_from_env
      @labels = ["crystal-#{Crystal::VERSION}"]
      @socket = TCPSocket.new(@location.host.as(String), @location.port.as(Int32))
      perform_initial_handshake      
    end

    # def hash_it_up(n : Int32, password : String, salt : String) : String
    #   sha = OpenSSL::Digest.new("SHA256")
    #   hashing = password + salt
    #   n.times do 
    #     hashing = sha.update(hashing.as(String))
    #   end
    #   sha.hexdigest
    # end

    def close
      send_command("END")
      @socket.close
    end

    def flush
      retry_if_necessary do
        send_command("FLUSH")
        verify_ok
      end
    end

    private def handshake_payload
      {
        :hostname => @location.host.as(String),
        :pid => Process.pid,
        :labels => @labels,
        :v => 2
      }
    end

    private def tls? : Bool
      @location.scheme.includes?("tls")
    end

    private def renew_socket
      @socket = TCPSocket.new(@location.host.as(String), @location.port.as(Int32))
    end

    private def perform_initial_handshake
      hi = get_server_response
      password_hash = nil
      if hi
        if hi.as(String) =~ /\AHI (.*)/
          served_hash = JSON.parse($1)
          ver = served_hash["v"].as_i
          if ver > 2
            puts "Warning: Faktory server protocol #{ver} in use, this worker doesn't speak that version."
            puts "We recommed you upgrade this shard with `shards update faktory_worker_crystal`."
          end

          # salt = served_hash["s"]?.try &.as_s?
          # if salt
          #   raise "server requires password, but none has been configured" unless @location.password
          #   i = served_hash["i"].as_i || 1
          #   raise "invalid hashing" if i < 1
          #   password_hash = hash_it_up(i, @location.password.as(String), salt)
          # end
        end
        handshake_payload_string = handshake_payload.merge({:pwdhash => password_hash}).to_json
        send_command("HELLO", handshake_payload_string)
        verify_ok
      else
        raise "did not get server response"
      end
    end

    def info : String
      info_string = ""
      retry_if_necessary do
        send_command("INFO")
        response = get_server_response
        if response
          puts response.as(String) if @debug
          info_string = response.as(String)
        else
          info_string = "No response"
        end
      end
      info_string
    end

    private def retry_if_necessary(limit : Int32 = 3, &block)
      success = false
      attempt = 0
      until success
        attempt += 1
        begin
          yield
          success = true
        rescue e
          if attempt < limit
            renew_socket
            perform_initial_handshake
          else
            raise "retry limit reached: #{e}"
          end
        end
      end
    end

    private def send_command(*args : String)
      command = args.join(" ")
      @socket.puts(command)
      puts "> #{command}" if @debug
    end

    private def verify_ok
      response = get_server_response
      raise "not okay" unless response
      raise "not okay" unless response.as(String) == "OK"
    end

    private def get_server_response : String | Nil
      line = @socket.gets
      puts "< #{line}" if @debug
      raise "no server response" unless line
      case line.char_at(0)
      when '+'
        return line[1..-1].strip
      when '$'
        count = line[1..-1].strip.to_i
        if count > -1
          slice = Slice(UInt8).new(count)
          @socket.read(slice)
          @socket.gets
          return String.new(slice)
        else
          return nil
        end
      when '-'
        raise "command error"
      else
        raise "parse error"
      end
    end

    private def uri_from_env : URI
      provider = ENV["FAKTORY_PROVIDER"]?
      if provider
        if provider.as(String).includes?(":")
          raise "FAKTORY_PROVIDER cannot include ':'"
        else
          url = ENV[provider.as(String)]?
          if url
            return URI.parse(url.as(String))
          else
            raise "Could not get a URL from #{provider.as(String)}"
          end
        end
      else
        raise "Missing FAKTORY_PROVIDER environment variable"
      end
    end
  end
end