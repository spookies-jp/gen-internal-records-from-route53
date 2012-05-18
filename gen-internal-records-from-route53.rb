#!/usr/bin/env ruby

$LOAD_PATH << File.expand_path(File.dirname(__FILE__)) + '/lib'

require 'rubygems'
require 'route53'
require 'optparse'
require 'yaml'
require 'dns_record_writer'

DEFAULT_CONFIG_PATH = 'config.yaml'
DEFAULT_ADDRESS_MAP_PATH = 'address_map.yaml'

def main
  options = parse_options
  config = load_config(options['config_path'])
  address_map = load_address_map(options['address_map_path'])

  io = options['output_path'] ? File.new(options['output_path'], 'w') : $stdout
  writer = eval('DNSRecordWriter::' + options['daemon_type'].capitalize).new(io)

  connection = Route53::Connection.new(config['aws_access_key'], config['aws_secret_key'])

  zone_message = config['domain'] ? "zone for domain #{config['domain']}" : 'all zones'
  #puts "Fetching #{zone_message}..."
  zones = connection.get_zones(config['domain'])
  exit_with_error_message("failed to fetch #{zone_message}") if zones.nil?
  exit_with_error_message("no zone found") if zones.empty?

  zones.each do |zone|
    #puts "Fetching records of #{zone.name} ..."
    internal_records = generate_internal_records(zone, address_map)
    writer.write(internal_records)
  end
end

def parse_options
  options = {}
  parser = OptionParser.new

  parser.on(
    '-t', '--type TYPE', String,
    'Specify type of DNS daemon to generate internal records. [' + get_dns_daemon_types.join(', ') + ']'
  ) { |type| options['daemon_type'] = type }

  parser.on(
    '-c', '--config CONFIGFILE', String,
    "Specify config file. default: #{DEFAULT_CONFIG_PATH}"
  ) { |path| options['config_path'] = path }

  parser.on(
    '-m', '--map MAPFILE', String,
    "Specify address map file. default: #{DEFAULT_ADDRESS_MAP_PATH}"
  ) { |path| options['address_map_path'] = path }

  parser.on(
    '-o', '--out OUTPUTFILE', String,
    "Specify destination path to write records."
  ) { |path| options['output_path'] = path }

  begin
    parser.parse(ARGV)
  rescue OptionParser::InvalidOption => e
    return false
  end

  exit_with_error_message "conf type of DNS daemon is required" unless options['daemon_type']
  options
end

def load_config(path = nil)
  config = load_yaml(DEFAULT_CONFIG_PATH, path)
  ['aws_access_key', 'aws_secret_key'].each do |key|
    exit_with_error_message "no #{key} provided in config file" unless config[key]
  end
  config
end

def load_address_map(path = nil)
  load_yaml(DEFAULT_ADDRESS_MAP_PATH, path)
end

def load_yaml(default_path, path = nil)
  path ||= default_path
  exit_with_error_message "#{path} does not exist" unless File.file?(path)
  YAML.load_file(path)
end

def exit_with_error_message(message)
  $stderr.puts 'Error: ' + message
  exit!
end

def get_dns_daemon_types
  DNSRecordWriter.constants().inject([]) do |array, constant|
    class_name = constant.to_s
    clazz = eval('DNSRecordWriter::' + class_name)
    if not clazz.eql?(DNSRecordWriter::Base) and clazz.ancestors.include?(DNSRecordWriter::Base)
      array << class_name.downcase
    end
    array
  end
end

def generate_internal_records(zone, address_map)
  records = zone.get_records
  exit_with_error_message("failed to fetch records of zone #{zone.name}") if records.nil?
  exit_with_error_message("no records found in zone #{zone.name}") if records.empty?

  internal_a_records = generate_internal_a_records(zone, address_map)
  converted_records = convert_cname_records_to_a_record(zone, internal_a_records)

  internal_a_records + converted_records
end

def generate_internal_a_records(zone, address_map)
  internal_a_records = []

  external_a_records = select_records_of_type(zone.records, 'A')

  external_a_records.each do |external_record|
    external_address = external_record.values.first

    if address_map.has_key?(external_address)
      internal_address = address_map[external_address]
      internal_record = external_record.clone
      # Route53::DNSRecord does not provide values=
      internal_record.instance_eval do
        @values = [internal_address]
      end
      internal_a_records << internal_record
    end
  end

  internal_a_records
end

def convert_cname_records_to_a_record(zone, internal_a_records)
  records_converted_from_cname_to_a = []

  cname_records = select_records_of_type(zone.records, 'CNAME')

  cname_records.each do |cname_record|
    cname_target = cname_record.values.first + '.'
    targeted_a_record = internal_a_records.find do |internal_a_record|
      internal_a_record.name == cname_target
    end

    if targeted_a_record
      a_record = Route53::DNSRecord.new(
        cname_record.name,
        'A',
        cname_record.ttl,
        targeted_a_record.values,
        zone
      )
      records_converted_from_cname_to_a << a_record
    end
  end

  records_converted_from_cname_to_a
end

def select_records_of_type(records, type)
  records.select { |record| record.type == type }
end

main
