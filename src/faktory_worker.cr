require "./faktory_worker/**"
require "log"

module Faktory
  Log = ::Log.for(self)

  @@producer : Producer | Nil

  protected def self.producer : Producer
    @@producer ||= Producer.new
  end

  @@provider : String | Nil

  def self.provider : String
    begin
      @@provider ||= ENV["FAKTORY_PROVIDER"]
      return @@provider.as(String)
    rescue
      Log.fatal("Missing FAKTORY_PROVIDER environment variable")
      raise "MissingProviderError"
    end
  end

  @@url : String | Nil

  def self.url : String
    begin
      @@url ||= ENV[Faktory.provider]
      return @@url.as(String)
    rescue
      Log.fatal("Unable to extract Faktory server URL from ENV variable #{Faktory.provider}")
      raise "MissingURLError"
    end
  end

  def self.info : String
    Faktory.producer.info
  end

  def self.flush
    Faktory.producer.flush
  end

  def self.version : String
    Faktory::VERSION
  end
end
