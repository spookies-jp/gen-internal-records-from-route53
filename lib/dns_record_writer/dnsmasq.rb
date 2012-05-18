require 'dns_record_writer/base'

module DNSRecordWriter
  class Dnsmasq < Base

    def write(records)
      records.each do |record|
        write_record(record)
      end
    end

    def write_record(record)
      host = record.name.sub(/\.$/, '')
      @io.puts "address=/#{host}/#{record.values.first}"
    end

  end
end
