##
# LogParser parses a Syslog log file looking for lines logged by the 'rails'
# program.  A typical log line looks like this:
#
#   Mar  7 00:00:20 online1 rails[59600]: Person Load (0.001884)   SELECT * FROM people WHERE id = 10519 LIMIT 1
#
# LogParser does not work with Rails' default logger because there is no way
# to group all the log output of a single request.  You must use SyslogLogger.

module LogParser

  ##
  # LogEntry contains a summary of log data for a single request.

  class LogEntry

    ##
    # Controller and action for this request

    attr_reader :page

    ##
    # Requesting IP

    attr_reader :ip

    ##
    # Time the request was made

    attr_reader :time

    ##
    # Array of SQL queries containing query type and time taken.  The
    # complete text of the SQL query is not saved to reduct memory usage.

    attr_reader :queries

    ##
    # Total request time, including database, render and other.

    attr_reader :request_time

    ##
    # Total render time.

    attr_reader :render_time

    ##
    # Total database time

    attr_reader :db_time

    ##
    # Creates a new LogEntry from the log data in +entry+.

    def initialize(entry)
      @page = nil
      @ip = nil
      @time = nil
      @queries = []
      @request_time = 0
      @render_time = 0
      @db_time = 0
      @in_component = 0

      parse entry
    end

    ##
    # Extracts log data from +entry+, which is an Array of lines from the
    # same request.

    def parse(entry)
      entry = entry.split(/\n/) if String === entry
      entry.each do |line|
        # $stderr.puts "line: #{line}"
        case line
        when /^Parameters/, /^Cookie set/, /^Rendering/,
          /^Redirected/, /^\*/ then
          # nothing
        # when /^Processing ([\S]+) \(for (.+) at (.*)\)/ then
        #Started GET "/user/edit/SheWolfNLust" for 71.202.110.154 at 2013-02-22 18:14:21 -0600
        when /^Started \w+ "([\S]+)" for (.+) at (.*)/ then          
          next if @in_component > 0
          @page = normalize_page $1
          @ip   = $2
          @time = $3
        #Completed 404 Not Found in 9ms (Views: 2.0ms | ActiveRecord: 0.9ms | Solr: 0.0ms)
        #Completed 200 OK in 42ms (Views: 1.1ms | ActiveRecord: 4.5ms | Solr: 0.0ms)
        # when /^Completed .*? in ([\S]+) .+ Rendering: ([\S]+) .+ DB: ([\S]+)/ then
        when /^Completed .+ in ([\S]+) \(Views: ([\S]+) \| ActiveRecord: ([\S]+)/ then   
          #$stderr.puts "completed with 1: #{$1} 2: #{$2} 3: #{$3}"
          next if @in_component > 0
          @request_time = $1.to_f
          @render_time = $2.to_f
          @db_time = $3.to_f
        # when /^Completed .*? in ([\S]+) .+ DB: ([\S]+)/ then # Redirect
        #   next if @in_component > 0
        #   @request_time = $1.to_f
        #   @render_time = 0
        #   @db_time = $2.to_f
        when /(.+?) \(([^)]+)\)   / then
          @queries << [$1, $2.to_f]
        when /^Start rendering component / then
          @in_component += 1
        when /^End of component rendering$/ then
          @in_component -= 1
        when /^Fragment hit: / then
        else # noop
#          raise "Can't handle #{line.inspect}" if $TESTING
        end
      end
    end

    # hmm, usernames are difficult.  I guess they'll just be stripped out
    # easiest way to solve this would be to just show by controller name instead of by url.
    def normalize_page(url)
      url.gsub!(/\/show\/.*$/,'/show/num')
      # url.gsub!(/^(.+\/\d+.*)$/,"#{$1}/num")
      url.gsub!(/^(.+)\/\d+.*$/,'\1/num')
      # bugs end up with percents & long urls
      url.gsub!(/^(.*)%.*$/,'\1/percent')  
      url.gsub!(/^(.*)\?.*$/,'\1?args') 
      
      url.gsub!(/\/user\/edit\/.*$/,'/user/edit/num')
            
      # misc others causing problems with me.  disable if we need to track these
      url.gsub! %r#/^(\/home\/level).*$#, '/ignored'
      url
    end
    
    def ==(other) # :nodoc:
      other.class == self.class and
      other.page == self.page and
      other.ip == self.ip and
      other.time == self.time and
      other.queries == self.queries and
      other.request_time == self.request_time and
      other.render_time == self.render_time and
      other.db_time == self.db_time
    end

  end

  ##
  # Parses IO stream +stream+, creating a LogEntry for each recognizable log
  # entry.
  #
  # Log entries are recognised as starting with Processing, continuing with
  # the same process id through Completed.

  def self.parse(stream) # :yields: log_entry
    buckets = Hash.new { |h,k| h[k] = [] }
    comp_count = Hash.new 0

    stream.each_line do |line|
      #$stderr.puts "stream line: #{line}"
      # line =~ / ([^ ]+) ([^ ]+)\[(\d+)\]: (.*)/
      line =~ / ([^ ]+) ([^ ]+)\[(\d+)\]: (.*)/      
      next if $2.nil? or $2 == 'newsyslog'
      bucket = [$1, $2, $3].join '-'
      data = $4

      buckets[bucket] << data

      case data
      when /^Start rendering component / then
        comp_count[bucket] += 1
      when /^End of component rendering$/ then
        comp_count[bucket] -= 1
      when /^Completed/ then
        next unless comp_count[bucket] == 0
        entry = buckets.delete bucket
        next unless entry.any? { |l| l =~ /^Processing/ }
        yield LogEntry.new(entry)
      end
    end

    buckets.sort.each do |bucket, data|
      yield LogEntry.new(data)
    end
  end

end

