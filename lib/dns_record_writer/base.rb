module DNSRecordWriter
  class Base

    def initialize(io)
      @io = io
    end

    def write(records)
    end

    def write_record(record)
    end

  end
end