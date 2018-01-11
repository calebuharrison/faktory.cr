module Faktory
  class Consumer < Client

    @wid : String

    private def handshake_payload
      super.merge({:wid => @wid})
    end

    def initialize(debug : Bool = false)
      @wid = Random.new.hex(8)
      super(debug)
    end

    def beat : String | Nil
      beat_payload = {
        wid: @wid
      }.to_json

      response = nil
      retry_if_necessary do
        send_command("BEAT", beat_payload)
        response = get_server_response
      end
      unless response.as(String) == "OK"
        JSON.parse(response.as(String))["state"].as_s
      else
        nil
      end
    end

    def fetch(queues : Array(String)) : JSON::Any | Nil
      job = nil
      retry_if_necessary do
        send_command("FETCH", queues.join(" "))
        job = get_server_response
      end
      if job
        JSON.parse(job)
      else
        nil
      end
    end

    def ack(jid : String)
      ack_payload = {
        jid: jid
      }.to_json

      retry_if_necessary do
        send_command("ACK", ack_payload)
        verify_ok
      end
    end

    def fail(jid : String, exception : Exception)
      fail_payload = {
        message:    exception.message,
        errtype:    exception.inspect,
        jid:        jid,
        backtrace:  exception.backtrace
      }.to_json

      retry_if_necessary do
        send_command("FAIL", fail_payload)
        verify_ok
      end
    end
  end
end