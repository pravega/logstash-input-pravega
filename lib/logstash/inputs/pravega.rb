# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "stud/interval"
require "java"
require "logstash-input-pravega_jars.rb"

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
        java_import("io.pravega.client.admin.StreamManager")
        java_import("io.pravega.client.admin.impl.StreamManagerImpl")
        java_import("io.pravega.client.stream.impl.Controller")
        java_import("io.pravega.client.stream.impl.ControllerImpl")
        java_import("io.pravega.client.stream.ScalingPolicy")
        java_import("io.pravega.client.stream.StreamConfiguration")
        java_import("io.pravega.client.stream.ReaderGroupConfig")
        java_import("io.pravega.client.admin.ReaderGroupManager")
        java_import("io.pravega.client.admin.impl.ReaderGroupManagerImpl")
        java_import("io.pravega.client.ClientFactory")
        java_import("io.pravega.client.stream.ReaderConfig")
        java_import("io.pravega.client.stream.Sequence")
        java_import("io.pravega.client.stream.impl.JavaSerializer")
	  
        uri = java.net.URI.new(pravega_endpoint)
        streamManager = StreamManager.create(uri)
        streamManager.createScope(scope)
        policy = ScalingPolicy.fixed(1)
        streamConfig = StreamConfiguration.builder().scalingPolicy(policy).build()
        streamManager.createStream(scope, stream_name, streamConfig)
        groupName = SecureRandom.uuid.gsub('-', '')
        readGroupConfig = ReaderGroupConfig.builder().startingPosition(Sequence::MIN_VALUE).build()
        readerGroupManager = ReaderGroupManager.withScope(scope,uri)
        readerGroupManager.createReaderGroup(groupName, readGroupConfig,java.util.Collections.singleton(stream_name))
        clientFactory = ClientFactory.withScope(scope,uri)
        readerConfig = ReaderConfig.builder().build()
        reader = clientFactory.createReader(SecureRandom.uuid, groupName, JavaSerializer.new(), readerConfig)
        return reader
    end
  end
end # class LogStash::Inputs::Pravega
