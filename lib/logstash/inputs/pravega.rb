# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "stud/interval"
require "java"

require "pravega"

class LogStash::Inputs::Pravega < LogStash::Inputs::Base
  config_name "pravega"

  default :codec, "json"
  
  config :pravega_endpoint, :validate => :string, :require => true

  config :stream_name, :validate => :string, :require => true

  config :scope, :validate => :string, :default => "global"

  config :reader_group_name, :validate => :string, :default => "default_reader_group"

  config :reader_threads, :validate => :number, :default => 1

  config :reader_id, :validate => :string, :default => SecureRandom.uuid

  config :read_timeout_ms, :validate => :number, :default => 60000
  
  public
  def register
    @runner_threads = []
  end # def register

  def run(logstash_queue)
    @runner_consumers = reader_threads.times.map { |i| create_consumer() }
    @runner_threads = @runner_consumers.map { |consumer| thread_runner(logstash_queue, consumer) }
    @runner_threads.each{ |t| t.join }
  end # def run

  def stop
  end

  public
  def pravega_consumers
    @runner_consumers
  end

  private
  def thread_runner(logstash_queue, consumer)
    Thread.new do 
      begin
        while true do
          data = consumer.readNextEvent(read_timeout_ms).getEvent()
          logger.debug("Receive event ", :streamName => @stream_name, :data => data)
          if data.to_s.empty?
             next
          end
          @codec.decode(data) do |event|
            decorate(event)
            event.set("streamName", @stream_name)
            logstash_queue << event
          end
        end
      end
    end
  end

  private
  def create_consumer()
    begin
      java_import('com.emc.pravega.stream.impl.ClientFactoryImpl')
      java_import("com.emc.pravega.stream.ReaderConfig")
      java_import("com.emc.pravega.stream.ReaderGroupConfig")
      java_import("com.emc.pravega.stream.impl.JavaSerializer")
      java_import("com.emc.pravega.stream.Sequence")
      java_import("com.emc.pravega.stream.impl.netty.ConnectionFactoryImpl")
      java_import("com.emc.pravega.stream.impl.ControllerImpl")
      java_import("com.emc.pravega.stream.impl.ReaderGroupManagerImpl")
      uri = java.net.URI.new(pravega_endpoint)
      controller = ControllerImpl.new(uri.getHost(), uri.getPort())
      connectionFactory = ConnectionFactoryImpl.new(false)
      clientFactory = ClientFactoryImpl.new(scope, controller, connectionFactory)
      readerGroupManager = ReaderGroupManagerImpl.new(scope, uri)
      groupName = SecureRandom.uuid.gsub('-', '')
      groupConfig = ReaderGroupConfig.builder().startingPosition(Sequence::MIN_VALUE).build()
      readerGroupManager.createReaderGroup(groupName, groupConfig, java.util.Collections.singleton(stream_name))
      readerConfig = ReaderConfig.builder().build()
      reader = clientFactory.createReader(SecureRandom.uuid, groupName, JavaSerializer.new(), readerConfig)
      return reader
    end
  end
end # class LogStash::Inputs::Pravega
