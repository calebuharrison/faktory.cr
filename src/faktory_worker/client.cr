require "uri"
require "socket"
require "random"
require "json"
require "openssl"

module Faktory
  abstract class Client

    @location : URI
    @labels   : Array(String)
    @socket   : TCPSocket

    def initialize
      Faktory.log.debug("Initializing client connection...")
      @location = URI.parse(Faktory.url)
      @labels = ["crystal-#{Crystal::VERSION}"]
      @socket = TCPSocket.new(@location.host.as(String), @location.port.as(Int32))
      perform_initial_handshake
      Faktory.log.debug("Client successfully connected to Faktory server at #{@location}")
    end

    # Thanks, RX14!
    #
    # https://stackoverflow.com/questions/42299037/
    private def hex_decode(hex : String) : Slice(UInt8)
      if hex.size.even?
        slice = Slice(UInt8).new(hex.size / 2)
        0.step(to: hex.size - 1, by: 2) do |i|
          high_nibble = hex.to_unsafe[i].unsafe_chr.to_u8?(16)
          low_nibble = hex.to_unsafe[i + 1].unsafe_chr.to_u8?(16)
          if high_nibble && low_nibble
            slice[i / 2] = (high_nibble << 4) | low_nibble
          else
            raise "InvalidHex"
          end
        end
        slice
      else
        raise "InvalidHex"
      end
    end

    def hash_it_up(n : Int32, password : String, salt : String) : String
      hash = OpenSSL::Digest.new("SHA256").update(password + salt)
      data = hex_decode(hash.hexdigest)
      (n - 1).times do |i|
        hash.reset
        hash.update(data)
        if i == (n - 2)
          data = hash.hexdigest
        else
          data = hash.digest
        end
      end
      data.as(String)
    end

    def close
      send_command("END")
      @socket.close
      Faktory.log.debug("Client connection closed")
    end

    def flush
      retry_if_necessary do
        send_command("FLUSH")
        verify_ok
      end
      Faktory.log.info("Flushed Faktory server dataset")
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
      Faktory.log.debug("Renewing socket...")
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
            warning = <<-WARNING
            Faktory server protocol #{ver} in use, but this client doesn't speak that version. Your results will be undefined.
            Upgrade this shard with `shards update faktory_worker` to see if an updated version is available.
            If you still see this message, open an issue on GitHub.
            WARNING
            Faktory.log.warn(warning)
          end

          salt = served_hash["s"]?.try &.as_s?
          if salt
            if @location.password
              i = served_hash["i"].as_i || 1
              unless i < 1
                password_hash = hash_it_up(i, @location.password.as(String), salt)
              else
                Faktory.log.fatal("Server requires negative hashing iterations, needs to see a doctor")
                raise "InvalidHashing"
              end
            else
              Faktory.log.fatal("Server requires password, but none has been configured")
              raise "MissingPassword"
            end
          end
        end
        handshake_payload_string = handshake_payload.merge({:pwdhash => password_hash}).to_json
        send_command("HELLO", handshake_payload_string)
        verify_ok
      else
        Faktory.log.fatal("Server did not say HI")
        raise "NoServerResponse"
      end
    end

    def info : String
      retry_if_necessary do
        send_command("INFO")
        response = get_server_response
        if response
          return response.as(String)
        else
          Faktory.fatal("Server did not return info upon request")
          raise "NoServerResponse"
        end
      end
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
          Faktory.log.error("Client retry attempt #{attempt} triggered")
          if attempt < limit
            renew_socket
            perform_initial_handshake
          else
            Faktory.log.fatal("Client retry limit reached")
            raise "RetryLimitReached"
          end
        end
      end
    end

    private def send_command(*args : String)
      command = args.join(" ")
      @socket.puts(command)
      Faktory.log.debug("> " + command)
    end

    private def verify_ok
      response = get_server_response
      unless response && response.as(String) == "OK"
        Faktory.log.fatal("Server did not verify OK")
        raise "NotOK"
      end
    end

    private def get_server_response : String | Nil
      line = @socket.gets
      if line
        Faktory.log.debug("< " + line)
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
          Faktory.log.fatal("Server response indicates a command error")
          raise "CommandError"
        else
          Faktory.log.fatal("Unable to parse server response")
          raise "ParseError"
        end
      else
        Faktory.log.fatal("Server did not respond")
        raise "NoServerResponse"
      end
    end
  end
end