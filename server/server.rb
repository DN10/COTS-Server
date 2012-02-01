# Gems
require 'bundler/setup'
require 'json'
require 'yajl'
require 'eventmachine'
require 'em-mongo'

# Ruby libraries
require 'optparse'
require 'socket'
require 'base64'
require_relative './lib/utilities'
require_relative './lib/logger'

# Global server variables. Not the best design, but there's not a much better way to do it.
$options = {} #hash to contain all options for running the server
$logger = nil
$db = nil
$collection = nil

#Encapsulates all of the methods for the server
module JSONResponder
    Failed = JSON::generate({:response => 400})
    Vague_failure= JSON::generate({:response => 500})
    Success = JSON::generate({:response => 200})

    def post_init
        port, ip = Socket.unpack_sockaddr_in(get_peername)

        @parser = Yajl::Parser.new(:symbolize_keys => true)
        @parser.on_parse_complete = method(:on_completed)
        $logger.log("#{ip} connected on port #{port}", :info)
    end

    def unbind
        $logger.log("Client disconnected", :info)
    end

    def connection_completed
    end

    #Method to determine what to do with the data
    def receive_data(data)
        #Parse and insert if successful
        #Otherwise do some exception handling using regular HTTP error codes
        begin
            @parser.parse(data)
        rescue Yajl::ParseError
            $logger.log("Failed parsing JSON", :error)
            send_data Failed
        rescue Exception => e
            $logger.log(e.message, :error)
            send_data Vague_failure
        end
        close_connection_after_writing
    end

    private
    #Method for Yajl to specify what to do when a parse is successful
    def on_completed(obj)
        $logger.log("Client sent #{obj.inspect}", :info)

        if validate_timestamp(obj)
            send_data Success
            $logger.log("Client got: #{Success}", :info)
        else
            send_data Failed
            $logger.log("Client got: #{Failed}", :info)
        end

    end

end

#Server definition
class COTServer
    attr_accessor :config, :directives

    def initialize(config_file)
        @config = config_file
        @directives = symbolize_keys(Psych.load(File.read(config_file)))
        puts @directives.inspect if $options[:verbose]

        #Configure globals
        $options.update(@directives) #update our global options with the contents of the config file 
        $logger = COTSLogger.new($options[:logfile], Logger.class_eval($options[:log_level]), $options[:verbose])
    end

    # Run EventMachine server
    def run
        EM.run do
            host = '0.0.0.0'
            port = @directives[:port]
            EventMachine::start_server host, port, JSONResponder
            $db = EM::Mongo::Connection.new('localhost').db('cotsbots')
            $collection = $db.collection($options[:collection])
            $logger.log("Started server running on #{host}:#{port}", :info)
        end
    end
end

# Parse cli options
parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ruby server.rb [options] <filename>' 

    opts.on("-v", "--verbose", "Output full information") do |v|
        $options[:verbose] = v 
    end
end
parser.parse!

# Read .yaml configuration file
configuration = ARGV[0]
if configuration.nil?
    puts parser.banner
    exit
end

# Setup and run server
server = COTServer.new(configuration)
server.run