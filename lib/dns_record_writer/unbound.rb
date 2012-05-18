require 'dns_record_writer/base'

module DNSRecordWriter
  class Unbound < Base

    def initialize(io)
      super
      @io.puts '# add below line to server section of your main unbound.conf'
      @io.puts '# include "/path/to/this/file"'
      @io.puts      
    end

    def write(records)
      records.each do |record|
        write_record(record)
      end
    end

    def write_record(record)
      @io.puts "local-data: \"#{record.name} #{record.ttl} IN #{record.type} #{record.values.first}\""
    end

  end
end
